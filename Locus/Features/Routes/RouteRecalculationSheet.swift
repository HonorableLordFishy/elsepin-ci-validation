import SwiftUI

/// An explicit replacement of the draft's directions, never an active trip or
/// a Library write. Reuse the planner's normal failure/restore handling.
struct RouteRecalculationSheet: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var preferences: SessionPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TravelMode
    @State private var speed: Double?
    let onRecalculate: (RouteLegChoice) -> Void

    init(mode: TravelMode, onRecalculate: @escaping (RouteLegChoice) -> Void) {
        _mode = State(initialValue: mode)
        self.onRecalculate = onRecalculate
    }

    private var chosenSpeed: Double { speed ?? session.usualSpeedMPH(for: mode) }

    var body: some View {
        List {
            Section {
                ForEach(TravelMode.allCases) { item in
                    Button {
                        guard mode != item else { return }
                        mode = item
                        speed = session.usualSpeedMPH(for: item)
                    } label: {
                        HStack {
                            Label(item.title, systemImage: item.icon)
                            Spacer()
                            if mode == item { Image(systemName: "checkmark").foregroundStyle(LocusTheme.accent) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == item ? .isSelected : [])
                }
            } footer: {
                Text("New directions through the same start, stops and destination. All legs use this mode; names and waits stay the same.")
            }.shiftSettingsRows()
            Section {
                LabeledContent("Speed", value: preferences.speedUnit.formatted(mph: chosenSpeed))
                SpeedSlider(mph: Binding(get: { chosenSpeed }, set: { speed = $0 }), mode: mode)
            }.shiftSettingsRows()
            Section {
                Button("Recalculate route") {
                    onRecalculate(.init(mode: mode, speedMPH: mode.clampedSpeedMPH(chosenSpeed)))
                    dismiss()
                }.accessibilityIdentifier("route.recalculate.confirm")
            } footer: {
                Text("Drawn and imported paths may change. Your Library copy stays unchanged until you save.")
            }.shiftSettingsRows()
        }
        .shiftSettingsScreen()
        .loggedNavigationTitle("Recalculate route")
        .navigationBarTitleDisplayMode(.inline)
    }
}
