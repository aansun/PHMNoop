import Foundation

// InsightReads.swift - what a number MEANS, worked out from the wearer's own data, for the lines Anya writes on the detail screens.
//
// The old lines said "Rest 88%, 3 points above your last 14 nights": the figure the ring already shows. These reads answer the next
// questions instead: which part of the night carried or held the score back, what is behind a reading that moved, and what is worth
// doing about it. Everything here is arithmetic over values the screens already hold (per-night figures, personal baselines), pure and
// unit-tested; the sentences are composed in the app layer, where they are localised.
//
// HONESTY. A read names a cause only as far as the data goes ("deep sleep ran 28% under your usual"), never a diagnosis, and returns
// no verdict when its inputs are missing.

// MARK: - Sleep

public enum SleepDriver: String, Equatable, Sendable, CaseIterable {
    case duration, efficiency, restorative, consistency
}

public struct SleepFacts: Equatable, Sendable {
    public var restPct: Double?
    public var asleepMin: Double
    public var needMin: Double
    public var debtMin: Double?
    /// The four parts Rest is made of, each 0...100 (duration against need, time asleep in bed, deep + REM share, bedtime regularity).
    public var hoursPct: Double?
    public var efficiencyPct: Double?
    public var restorativePct: Double?
    public var consistencyPct: Double?
    public var deepMin: Double?, remMin: Double?, awakeMin: Double?
    public var wakeEvents: Int?
    public var usualDeepMin: Double?, usualRemMin: Double?
    /// Minutes later (+) or earlier (-) than the usual bedtime.
    public var bedShiftMin: Double?
    /// HRV against the personal baseline, in percent, and resting heart rate in bpm (+ above the usual).
    public var hrvDeltaPct: Double?
    public var rhrDeltaBpm: Double?

    public init(restPct: Double? = nil, asleepMin: Double, needMin: Double, debtMin: Double? = nil,
                hoursPct: Double? = nil, efficiencyPct: Double? = nil, restorativePct: Double? = nil, consistencyPct: Double? = nil,
                deepMin: Double? = nil, remMin: Double? = nil, awakeMin: Double? = nil, wakeEvents: Int? = nil,
                usualDeepMin: Double? = nil, usualRemMin: Double? = nil, bedShiftMin: Double? = nil,
                hrvDeltaPct: Double? = nil, rhrDeltaBpm: Double? = nil) {
        self.restPct = restPct; self.asleepMin = asleepMin; self.needMin = needMin; self.debtMin = debtMin
        self.hoursPct = hoursPct; self.efficiencyPct = efficiencyPct; self.restorativePct = restorativePct; self.consistencyPct = consistencyPct
        self.deepMin = deepMin; self.remMin = remMin; self.awakeMin = awakeMin; self.wakeEvents = wakeEvents
        self.usualDeepMin = usualDeepMin; self.usualRemMin = usualRemMin; self.bedShiftMin = bedShiftMin
        self.hrvDeltaPct = hrvDeltaPct; self.rhrDeltaBpm = rhrDeltaBpm
    }
}

public struct SleepRead: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case heldBack(SleepDriver)
        case carriedBy(SleepDriver)
        case balanced
    }
    public enum BodySignal: Equatable, Sendable { case supportive, lagging, neutral }

    public let verdict: Verdict
    /// Asleep minus need: negative is short.
    public let durationGapMin: Int
    public let deepDeltaPct: Int?
    public let remDeltaPct: Int?
    public let bedShiftMin: Int?
    public let wakeEvents: Int?
    public let awakeMin: Int?
    public let debtMin: Int?
    public let body: BodySignal

    /// Share of Rest each part carries (the Rest "How it's calculated" text: half is time against need, the rest is split evenly).
    static let weights: [SleepDriver: Double] = [.duration: 0.5, .efficiency: 1.0 / 6, .restorative: 1.0 / 6, .consistency: 1.0 / 6]
    /// A part must cost at least this many Rest points to be named as what held the night back.
    static let minShortfallPoints = 5.0

    public static func analyze(_ f: SleepFacts) -> SleepRead? {
        guard f.asleepMin > 0, f.needMin > 0 else { return nil }
        var parts: [(SleepDriver, Double)] = []
        parts.append((.duration, min(max(f.hoursPct ?? min(f.asleepMin / f.needMin * 100, 100), 0), 100)))
        if let v = f.efficiencyPct { parts.append((.efficiency, min(max(v, 0), 100))) }
        if let v = f.restorativePct { parts.append((.restorative, min(max(v, 0), 100))) }
        if let v = f.consistencyPct { parts.append((.consistency, min(max(v, 0), 100))) }
        let shortfall = parts.map { ($0.0, (weights[$0.0] ?? 0) * (100 - $0.1)) }
        let worst = shortfall.max { $0.1 < $1.1 }
        let best = parts.max { lhs, rhs in lhs.1 < rhs.1 || (lhs.1 == rhs.1 && lhs.0 != .duration && rhs.0 == .duration) }

        let rest = f.restPct ?? 100
        let verdict: Verdict
        if let worst, worst.1 >= minShortfallPoints, rest < 85 { verdict = .heldBack(worst.0) }
        else if let best { verdict = .carriedBy(best.0) }
        else { verdict = .balanced }

        func delta(_ v: Double?, _ usual: Double?) -> Int? {
            guard let v, let usual, usual > 0 else { return nil }
            return Int(((v - usual) / usual * 100).rounded())
        }
        var body = BodySignal.neutral
        if let h = f.hrvDeltaPct, h >= 5 { body = .supportive }
        if let r = f.rhrDeltaBpm, r <= -2, body == .neutral { body = .supportive }
        if let h = f.hrvDeltaPct, h <= -5 { body = .lagging }
        if let r = f.rhrDeltaBpm, r >= 3 { body = .lagging }

        return SleepRead(verdict: verdict, durationGapMin: Int((f.asleepMin - f.needMin).rounded()),
                         deepDeltaPct: delta(f.deepMin, f.usualDeepMin), remDeltaPct: delta(f.remMin, f.usualRemMin),
                         bedShiftMin: f.bedShiftMin.map { Int($0.rounded()) }, wakeEvents: f.wakeEvents,
                         awakeMin: f.awakeMin.map { Int($0.rounded()) }, debtMin: f.debtMin.map { Int($0.rounded()) }, body: body)
    }
}

// MARK: - A vital sign against its own usual

public struct VitalRead: Equatable, Sendable {
    public enum Position: Equatable, Sendable { case below, within, above }

    public let position: Position
    /// Latest against the mean of the earlier days, in percent.
    public let pctFromUsual: Double
    /// Latest minus the mean of the earlier days, in the metric's own unit.
    public let deltaFromUsual: Double
    /// Days in a row (the latest included) on the same side of the usual; 1 when only today is.
    public let streakDays: Int
    /// The last seven days' mean against the 21 before them, in percent; nil without enough days.
    public let weekTrendPct: Double?

    /// - Parameters:
    ///   - latest: the newest reading.
    ///   - history: earlier readings, oldest first (up to ~30 days).
    ///   - minimumDays: days of history required before a read is given.
    public static func analyze(latest: Double, history: [Double], minimumDays: Int = 7) -> VitalRead? {
        let h = history.filter(\.isFinite)
        guard latest.isFinite, h.count >= minimumDays else { return nil }
        let mean = h.reduce(0, +) / Double(h.count)
        guard mean != 0 else { return nil }
        let sd = (h.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(h.count)).squareRoot()
        // "Within" is half a spread either side, floored so a flat series is not read as always unusual.
        let band = max(sd * 0.75, abs(mean) * 0.02)
        let pos: Position = latest > mean + band ? .above : (latest < mean - band ? .below : .within)

        var streak = 1
        if pos != .within {
            for v in h.reversed() {
                let side: Position = v > mean + band ? .above : (v < mean - band ? .below : .within)
                if side == pos { streak += 1 } else { break }
            }
        }
        var trend: Double?
        if h.count >= 28 {
            let last = Array(h.suffix(7)), before = Array(h.dropLast(7).suffix(21))
            let a = last.reduce(0, +) / 7, b = before.reduce(0, +) / Double(before.count)
            if b != 0 { trend = (a - b) / abs(b) * 100 }
        }
        return VitalRead(position: pos, pctFromUsual: (latest - mean) / abs(mean) * 100, deltaFromUsual: latest - mean,
                         streakDays: streak, weekTrendPct: trend)
    }
}

// MARK: - Charge

public struct ChargeRead: Equatable, Sendable {
    public enum Factor: String, Equatable, Sendable { case hrv, restingHr, sleep, load, breathing, skinTemp }
    public struct Item: Equatable, Sendable {
        public let factor: Factor
        /// Positive supported Charge, negative pulled it down; roughly -3...3.
        public let score: Double
    }

    public let lift: Item?
    public let drag: Item?

    public static func analyze(hrvDeltaPct: Double?, rhrDeltaBpm: Double?, sleepPct: Double?,
                               priorEffort: Double?, usualEffort: Double?,
                               respDeltaBpm: Double?, skinTempDevC: Double?) -> ChargeRead {
        func cap(_ v: Double) -> Double { min(max(v, -3), 3) }
        var items: [Item] = []
        if let h = hrvDeltaPct { items.append(Item(factor: .hrv, score: cap(h / 8))) }
        if let r = rhrDeltaBpm { items.append(Item(factor: .restingHr, score: cap(-r / 2))) }
        if let s = sleepPct { items.append(Item(factor: .sleep, score: cap((s - 75) / 8))) }
        if let e = priorEffort, let u = usualEffort, u > 0 { items.append(Item(factor: .load, score: cap(-(e / u - 1) * 2.5))) }
        if let r = respDeltaBpm { items.append(Item(factor: .breathing, score: cap(-abs(r) * 1.5))) }
        if let t = skinTempDevC { items.append(Item(factor: .skinTemp, score: cap(-max(abs(t) - 0.3, 0) * 4))) }
        let lift = items.filter { $0.score >= 1 }.max { $0.score < $1.score }
        let drag = items.filter { $0.score <= -1 }.min { $0.score < $1.score }
        return ChargeRead(lift: lift, drag: drag)
    }
}

// MARK: - Stress through the day

public struct StressRead: Equatable, Sendable {
    /// The longest stretch at "high" (level 2 and above): first hour (local, 0...23) and how many hours it ran.
    public let peakStartHour: Int?
    public let peakHours: Int
    /// Hours with a score, and how many of them were low (under 1).
    public let scoredHours: Int
    public let calmHours: Int
    /// The hours since the last high hour (nil when there was none), measured against the last scored hour.
    public let calmSinceHours: Int?

    /// `levels` are (local hour, level 0...3) for the hours that have a score, oldest first.
    public static func analyze(levels: [(hour: Int, level: Double)]) -> StressRead? {
        guard levels.count >= 4 else { return nil }
        let sorted = levels.sorted { $0.hour < $1.hour }
        var bestStart: Int?, bestLen = 0
        var runStart: Int?, runLen = 0, prevHour = -10
        for (h, l) in sorted {
            if l >= 2 {
                if runStart != nil, h == prevHour + 1 { runLen += 1 } else { runStart = h; runLen = 1 }
                if runLen > bestLen { bestLen = runLen; bestStart = runStart }
            } else { runStart = nil; runLen = 0 }
            prevHour = h
        }
        let lastHigh = sorted.last(where: { $0.level >= 2 })?.hour
        let lastHour = sorted.last?.hour ?? 0
        return StressRead(peakStartHour: bestStart, peakHours: bestLen, scoredHours: sorted.count,
                          calmHours: sorted.filter { $0.level < 1 }.count,
                          calmSinceHours: lastHigh.map { max(lastHour - $0, 0) })
    }
}
