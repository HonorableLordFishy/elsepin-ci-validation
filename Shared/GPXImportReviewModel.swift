import Foundation
import Combine

/// Owns only an import preview. Applying it to an editor requires a separate action.
@MainActor final class GPXImportReviewModel: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var loading = false
    @Published private(set) var document: GPXImport? { didSet { updateSelection() } }
    @Published private(set) var error: String?
    @Published var pathIndex = 0 { didSet { segmentIndex = 0 } }
    // -1 explicitly joins every segment. A separated track defaults to one segment.
    @Published var segmentIndex = 0 { didSet { updateSelection() } }
    @Published private(set) var selectedPoints: [RoutePoint] = []
    private var selectionIsUsable = false
    private var task: Task<Void, Never>?
    private var request = UUID()
    private var workspace = UUID()
    private var url: URL?
    private let loader: @Sendable (URL) async throws -> GPXImport
    private let currentWorkspace: () -> UUID
    init(loader: @escaping @Sendable (URL) async throws -> GPXImport = { try await GPXImporter.load(from: $0) },
         currentWorkspace: @escaping () -> UUID = { AppDataWorkspace.shared.context.generation }) {
        self.loader = loader; self.currentWorkspace = currentWorkspace
    }
    var selectedPath: GPXPath? {
        guard let paths = document?.paths, paths.indices.contains(pathIndex) else { return nil }
        return paths[pathIndex]
    }
    private func updateSelection() {
        let points: [RoutePoint]
        if let path = selectedPath {
            points = !path.hasGaps || segmentIndex == -1 ? path.points
                : (path.segments.indices.contains(segmentIndex) ? path.segments[segmentIndex] : [])
        } else { points = [] }
        selectionIsUsable = points.count > 1 && points.dropFirst().contains { $0 != points.first }
        selectedPoints = points
    }
    var canImport: Bool { !loading && error == nil && selectionIsUsable }
    func start(_ url: URL) {
        invalidate()
        self.url = url; workspace = currentWorkspace()
        document = nil; error = nil; pathIndex = 0
        loading = true; isPresented = true
        let token = request, destination = workspace, loader = loader
        task = Task { [weak self] in
            do {
                let result = try await loader(url)
                guard let self, self.accepts(token, destination) else { return }
                self.document = result; self.loading = false; self.task = nil
            } catch {
                guard let self, self.accepts(token, destination) else { return }
                self.error = error.localizedDescription; self.loading = false; self.task = nil
            }
        }
    }
    func retry() { if let url { start(url) } }
    func cancel() { invalidate(); loading = false; isPresented = false; document = nil; url = nil }
    func interrupt() {
        guard loading else { return }
        invalidate(); loading = false; error = "Import paused. Try again when you're ready."
    }
    func takePoints() -> [RoutePoint]? {
        guard workspace == currentWorkspace(), canImport else { cancel(); return nil }
        let result = selectedPoints
        cancel()
        return result
    }
    private func invalidate() { request = UUID(); task?.cancel(); task = nil }
    private func accepts(_ token: UUID, _ destination: UUID) -> Bool {
        !Task.isCancelled && request == token && isPresented && destination == currentWorkspace()
    }
}
