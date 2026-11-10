import Foundation

/// The usual range of a vital sign (HRV, resting heart rate, respiratory rate) read from the person's own last nights, and how far along
/// that range is.
///
/// Three stages, by how many nights have a reading:
/// - under `calibrationNights`: nothing to compare with, so no range and no verdict;
/// - from `calibrationNights` up to `trustedNights`: a range, but a short one, so it is read with a wider tolerance that narrows night by night;
/// - from `trustedNights`: the plain range.
///
/// The centre is the median and the range `rangeSpreads` (2) standard deviations either side of it, the standard deviation read from the
/// median absolute deviation (scaled by 1.4826), so one night out (a drink,
/// a late workout, a cold coming) does not drag the range to itself the way a mean and a standard deviation would, and it matters most
/// while there are few nights.
public enum VitalRange {

    /// Nights with a reading before a range exists.
    public static let calibrationNights = 7
    /// Nights with a reading before the range is final (and before the early warning speaks).
    public static let trustedNights = 14
    /// How many of the newest earlier readings the range is read from.
    public static let windowNights = 30
    /// A range of `calibrationNights` readings is this many times wider than the final one.
    public static let widestFactor = 1.5
    /// Standard deviations either side of the median that are still the usual range. At 1 a third of perfectly ordinary nights fall outside
    /// each vital, and with several vitals watched most ordinary days show one out of range; at 2 it is about one night in twenty, and a
    /// night that is really off (an illness, a drink) still shows on two or more vitals. Measured with `Tools/StressSim --sixmonths`.
    public static let rangeSpreads = 2.0
    /// The smallest half-width of a respiratory-rate range (breaths a minute). The nightly figure moves in steps of about 0.8 (it is read
    /// from a spectrum), so a steady sleeper's readings are one value and its neighbours: a floor under one step calls every step out of range.
    public static let respiratoryFloor = 1.0

    public enum Phase: Equatable, Sendable {
        case calibrating(nights: Int)
        case learning(nights: Int)
        case trusted

        public var hasRange: Bool { if case .calibrating = self { return false } else { return true } }
        public var isTrusted: Bool { self == .trusted }
    }

    public static func phase(nights: Int) -> Phase {
        if nights < calibrationNights { return .calibrating(nights: max(nights, 0)) }
        if nights < trustedNights { return .learning(nights: nights) }
        return .trusted
    }

    public struct Band: Equatable, Sendable {
        /// The median of the readings.
        public let centre: Double
        /// Half the width of the usual range: `rangeSpreads` standard deviations, wider still while the range is short.
        public let spread: Double
        public let lo: Double
        public let hi: Double
        /// Readings the range was read from, with the one being judged.
        public let nights: Int

        public var learning: Bool { nights < VitalRange.trustedNights }
    }

    public enum Verdict: Equatable, Sendable { case inRange, above, below }

    /// The range from the earlier readings (oldest first, without the one being judged). Nil while there are too few nights.
    public static func band(history: [Double]) -> Band? {
        let values = Array(history.suffix(windowNights))
        let nights = values.count + 1
        guard nights >= calibrationNights else { return nil }
        let centre = median(values)
        let mad = median(values.map { abs($0 - centre) })
        let widen: Double = nights >= trustedNights
            ? 1
            : 1 + (widestFactor - 1) * Double(trustedNights - nights) / Double(trustedNights - calibrationNights)
        let spread = 1.4826 * mad * rangeSpreads * widen
        return Band(centre: centre, spread: spread, lo: values.min() ?? centre, hi: values.max() ?? centre, nights: nights)
    }

    /// Where a reading sits against the range. `floor` is the smallest spread worth noticing (1 ms of HRV, 1 bpm, 0.3 breaths a minute), so a
    /// very steady person is not flagged for a wobble no one could feel.
    public static func verdict(_ value: Double, in band: Band, floor: Double) -> Verdict {
        let tolerance = max(band.spread, floor)
        if abs(value - band.centre) <= tolerance { return .inRange }
        return value > band.centre ? .above : .below
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
