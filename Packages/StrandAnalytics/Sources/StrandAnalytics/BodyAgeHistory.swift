import Foundation

/// The weekly Body Age is stored under each week's Saturday. The model that makes it changed with version 3 (nine inputs, new break-even points), so the
/// weeks stored by an older version are on another scale than the weeks stored now, and a pace of aging fitted across both would read the step between
/// them as a change in the wearer. This is the pure part of rebuilding that history: which Saturdays to rebuild, which days make each week, and the
/// figures a week's data comes to. Reading the data and writing the rows is the app's job (`IntelligenceEngine`).
public enum BodyAgeHistory {
    /// The model the stored Body Age is made with. A history marked with a lower number is rebuilt.
    public static let modelVersion = 3
    /// How many completed weeks are rebuilt: the weeks the pace of aging reads (`PaceOfAging.windowDays`).
    public static let maxWeeks = 26
    /// A week with fewer days than this is left out; too little of it was recorded to say anything.
    public static let minDays = 3
    /// The metric key of the mark that says which model the stored history is made with.
    public static let markerKey = "body_age_model"

    public struct Point: Equatable, Sendable {
        public let day: String
        public let bodyAge: Double
        public let vitality: Double
    }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    private static func key(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day key `n` days from `day` (negative for earlier), or nil when `day` is not a `yyyy-MM-dd` key.
    public static func addDays(_ day: String, _ n: Int) -> String? {
        guard let d = date(day), let r = utc.date(byAdding: .day, value: n, to: d) else { return nil }
        return key(r)
    }

    /// The `count` Saturdays before the one on or before `day`, oldest first. The current week is left out: the weekly job writes it.
    public static func saturdays(before day: String, count: Int = maxWeeks) -> [String] {
        guard count > 0, let d = date(day) else { return [] }
        let sinceSaturday = utc.component(.weekday, from: d) % 7   // Saturday is 7, so 0; Sunday is 1
        guard let current = utc.date(byAdding: .day, value: -sinceSaturday, to: d) else { return [] }
        return (1...count).reversed().compactMap { utc.date(byAdding: .day, value: -7 * $0, to: current).map(key) }
    }

    /// The seven day keys of the week that ends on `saturday`, oldest first.
    public static func weekDays(endingOn saturday: String) -> [String] {
        (0..<7).reversed().compactMap { addDays(saturday, -$0) }
    }

    /// The stored figures for each week that has enough inputs; weeks that do not are left out, never filled in.
    public static func points(_ weeks: [(saturday: String, data: VitalityEngine.WeekData)]) -> [Point] {
        weeks.compactMap { w in
            VitalityEngine.compute(VitalityEngine.weeklyInputs(w.data)).map { Point(day: w.saturday, bodyAge: $0.bodyAge, vitality: $0.vitality) }
        }
    }
}
