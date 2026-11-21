import SwiftUI

@MainActor
final class LibraryBackupInput: ObservableObject {
    @Published var isFilePickerPresented = false
    @Published private(set) var isChoosingFile = false
    @Published private(set) var state = BackupImportState()
    private var preparation: Task<Void, Never>?

    func chooseFile() {
        guard !isChoosingFile, !state.isLoading else { return }
        state.notice(nil)
        isChoosingFile = true
        isFilePickerPresented = true
    }

    func picked(_ result: Result<[URL], Error>) {
        // SwiftUI clears the presentation binding before delivering its result.
        // Keep selection ownership until completion/cancellation, not onDismiss.
        guard isChoosingFile else { return }
        isChoosingFile = false
        isFilePickerPresented = false
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                state.notice("No file selected. Your previous preview is unchanged.")
                return
            }
            // Retain scoped access across coordinated background reading,
            // including cloud-provider downloads, failure and cancellation.
            let access = BackupFileAccess(url)
            prepare {
                defer { withExtendedLifetime(access) {} }
                return try BackupImportReader.file(access.url)
            }
        case .failure(let error):
            state.notice(error.localizedDescription)
        }
    }

    func cancelledFileSelection() {
        guard isChoosingFile else { return }
        isChoosingFile = false
        isFilePickerPresented = false
        state.notice("No file selected. Your previous preview is unchanged.")
    }

    func paste(_ strings: [String]) {
        guard !isChoosingFile, let text = strings.first else { return }
        prepare { try BackupImportReader.text(text) }
    }

    func clearPreview() { state.clearPreview() }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
        state.cancel()
    }

    private func prepare(_ load: @escaping @Sendable () throws -> BackupImportPreview) {
        guard let id = state.begin() else { return }
        let worker = Task.detached(priority: .userInitiated) { Result { try load() } }
        preparation = Task {
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            state.finish(id, result: result)
            preparation = nil
        }
    }
}

/// Immutable access lease, released after the worker (also on failure/cancellation).
private final class BackupFileAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
