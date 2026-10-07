#if os(iOS)
import Foundation
import WhoopStore

/// How loaded each muscle still is from the last days of training, worked out from the sets that were logged. It is a rule of thumb,
/// not a measurement: the strap cannot see a muscle, so this only reads the sets back.
///
/// Every working set adds a stimulus to the muscle it was counted under (1 for the main one, ½ for the ones it also works). The
/// stimulus fades with a half-life of two days, and the total is squeezed into 0…1 with `1 - exp(-load / referenceSets)`, so a
/// big session raises the reading a lot without ever pinning it. A reading under 0.25 is ready, up to 0.55 recovering, above it
/// still fatigued. The numbers are this app's own and are only a starting point.
enum NunaMuscleReadiness {
    static let halfLifeHours = 48.0
    /// About one hard session for a muscle, in weighted sets.
    static let referenceSets = 8.0
    static let readyBelow = 0.25
    static let fatiguedAbove = 0.55
    /// A set older than this adds under 3% and is not scanned.
    static let horizonDays = 10

    enum State { case ready, recovering, fatigued }

    static func state(_ load: Double) -> State { load < readyBelow ? .ready : (load > fatiguedAbove ? .fatigued : .recovering) }

    /// The reading of every muscle that was trained inside the horizon. `sets` carry the time of the session they belong to.
    static func readings(sets: [(set: LiftSetRow, at: Int)], now: Int) -> [LiftMuscle: Double] {
        var load: [LiftMuscle: Double] = [:]
        for (s, at) in sets where !s.isWarmup {
            let ageH = Double(max(0, now - at)) / 3600
            let fade = pow(0.5, ageH / halfLifeHours)
            if let p = s.primaryMuscle { load[p, default: 0] += fade }
            for m in s.secondaryMuscles where m != s.primaryMuscle { load[m, default: 0] += 0.5 * fade }
        }
        return load.mapValues { 1 - exp(-$0 / referenceSets) }
    }
}
#endif
