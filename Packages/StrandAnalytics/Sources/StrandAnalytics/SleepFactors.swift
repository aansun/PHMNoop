import Foundation

// SleepFactors.swift - do the evening habits the wearer logs (alcohol, late caffeine, a meal close to bedtime) move their night?
//
// Pure and DB-free. A journal answer for day D is about the evening of D, so it belongs to the night that ends on the morning of D+1.
// For each habit, the nights that followed a "yes" are split from the nights that followed a "no" (a day never answered is neither,
// exactly as `BehaviorInsights.effect` treats it), and Rest is compared between the two groups. A habit is named as a cause of a
// night only when the wearer's OWN nights show it costing Rest; the textbook claim alone is never enough.

public enum SleepFactorKind: String, CaseIterable, Equatable, Sendable {
    case alcohol, lateCaffeine, lateMeal
}

public enum SleepFactors {

    /// Nights with the habit, and without it, needed before a difference is called a pattern.
    public static let minNights = 3
    /// Rest points the habit must cost, on average, to be named.
    public static let minCostPoints = 4.0

    public struct Entry: Equatable, Sendable {
        public let day: String
        public let question: String
        public let yes: Bool
        public init(day: String, question: String, yes: Bool) { self.day = day; self.question = question; self.yes = yes }
    }

    public struct Evidence: Equatable, Sendable {
        public let kind: SleepFactorKind
        public let nYes: Int
        public let nNo: Int
        /// Mean Rest after a "yes" minus mean Rest after a "no", in points (negative: the habit costs Rest). Nil without both groups.
        public let restDelta: Double?
        /// The difference clears `BehaviorInsights`' own significance bar (p < 0.05 and at least five nights each way).
        public let significant: Bool

        /// True when the wearer's own nights show the habit costing Rest.
        public var costsRest: Bool {
            guard nYes >= SleepFactors.minNights, nNo >= SleepFactors.minNights, let d = restDelta else { return false }
            return d <= -SleepFactors.minCostPoints
        }
    }

    public static func kind(ofQuestion question: String) -> SleepFactorKind? {
        let q = question.lowercased()
        if q.contains("alcohol") { return .alcohol }
        if q.contains("caffeine") && q.contains("late") { return .lateCaffeine }
        if q.contains("close to bedtime") || q.contains("late meal") { return .lateMeal }
        return nil
    }

    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The key of the morning after `day` (the wake day of the night that follows it).
    public static func nextDay(_ day: String) -> String? {
        guard let d = keyFormatter.date(from: day), let n = utc.date(byAdding: .day, value: 1, to: d) else { return nil }
        return keyFormatter.string(from: n)
    }

    /// Per habit: the groups of nights and the Rest difference between them.
    /// - Parameter restByWakeDay: Rest (0...100) keyed by the day the night ended.
    public static func evidence(journal: [Entry], restByWakeDay: [String: Double]) -> [Evidence] {
        var yesNights: [SleepFactorKind: Set<String>] = [:], noNights: [SleepFactorKind: Set<String>] = [:]
        for e in journal {
            guard let kind = kind(ofQuestion: e.question), let wake = nextDay(e.day) else { continue }
            if e.yes { yesNights[kind, default: []].insert(wake) } else { noNights[kind, default: []].insert(wake) }
        }
        return SleepFactorKind.allCases.map { kind in
            let yes = yesNights[kind] ?? [], no = (noNights[kind] ?? []).subtracting(yes)
            let effect = BehaviorInsights.effect(behaviorDays: yes, controlDays: no, outcomeByDay: restByWakeDay,
                                                 behavior: kind.rawValue, outcome: "Rest")
            return Evidence(kind: kind, nYes: effect?.nWith ?? 0, nNo: effect?.nWithout ?? 0,
                            restDelta: effect?.delta, significant: effect?.significant ?? false)
        }
    }

    /// The habits the journal says the wearer indulged in the evening before the night that ended on `wakeDay`.
    public static func loggedYes(journal: [Entry], wakeDay: String) -> Set<SleepFactorKind> {
        var out = Set<SleepFactorKind>()
        for e in journal where e.yes {
            if let k = kind(ofQuestion: e.question), nextDay(e.day) == wakeDay { out.insert(k) }
        }
        return out
    }
}
