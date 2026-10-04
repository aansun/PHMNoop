import Foundation

/// Pure helpers behind the Trends screens: zone counts, weekday and weekly patterns, "what happens the day after"
/// buckets and a plain-language strength label. Everything works on `yyyy-MM-dd` keyed series and returns
/// only what the series holds; nothing is filled in.
public enum TrendInsights {

    // MARK: Day keys

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Day key shifted by a number of days, nil when the key does not parse.
    public static func shift(_ day: String, by days: Int) -> String? {
        guard let d = parser.date(from: day), let n = utc.date(byAdding: .day, value: days, to: d) else { return nil }
        return parser.string(from: n)
    }

    /// Calendar weekday (1 = Sunday ... 7 = Saturday) of a day key.
    public static func weekday(_ day: String) -> Int? {
        parser.date(from: day).map { utc.component(.weekday, from: $0) }
    }

    // MARK: Zones

    /// How many values fall in each band. `edges` are the ascending lower bounds of the second and later bands, so
    /// `[10, 14, 18]` gives four bands: below 10, 10 to under 14, 14 to under 18 and 18 and above.
    public static func zoneCounts(_ values: [Double], edges: [Double]) -> [Int] {
        var out = Array(repeating: 0, count: edges.count + 1)
        for v in values {
            var i = 0
            while i < edges.count, v >= edges[i] { i += 1 }
            out[i] += 1
        }
        return out
    }

    // MARK: Patterns

    /// Mean per weekday (1 = Sunday ... 7 = Saturday). Weekdays without a value are absent.
    public static func weekdayMeans(_ series: [(day: String, value: Double)]) -> [Int: Double] {
        var sum: [Int: Double] = [:], n: [Int: Int] = [:]
        for r in series {
            guard let w = weekday(r.day) else { continue }
            sum[w, default: 0] += r.value; n[w, default: 0] += 1
        }
        return sum.reduce(into: [:]) { $0[$1.key] = $1.value / Double(n[$1.key] ?? 1) }
    }

    /// Sum over consecutive 7-day blocks ending at `lastDay`, oldest first. A block with no value is dropped.
    public static func weeklyTotals(_ series: [(day: String, value: Double)], lastDay: String, weeks: Int) -> [(endDay: String, total: Double)] {
        let byDay = Dictionary(series.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        var out: [(String, Double)] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            guard let end = shift(lastDay, by: -7 * w) else { continue }
            var total = 0.0, any = false
            for k in 0..<7 {
                if let d = shift(end, by: -k), let v = byDay[d] { total += v; any = true }
            }
            if any { out.append((end, total)) }
        }
        return out
    }

    // MARK: Relationship

    public struct Bucket: Equatable, Sendable {
        /// Index of the band (0 = lowest).
        public let band: Int
        public let n: Int
        /// Mean outcome for the days in this band, nil when the band is empty.
        public let meanOutcome: Double?
    }

    /// Groups days by the band their `driver` value falls in and averages the `outcome` found `lag` days later.
    /// `lag` 1 answers "what is tomorrow's Charge after a day like this"; `lag` 0 pairs values of the same day.
    public static func buckets(driver: [(day: String, value: Double)], outcome: [(day: String, value: Double)],
                               edges: [Double], lag: Int) -> [Bucket] {
        let out = Dictionary(outcome.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        var sums = Array(repeating: 0.0, count: edges.count + 1), counts = Array(repeating: 0, count: edges.count + 1)
        for r in driver {
            guard let d = shift(r.day, by: lag), let y = out[d] else { continue }
            var i = 0
            while i < edges.count, r.value >= edges[i] { i += 1 }
            sums[i] += y; counts[i] += 1
        }
        return (0...edges.count).map { Bucket(band: $0, n: counts[$0], meanOutcome: counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil) }
    }

    /// (driver, outcome) pairs for a scatter, same pairing as `buckets`.
    public static func pairs(driver: [(day: String, value: Double)], outcome: [(day: String, value: Double)], lag: Int)
        -> [(day: String, x: Double, y: Double)] {
        let out = Dictionary(outcome.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        return driver.sorted { $0.day < $1.day }.compactMap { r in
            guard let d = shift(r.day, by: lag), let y = out[d] else { return nil }
            return (r.day, r.value, y)
        }
    }

    public enum Strength: String, Sendable { case weak, moderate, strong }

    /// Plain label for the size of a correlation: under 0.3 weak, under 0.6 moderate, otherwise strong.
    public static func strength(_ r: Double) -> Strength {
        let a = abs(r)
        return a < 0.3 ? .weak : (a < 0.6 ? .moderate : .strong)
    }

    // MARK: Streaks

    /// Longest run of consecutive calendar days whose value is at least `threshold`, with the day the run ended.
    public static func longestStreak(_ series: [(day: String, value: Double)], atLeast threshold: Double) -> (length: Int, endDay: String)? {
        let days = series.filter { $0.value >= threshold }.map(\.day).sorted()
        var best: (Int, String)?
        var run = 0
        var prev: String?
        for d in days {
            if let p = prev, shift(p, by: 1) == d { run += 1 } else { run = 1 }
            if best == nil || run > best!.0 { best = (run, d) }
            prev = d
        }
        return best.map { (length: $0.0, endDay: $0.1) }
    }

    // MARK: Load balance

    public enum LoadBand: String, Sendable { case under, optimal, high, excessive }

    /// Acute-to-chronic balance: the last block against the mean of all blocks (the last one included), e.g. this
    /// week's load against the average of the last six weeks. Nil unless at least `minBlocks` blocks carry load.
    public static func loadRatio(blocks: [Double], minBlocks: Int = 3) -> Double? {
        let loaded = blocks.filter { $0 > 0 }
        guard loaded.count >= minBlocks, let last = blocks.last else { return nil }
        let mean = blocks.reduce(0, +) / Double(blocks.count)
        return mean > 0 ? last / mean : nil
    }

    /// Under 0.8, 0.8 to 1.3 optimal, 1.3 to 1.5 high, above that excessive.
    public static func loadBand(_ ratio: Double) -> LoadBand {
        ratio < 0.8 ? .under : (ratio <= 1.3 ? .optimal : (ratio <= 1.5 ? .high : .excessive))
    }

    /// Form (CTL minus ATL) read as a state: above +2 fresh, -3 to +2 balanced, -6 to -3 loaded, below -6 overreached.
    public enum FormState: String, Sendable { case fresh, balanced, loaded, overreached }

    public static func formState(_ tsb: Double) -> FormState {
        tsb > 2 ? .fresh : (tsb >= -3 ? .balanced : (tsb >= -6 ? .loaded : .overreached))
    }
}
