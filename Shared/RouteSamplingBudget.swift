import Foundation

/// Limits interpolation, never the supplied vertices. Each segment keeps its end.
enum RouteSamplingBudget {
    static func steps(distances: [Double], spacing: Double, maximumPoints: Int = 100_000) -> [Int] {
        guard spacing.isFinite, spacing > 0,
              distances.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return [] }
        let budget = max(0, maximumPoints - distances.count - 1)
        // Clamp before converting to Int, including pathological tiny spacing.
        let extras = distances.map { Int(min(Double(budget), max(0, ceil($0 / spacing) - 1))) }
        let total = extras.reduce(0.0) { $0 + Double($1) }
        guard total > Double(budget) else { return extras.map { $0 + 1 } }
        let scale = Double(budget) / total
        return extras.map { 1 + Int((Double($0) * scale).rounded(.down)) }
    }
}
