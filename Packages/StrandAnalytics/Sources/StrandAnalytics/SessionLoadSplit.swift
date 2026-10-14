import Foundation

/// How a strength session split between cardio and muscular work, for the bar on the gym session page.
///
/// WHAT THIS IS, AND IS NOT. There is no validated path from typed sets and weights to a cardiovascular-strain equivalent (see the
/// note at the top of `LiftMetrics`), so this does not convert one into the other and does not touch Effort. It answers a relative
/// question the wearer's own log can answer: against your usual sessions, how hard was this one on the heart (Effort per minute,
/// measured from heart rate) and how hard on the muscles (kilograms lifted per minute, from the logged sets)?
///
/// Each of the two is ranked among the wearer's earlier sessions (a mid-rank percentile, kept off 0 and 1 so a first-ever best does
/// not zero the other side), and the bar is each rank's share of the two: a session that was unusually heavy for the muscles and
/// ordinary for the heart reads mostly muscular. Under `minHistory` earlier sessions with a figure, nothing is shown: a share against
/// no usual is a number made up.
///
/// Display only. Pure, so the whole surface is unit-testable.
public enum SessionLoadSplit {

    /// Earlier sessions needed, for each of the two figures, before a split is shown.
    public static let minHistory = 3

    public struct Result: Equatable, Sendable {
        /// Whole percentages that add to 100.
        public let cardioPct: Int
        public let muscularPct: Int
        /// How many earlier sessions the split was ranked against (the smaller of the two histories).
        public let sessions: Int
    }

    /// Mid-rank percentile of `value` among `history`, strictly inside 0...1: `(below + ½·equal + ½) / (n + 1)`.
    static func rank(_ value: Double, among history: [Double]) -> Double {
        let below = history.filter { $0 < value }.count
        let equal = history.filter { $0 == value }.count
        return (Double(below) + 0.5 * Double(equal) + 0.5) / Double(history.count + 1)
    }

    /// - Parameters:
    ///   - cardio: this session's Effort per minute (HR-measured), nil without an Effort.
    ///   - muscular: this session's kilograms lifted per minute (working sets), nil without logged sets.
    ///   - cardioHistory / muscularHistory: the same two figures for the wearer's earlier sessions.
    public static func split(cardio: Double?, muscular: Double?,
                             cardioHistory: [Double], muscularHistory: [Double]) -> Result? {
        guard let cardio, let muscular, cardio.isFinite, muscular.isFinite, cardio > 0, muscular > 0 else { return nil }
        let c = cardioHistory.filter { $0.isFinite && $0 > 0 }
        let m = muscularHistory.filter { $0.isFinite && $0 > 0 }
        guard c.count >= minHistory, m.count >= minHistory else { return nil }
        let rc = rank(cardio, among: c), rm = rank(muscular, among: m)
        let cardioPct = Int((rc / (rc + rm) * 100).rounded())
        return Result(cardioPct: cardioPct, muscularPct: 100 - cardioPct, sessions: min(c.count, m.count))
    }
}
