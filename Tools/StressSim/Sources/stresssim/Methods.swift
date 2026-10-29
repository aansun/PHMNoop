import Foundation
import StrandAnalytics
import WhoopProtocol

/// The nightly figures the app keeps for a night: the resting heart rate and the RMSSD. Measured here the way a night is read: the
/// resting heart rate is the mean of the lowest tenth of the 5-minute means, the HRV the mean of the 5-minute RMSSDs.
enum NightMetrics {
    static func measure(hr: [HRSample], rr: [RRInterval], from: Int, to: Int) -> (rhr: Double, rmssd: Double) {
        var means: [Double] = [], rmssds: [Double] = []
        var t = from
        var hi = 0, ri = 0
        while t + 300 <= to {
            var s = 0, n = 0
            while hi < hr.count, hr[hi].ts < t + 300 { if hr[hi].ts >= t { s += hr[hi].bpm; n += 1 }; hi += 1 }
            var raw: [Double] = []
            while ri < rr.count, rr[ri].ts < t + 300 { if rr[ri].ts >= t { raw.append(Double(rr[ri].rrMs)) }; ri += 1 }
            if n > 100 { means.append(Double(s) / Double(n)) }
            if raw.count >= 60, let v = HRVAnalyzer.analyze(rawRR: raw).rmssd, v > 0 { rmssds.append(v) }
            t += 300
        }
        let low = means.sorted().prefix(max(1, means.count / 10))
        let rhr = low.reduce(0, +) / Double(max(low.count, 1))
        let hrv = rmssds.isEmpty ? 0 : rmssds.reduce(0, +) / Double(rmssds.count)
        return (rhr, hrv)
    }
}

/// The app's existing reading, as it is wired: the daytime read per calendar day (`DaytimeStress`, the day's own calm quartile, hours
/// 06:00 to 22:00, motion hours masked) and the nightly proxy for sleep (the night's resting heart rate and HRV against the trailing 30
/// nights, one level for the whole night). Both are the app's own formulas; nothing here changes them.
enum Legacy {
    static func daytime(_ d: SimData, day: Int) -> DaytimeStress.Result {
        let a = d.t0 + day * 86_400, b = a + 86_400
        return DaytimeStress.analyze(hr: d.hr.filter { $0.ts >= a && $0.ts < b }, rr: d.rr.filter { $0.ts >= a && $0.ts < b },
                                     gravity: d.gravity.filter { $0.ts >= a && $0.ts < b }, tzOffsetSeconds: 0, includeTimeline: false)
    }

    /// The nightly proxy: z of resting heart rate (up is stress) plus z of HRV (down is stress), squashed onto 0 to 3.
    static func nightLevel(rhr: Double, rmssd: Double, history: [(rhr: Double, rmssd: Double)]) -> Double {
        let base = Array(history.suffix(30))
        func mean(_ x: [Double]) -> Double { x.reduce(0, +) / Double(x.count) }
        func sd(_ x: [Double]) -> Double { let m = mean(x); return (x.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(x.count)).squareRoot() }
        let r = base.map(\.rhr), h = base.map(\.rmssd)
        var raw = 0.0
        if sd(r) > 0.0001 { raw += (rhr - mean(r)) / sd(r) }
        if sd(h) > 0.0001 { raw += (mean(h) - rmssd) / sd(h) }
        return min(max(3.0 / (1.0 + exp(-raw)), 0), 3)
    }
}

/// One WHOOP-reference run with a named tuning.
struct Variant {
    let name: String
    var tuning: WhoopStress.Tuning
}

extension Variant {
    static let standard = Variant(name: "WHOOP-ver (HR+HRV, filtered)", tuning: WhoopStress.Tuning())
    static let hrOnly: Variant = { var t = WhoopStress.Tuning(); t.useHRV = false; return Variant(name: "WHOOP-ver (HR only)", tuning: t) }()
    /// Daytime HRV the careless way: equal weight, no clamp on the z-scores, almost no beat or rejection requirement.
    static let naiveHRV: Variant = {
        var t = WhoopStress.Tuning()
        t.hrWeight = 1; t.hrvWeight = 1; t.zClamp = 10; t.minCleanBeats = 30; t.maxRejectedFraction = 1.0
        return Variant(name: "WHOOP-ver (naive HRV)", tuning: t)
    }()
    static func miscalibrated(_ deltaBPM: Double) -> Variant {
        var t = WhoopStress.Tuning(); t.wakeHROffsetBPM += deltaBPM
        return Variant(name: String(format: "WHOOP-ver (wake HR offset %+.0f bpm)", deltaBPM), tuning: t)
    }
}
