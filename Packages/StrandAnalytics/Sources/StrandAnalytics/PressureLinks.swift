import Foundation

/// How a person's own blood pressure readings sit beside the rest of their data, and when to remind them to measure.
///
/// Everything here is a plain comparison of day means: it says which side read higher and by how much, never why. Cuff readings vary by several mmHg on
/// their own, so a side needs `daysNeeded` days before anything is said, and a gap smaller than `systolicStep` and `diastolicStep` counts as none.
/// Pure and database-free.
public enum PressureLinks {
    public struct Reading: Equatable, Sendable {
        public let takenAt: Int
        public let systolic: Double
        public let diastolic: Double
        public init(takenAt: Int, systolic: Double, diastolic: Double) {
            self.takenAt = takenAt; self.systolic = systolic; self.diastolic = diastolic
        }
    }

    public struct Pressure: Equatable, Sendable {
        public let systolic: Double
        public let diastolic: Double
        public init(_ systolic: Double, _ diastolic: Double) { self.systolic = systolic; self.diastolic = diastolic }
    }

    /// One side of a comparison: its days and, when it has any, the mean of their day means in whole mmHg.
    public struct Side: Equatable, Sendable {
        public let days: Int
        public let mean: Pressure?
    }

    public enum Verdict: Equatable, Sendable {
        /// A side has fewer than `daysNeeded` days.
        case needMore
        /// No gap worth naming, or the two figures point opposite ways.
        case same
        case firstHigher
        case firstLower
    }

    public struct Comparison: Equatable, Sendable {
        public let first: Side
        public let second: Side
        /// First minus second; nil while either side is empty.
        public let difference: Pressure?
        public let verdict: Verdict
        /// Said only while one side still holds few days.
        public var early: Bool { min(first.days, second.days) < PressureLinks.settledDays }
    }

    public static let daysNeeded = 5
    public static let settledDays = 10
    public static let systolicStep = 3.0
    public static let diastolicStep = 2.0

    private static func mean(_ list: [Pressure]) -> Pressure? {
        guard !list.isEmpty else { return nil }
        let n = Double(list.count)
        return Pressure(list.reduce(0) { $0 + $1.systolic } / n, list.reduce(0) { $0 + $1.diastolic } / n)
    }

    /// One mean a day, so a day measured five times weighs no more than a day measured once.
    public static func daily(_ readings: [Reading], dayKey: (Int) -> String) -> [String: Pressure] {
        Dictionary(grouping: readings) { dayKey($0.takenAt) }
            .compactMapValues { mean($0.map { Pressure($0.systolic, $0.diastolic) }) }
    }

    /// Days flagged true against days flagged false; days with no flag are left out.
    public static func compare(_ daily: [String: Pressure], flags: [String: Bool]) -> Comparison {
        var yes: [Pressure] = [], no: [Pressure] = []
        // In day order, so the sums are the same every time.
        for day in daily.keys.sorted() {
            guard let flag = flags[day], let p = daily[day] else { continue }
            if flag { yes.append(p) } else { no.append(p) }
        }
        // Whole figures, so the two means a screen shows, the gap it names and the verdict can never disagree.
        func whole(_ p: Pressure?) -> Pressure? { p.map { Pressure($0.systolic.rounded(), $0.diastolic.rounded()) } }
        let first = Side(days: yes.count, mean: whole(mean(yes))), second = Side(days: no.count, mean: whole(mean(no)))
        let difference = first.mean.flatMap { a in second.mean.map { Pressure(a.systolic - $0.systolic, a.diastolic - $0.diastolic) } }
        return Comparison(first: first, second: second, difference: difference, verdict: verdict(first.days, second.days, difference))
    }

    private static func verdict(_ first: Int, _ second: Int, _ difference: Pressure?) -> Verdict {
        guard first >= daysNeeded, second >= daysNeeded, let d = difference else { return .needMore }
        let s = abs(d.systolic) >= systolicStep, dia = abs(d.diastolic) >= diastolicStep
        if !s && !dia { return .same }
        if s && dia && (d.systolic > 0) != (d.diastolic > 0) { return .same }
        return (s ? d.systolic : d.diastolic) > 0 ? .firstHigher : .firstLower
    }

    /// A measured level (hours slept, effort, weight) split at the middle of the person's own days: the first side is below it, the second at or above.
    /// Nil when there are no shared days or the level hardly moves (`minimumSpread` between its lowest and highest).
    public static func compareByLevel(_ daily: [String: Pressure], level: [String: Double], minimumSpread: Double) -> (middle: Double, comparison: Comparison)? {
        let values = daily.keys.compactMap { level[$0] }.sorted()
        guard let low = values.first, let high = values.last, high - low >= minimumSpread else { return nil }
        let n = values.count
        let middle = n % 2 == 1 ? values[n / 2] : (values[n / 2 - 1] + values[n / 2]) / 2
        let flags = Dictionary(uniqueKeysWithValues: daily.keys.compactMap { day in level[day].map { (day, $0 < middle) } })
        return (middle, compare(daily, flags: flags))
    }

    // MARK: Breathing sessions

    /// A reading counts as before or after a session when taken within this long of it.
    public static let breathWindow = 30 * 60

    public struct Session: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
    }

    public struct BreathPair: Equatable, Sendable {
        public let session: Session
        public let before: Reading
        public let after: Reading
        /// After minus before.
        public var change: Pressure { Pressure(after.systolic - before.systolic, after.diastolic - before.diastolic) }
    }

    /// The last reading in the half hour up to the session's start.
    public static func before(_ readings: [Reading], _ session: Session) -> Reading? {
        readings.filter { $0.takenAt <= session.start && $0.takenAt >= session.start - breathWindow }.max { $0.takenAt < $1.takenAt }
    }

    /// The first reading in the half hour from the session's end.
    public static func after(_ readings: [Reading], _ session: Session) -> Reading? {
        readings.filter { $0.takenAt >= session.end && $0.takenAt <= session.end + breathWindow }.min { $0.takenAt < $1.takenAt }
    }

    /// The sessions measured on both sides, newest first. A reading serves one pair only, the newest session's, so back-to-back sessions do not count
    /// the same change twice.
    public static func breathPairs(_ readings: [Reading], sessions: [Session]) -> [BreathPair] {
        var used = Set<Int>()
        var out: [BreathPair] = []
        for s in sessions.sorted(by: { $0.start > $1.start }) {
            guard let b = before(readings, s), let a = after(readings, s), !used.contains(b.takenAt), !used.contains(a.takenAt) else { continue }
            used.insert(b.takenAt); used.insert(a.takenAt)
            out.append(BreathPair(session: s, before: b, after: a))
        }
        return out
    }

    public static func meanChange(_ pairs: [BreathPair]) -> Pressure? { mean(pairs.map(\.change)) }

    // MARK: Reminder

    /// A reading this long before a reminder's time (or since) makes that reminder unnecessary.
    public static let reminderCovers: TimeInterval = 3 * 3600

    /// The moments to remind over the coming `days`, from now: each of `minutes` (minutes since local midnight) on each day, leaving out those a reading
    /// already covers.
    public static func reminderDates(now: Date, minutes: [Int], readings: [Int], days: Int, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for m in Set(minutes).sorted() where (0..<24 * 60).contains(m) {
                guard let at = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), at > now else { continue }
                let covered = readings.contains { r in
                    let t = Date(timeIntervalSince1970: TimeInterval(r))
                    return t >= at.addingTimeInterval(-reminderCovers) && t <= now
                }
                if !covered { out.append(at) }
            }
        }
        return out
    }
}
