import Foundation

/// Presentation only: these states never authorize movement or change a draft.
enum RoutePlanningReadiness: Equatable {
    case choosingPlaces, finding, ready, needsDirections, failed

    static func resolve(hasOrigin: Bool, hasDestination: Bool, hasRoute: Bool,
                        isLoading: Bool, hasError: Bool) -> Self {
        if isLoading { return .finding }
        if hasRoute { return .ready }
        guard hasOrigin && hasDestination else { return .choosingPlaces }
        return hasError ? .failed : .needsDirections
    }

    var offersDirections: Bool { self == .failed || self == .needsDirections }

    func guidance(nextRoute: Bool, cyclingUnavailable: Bool) -> String {
        switch self {
        case .choosingPlaces: return "Choose a start and destination."
        case .finding: return "Building your preview. No movement has started."
        case .ready: return nextRoute ? "Returns to next-route setup." : "Next: tap Start route on the map."
        case .failed, .needsDirections:
            return cyclingUnavailable
                ? "Your places are kept. Try a nearby street or path, or retry directions."
                : "Your places are kept. Find directions again or edit a stop."
        }
    }
}

enum RouteJourneyPresentation {
    /// JourneyProgress starts in .moving while the first write is still pending.
    /// Connection evidence takes priority over that optimistic worker state.
    static func subtitle(phase: SessionPhase, state: JourneyState,
                         restored: Bool, recovering: Bool) -> String {
        if phase == .stopping { return phase.title }
        if restored { return "Saved route position" }
        if recovering { return "Reconnecting route…" }
        switch phase {
        case .active: return state.title
        case .connecting: return "Starting route…"
        case .reconnecting: return "Checking connection…"
        case .unverified: return "Connection unverified"
        case .disconnected: return "Route interrupted"
        case .idle: return "Route not running"
        case .stopping: return phase.title
        }
    }
}
