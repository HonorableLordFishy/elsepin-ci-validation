import Foundation

enum DiagnosticMonitorPolicy {
    /// Preserve background diagnostic coverage while recording, and stop all
    /// diagnostic monitors when logging is disabled.
    static func observesNetwork(loggingEnabled: Bool, appActive: Bool) -> Bool {
        loggingEnabled
    }
}

/// Owns callback validity and idempotent start/stop across recording toggles.
@MainActor final class DiagnosticMonitorLifecycle {
    private(set) var generation = UUID()
    private(set) var running = false
    func update(enabled: Bool, start: (UUID) -> Void, stop: () -> Void) {
        guard enabled != running else { return }
        generation = UUID(); running = enabled
        if enabled { start(generation) } else { stop() }
    }
    func accepts(_ token: UUID) -> Bool { running && token == generation }
}
