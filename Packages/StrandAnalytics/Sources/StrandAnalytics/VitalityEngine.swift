import Foundation

// VitalityEngine.swift — a transparent 0–100 "Vitality" wellness score + an optional "Body Age in years".
//
// INDEPENDENT implementation of the published, peer-reviewed method WHOOP's "Healthspan / WHOOP Age" also
// uses (NOT medical advice; a wellness comparison, never a clinical biological age): map each wearable-
// measurable input to its published ALL-CAUSE-MORTALITY hazard ratio relative to a population reference,
// sum the log-hazards with an overlap correction (the inputs are correlated, so the naive sum overstates),
// and convert that combined hazard into a "years of aging" offset using the Gompertz mortality-rate
// doubling time (mortality roughly doubles every ~8 years, so 1 doubling of hazard ≈ 8 years of age).
//
// Body Age = chronological age + Δage. An average-for-their-age person nets ~0 and reads at their own age;
// healthier-than-average reads younger, less healthy reads older. Presented with a ±band and a hard
// "wellness trend, not a biological/clinical age" disclaimer, gated on a minimum number of inputs.
//
// Per-factor hazard ratios are taken from large cohorts / meta-analyses (UK Biobank, FRIEND, pooled
// step- and activity-mortality meta-analyses, sleep-regularity and HRV cohorts). They are deliberately
// CONSERVATIVE and the model is clamped, because this is a wellness estimate, not a diagnosis.
public enum VitalityEngine {

    // Gompertz: mortality-rate doubling time ≈ 8 years → ln(hazard) per year of age = ln(2)/8.
    static let lnHazardPerYear = 0.6931471805599453 / 8.0   // ≈ 0.0866
    /// Correlated inputs (fitness, RHR, activity all move together) → shrink the naive log-hazard sum so
    /// we don't multiply the same underlying signal several times. 0.75 is a deliberately gentle shrink.
    static let overlapShrink = 0.75
    /// Body Age is clamped to a sane band; Vitality maps Δage linearly around 50 (= "at your age").
    static let minBodyAge = 20.0, maxBodyAge = 90.0
    static let vitalityPerYear = 2.5   // each year younger than your age = +2.5 Vitality points

    /// The wearable inputs Vitality reads. All optional — the score uses whatever is present (≥ minFactors).
    public struct Inputs: Equatable, Sendable {
        public var chronoAge: Double
        public var restingHR: Double?          // bpm
        public var vo2max: Double?             // ml/kg/min (e.g. from FitnessAgeEngine)
        public var expectedVO2max: Double?     // age/sex-expected ml/kg/min (the reference for vo2max)
        public var sleepHours: Double?         // mean nightly sleep
        public var sleepConsistency: Double?   // 0–1 regularity (1 = perfectly regular)
        public var rmssd: Double?              // ms, nocturnal HRV
        public var rmssdNorm: Double?          // age/sex-normative RMSSD (the reference)
        public var steps: Double?              // mean daily steps
        public var zonesLowMin: Double?        // minutes per week in heart-rate zones 1–3
        public var zonesHighMin: Double?       // minutes per week in heart-rate zones 4–5
        public var strengthMin: Double?        // minutes per week of strength training
        public init(chronoAge: Double, restingHR: Double? = nil, vo2max: Double? = nil,
                    expectedVO2max: Double? = nil, sleepHours: Double? = nil,
                    sleepConsistency: Double? = nil, rmssd: Double? = nil,
                    rmssdNorm: Double? = nil, steps: Double? = nil,
                    zonesLowMin: Double? = nil, zonesHighMin: Double? = nil, strengthMin: Double? = nil) {
            self.chronoAge = chronoAge; self.restingHR = restingHR; self.vo2max = vo2max
            self.expectedVO2max = expectedVO2max; self.sleepHours = sleepHours
            self.sleepConsistency = sleepConsistency; self.rmssd = rmssd
            self.rmssdNorm = rmssdNorm; self.steps = steps
            self.zonesLowMin = zonesLowMin; self.zonesHighMin = zonesHighMin; self.strengthMin = strengthMin
        }
    }

    /// One factor's contribution: its label and signed log-hazard vs the population reference
    /// (positive = ages you, negative = protective).
    public struct Contribution: Equatable, Sendable {
        public let key: String
        public let label: String
        public let lnHazard: Double
        public init(key: String, label: String, lnHazard: Double) {
            self.key = key; self.label = label; self.lnHazard = lnHazard
        }
    }

    public struct Result: Equatable, Sendable {
        public let vitality: Double        // 0–100 (50 = typical for your age)
        public let bodyAge: Double         // years, clamped
        public let chronoAge: Double
        public let deltaYears: Double      // chronoAge − bodyAge (positive = younger than your age)
        public let bandYears: Double
        public let contributions: [Contribution]   // for the "what's driving this" breakdown
        public let factorsUsed: Int
        public init(vitality: Double, bodyAge: Double, chronoAge: Double, deltaYears: Double,
                    bandYears: Double, contributions: [Contribution], factorsUsed: Int) {
            self.vitality = vitality; self.bodyAge = bodyAge; self.chronoAge = chronoAge
            self.deltaYears = deltaYears; self.bandYears = bandYears
            self.contributions = contributions; self.factorsUsed = factorsUsed
        }
    }

    /// Minimum distinct factors before we'll show a number (honesty gate).
    public static let minFactors = 3
    public static let bandYears = 5.0

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// Nocturnal RMSSD ~50th-percentile by age (ms), piecewise-linear between decade anchors (the WHOOP-
    /// window norms banked in the spec — never mixed with daytime clinical norms). The reference for the
    /// HRV factor: a person at the age norm contributes 0.
    public static func rmssdNorm(forAge age: Double) -> Double {
        let anchors: [(Double, Double)] = [(20, 47), (30, 40), (40, 33), (50, 29), (60, 25), (70, 22), (80, 20)]
        if age <= anchors[0].0 { return anchors[0].1 }
        if age >= anchors[anchors.count - 1].0 { return anchors[anchors.count - 1].1 }
        for i in 1..<anchors.count where age <= anchors[i].0 {
            let (a0, v0) = anchors[i - 1]; let (a1, v1) = anchors[i]
            return v0 + (v1 - v0) * (age - a0) / (a1 - a0)
        }
        return anchors[anchors.count - 1].1
    }

    /// Sleep regularity (0–1) from a window of nightly sleep durations (hours): 1 − coefficient of
    /// variation, clamped. A rough but honest on-device proxy for the Sleep Regularity Index when we only
    /// have durations, not full timing. Fewer than 3 nights → nil (not enough to judge).
    public static func sleepConsistency(nightlyHours: [Double]) -> Double? {
        let xs = nightlyHours.filter { $0 > 0 }
        guard xs.count >= 3 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        guard mean > 0 else { return nil }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        let cv = variance.squareRoot() / mean
        return clamp(1 - cv, 0, 1)
    }

    /// Compute the per-factor log-hazard contributions present in `inputs`. Each references a population
    /// value, so an average person nets ~0. Published per-unit hazard ratios (conservative, clamped):
    ///   • Resting HR: +~10.5% all-cause mortality per +10 bpm (UK Biobank / meta-analyses). ref 65.
    ///   • VO₂max: ~14% per MET (3.5 ml/kg/min) vs the age/sex-expected value (FRIEND). fitter = protective.
    ///   • Sleep duration: U-shaped, optimum ~7.5 h; only deviation beyond ±0.5 h adds hazard (~12%/h).
    ///   • Sleep regularity: most-regular vs least ≈ HR 0.70 (UK Biobank SRI). ref 0.75 of the 0–1 range.
    ///   • HRV (RMSSD): ~16% per relative SD below the age norm (lower HRV = higher hazard).
    ///   • Steps: ~12% per 1,000 steps/day up to ~7k, diminishing to ~11k (pooled step-mortality meta).
    ///   • Zones 1–3 minutes/week: see `lowZoneEffect`, break-even 150 min (the WHO moderate-activity guideline).
    ///   • Zones 4–5 minutes/week: see `highZoneEffect`, break-even 30 min.
    ///   • Strength minutes/week: see `strengthEffect`, break-even 60 min.
    public static func contributions(_ inputs: Inputs) -> [Contribution] {
        var out: [Contribution] = []
        if let rhr = inputs.restingHR {
            out.append(Contribution(key: "rhr", label: "Resting heart rate",
                                    lnHazard: ((rhr - 65) / 10) * 0.100))
        }
        if let vo2 = inputs.vo2max, let exp = inputs.expectedVO2max, exp > 0 {
            // (expected − vo2): if fitter than expected this is negative → protective.
            out.append(Contribution(key: "vo2max", label: "Cardio fitness",
                                    lnHazard: clamp((exp - vo2) / 3.5, -4, 4) * 0.130))
        }
        if let sh = inputs.sleepHours {
            let dev = max(0, abs(sh - 7.5) - 0.5)   // only deviation > ±0.5 h is a risk; optimum is neutral
            out.append(Contribution(key: "sleep", label: "Sleep duration",
                                    lnHazard: clamp(dev, 0, 3) * 0.110))
        }
        if let c = inputs.sleepConsistency {
            out.append(Contribution(key: "consistency", label: "Sleep regularity",
                                    lnHazard: (0.75 - clamp(c, 0, 1)) * 0.450))
        }
        if let h = inputs.rmssd, let norm = inputs.rmssdNorm, norm > 0 {
            out.append(Contribution(key: "hrv", label: "Heart-rate variability",
                                    lnHazard: clamp((norm - h) / norm, -1, 1) * 0.160))
        }
        if let s = inputs.steps {
            // Below ~7k each −1,000 steps adds hazard; protection caps near 11k (diminishing returns).
            let deficit = (7000 - clamp(s, 0, 11000)) / 1000
            out.append(Contribution(key: "steps", label: "Daily steps",
                                    lnHazard: clamp(deficit, -4, 4) * 0.064))
        }
        if let m = inputs.zonesLowMin {
            out.append(Contribution(key: "zonesLow", label: "Heart rate zones 1–3",
                                    lnHazard: lowZoneEffect(m) - lowZoneEffect(lowZoneBreakEven)))
        }
        if let m = inputs.zonesHighMin {
            out.append(Contribution(key: "zonesHigh", label: "Heart rate zones 4–5",
                                    lnHazard: highZoneEffect(m) - highZoneEffect(highZoneBreakEven)))
        }
        if let m = inputs.strengthMin {
            out.append(Contribution(key: "strength", label: "Strength activity",
                                    lnHazard: strengthEffect(m) - strengthEffect(strengthBreakEven)))
        }
        return out
    }

    // MARK: Activity-time factors (the three WHOOP inputs beyond the six above)
    //
    // Each is an absolute log-hazard curve over minutes per week; a factor's contribution is the curve at the wearer's
    // minutes minus the curve at the break-even, so someone exactly at the break-even adds nothing. The curves are a
    // CONSERVATIVE reading of the cited work, not a re-fit: the sources measure self-reported minutes of moderate or vigorous
    // activity, while these inputs are minutes in heart-rate zones, so the match is approximate. They are the least certain
    // factors of the model; the overlap shrink below also keeps them from counting the same activity twice with steps.

    /// Weekly minutes at which the activity factors read as neutral.
    public static let lowZoneBreakEven = 150.0, highZoneBreakEven = 30.0, strengthBreakEven = 60.0

    /// Zones 1–3: Wen et al. 2011 (Lancet): the first ~92 min/week of moderate activity lowers all-cause mortality ~14%, every
    /// further ~92 min a further ~4%. Flat beyond ~10 h/week.
    public static func lowZoneEffect(_ minutesPerWeek: Double) -> Double {
        let m = clamp(minutesPerWeek, 0, 600)
        return -0.151 * min(m, 92) / 92 - 0.040 * max(0, m - 92) / 92
    }

    /// Zones 4–5: an extra ~10% lower hazard by two hours a week of vigorous activity on top of the moderate curve
    /// (the direction of Arem 2015 and Stamatakis 2022; the size is a deliberately small reading of them).
    public static func highZoneEffect(_ minutesPerWeek: Double) -> Double {
        -0.0012 * clamp(minutesPerWeek, 0, 120)
    }

    /// Strength: Momma et al. 2022 (BJSM): 30–60 min/week of muscle-strengthening is linked to roughly 10–17% lower all-cause
    /// mortality, with no further gain past about an hour.
    public static func strengthEffect(_ minutesPerWeek: Double) -> Double {
        -0.12 * min(clamp(minutesPerWeek, 0, 600), 60) / 60
    }

    /// The years of age a factor adds (positive, older) or takes away (negative, younger) as `compute` counts it, after the overlap shrink, so a screen
    /// that lists the factors shows figures that add up to the Body Age.
    public static func years(of contribution: Contribution) -> Double {
        contribution.lnHazard * overlapShrink / lnHazardPerYear
    }

    /// Full Vitality + Body Age. Returns nil until at least `minFactors` inputs are present.
    public static func compute(_ inputs: Inputs) -> Result? {
        guard inputs.chronoAge > 0 else { return nil }
        let contribs = contributions(inputs)
        guard contribs.count >= minFactors else { return nil }
        let sumLn = contribs.reduce(0) { $0 + $1.lnHazard } * overlapShrink
        let deltaAge = sumLn / lnHazardPerYear              // +ve = ages you
        let bodyAge = clamp(inputs.chronoAge + deltaAge, minBodyAge, maxBodyAge)
        let delta = inputs.chronoAge - bodyAge              // +ve = younger than your age
        let vitality = clamp(50 + delta * vitalityPerYear, 0, 100)
        return Result(vitality: vitality, bodyAge: bodyAge, chronoAge: inputs.chronoAge,
                      deltaYears: delta, bandYears: bandYears, contributions: contribs,
                      factorsUsed: contribs.count)
    }
}
