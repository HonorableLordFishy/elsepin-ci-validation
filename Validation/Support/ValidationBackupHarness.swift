#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Backup fixtures are simulator tests only")
#endif
import SwiftUI
import UIKit

/// The real exporter and importer own all backup writes/restores. This fixture
/// supplies disposable settings, changes them on request, and observes disk data.
struct ValidationBackupHarness: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var preferences: SessionPreferences
    @EnvironmentObject private var library: TripLibrary
    @StateObject private var planner = RoutePlanner()
    @State private var showing = false
    @State private var started = false
    @State private var snapshot = "{}"

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func refresh() {
        do {
            var result: [String: Any] = [
                "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.backupPreferences)),
                "tripCount": TripLibrary().trips.count, "pinCount": session.savedPins.count,
                "filesReady": FileManager.default.fileExists(atPath: documents.appendingPathComponent(".validation-files-ready").path)
            ]
            if let files = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: nil) {
                for case let file as URL in files where file.lastPathComponent.hasPrefix("Elsepin-Settings") && file.pathExtension == "json" {
                    let data = try Data(contentsOf: file)
                    let backup = try LibraryBackup.decode(data)
                    result["export"] = try JSONSerialization.jsonObject(with: data)
                    result["valid"] = backup.isValid
                    result["file"] = file.lastPathComponent
                    break
                }
            }
            snapshot = String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self)
        } catch { snapshot = "ERROR: \(error.localizedDescription)" }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("Import and export") { showing = true }
                Button("Change disposable settings") {
                    session.setUsualSpeedMPH(6, for: .walk)
                    session.setUsualSpeedMPH(1, for: .drive)
                    session.smoothMovement = false
                    preferences.mapPinSize = 22
                    preferences.mapPinVisibilityMiles = 1
                    preferences.showSavedPinsOnMap = false
                    refresh()
                }
                Button("Read settings and export") { refresh() }
                Button("Copy exported backup text") {
                    do {
                        let files = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: nil)
                        let file = (files?.allObjects as? [URL])?.first {
                            $0.lastPathComponent.hasPrefix("Elsepin-Settings") && $0.pathExtension == "json"
                        }
                        guard let file else { snapshot = "ERROR: No actual export to copy"; return }
                        UIPasteboard.general.string = try String(contentsOf: file, encoding: .utf8)
                    } catch { snapshot = "ERROR: \(error.localizedDescription)" }
                }
                Text(snapshot).font(.system(size: 7)).lineLimit(1)
                    .accessibilityIdentifier("validation.backupSnapshot")
            }.navigationTitle("Backup validation")
            .navigationDestination(isPresented: $showing) {
                // Match Settings' real navigation. A second modal shell around
                // the system document UI is not part of the production flow.
                LibraryBackupView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Close backup test") { showing = false }
                    } }
            }
        }
        // Navigation destinations share the stack's environment. Installing
        // this only on its first screen leaves the pushed review without it.
        // Production RootView supplies its planner above navigation as well.
        .environmentObject(planner)
        .task {
            guard !started else { return }; started = true
            do {
                try FileManager.default.createDirectory(at: documents.appendingPathComponent("Validation exports"), withIntermediateDirectories: true)
                if !ProcessInfo.processInfo.arguments.contains("--preserve-backup-test-data") {
                    session.setUsualSpeedMPH(4.5, for: .walk)
                    session.setUsualSpeedMPH(85, for: .drive)
                    session.smoothMovement = true
                    preferences.mapPinSize = 52
                    preferences.mapPinVisibilityMiles = 7
                    preferences.showSavedPinsOnMap = true
                    preferences.speedUnit = .mph
                }
                refresh()
            } catch { snapshot = "ERROR: \(error.localizedDescription)" }
        }
    }
}
