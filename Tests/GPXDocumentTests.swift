import XCTest
@testable import SessionPresentation

final class GPXDocumentTests: XCTestCase {
    private let namespace = "http://www.topografix.com/GPX/1/1"

    private func gpx(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test" xmlns="\(namespace)">
        \(body)
        </gpx>
        """.utf8)
    }

    private func track(points: [(Double, Double)]) -> String {
        let trackPoints = points.map { "<trkpt lat=\"\($0.0)\" lon=\"\($0.1)\"></trkpt>" }.joined()
        return "<trk><trkseg>\(trackPoints)</trkseg></trk>"
    }

    func testTrackAttributesWorkInEitherOrderAndQuotes() throws {
        let data = gpx("""
        <trk><trkseg>
          <trkpt lat="51.5000" lon="-0.1200"></trkpt>
          <trkpt lon='-0.1210' lat='51.5010'></trkpt>
        </trkseg></trk>
        """)
        let result = try GPXDocument.parse(data)
        XCTAssertEqual(result.kind, .track)
        XCTAssertEqual(result.points, [
            RoutePoint(latitude: 51.5, longitude: -0.12),
            RoutePoint(latitude: 51.501, longitude: -0.121)
        ])
        XCTAssertEqual(result.segmentCount, 1)
    }

    func testNamespacedElementsParse() throws {
        let data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1" version="1.1" creator="Test">
          <g:trk><g:trkseg>
            <g:trkpt lat="1" lon="2"/>
          </g:trkseg></g:trk>
        </g:gpx>
        """.utf8)
        let result = try GPXDocument.parse(data)
        XCTAssertEqual(result.points, [RoutePoint(latitude: 1, longitude: 2)])
    }

    func testBoundsAndWaypointsAreNotRoutePoints() throws {
        let data = gpx("""
        <bounds minlat="0" minlon="0" maxlat="2" maxlon="3"/>
        <wpt lat="0.5" lon="0.5"><name>A waypoint</name></wpt>
        \(track(points: [(0, 0), (1, 1)]))
        """)
        let result = try GPXDocument.parse(data)
        XCTAssertEqual(result.points, [RoutePoint(latitude: 0, longitude: 0),
                                       RoutePoint(latitude: 1, longitude: 1)])
        XCTAssertEqual(result.waypointCount, 1)
    }

    func testContiguousSegmentsAreJoinedAndCounted() throws {
        let data = gpx("""
        <trk>
          <trkseg><trkpt lat="1" lon="1"/><trkpt lat="1" lon="2"/></trkseg>
          <trkseg><trkpt lat="1" lon="2"/><trkpt lat="1" lon="3"/></trkseg>
        </trk>
        """)
        let result = try GPXDocument.parse(data)
        XCTAssertEqual(result.points.count, 4)
        XCTAssertEqual(result.segmentCount, 2)
    }

    func testDisconnectedSegmentsRemainSeparateForExplicitChoice() throws {
        let data = gpx("<trk><trkseg><trkpt lat='1' lon='1'/><trkpt lat='1' lon='2'/></trkseg><trkseg><trkpt lat='9' lon='9'/><trkpt lat='9' lon='10'/></trkseg></trk>")
        let result = try GPXDocument.parse(data)
        XCTAssertTrue(result.paths[0].hasGaps)
        XCTAssertEqual(result.paths[0].segments.count, 2)
    }

    func testMultipleTracksRemainAvailableForSelection() throws {
        let result = try GPXDocument.parse(gpx(track(points: [(1,1),(1,2)]) + track(points: [(2,2),(2,3)])))
        XCTAssertEqual(result.paths.count, 2)
        XCTAssertEqual(result.paths[1].points.first?.latitude, 2)
    }

    func testEmptyTracksDoNotConflictWithARoute() throws {
        let data = gpx("""
        <trk><trkseg></trkseg></trk>
        <rte><rtept lat="1" lon="1"/><rtept lat="2" lon="2"/></rte>
        """)
        let result = try GPXDocument.parse(data)
        XCTAssertEqual(result.kind, .route)
        XCTAssertEqual(result.points.count, 2)
    }

    func testTrackAndRouteAreBothAvailable() throws {
        let result = try GPXDocument.parse(gpx(track(points: [(1,1),(1,2)]) + "<rte><rtept lat='2' lon='2'/></rte>"))
        XCTAssertEqual(result.paths.map(\.kind), [.track, .route])
    }

    func testMultipleRoutesRemainAvailable() throws {
        let result = try GPXDocument.parse(gpx("<rte><rtept lat='1' lon='1'/></rte><rte><rtept lat='2' lon='2'/></rte>"))
        XCTAssertEqual(result.paths.count, 2)
    }

    func testMalformedAndTruncatedXMLAreRejected() throws {
        XCTAssertThrowsError(try GPXDocument.parse(gpx("<trk><trkseg>"))) {
            XCTAssertEqual($0 as? GPXImportError, .malformedXML)
        }
        XCTAssertThrowsError(try GPXDocument.parse(Data("<gpx><trk>".utf8))) {
            XCTAssertEqual($0 as? GPXImportError, .malformedXML)
        }
    }

    func testEmptyFailsButWaypointOnlyImportIsPreserved() throws {
        XCTAssertThrowsError(try GPXDocument.parse(Data()))
        let result = try GPXDocument.parse(gpx("<wpt lat='1' lon='1'/><wpt lat='2' lon='2'/>"))
        XCTAssertEqual(result.kind, .waypoints)
        XCTAssertEqual(result.points.count, 2)
    }

    func testInvalidCoordinatesAreRejected() throws {
        for point in ["<trkpt lat='91' lon='0'/>", "<trkpt lat='0' lon='181'/>",
                      "<trkpt lat='NaN' lon='0'/>", "<trkpt lat='' lon='0'/>",
                      "<trkpt lon='0'/>"] {
            XCTAssertThrowsError(try GPXDocument.parse(gpx("<trk><trkseg>\(point)</trkseg></trk>"))) {
                XCTAssertEqual($0 as? GPXImportError, .invalidCoordinate, point)
            }
        }
    }

    func testForbiddenDeclarationsAreRejectedBeforeParsing() throws {
        let doctype = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE gpx [<!ENTITY x "y">]>
        <gpx version="1.1" creator="Test"><trk><trkseg><trkpt lat="1" lon="1"/></trkseg></trk></gpx>
        """.utf8)
        XCTAssertThrowsError(try GPXDocument.parse(doctype)) {
            XCTAssertEqual($0 as? GPXImportError, .forbiddenDeclaration)
        }
        XCTAssertThrowsError(try GPXDocument.parse(Data(repeating: 0, count: GPXDocument.maximumBytes + 1))) {
            XCTAssertEqual($0 as? GPXImportError, .tooLarge)
        }
    }

    func testExcessivePointsAreBounded() throws {
        let points = (0...GPXDocument.maximumPoints)
            .map { "<trkpt lat='0' lon='\(Double($0) / 100_000)'/>" }.joined()
        let data = gpx("<trk><trkseg>\(points)</trkseg></trk>")
        XCTAssertThrowsError(try GPXDocument.parse(data)) {
            XCTAssertEqual($0 as? GPXImportError, .tooManyPoints)
        }
    }

    func testExportRoundTripsWithinSixDecimalPlaces() throws {
        let points = [RoutePoint(latitude: 51.5001234, longitude: -0.1209876),
                      RoutePoint(latitude: 51.501, longitude: -0.121)]
        let text = GPXDocument.export(points, name: "A & B <route>")
        XCTAssertTrue(text.contains("A &amp; B &lt;route&gt;"))
        let result = try GPXDocument.parse(Data(text.utf8))
        XCTAssertEqual(result.kind, .track)
        XCTAssertEqual(result.points.count, points.count)
        for (expected, actual) in zip(points, result.points) {
            XCTAssertEqual(expected.latitude, actual.latitude, accuracy: 0.000001)
            XCTAssertEqual(expected.longitude, actual.longitude, accuracy: 0.000001)
        }
    }

    func testBoundedReaderLoadsAFileOffTheMainPath() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try gpx(track(points: [(1, 1), (1, 2)])).write(to: url)
        let result = try await GPXImporter.load(from: url)
        XCTAssertEqual(result.points.count, 2)
    }

    func testBoundedReaderRejectsAnOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(GPXDocument.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try GPXImporter.readBounded(url)) {
            XCTAssertEqual($0 as? GPXImportError, .tooLarge)
        }
    }
}
