import Foundation

/// One day's alarm in My Schedule.
struct AlarmDayPlan: Codable, Equatable {
    /// The wake time, minutes since local midnight; with an early wake, the latest one.
    var minutes: Int
    /// "exact", "goal" or "green".
    var mode: String
    /// 100, 85 or 70.
    var goal: Int
}

/// My Schedule: an alarm of its own for each weekday that has one (Calendar numbers, 1 = Sunday … 7 = Saturday).
///
/// The schedule does not run beside the alarm: while it is on it is written INTO the alarm's own settings (the days it fires on, the time of each day
/// as the per-day wake time, and the mode and goal of the next alarm), so the strap, the phone notification, the bedtime reminder and every screen read
/// one set of figures. Turning it off puts back what the alarm was before.
struct AlarmSchedule: Codable, Equatable {
    /// What the alarm was before the schedule was turned on.
    struct Before: Codable, Equatable {
        var minutes: Int
        var mode: String
        var goal: Int
        var weekdays: [Int]
        var overrides: [Int: Int]
    }

    var on = false
    var days: [Int: AlarmDayPlan] = [:]
    var before: Before?

    /// Monday first.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
    static let key = "alarm.schedule.v1"

    static func load(_ defaults: UserDefaults = .standard) -> AlarmSchedule {
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(AlarmSchedule.self, from: data) else { return AlarmSchedule() }
        return s
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// Whether the schedule is the one driving the alarm: on, with at least one day.
    var drives: Bool { on && !days.isEmpty }

    /// The days that share a time, a mode and a goal, each group in week order and the groups in the order of their first day.
    var groups: [(days: [Int], plan: AlarmDayPlan)] {
        var out: [(days: [Int], plan: AlarmDayPlan)] = []
        for d in Self.weekOrder {
            guard let plan = days[d] else { continue }
            if let i = out.firstIndex(where: { $0.plan == plan }) { out[i].days.append(d) } else { out.append(([d], plan)) }
        }
        return out
    }

    /// The weekdays that share `weekday`'s alarm, itself included; just itself when it has none.
    func group(of weekday: Int) -> [Int] {
        guard let plan = days[weekday] else { return [weekday] }
        return Self.weekOrder.filter { days[$0] == plan }
    }

    /// Gives `plan` to every day of `group` and takes the alarm away from the days of `previous` that are no longer in it.
    mutating func set(_ plan: AlarmDayPlan, on group: [Int], replacing previous: [Int] = []) {
        for d in previous where !group.contains(d) { days[d] = nil }
        for d in group { days[d] = plan }
    }
}
