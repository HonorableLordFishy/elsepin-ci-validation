import Foundation

enum RemoteCheckLifecyclePolicy {
    /// Idle refreshLifecycle calls are common after every confirmed location
    /// write. They must not repeatedly cancel notifications or clear state.
    static func needsTeardown(monitoring: Bool, hasTask: Bool, hasResponse: Bool,
                              hasNetwork: Bool, checking: Bool) -> Bool {
        monitoring || hasTask || hasResponse || hasNetwork || checking
    }
}
