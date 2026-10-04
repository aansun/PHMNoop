import Foundation

/// A suggested session for today, worked out only from numbers the phone already has: Charge, yesterday's Effort, the
/// acute-to-chronic load band and the wearer's heart-rate zones. It is a suggestion, never a prescription, and every
/// line of the reasoning cites the figure it came from. Nothing is invented: the Effort estimate is the wearer's own median
/// Effort per minute, and is left out when there are too few sessions to take a median.
public enum DayPlan {

    public enum Kind: String, Sendable, Equatable { case recovery, easy, steady, quality }

    public struct Step: Sendable, Equatable {
        public enum Phase: String, Sendable { case warmup, main, cooldown }
        public let phase: Phase
        public let minutes: Int
        /// Heart-rate zone the step aims at (1...5).
        public let zone: Int
    }

    public struct Plan: Sendable, Equatable {
        public let kind: Kind
        public let totalMinutes: Int
        /// The zone most of the session is spent in.
        public let mainZone: Int
        public let steps: [Step]
        /// Estimated Effort on the stored 0-100 axis, from the wearer's own sessions. Nil without enough history.
        public let effortLow: Double?
        public let effortHigh: Double?
    }

    /// Minutes of the main block and the zone, by kind.
    static func shape(_ kind: Kind) -> (warm: Int, main: Int, cool: Int, warmZone: Int, mainZone: Int) {
        switch kind {
        case .recovery: return (4, 12, 4, 1, 1)
        case .easy:     return (6, 20, 4, 1, 2)
        case .steady:   return (8, 28, 6, 1, 2)
        case .quality:  return (10, 24, 8, 2, 4)
        }
    }

    /// Chooses the kind of session.
    /// - `charge`: today's Charge, 0-100.
    /// - `yesterdayEffort`: stored 0-100 Effort for yesterday, if any.
    /// - `usualEffort`: the wearer's typical daily Effort (a median), if known; a hard yesterday is judged against it.
    /// - `loadBand`: the acute-to-chronic band from `TrendInsights.loadBand`.
    public static func kind(charge: Double, yesterdayEffort: Double?, usualEffort: Double?, loadBand: TrendInsights.LoadBand?) -> Kind {
        if charge < 34 || loadBand == .excessive { return .recovery }
        let hardYesterday = { () -> Bool in
            guard let y = yesterdayEffort, let u = usualEffort, u > 0 else { return false }
            return y >= u * 1.5
        }()
        if charge < 67 || loadBand == .high || hardYesterday { return charge < 50 ? .easy : .steady }
        return .quality
    }

    /// - `effortPerMinute`: the wearer's own Effort per minute of training (stored axis), as medians of past sessions. Pass the
    ///   per-session values; a median is taken here and the result is left nil under 3 sessions.
    public static func plan(charge: Double, yesterdayEffort: Double?, usualEffort: Double?, loadBand: TrendInsights.LoadBand?,
                            effortPerMinute: [Double]) -> Plan {
        let k = kind(charge: charge, yesterdayEffort: yesterdayEffort, usualEffort: usualEffort, loadBand: loadBand)
        let s = shape(k)
        let total = s.warm + s.main + s.cool
        let steps = [Step(phase: .warmup, minutes: s.warm, zone: s.warmZone),
                     Step(phase: .main, minutes: s.main, zone: s.mainZone),
                     Step(phase: .cooldown, minutes: s.cool, zone: 1)]
        var lo: Double?, hi: Double?
        let usable = effortPerMinute.filter { $0.isFinite && $0 > 0 }.sorted()
        if usable.count >= 3 {
            let median = usable[usable.count / 2]
            // An easier zone earns less Effort per minute than the wearer's typical session, a harder one more.
            let factor: Double = { switch k { case .recovery: return 0.4; case .easy: return 0.7; case .steady: return 1.0; case .quality: return 1.4 } }()
            let mid = median * Double(total) * factor
            lo = mid * 0.8; hi = mid * 1.2
        }
        return Plan(kind: k, totalMinutes: total, mainZone: s.mainZone, steps: steps, effortLow: lo, effortHigh: hi)
    }
}
