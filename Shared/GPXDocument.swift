import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum GPXPathKind: Equatable, Sendable { case track, route, waypoints }
struct GPXPath: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let kind: GPXPathKind
    let segments: [[RoutePoint]]
    var points: [RoutePoint] { segments.count == 1 ? segments[0] : segments.flatMap { $0 } }
    var hasGaps: Bool {
        zip(segments, segments.dropFirst()).contains { left, right in
            guard let end = left.last, let start = right.first else { return false }
            return end.distance(to: start) > 0.5
        }
    }
}
struct GPXImport: Equatable, Sendable {
    let paths: [GPXPath]
    let waypointCount: Int
    var kind: GPXPathKind { paths[0].kind }
    var points: [RoutePoint] { paths[0].points }
    var segmentCount: Int { paths[0].segments.count }
}
enum GPXImportError: Error, LocalizedError, Equatable, Sendable {
    case emptyFile, tooLarge, tooManyPoints, forbiddenDeclaration, malformedXML, invalidCoordinate, noPath, notAFile
    var errorDescription: String? {
        switch self {
        case .emptyFile: return "This GPX file is empty."
        case .tooLarge: return "This GPX file is larger than 32 MB."
        case .tooManyPoints: return "This GPX file has more than 100,000 points. Split it into smaller files and try again."
        case .forbiddenDeclaration: return "This GPX file uses a document type or entity declaration that isn't supported."
        case .malformedXML: return "This isn't a valid GPX file."
        case .invalidCoordinate: return "This GPX file has an invalid latitude or longitude."
        case .noPath: return "This GPX file has no track, route or waypoint coordinates."
        case .notAFile: return "Choose a GPX file, not a folder."
        }
    }
}
enum GPXDocument {
    static let maximumBytes = 32 * 1024 * 1024
    static let maximumPoints = 100_000

    static func parse(_ data: Data) throws -> GPXImport {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw GPXImportError.emptyFile }
        guard data.count <= maximumBytes else { throw GPXImportError.tooLarge }
        var bytes = Array(data.prefix(4))
        bytes += Array(repeating: 0, count: max(0, 4 - bytes.count))
        let encoding: String.Encoding
        if bytes == [0, 0, 254, 255] || bytes == [0, 0, 0, 60] { encoding = .utf32BigEndian }
        else if bytes == [255, 254, 0, 0] || bytes == [60, 0, 0, 0] { encoding = .utf32LittleEndian }
        else if Array(bytes.prefix(2)) == [254, 255] || Array(bytes.prefix(2)) == [0, 60] { encoding = .utf16BigEndian }
        else if Array(bytes.prefix(2)) == [255, 254] || Array(bytes.prefix(2)) == [60, 0] { encoding = .utf16LittleEndian }
        else { encoding = .utf8 }
        guard let text = String(data: data, encoding: encoding) else { throw GPXImportError.malformedXML }
        // Scan markup once; comments and CDATA may contain declaration-like text.
        var cursor = text.startIndex
        while let start = text.range(of: "<", range: cursor..<text.endIndex) {
            try Task.checkCancellation()
            let tail = text[start.lowerBound...]
            if tail.hasPrefix("<!--") || tail.hasPrefix("<![CDATA[") {
                let close = tail.hasPrefix("<!--") ? "-->" : "]]>"
                guard let end = text.range(of: close, range: start.upperBound..<text.endIndex) else { throw GPXImportError.malformedXML }
                cursor = end.upperBound
            } else {
                if tail.hasPrefix("<!DOCTYPE") || tail.hasPrefix("<!ENTITY") { throw GPXImportError.forbiddenDeclaration }
                cursor = start.upperBound
            }
        }
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let complete = parser.parse()
        if delegate.cancelled { throw CancellationError() }
        if let failure = delegate.failure { throw failure }
        guard complete else { throw GPXImportError.malformedXML }
        return try delegate.result()
    }
    static func export(_ points: [RoutePoint], name: String = "Elsepin Route") -> String {
        let name = name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                     "<gpx version=\"1.1\" creator=\"Elsepin\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(name)</name><trkseg>"]
        for point in points where point.isValid {
            lines.append(String(format: "<trkpt lat=\"%.6f\" lon=\"%.6f\"/>",
                                locale: Locale(identifier: "en_US_POSIX"), point.latitude, point.longitude))
        }
        lines.append("</trkseg></trk></gpx>")
        return lines.joined(separator: "\n")
    }
}
enum GPXImporter {
    static func load(from url: URL) async throws -> GPXImport {
        try await runCancellable {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return try GPXDocument.parse(readBounded(url))
        }
    }
    static func runCancellable<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
    static func readBounded(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw GPXImportError.notAFile }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw GPXImportError.notAFile }
        if let size = values.fileSize, size > GPXDocument.maximumBytes { throw GPXImportError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            guard data.count <= GPXDocument.maximumBytes - chunk.count else { throw GPXImportError.tooLarge }
            data.append(chunk)
        }
        return data
    }
}
private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var rootNamespace = ""
    private var paths: [GPXPath] = []
    private var segments: [[RoutePoint]] = []
    private var name = ""
    private var waypoints: [RoutePoint] = []
    private var pointCount = 0
    private(set) var failure: GPXImportError?
    private(set) var cancelled = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard !stopIfCancelled(parser) else { return }
        let ns = namespaceURI ?? ""
        if stack.isEmpty {
            guard elementName == "gpx", ["", "http://www.topografix.com/GPX/1/0", "http://www.topografix.com/GPX/1/1"].contains(ns) else {
                fail(.malformedXML, parser); return
            }
            rootNamespace = ns
        }
        stack.append(ns == rootNamespace ? elementName : "#extension")
        switch stack {
        case ["gpx", "trk"], ["gpx", "rte"]: segments = []; name = ""
        case ["gpx", "trk", "trkseg"]: segments.append([])
        case ["gpx", "trk", "trkseg", "trkpt"], ["gpx", "rte", "rtept"], ["gpx", "wpt"]:
            guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else { fail(.invalidCoordinate, parser); return }
            let point = RoutePoint(latitude: lat, longitude: lon)
            guard point.isValid else { fail(.invalidCoordinate, parser); return }
            pointCount += 1
            guard pointCount <= GPXDocument.maximumPoints else { fail(.tooManyPoints, parser); return }
            if stack == ["gpx", "wpt"] { waypoints.append(point) }
            else { if segments.isEmpty { segments.append([]) }; segments[segments.count - 1].append(point) }
        default: break
        }
    }
    private func stopIfCancelled(_ parser: XMLParser) -> Bool {
        guard Task.isCancelled else { return false }
        cancelled = true; parser.abortParsing(); return true
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !stopIfCancelled(parser) else { return }
        guard stack == ["gpx", "trk", "name"] || stack == ["gpx", "rte", "name"] else { return }
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stopIfCancelled(parser) else { return }
        if stack == ["gpx", "trk", "name"] || stack == ["gpx", "rte", "name"] {
            if name.count < 256 { name += String(string.prefix(256 - name.count)) }
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard !stopIfCancelled(parser) else { return }
        if stack == ["gpx", "trk"] || stack == ["gpx", "rte"] {
            let nonempty = segments.filter { !$0.isEmpty }
            if !nonempty.isEmpty {
                let kind: GPXPathKind = stack.last == "trk" ? .track : .route
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                paths.append(GPXPath(id: paths.count, name: title.isEmpty ? "\(kind == .track ? "Track" : "Route") \(paths.count + 1)" : title,
                                     kind: kind, segments: nonempty))
            }
        }
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) { if failure == nil && !cancelled { failure = .malformedXML } }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(.forbiddenDeclaration, parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { fail(.forbiddenDeclaration, parser) }
    private func fail(_ error: GPXImportError, _ parser: XMLParser) { failure = failure ?? error; parser.abortParsing() }
    func result() throws -> GPXImport {
        var result = paths
        if !waypoints.isEmpty { result.append(GPXPath(id: result.count, name: "Waypoints in file order", kind: .waypoints, segments: [waypoints])) }
        guard !result.isEmpty else { throw GPXImportError.noPath }
        return GPXImport(paths: result, waypointCount: waypoints.count)
    }
}
