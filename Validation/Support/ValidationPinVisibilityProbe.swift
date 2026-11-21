#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Map validation probes must never compile into a device app")
#endif
import SwiftUI
import UIKit

enum ValidationGestureTrace {
    static func record(_ value: String) {
        let previous = UserDefaults.standard.string(forKey: "validation.gestureTrace") ?? ""
        UserDefaults.standard.set(String((previous + " | " + value).suffix(1800)), forKey: "validation.gestureTrace")
    }
}

struct ValidationGestureTraceView: View {
    @AppStorage("validation.gestureTrace") private var trace = "No gesture events"
    var body: some View {
        Text(trace).font(.system(size: 8)).lineLimit(8)
            .accessibilityIdentifier("validation.gestureTrace").allowsHitTesting(false)
    }
}

/// Records the production map's actual filtered pins. Counters advance only in
/// its continuous callback, never in its settled callback or synthetic engine.
@MainActor final class ValidationPinVisibilityProbe: ObservableObject {
    @Published var width: Double = 0
    @Published var pins = 0
    @Published var liveShows = 0
    @Published var liveHides = 0
    @Published var settled = 0
    func record(width: Double?, pins: Int, continuous: Bool) {
        if continuous {
            if self.pins == 0 && pins > 0 { liveShows += 1 }
            if self.pins > 0 && pins == 0 { liveHides += 1 }
        }
        let miles = (width ?? 0) / SavedPinVisibility.metersPerMile
        if self.width != miles { self.width = miles }
        if self.pins != pins { self.pins = pins }
    }
    func didSettle() { settled += 1 }
}

struct ValidationPinVisibilityControls: View {
    @ObservedObject var probe: ValidationPinVisibilityProbe
    let move: (String) -> Void
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("PIN TEST")
                Text(String(format: "%.3f", probe.width)).accessibilityIdentifier("validation.pinWidth")
                Text(String(probe.pins)).accessibilityIdentifier("validation.pinCount")
                Text(String(probe.liveShows)).accessibilityIdentifier("validation.pinLiveShows")
                Text(String(probe.liveHides)).accessibilityIdentifier("validation.pinLiveHides")
                Text(String(probe.settled)).accessibilityIdentifier("validation.pinSettled")
            }
            HStack {
                ForEach(["near", "edge", "rotate"], id: \.self) { action in
                    Button { move(action) } label: {
                        Text(action).frame(width: 54, height: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("validation.pin." + action)
                }
            }
        }.font(.system(size: 10)).padding(4).background(.yellow).foregroundStyle(.black)
    }
}

/// Gives XCTest a small, unobstructed rectangle for its two-finger gesture.
/// Touches pass through to the real MapKit map; no gesture is simulated in code.
struct ValidationPinchSurface: UIViewRepresentable {
    final class Surface: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "validation.pinchSurface"
        view.accessibilityLabel = "Map pinch test area"
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: Surface, context: Context) {}
}
