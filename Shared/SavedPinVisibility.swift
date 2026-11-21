import Foundation

/// Visibility follows the ground span of the map, never camera altitude or the
/// distance from the phone. The wider default includes neighborhood overviews.
/// Selected pins, route markers and the simulated location are separate layers.
enum SavedPinVisibility {
    static let rangeMiles = 0.5...20.0
    static let defaultMiles = 5.0
    static let metersPerMile = 1_609.344

    static func boundedMiles(_ value: Double) -> Double {
        value.isFinite ? min(rangeMiles.upperBound, max(rangeMiles.lowerBound, value)) : defaultMiles
    }

    /// Extrapolate a short horizontal sample at screen center. A camera's map
    /// rect is an axis-aligned bounding box, not its screen width when rotated.
    static func mapWidthMeters(sampleMeters: Double, samplePoints: Double, viewportPoints: Double) -> Double? {
        guard sampleMeters.isFinite, sampleMeters > 0, samplePoints.isFinite,
              samplePoints > 0, viewportPoints.isFinite, viewportPoints >= samplePoints else { return nil }
        let meters = sampleMeters * (viewportPoints / samplePoints)
        guard meters.isFinite else { return nil }
        return meters
    }

    static func isVisible(mapWidthMeters: Double?, maximumMiles: Double) -> Bool {
        guard let mapWidthMeters, mapWidthMeters.isFinite, mapWidthMeters > 0 else { return false }
        return mapWidthMeters <= boundedMiles(maximumMiles) * metersPerMile
    }

    static func label(miles: Double) -> String {
        "\(miles.formatted(.number.precision(.fractionLength(0...1)))) mi across"
    }
}

/// Crossing the cutoff is immediate in either direction. Only repeated spatial
/// filtering while panning is throttled; a settled camera always gets a final pass.
struct SavedPinRefreshCadence {
    static let interval: TimeInterval = 0.1
    private var lastRefresh: TimeInterval?
    private var lastVisibility: Bool?

    mutating func shouldRefresh(visible: Bool, now: TimeInterval, force: Bool = false) -> Bool {
        let elapsed = now - (lastRefresh ?? -.infinity)
        guard force || lastVisibility != visible || (visible && elapsed >= Self.interval) else { return false }
        lastRefresh = now
        lastVisibility = visible
        return true
    }
}
