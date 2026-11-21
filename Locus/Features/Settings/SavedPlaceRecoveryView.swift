import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SavedPlaceRecoveryView: View {
    @EnvironmentObject private var session: SpoofSession
    @State private var message: String?
    @State private var confirmation: RecoveryAction?
    @State private var exporting = false
    @State private var document = SavedPlaceRecoveryDocument()

    var body: some View {
        List {
            if let message {
                Section { Text(message).font(.footnote).textSelection(.enabled) }
                    .shiftSettingsRows()
            }
            savedPlaces
            recentPlaces
        }
        .shiftSettingsScreen()
        .loggedNavigationTitle("Saved place recovery")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "Elsepin-Saved-Place-Recovery.json") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .confirmationDialog(confirmation?.title ?? "Recovery action",
                            isPresented: Binding(get: { confirmation != nil },
                                                 set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible) {
            if let confirmation {
                if confirmation.isDestructive {
                    Button(confirmation.buttonTitle, role: .destructive) { perform(confirmation) }
                } else {
                    Button(confirmation.buttonTitle) { perform(confirmation) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(confirmation?.detail ?? "")
        }
    }

    @ViewBuilder private var savedPlaces: some View {
        if session.savedPinRecoveryCount > 0 {
            Section {
                Button("Export saved-place recovery copies") {
                    if let data = session.savedPinRecoveryExport { document.data = data; exporting = true }
                }.accessibilityIdentifier("recovery.export")
                if let places = session.savedPinRecovery {
                    placeRows(places)
                    Button("Restore saved places") { confirmation = .restoreSaved }
                        .frame(minHeight: 44)
                    Button("Discard saved-place recovery copy", role: .destructive) {
                        confirmation = .discardSaved
                    }.frame(minHeight: 44)
                } else {
                    Text("The preserved saved-place copy could not be read. The current library is unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Discard unreadable recovery copy", role: .destructive) {
                        confirmation = .discardSaved
                    }.frame(minHeight: 44)
                }
            } header: {
                Text("Saved places")
            } footer: {
                Text("Export keeps the original bytes for troubleshooting. Restore is available only if a copy can be read. Discard removes the copies and any unreadable original; readable saved places stay unchanged.")
            }.shiftSettingsRows()
        }
    }

    @ViewBuilder private var recentPlaces: some View {
        if session.recentPinRecoveryCount > 0 {
            Section {
                Button("Export recent-location recovery copies") {
                    if let data = session.recentPinRecoveryExport { document.data = data; exporting = true }
                }
                if let places = session.recentPinRecovery {
                    placeRows(places)
                    if session.preferences.saveRecentLocations {
                        Button("Restore recent locations") { confirmation = .restoreRecent }
                            .frame(minHeight: 44)
                    } else {
                        Text("Recent locations are turned off in Privacy, so restoring is unavailable. Turn that setting on first if you want to keep them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Discard recent-location recovery copy", role: .destructive) {
                        confirmation = .discardRecent
                    }.frame(minHeight: 44)
                } else {
                    Text("The preserved recent-location copy could not be read. Current recent locations are unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Discard unreadable recovery copy", role: .destructive) {
                        confirmation = .discardRecent
                    }.frame(minHeight: 44)
                }
            } header: {
                Text("Recent locations")
            } footer: {
                Text("Recent locations are local history and are not included in backups. Discarding this copy does not change your saved places.")
            }.shiftSettingsRows()
        }
    }

    private func placeRows(_ places: [SavedPlace]) -> some View {
        ForEach(Array(places.enumerated()), id: \.offset) { entry in
            let place = entry.element
            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName)
                Text(verbatim: String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 44)
        }
    }

    private func perform(_ action: RecoveryAction) {
        switch action {
        case .restoreSaved:
            message = session.restoreSavedPinRecovery()
                ? "Saved places restored from the recovery copy."
                : "Couldn't restore this copy within the saved-place limits. Export it to keep all entries. The current library is unchanged."
        case .restoreRecent:
            message = session.restoreRecentPinRecovery()
                ? "Recent locations restored using your history limits. The full recovery copy is still available to export."
                : "Couldn't restore the recent-location recovery copy. Current recent locations are unchanged."
        case .discardSaved:
            session.discardSavedPinRecovery()
            message = "Saved-place recovery copy discarded. Your current library is unchanged."
        case .discardRecent:
            session.discardRecentPinRecovery()
            message = "Recent-location recovery copy discarded. Current recent locations are unchanged."
        }
    }
}

private enum RecoveryAction: String, Identifiable {
    case restoreSaved, restoreRecent, discardSaved, discardRecent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .restoreSaved, .restoreRecent: return "Restore from recovery copy?"
        case .discardSaved, .discardRecent: return "Discard recovery copy?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .restoreSaved, .restoreRecent: return "Restore"
        case .discardSaved, .discardRecent: return "Discard"
        }
    }

    var detail: String {
        switch self {
        case .restoreSaved:
            return "This replaces the current saved-place library with the readable copy. Other recovery copies stay available to export."
        case .restoreRecent:
            return "This replaces recent locations using your current history limits. The full recovery copy stays available to export."
        case .discardSaved:
            return "This removes all saved-place recovery copies and any unreadable original. Readable saved places stay unchanged. Export a copy first if you want to keep it."
        case .discardRecent:
            return "This removes all recent-location recovery copies and any unreadable original. Readable recent locations stay unchanged."
        }
    }

    var isDestructive: Bool {
        switch self {
        case .discardSaved, .discardRecent: return true
        case .restoreSaved, .restoreRecent: return false
        }
    }
}

private struct SavedPlaceRecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init() {}
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
