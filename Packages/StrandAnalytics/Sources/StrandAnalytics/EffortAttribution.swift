import Foundation

/// Splits a day's Effort between its workouts and everyday movement.
///
/// Effort is a logarithm of the day's heart-rate load (`StrainScorer`): `effort = 100 * ln(1 + load) / ln(D)`. Loads add up,
/// Effort points do not (two sessions of Effort 40 do not make 80). So the split is done on the load: each workout's stored
/// Effort is turned back into its load, whatever load the day has beyond the workouts is everyday movement, and each source gets
/// its share of the day's Effort. If the workouts' loads add up to more than the day's (their windows overlap the day's
/// measurement), they are scaled down to fit, so the parts always add up to the day's Effort.
public enum EffortAttribution {

    public struct Split: Sendable, Equatable {
        /// Effort points per workout, in the order given (0 for a workout without Effort).
        public let workoutPoints: [Double]
        /// Effort points not explained by a workout.
        public let dailyPoints: Double
        public var total: Double { workoutPoints.reduce(0, +) + dailyPoints }
    }

    /// - Parameters:
    ///   - dayEffort: the day's Effort, 0...100.
    ///   - workoutEfforts: each workout's stored Effort (nil or 0 when it has none).
    ///   - logDenominator: `StrainScorer.logMapDenominator(method:sex:)` for the Effort method in use.
    public static func split(dayEffort: Double, workoutEfforts: [Double?], logDenominator: Double) -> Split {
        guard dayEffort > 0, logDenominator > 1 else {
            return Split(workoutPoints: workoutEfforts.map { _ in 0 }, dailyPoints: 0)
        }
        let lnD = log(logDenominator)
        func load(_ e: Double) -> Double { exp(min(max(e, 0), 100) / 100 * lnD) - 1 }
        let total = load(dayEffort)
        let loads = workoutEfforts.map { ($0 ?? 0) > 0 ? load($0!) : 0 }
        let sum = loads.reduce(0, +)
        let k = sum > total ? total / sum : 1
        let points = loads.map { $0 * k / total * dayEffort }
        let daily = max(0, total - sum * k) / total * dayEffort
        return Split(workoutPoints: points, dailyPoints: daily)
    }
}
