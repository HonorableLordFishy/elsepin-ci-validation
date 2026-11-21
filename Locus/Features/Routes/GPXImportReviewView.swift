import SwiftUI

struct GPXImportReviewView: View {
    @ObservedObject var model: GPXImportReviewModel
    var onImport: ([RoutePoint]) -> Void
    var body: some View {
        NavigationStack {
            List {
                if model.loading {
                    ProgressView("Reading GPX…").accessibilityIdentifier("gpx.loading")
                } else if let error = model.error {
                    Section {
                        Text(error).accessibilityIdentifier("gpx.error")
                        Button("Try again") { model.retry() }.accessibilityIdentifier("gpx.retry")
                    }
                } else if let document = model.document {
                    Section("Path") {
                        Picker("Path", selection: $model.pathIndex) {
                            ForEach(Array(document.paths.enumerated()), id: \.offset) { index, path in
                                Text(path.name).tag(index)
                            }
                        }.accessibilityIdentifier("gpx.path")
                        if let path = model.selectedPath, path.hasGaps {
                            Picker("Sections", selection: $model.segmentIndex) {
                                ForEach(path.segments.indices, id: \.self) { index in
                                    Text("Section \(index + 1)").tag(index)
                                }
                                Text("Connect all sections").tag(-1)
                            }.accessibilityIdentifier("gpx.sections")
                            Text(model.segmentIndex == -1
                                 ? "Gaps will be connected with straight lines. These connections aren't verified roads or paths."
                                 : "This track has separate sections. Choose one, or explicitly connect them.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if model.selectedPath?.kind == .waypoints {
                            Text("Waypoints will be connected in file order with straight lines, not road directions.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("\(model.selectedPoints.count) points").foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Use this path") { if let points = model.takePoints() { onImport(points) } }
                            .disabled(!model.canImport).accessibilityIdentifier("gpx.apply")
                    } footer: {
                        Text("Opens this path in the route planner. Your saved routes stay unchanged. Importing never starts movement.")
                    }
                }
            }
            .shiftSettingsScreen()
            .navigationTitle("Import GPX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { model.cancel() }.accessibilityIdentifier("gpx.cancel")
            } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in model.interrupt() }
    }
}
