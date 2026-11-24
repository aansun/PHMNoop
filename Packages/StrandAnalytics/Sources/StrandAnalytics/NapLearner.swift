import Foundation
import WhoopProtocol

// NapLearner.swift — a small classifier for "is this daytime still stretch a nap?", trained on the person's OWN explicit answers, run in SHADOW MODE.
//
// THE LABELS. A person answers in two ways and only these count:
//   • a nap they logged by hand (or edited) is a nap (positive);
//   • a nap the detector found and they deleted is not a nap (negative).
// A nap the detector found and they left alone is NOT a label: it already passed the rules, so learning from it would teach the rules their own bias.
//
// SHADOW MODE: it is trained and measured against the rules (`NapRules`) on the same windows, leave one out; nothing in detection reads it. It needs at
// least `minPerSide` windows of each kind before it says anything. Pure and deterministic. NOT medical advice.

/// The nap bar in one place, used by the stager's daytime guard and by the comparison below, so the two can never drift apart.
public enum NapRules {
    /// Whether a daytime window is a nap. `restingRatio` is the window's lowest 5-minute mean HR over the day's baseline; `bandAsleepFraction` is the share of
    /// the strap's own sleep-state samples inside the window that read "asleep", or nil when the strap banked none.
    public static func passes(durationS: Int, restingRatio: Double?, bandAsleepFraction: Double?) -> Bool {
        guard durationS >= SleepStager.daytimeMinSleepMin * 60, let ratio = restingRatio else { return false }
        if durationS >= SleepStager.shortNapMaxMin * 60 { return ratio <= SleepStager.daytimeRestingHRMult }
        if let band = bandAsleepFraction {
            return ratio <= SleepStager.shortNapRestingHRMult && band >= SleepStager.shortNapBandAsleepFrac
        }
        return ratio <= SleepStager.shortNapNoBandRestingHRMult
    }
}

public struct NapWindowFeatures: Codable, Equatable, Sendable {
    public let durationMin: Double
    /// Lowest 5-minute mean HR over the window, divided by the day's baseline.
    public let restingRatio: Double
    /// Mean HR over the window, divided by the baseline.
    public let meanRatio: Double
    /// Share of the strap's sleep-state samples in the window that read "asleep"; nil when none.
    public let bandAsleepFraction: Double?
    /// Mean per-second gravity change over the window (lower is stiller).
    public let stillness: Double

    public init(durationMin: Double, restingRatio: Double, meanRatio: Double, bandAsleepFraction: Double?, stillness: Double) {
        self.durationMin = durationMin; self.restingRatio = restingRatio; self.meanRatio = meanRatio
        self.bandAsleepFraction = bandAsleepFraction; self.stillness = stillness
    }
}

public enum NapFeatureExtractor {
    /// Features of `[start, end]` from the strap's streams. `baselineHR` is the day's median HR (nil: the median of `hr` itself). nil when the window has too
    /// little heart rate to say anything (under a minute of samples).
    public static func extract(start: Int, end: Int, hr: [HRSample], gravity: [GravitySample],
                               band: [(ts: Int, state: Int)], baselineHR: Double? = nil) -> NapWindowFeatures? {
        guard end > start else { return nil }
        let inside = hr.filter { $0.ts >= start && $0.ts <= end }
        guard inside.count >= 60 else { return nil }
        guard let baseline = baselineHR ?? SleepStager.hrBaseline(hr), baseline > 0,
              let resting = SleepStager.sessionRestingHR(start: start, end: end, hr: hr) else { return nil }
        let mean = Double(inside.reduce(0) { $0 + $1.bpm }) / Double(inside.count)
        let bandIn = band.filter { $0.ts >= start && $0.ts <= end }
        let bandFrac: Double? = bandIn.isEmpty ? nil : Double(bandIn.filter { $0.state == SleepStager.bandStateAsleep }.count) / Double(bandIn.count)
        let g = gravity.filter { $0.ts >= start && $0.ts <= end }.sorted { $0.ts < $1.ts }
        var stillness = 0.0
        if g.count >= 2 {
            var total = 0.0
            for i in 1..<g.count {
                let dx = g[i].x - g[i - 1].x, dy = g[i].y - g[i - 1].y, dz = g[i].z - g[i - 1].z
                total += (dx * dx + dy * dy + dz * dz).squareRoot()
            }
            stillness = total / Double(g.count - 1)
        }
        return NapWindowFeatures(durationMin: Double(end - start) / 60, restingRatio: Double(resting) / baseline, meanRatio: mean / baseline,
                                 bandAsleepFraction: bandFrac, stillness: stillness)
    }
}

public struct LabelledNapWindow: Equatable, Sendable {
    public let id: String
    public let isNap: Bool
    public let features: NapWindowFeatures
    public init(id: String, isNap: Bool, features: NapWindowFeatures) { self.id = id; self.isNap = isNap; self.features = features }
}

/// Trained parameters (logistic regression on standardised features), kept between launches as JSON.
public struct NapLearnerModel: Codable, Equatable, Sendable {
    public let trainedAt: Int
    public let positives: Int
    public let negatives: Int
    public let mean: [Double]
    public let scale: [Double]
    public let weights: [Double]
    public let bias: Double
    public let featureVersion: Int
}

public enum NapLearner {
    public static let featureVersion = 1
    /// Fewest windows of EACH kind (a nap, not a nap) before the learner trains at all.
    public static let minPerSide = 6
    static let names = ["logDuration", "restingRatio", "meanRatio", "bandFraction", "hasBand", "logStillness"]

    static func vector(_ f: NapWindowFeatures) -> [Double] {
        [log(max(f.durationMin, 1)), f.restingRatio, f.meanRatio, f.bandAsleepFraction ?? 0.5, f.bandAsleepFraction == nil ? 0 : 1, log(1 + f.stillness * 100)]
    }

    public static func train(_ windows: [LabelledNapWindow], now: Int) -> NapLearnerModel? {
        let pos = windows.filter(\.isNap), neg = windows.filter { !$0.isNap }
        guard pos.count >= minPerSide, neg.count >= minPerSide else { return nil }
        let x = windows.map { vector($0.features) }
        let y = windows.map { $0.isNap ? 1.0 : 0.0 }
        let d = names.count, n = Double(x.count)
        let mean = (0..<d).map { i in x.reduce(0) { $0 + $1[i] } / n }
        let scale = (0..<d).map { i -> Double in
            let v = (x.reduce(0) { $0 + ($1[i] - mean[i]) * ($1[i] - mean[i]) } / n).squareRoot()
            return max(v, 1e-3)
        }
        let z = x.map { row in (0..<d).map { (row[$0] - mean[$0]) / scale[$0] } }
        var w = [Double](repeating: 0, count: d), b = 0.0
        let lambda = 0.1, rate = 0.5
        for _ in 0..<600 {
            var gw = [Double](repeating: 0, count: d), gb = 0.0
            for (row, label) in zip(z, y) {
                let p = 1 / (1 + exp(-(zip(w, row).reduce(b) { $0 + $1.0 * $1.1 })))
                let err = p - label
                for i in 0..<d { gw[i] += err * row[i] }
                gb += err
            }
            for i in 0..<d { w[i] -= rate * (gw[i] / n + lambda * w[i]) }
            b -= rate * gb / n
        }
        return NapLearnerModel(trainedAt: now, positives: pos.count, negatives: neg.count, mean: mean, scale: scale, weights: w, bias: b,
                               featureVersion: featureVersion)
    }

    /// The chance the window is a nap (0 to 1), or nil when the model is from another feature layout.
    public static func probability(_ model: NapLearnerModel, _ f: NapWindowFeatures) -> Double? {
        guard model.featureVersion == featureVersion, model.weights.count == names.count else { return nil }
        let row = vector(f)
        let s = (0..<names.count).reduce(model.bias) { $0 + model.weights[$1] * (row[$1] - model.mean[$1]) / model.scale[$1] }
        return 1 / (1 + exp(-s))
    }
}

/// The learner against the rules on the same labelled windows, each predicted by a model trained without it.
public struct NapLearnerComparison: Equatable, Sendable {
    public let windows: Int
    public let rulesCorrect: Int
    public let learnerCorrect: Int
    /// Naps the rules would have missed, and how many of those the learner would have kept.
    public let rulesMissedNaps: Int
    public let learnerRescuedNaps: Int
    /// Deleted (not-nap) windows the rules would have kept, and how many of those the learner would have dropped.
    public let rulesFalseNaps: Int
    public let learnerDroppedFalseNaps: Int
}

public enum NapLearnerReplay {
    public static func rulesSayNap(_ f: NapWindowFeatures) -> Bool {
        NapRules.passes(durationS: Int(f.durationMin * 60), restingRatio: f.restingRatio, bandAsleepFraction: f.bandAsleepFraction)
    }

    /// nil when there are not enough windows of each kind for a model to exist (there is nothing to compare).
    public static func leaveOneOut(_ windows: [LabelledNapWindow], now: Int = 0) -> NapLearnerComparison? {
        guard NapLearner.train(windows, now: now) != nil else { return nil }
        var rc = 0, lc = 0, missed = 0, rescued = 0, falseNaps = 0, dropped = 0, scored = 0
        for (i, w) in windows.enumerated() {
            var rest = windows; rest.remove(at: i)
            guard let model = NapLearner.train(rest, now: now), let p = NapLearner.probability(model, w.features) else { continue }
            scored += 1
            let rules = rulesSayNap(w.features), learner = p >= 0.5
            if rules == w.isNap { rc += 1 }
            if learner == w.isNap { lc += 1 }
            if w.isNap, !rules { missed += 1; if learner { rescued += 1 } }
            if !w.isNap, rules { falseNaps += 1; if !learner { dropped += 1 } }
        }
        return NapLearnerComparison(windows: scored, rulesCorrect: rc, learnerCorrect: lc, rulesMissedNaps: missed, learnerRescuedNaps: rescued,
                                    rulesFalseNaps: falseNaps, learnerDroppedFalseNaps: dropped)
    }
}
