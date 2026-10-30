import Foundation

/// What the Behavior Insights pages say about each journal question: how many days it was answered yes and no, whether it moves the outcome
/// (Charge), and a calendar of what was logged on each day.
///
/// Pure and database-free. The effect itself is `BehaviorInsights.effect`; this adds the counting and the bookkeeping the pages need, and the
/// rule for when an effect may be shown at all.
public enum BehaviorSummary {

    /// Yes and No answers a behavior needs before its effect is shown (each of them), as the journal tells the wearer.
    public static let answersNeeded = 5

    /// How a day was answered.
    public enum Answer: Equatable, Sendable { case yes, no, missing }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { behavior }
        public let behavior: String
        public let yes: Int
        public let no: Int
        /// The effect on the outcome, or nil while there are fewer than `answersNeeded` of each answer inside the window.
        public let effect: BehaviorEffect?
        /// The effect as a percentage of the without-days mean, only when it is significant; otherwise nil (nothing is claimed).
        public var percent: Double? { effect.flatMap { $0.significant ? $0.pctChange : nil } }
        public var unlocked: Bool { yes >= BehaviorSummary.answersNeeded && no >= BehaviorSummary.answersNeeded }
    }

    /// The summary of every behavior that has at least one answer, from the journal's days. `answers` is behavior → day → yes/no.
    /// Only the days from `since` on (a day key, "yyyy-MM-dd") are counted.
    public static func rows(answers: [String: [String: Bool]], outcomeByDay: [String: Double], since: String, outcome: String) -> [Row] {
        var out: [Row] = []
        for (behavior, byDay) in answers {
            let inWindow = byDay.filter { $0.key >= since }
            let yesDays = Set(inWindow.filter { $0.value }.keys), noDays = Set(inWindow.filter { !$0.value }.keys)
            guard !inWindow.isEmpty else { continue }
            let effect: BehaviorEffect? = (yesDays.count >= answersNeeded && noDays.count >= answersNeeded)
                ? BehaviorInsights.effect(behaviorDays: yesDays, controlDays: noDays, outcomeByDay: outcomeByDay, behavior: behavior, outcome: outcome)
                : nil
            out.append(Row(behavior: behavior, yes: yesDays.count, no: noDays.count, effect: effect))
        }
        return out.sorted { a, b in
            // Unlocked ones first, then the biggest effect, then the name.
            if a.unlocked != b.unlocked { return a.unlocked }
            let pa = abs(a.percent ?? 0), pb = abs(b.percent ?? 0)
            if pa != pb { return pa > pb }
            return a.behavior < b.behavior
        }
    }

    /// The answer a behavior got on a day.
    public static func answer(_ byDay: [String: Bool], on day: String) -> Answer {
        guard let v = byDay[day] else { return .missing }
        return v ? .yes : .no
    }

    /// Splits the rows into those that hurt and those that help the outcome, by the sign of the significant effect.
    public static func split(_ rows: [Row]) -> (hurts: [Row], helps: [Row]) {
        let hurts = rows.filter { ($0.percent ?? 0) < 0 }.sorted { ($0.percent ?? 0) < ($1.percent ?? 0) }
        let helps = rows.filter { ($0.percent ?? 0) > 0 }.sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
        return (hurts, helps)
    }

    /// The day keys of one calendar month, "yyyy-MM-dd", and the weekday (Sunday = 0) of its first day, for a calendar drawn from Sunday.
    public static func month(year: Int, month: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> (days: [String], firstWeekday: Int)? {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = calendar.date(from: comps), let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let weekday = calendar.component(.weekday, from: first) - 1
        let days = range.map { String(format: "%04d-%02d-%02d", year, month, $0) }
        return (days, weekday)
    }
}
