import MapKit
import SwiftUI

/// Hold only the selected marker. Pans elsewhere stay with the main map.
struct MapPinAdjustmentGesture: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var pin: CLLocationCoordinate2D?
    var savedSymbolSize: Double? = nil
    var onBegan: () -> Void
    var onMoved: (CLLocationCoordinate2D) -> Void
    var onEnded: (CLLocationCoordinate2D?, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(parent: self)
    }
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.minimumPressDuration = 0.28
        hold.allowableMovement = 12
        hold.numberOfTouchesRequired = 1
        hold.cancelsTouchesInView = true
        hold.delaysTouchesBegan = false
        hold.delaysTouchesEnded = false
        hold.delegate = context.coordinator
        hold.isEnabled = enabled
        return hold
    }
    func updateUIGestureRecognizer(_ hold: UILongPressGestureRecognizer, context: Context) {
        context.coordinator.parent = self
        if hold.isEnabled != enabled { hold.isEnabled = enabled }
    }
    func handleUIGestureRecognizerAction(_ hold: UILongPressGestureRecognizer, context: Context) {
#if ELSEPIN_UI_TESTING
        ValidationGestureTrace.record("hold state \(hold.state.rawValue)")
#endif
        let coordinator = context.coordinator
        if hold.numberOfTouches > 1 {
            coordinator.finish(cancelled: true, hold: hold)
            return
        }
        switch hold.state {
        case .began:
            guard enabled, let pin, let anchor = coordinator.projected(pin) else { return }
            guard let finger = coordinator.pointer(hold) else { return }
            coordinator.offset = CGPoint(x: anchor.x - finger.x, y: anchor.y - finger.y)
            coordinator.dragging = true
            onBegan()
            onMoved(pin)
        case .changed:
            if coordinator.dragging, let point = coordinator.adjustedCoordinate(hold) { onMoved(point) }
        case .ended: coordinator.finish(cancelled: false, hold: hold)
        case .cancelled, .failed: coordinator.finish(cancelled: true, hold: hold)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapPinAdjustmentGesture
        weak var map: MKMapView?
        var offset = CGPoint.zero
        var dragging = false
        init(parent: MapPinAdjustmentGesture) {
            self.parent = parent
        }
        // UIKit delegates can outlive SwiftUI's event graph during zoom/style
        // changes. Missing native-map evidence fails the gesture; never fall
        // back to a retained MapProxy or CoordinateSpaceConverter closure.
        func pointer(_ hold: UIGestureRecognizer) -> CGPoint? {
            guard let map, map.window != nil else { return nil }
            let point = hold.location(in: map)
            return point.x.isFinite && point.y.isFinite ? point : nil
        }
        func projected(_ pin: CLLocationCoordinate2D) -> CGPoint? {
            guard let map else { return nil }
            return NativeRouteTouch(map: map, point: .zero).project(pin)
        }
        func adjustedCoordinate(_ hold: UIGestureRecognizer) -> CLLocationCoordinate2D? {
            guard let map, map.window != nil, let finger = pointer(hold) else { return nil }
            let adjusted = CGPoint(x: finger.x + offset.x, y: finger.y + offset.y)
            guard adjusted.x.isFinite, adjusted.y.isFinite, map.bounds.contains(adjusted) else { return nil }
            return NativeRouteTouch(map: map, point: adjusted).coordinate
        }
        func finish(cancelled: Bool, hold: UIGestureRecognizer) {
            guard dragging else { return }
            dragging = false
            parent.onEnded(cancelled ? nil : adjustedCoordinate(hold), cancelled)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // A second finger cancels the edit before a pinch or another
            // control can move the map underneath an active pin adjustment.
            if dragging {
                finish(cancelled: true, hold: gestureRecognizer)
                return false
            }
            map = nil
            var candidate = touch.view
            var touchedControl = false
            var insideAnnotation = false
#if ELSEPIN_UI_TESTING
            var ancestry: [String] = []
#endif
            while let view = candidate {
#if ELSEPIN_UI_TESTING
                ancestry.append(String(describing: type(of: view)))
#endif
                if view is UIControl { touchedControl = true }
                if view is MKAnnotationView { insideAnnotation = true }
                if let nativeMap = view as? MKMapView { map = nativeMap; break }
                candidate = view.superview
            }
#if ELSEPIN_UI_TESTING
            ValidationGestureTrace.record("receive \(ancestry.joined(separator: ">")) map=\(map != nil) control=\(touchedControl) annotation=\(insideAnnotation)")
#endif
            // Saved symbols are buttons hosted inside map annotations. They
            // must allow the selected-pin hold, while map controls stay excluded.
            if touchedControl && !insideAnnotation { map = nil; return false }
            return map?.window != nil
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
#if ELSEPIN_UI_TESTING
            ValidationGestureTrace.record("begin? enabled=\(parent.enabled) touches=\(gestureRecognizer.numberOfTouches) pin=\(parent.pin != nil)")
#endif
            guard parent.enabled, gestureRecognizer.numberOfTouches == 1,
                  let pin = parent.pin, let anchor = projected(pin),
                  let finger = pointer(gestureRecognizer) else { return false }
#if ELSEPIN_UI_TESTING
            ValidationGestureTrace.record("anchor=\(anchor) finger=\(finger) saved=\(String(describing: parent.savedSymbolSize))")
#endif
            return MapPinHitArea.bounds(anchor: anchor, savedSymbolSize: parent.savedSymbolSize).contains(finger)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // SwiftUI's button/annotation recognizers begin before a hold.
            // They must not prevent it; the hold still excludes map panning.
            !(other is UIPanGestureRecognizer)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            // The selected pin's shorter hold gets first refusal. If the touch
            // is outside its bounds, the ordinary context-menu hold can proceed.
            other is UILongPressGestureRecognizer
        }
    }
}

/// Exists only during a hold. It is a magnified map, not a screenshot of app UI.
struct PinMagnifier: View {
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let heading: CLLocationDirection
    let style: MapStyle
    var body: some View {
        Map(position: .constant(.camera(MapCamera(centerCoordinate: coordinate,
            distance: max(20, distance / 4), heading: heading, pitch: 0))), interactionModes: [])
            .mapStyle(style).mapControlVisibility(.hidden)
            .frame(width: 132, height: 132)
            .overlay {
                ZStack {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 12, height: 12)
                    Image(systemName: "plus").font(.system(size: 24, weight: .medium)).foregroundStyle(.black)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
