import Foundation

/// An estimate of how far a treadmill session went, from the steps counted and the wearer's height: a treadmill gives the strap no
/// GPS and no speed, but a step count is known. Distance = steps x step length, where the step length is a share of the height.
///
/// Walking: about 0.413 of the height (the usual stride-to-height ratio). Running: the step lengthens with the pace, and a faster
/// pace shows as a higher cadence, so the share rises from 0.413 at 110 steps a minute to 0.70 at 180. It is an estimate: a few
/// per cent off for a steady walker, more for a runner whose stride differs from the average. The wearer can replace it with the
/// treadmill's own reading.
public enum TreadmillDistance {

    public enum Gait: Equatable, Sendable { case walk, run }

    /// Metres, or nil when there is too little to go on (under 50 steps, no duration, or no usable height).
    public static func estimateMeters(steps: Int, heightCm: Double, durationS: Double, gait: Gait) -> Double? {
        guard steps >= 50, durationS >= 30, heightCm.isFinite, (120...230).contains(heightCm) else { return nil }
        let cadence = Double(steps) / (durationS / 60)
        let share: Double
        switch gait {
        case .walk:
            share = 0.413
        case .run:
            let t = min(max((cadence - 110) / 70, 0), 1)
            share = 0.413 + t * (0.70 - 0.413)
        }
        let meters = Double(steps) * heightCm / 100 * share
        return (meters * 10).rounded() / 10
    }

    /// The gait a sport name stands for: "Treadmill walk" and walking are walks, every other treadmill or running name is a run.
    public static func gait(forSport sport: String) -> Gait {
        sport.lowercased().contains("walk") ? .walk : .run
    }
}
