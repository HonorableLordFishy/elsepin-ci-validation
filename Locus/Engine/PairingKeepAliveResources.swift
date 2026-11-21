import CoreLocation
import UIKit

/// Own global pairing keep-alives separately from the screen/service lifetime.
/// A replacement stops the old owner synchronously, before activating itself.
/// Its predecessor's delayed deinit cleanup therefore cannot stop the new owner.
@MainActor
final class PairingKeepAliveResources {
    private static var active: PairingKeepAliveResources?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var previousIdleTimerDisabled = false
    private let location = PairingLocationKeepAlive()
    private let audio = SilentAudioKeepAlive()

    func start(onExpired: @escaping @MainActor () -> Void) {
        guard Self.active !== self else { return }
        Self.active?.stop()
        Self.active = self
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        location.start()
        audio.start()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "locus.pairable-host") {
            onExpired()
        }
    }

    func stop() {
        guard Self.active === self else { return }
        Self.active = nil
        location.stop()
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}

@MainActor
private final class PairingLocationKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}
