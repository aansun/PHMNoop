import Foundation

/// Pace of aging: how many years the fitness age moves for each calendar year.
///
/// The fitness age is `chronological age + offset`, where the offset comes from resting heart rate and activity
/// (`FitnessAgeEngine`). The chronological part grows by exactly 1 per year, so the pace is
/// `1 + (change of the offset per year)`:
///   • 1.0x  the offset is steady, the fitness age ages at the same speed as the calendar ("normal")
///   • 0.0x  the fitness gains cancel a year of ageing, the fitness age stands still
///   • below 0  the fitness age is falling, you are getting fitter faster than time passes
///   • above 1  the offset is growing, the fitness age is rising faster than the calendar
///
/// The weekly fitness age is a noisy reading (a few bpm of resting heart rate is worth more than a year), so a raw slope
/// over a few weeks would swing wildly. The estimate therefore (1) fits a straight line through up to 26 weekly readings,
/// (2) measures how noisy the readings are around that line, and (3) pulls the slope towards "normal" (1.0x) in proportion to
/// that noise, so a short or jumpy history reads close to 1.0x and only a long, consistent trend moves it far. The result is
/// clamped to the -1.0x ... 3.0x dial. A slope past ±3 years per year is treated as a step in the inputs and capped first. It is a fitness comparison, not a biological age.
public enum PaceOfAging {

    public struct Reading: Sendable, Equatable {
        /// Seconds since 1970 of the weekly reading.
        public let time: TimeInterval
        /// Fitness age in years as stored for that week.
        public let fitnessAge: Double
        public init(time: TimeInterval, fitnessAge: Double) { self.time = time; self.fitnessAge = fitnessAge }
    }

    public enum Confidence: String, Sendable { case early, building, solid }

    public struct Result: Sendable, Equatable {
        /// Dial value, -1.0 ... 3.0.
        public let pace: Double
        /// Raw fitted slope of the fitness age, in years per year, before shrinking.
        public let slopeYearsPerYear: Double
        /// How much of the raw trend is kept (0...1). Low means "mostly the neutral 1.0x".
        public let weight: Double
        public let weeks: Int
        public let confidence: Confidence

        public enum Band: Sendable { case slow, normal, fast }
        /// Words for the dial: slower or faster than the calendar, with a 0.15 dead band around 1.0x.
        public var band: Band { pace < 0.85 ? .slow : (pace > 1.15 ? .fast : .normal) }
    }

    public static let range: ClosedRange<Double> = -1...3
    public static let windowDays = 182
    public static let minReadings = 6
    public static let minSpanDays = 35.0
    /// Prior spread of the real trend, years of fitness age per year. Larger trusts the data more.
    static let priorSD = 1.0
    /// Floor on the residual spread (years). The weekly reading is a rounded, median-based estimate, so it is never exact.
    static let noiseFloor = 0.6
    /// A fitted slope beyond this (years per year) is not a physiological trend, it is a step in the inputs (a new profile, a
    /// restart of the baseline, a long gap). It is capped before shrinking so one such step cannot pin the dial to an end.
    static let slopeCap = 3.0
    static let secondsPerYear = 365.25 * 86_400

    /// The pace for the readings, or nil when there is not enough history (fewer than 6 weekly readings spanning 5 weeks).
    public static func compute(_ readings: [Reading]) -> Result? {
        let sorted = readings.filter { $0.fitnessAge.isFinite && $0.time.isFinite }.sorted { $0.time < $1.time }
        guard let last = sorted.last else { return nil }
        let cutoff = last.time - Double(windowDays) * 86_400
        let r = sorted.filter { $0.time >= cutoff }
        guard r.count >= minReadings, let first = r.first, (last.time - first.time) / 86_400 >= minSpanDays else { return nil }

        let n = Double(r.count)
        let xs = r.map { $0.time / secondsPerYear }
        let ys = r.map(\.fitnessAge)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let sse = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (intercept + slope * $1.0), 2) }
        let sigma = max((sse / max(n - 2, 1)).squareRoot(), noiseFloor)
        let se = sigma / sxx.squareRoot()
        let w = priorSD * priorSD / (priorSD * priorSD + se * se)
        let capped = min(max(slope, -slopeCap), slopeCap)
        let pace = min(max(1 + w * capped, range.lowerBound), range.upperBound)
        let conf: Confidence = w >= 0.5 ? .solid : (w >= 0.2 ? .building : .early)
        return Result(pace: pace, slopeYearsPerYear: slope, weight: w, weeks: r.count, confidence: conf)
    }
}
