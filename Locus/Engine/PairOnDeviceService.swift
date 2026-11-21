import Foundation
import idevice
import UIKit
import UserNotifications
import CoreLocation
import Network

/// Runs idevice's iOS 27+ pairable-host flow on-device.
///
/// Advertising uses Network.framework NWListener (Bonjour). Inbound TCP is
/// relayed to the Rust pairable-host on loopback. The 6-digit PIN is created
/// only after that connection + pair-setup handshake.
@MainActor
final class PairOnDeviceService: ObservableObject {
    nonisolated private static let workerGate = AppResetWorkGate()
    private static weak var currentService: PairOnDeviceService?
    static var nativeWorkOutstanding: Bool { workerGate.isBusy }
    enum Phase: Equatable {
        case idle
        case stopping
        case advertising
        case deviceConnected
        case awaitingPIN(String)
        case succeeded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pin: String?
    @Published private(set) var debugPort: UInt16?

    private var worker: Thread?
    private var callbackBox: PairCallbackBox?
    private var restartTask: Task<Void, Never>?
    private var activityOwner: UUID?
    private var activityVisibilityTask: Task<Void, Never>?
    private var pinNotificationIdentifier = "locus.pairing.pin.\(UUID().uuidString)"
    private var pinNotificationActive = false
    private let keepAlive = PairingKeepAliveResources()
    private let advertiser = PairableHostAdvertiser()

    deinit {
        restartTask?.cancel()
        activityVisibilityTask?.cancel()
        // Deinitialization is not guaranteed to run on the main actor. Capture
        // only the resources, never the disappearing service itself.
        let box = callbackBox, resources = keepAlive, advertiser = advertiser
        let owner = activityOwner, identifier = pinNotificationIdentifier
        Task { @MainActor in
            box?.cancel()
            box?.owner = nil
            advertiser.stop()
            resources.stop()
            if let owner { SessionActivityController.shared.endPairing(owner: owner) }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    var isBusy: Bool {
        switch phase {
        case .stopping, .advertising, .deviceConnected, .awaitingPIN: return true
        default: return false
        }
    }

    func start(pairingStore: PairingStore, preferences: SessionPreferences) {
        guard !isBusy else { return }
        DeveloperLogStore.shared.record("pairing_start_requested")
        // A pairing file can be imported from another screen or via Open In.
        // There must only ever be one native accept worker in this process.
        Self.currentService?.resetToIdle()
        Self.currentService = self
        guard Self.workerGate.begin() else {
            DeveloperLogStore.shared.record("pairing_waiting_for_cleanup")
            phase = .stopping
            restartTask = Task { [weak self] in
                // Bounded cleanup wait, not an indefinite busy/polling state.
                for _ in 0..<50 {
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return }
                    guard let self, !Task.isCancelled else { return }
                    if !Self.workerGate.isBusy {
                        self.restartTask = nil
                        self.phase = .idle
                        self.start(pairingStore: pairingStore, preferences: preferences)
                        return
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.restartTask = nil
                self.phase = .failed("Elsepin could not finish stopping the previous attempt. Close and reopen Elsepin, then try pairing again. Your saved pairing has not changed.")
                DeveloperLogStore.shared.record("pairing_cleanup_timeout")
            }
            return
        }
        phase = .advertising
        pin = nil
        debugPort = nil
        pinNotificationIdentifier = "locus.pairing.pin.\(UUID().uuidString)"
        // A distinct box per attempt prevents a late native callback from an old
        // attempt attaching itself to a new attempt after Cancel/Retry.
        let box = PairCallbackBox(pairingStore: pairingStore)
        box.owner = self
        callbackBox = box

        if preferences.liveActivities {
            let owner = UUID()
            activityOwner = owner
            let state = PairingActivity(stage: .waiting, now: Date())
            SessionActivityController.shared.beginPairing(owner: owner, state: state,
                style: preferences.visualStyle.rawValue, icon: preferences.iconSelection.design.rawValue)
            scheduleActivityExpiry(owner: owner)
        }

        requestNotificationPermission()
        beginKeepAlive()

        _ = pairingStore.pairingURL
        try? FileManager.default.createDirectory(
            at: pairingStore.pairingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // The worker never writes the live pairing. Only the current attempt
        // may validate and install its staged result on the main actor.
        let outputPath = box.stagedURL.path
        _ = box.nativeWork.begin()

        worker = Thread {
            defer {
                box.nativeWork.end()
                Self.workerGate.end()
                DispatchQueue.main.async { box.workerFinished() }
            }
            autoreleasepool {
                Self.runBlockingAccept(outputPath: outputPath, box: box)
            }
        }
        worker?.name = "locus.pairable-host"
        worker?.qualityOfService = .userInitiated
        worker?.start()
    }

    func acknowledgeFailure() {
        if case .failed = phase {
            teardown()
            phase = .idle
            pin = nil
        }
    }

    func resetToIdle() {
        if isBusy { DeveloperLogStore.shared.record("pairing_cancel_requested") }
        restartTask?.cancel()
        restartTask = nil
        teardown()
        phase = .idle
        pin = nil
        debugPort = nil
    }

    /// Called after a valid file import, or before explicit pairing removal.
    /// Invalid imports deliberately leave the current pairing attempt untouched.
    static func cancelCurrentAttempt() {
        currentService?.resetToIdle()
    }

    fileprivate func handleListening(
        port: UInt16,
        serviceIdentifier: String,
        name: String,
        model: String,
        authTag: String,
        ver: String,
        minVer: String
    ) {
        guard isBusy else { return }
        debugPort = port
        phase = .advertising
        advertiser.publish(
            port: port,
            serviceIdentifier: serviceIdentifier,
            name: name,
            model: model,
            authTag: authTag,
            ver: ver,
            minVer: minVer,
            onFailure: { [weak self] message in self?.handleFailure(message) }
        )
        NSLog("[Elsepin] listening on %u, Bonjour id=%@", port, serviceIdentifier)
    }

    fileprivate func handleConnected() {
        guard isBusy else { return }
        phase = .deviceConnected
        updateActivity(stage: .connected)
        Self.postPlainNotification(
            title: "Elsepin connected",
            body: "Generating pairing code…"
        )
    }

    fileprivate func handlePIN(_ value: String) {
        guard isBusy else { return }
        guard PairingActivity.validCode(value) else {
            handleFailure("Pairing did not return a valid six-digit code. Try again.")
            return
        }
        pin = value
        phase = .awaitingPIN(value)
        updateActivity(stage: .code, code: value)
        postPINNotification(value)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    fileprivate func handleSuccess(_ box: PairCallbackBox) {
        guard callbackBox === box, box.state.acceptsCallbacks else { return }
        guard let store = box.pairingStore,
              box.state.canInstall(startingRevision: box.startingRevision, currentRevision: store.revision) else {
            handleFailure("Your saved pairing changed during this attempt. Use the saved pairing or start a new attempt.")
            return
        }
        do {
            try store.installOnDevicePairing(from: box.stagedURL)
        } catch {
            handleFailure("Pairing could not be saved. \(error.localizedDescription)")
            return
        }
        box.state.finish()
        pin = nil
        phase = .succeeded
        teardown()
        Self.postPlainNotification(
            title: "Elsepin paired",
            body: "RPPairing is ready. Connect LocalDevVPN, then teleport."
        )
    }

    fileprivate func handleFailure(_ message: String) {
        guard isBusy else { return }
        DeveloperLogStore.shared.record("pairing_failed")
        pin = nil
        phase = .failed(message)
        teardown()
    }

    private func teardown() {
        callbackBox?.cancel()
        callbackBox?.owner = nil
        callbackBox = nil
        finishActivity()
        clearPINNotification()
        advertiser.stop()
        endKeepAlive()
        if Self.currentService === self { Self.currentService = nil }
    }

    private func updateActivity(stage: PairingActivity.Stage, code: String? = nil) {
        guard let owner = activityOwner else { return }
        SessionActivityController.shared.updatePairing(owner: owner,
            state: PairingActivity(stage: stage, code: code, now: Date()))
        scheduleActivityExpiry(owner: owner)
    }

    private func scheduleActivityExpiry(owner: UUID) {
        activityVisibilityTask?.cancel()
        // One sleep per pairing event, never a polling loop. The extension also
        // hides stale codes if iOS suspends this cleanup task. This is a display
        // lifetime, not a claim about the native protocol's code validity.
        activityVisibilityTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(PairingActivity.visibilityLifetime)) }
            catch { return }
            guard let self, self.activityOwner == owner else { return }
            self.finishActivity()
            self.clearPINNotification()
        }
    }

    private func finishActivity() {
        activityVisibilityTask?.cancel()
        activityVisibilityTask = nil
        if let owner = activityOwner { SessionActivityController.shared.endPairing(owner: owner) }
        activityOwner = nil
    }

    private func clearPINNotification() {
        pinNotificationActive = false
        let center = UNUserNotificationCenter.current()
        let identifiers = [pinNotificationIdentifier, "locus.pairing.pin"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func beginKeepAlive() {
        keepAlive.start { [weak self] in
            self?.handleFailure("Pairing ran out of background time. Return to Elsepin and try again. Your saved pairing has not changed.")
        }
    }

    private func endKeepAlive() {
        keepAlive.stop()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postPINNotification(_ pin: String) {
        pinNotificationActive = true
        let identifier = pinNotificationIdentifier
        let content = UNMutableNotificationContent()
        content.title = "Elsepin pairing code"
        content.body = pin
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] _ in
            // Notification submission is asynchronous too. A late completion
            // must not leave a cancelled code behind or clear a newer attempt.
            Task { @MainActor in
                guard let self, self.isBusy, self.pinNotificationActive,
                      self.pinNotificationIdentifier == identifier else {
                    let center = UNUserNotificationCenter.current()
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                    return
                }
            }
        }
    }

    private static func postPlainNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "locus.pairing.status.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated private static func runBlockingAccept(outputPath: String, box: PairCallbackBox) {
        let name = "Elsepin"
        let model = "Mac17,7"

        var outFile: OpaquePointer?
        var altIRK = [UInt8](repeating: 0, count: 16)

        let err: UnsafeMutablePointer<IdeviceFfiError>? = name.withCString { namePtr in
            model.withCString { modelPtr in
                pairable_host_accept(
                    namePtr,
                    modelPtr,
                    0,
                    pinDisplayTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    listeningTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    connectedTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    &altIRK,
                    &outFile
                )
            }
        }

        if let err {
            let message: String
            if let cMessage = err.pointee.message {
                message = String(cString: cMessage)
            } else {
                message = "Unknown pairing error (\(err.pointee.code))"
            }
            idevice_error_free(err)
            DispatchQueue.main.async { box.owner?.handleFailure(message) }
            return
        }

        guard let outFile else {
            DispatchQueue.main.async {
                box.owner?.handleFailure("Pairing finished but no pairing file was returned.")
            }
            return
        }

        defer { rp_pairing_file_free(outFile) }

        let parent = (outputPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

        let writeError = outputPath.withCString { path in
            rp_pairing_file_write(outFile, path)
        }
        if let writeError {
            let message: String
            if let cMessage = writeError.pointee.message {
                message = String(cString: cMessage)
            } else {
                message = "Failed to write pairing file"
            }
            idevice_error_free(writeError)
            DispatchQueue.main.async {
                box.owner?.handleFailure("Paired, but failed to save file: \(message)")
            }
            return
        }

        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputPath)
        DispatchQueue.main.async { box.owner?.handleSuccess(box) }
    }
}

@MainActor
final class PairCallbackBox {
    weak var owner: PairOnDeviceService?
    weak var pairingStore: PairingStore?
    let startingRevision: UUID
    let stagedURL: URL
    nonisolated let nativeWork = AppResetWorkGate()
    var state = PairingAttemptState()
    private var wakeup: NWConnection?

    init(pairingStore: PairingStore) {
        self.pairingStore = pairingStore
        startingRevision = pairingStore.revision
        stagedURL = pairingStore.pairingURL.deletingLastPathComponent()
            .appendingPathComponent(".on-device-\(UUID().uuidString).plist")
    }

    func listening(on port: UInt16) {
        if let port = state.listening(on: port) { wakeAccept(on: port) }
    }

    func cancel() {
        if let port = state.cancel() { wakeAccept(on: port) }
    }

    func workerFinished() {
        DeveloperLogStore.shared.record("pairing_worker_finished", ["cancelled": String(state.cancelled)])
        state.finish()
        wakeup?.cancel()
        wakeup = nil
        try? FileManager.default.removeItem(at: stagedURL)
    }

    private func wakeAccept(on port: UInt16) {
        guard nativeWork.isBusy, let endpoint = NWEndpoint.Port(rawValue: port) else { return }
        // This bundled ABI has no cancellation handle. A loopback connection
        // followed by EOF releases its single blocking accept/read. If Settings
        // already connected, advertiser.stop() closes that relay instead.
        let connection = NWConnection(host: "127.0.0.1", port: endpoint, using: .tcp)
        wakeup = connection
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .ready:
                connection?.send(content: nil, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { [weak connection] _ in connection?.cancel() })
            case .failed: connection?.cancel()
            default: break
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak connection] in
            connection?.cancel()
        }
    }
}

private func pinDisplayTrampoline(pin: UnsafePointer<CChar>?, context: UnsafeMutableRawPointer?) {
    guard let pin, let context else { return }
    let value = String(cString: pin)
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        guard box.state.acceptsCallbacks else { return }
        box.owner?.handlePIN(value)
    }
}

private func listeningTrampoline(
    port: UInt16,
    serviceIdentifier: UnsafePointer<CChar>?,
    name: UnsafePointer<CChar>?,
    model: UnsafePointer<CChar>?,
    authTag: UnsafePointer<CChar>?,
    ver: UnsafePointer<CChar>?,
    minVer: UnsafePointer<CChar>?,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    let values = (
        port,
        serviceIdentifier.map { String(cString: $0) } ?? "",
        name.map { String(cString: $0) } ?? "Elsepin",
        model.map { String(cString: $0) } ?? "Mac17,7",
        authTag.map { String(cString: $0) } ?? "",
        ver.map { String(cString: $0) } ?? "26",
        minVer.map { String(cString: $0) } ?? "17"
    )
    // NetService must be touched on the main thread / runloop.
    DispatchQueue.main.async {
        box.listening(on: port)
        guard box.state.acceptsCallbacks else { return }
        box.owner?.handleListening(
            port: values.0,
            serviceIdentifier: values.1,
            name: values.2,
            model: values.3,
            authTag: values.4,
            ver: values.5,
            minVer: values.6
        )
    }
}

private func connectedTrampoline(context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        guard box.state.acceptsCallbacks else { return }
        box.owner?.handleConnected()
    }
}
