import Foundation
import WhoopProtocol

// WhoopStress.swift — the "WHOOP reference" reading of the Stress monitor, kept BESIDE `DaytimeStress`, never in place of it.
//
// What it follows is the public description of WHOOP's Stress Monitor, which gives no formula:
//   • a real-time score from 0 to 3 from the heart rate AND the heart rate variability in the moment, against a personal baseline
//     (a heart rate variability baseline from the last 14 days, and the typical resting heart rate);
//   • the effect of exercise is limited by taking motion into account;
//   • stress is split three ways: Total day (it includes exercise and sleep), Non-activity (outside Strain activities and sleep) and
//     Sleep (stress while asleep, where lower is better);
//   • bands: 0.0 to 0.9 Low, 1.0 to 1.9 Medium, 2.0 to 3.0 High.
//
// Everything below that is NOT in that description is this file's own reading of it, and each such choice is a named constant in
// `Tuning` so that a simulation, or real nights, can change it without touching the code:
//   • the score is a logistic squash of a z-sum, the same curve and bands as `DaytimeStress` (so the two can be laid side by side);
//   • the epoch is 5 minutes, read over a trailing 10-minute window (a "moment", not an hour);
//   • daytime RMSSD is read from artifact-filtered R-R, on a log scale, with a minimum of clean beats, and the HRV term is dropped
//     for an epoch whose R-R is too poor — the failure `DaytimeStress.daytimeRMSSDScoringEnabled` documents;
//   • the nightly baselines are shifted for daytime (heart rate runs higher and RMSSD lower awake than asleep): `wakeHROffsetBPM`
//     and `wakeHRVRatio`, and a typical night is placed in Low (`sleepRawShift`). These are the least certain numbers here and are
//     the ones to calibrate on real data;
//   • exercise is not removed from Total day but pulled toward neutral in proportion to how much of the epoch was motion.
//
// Pure and deterministic. Experimental: not wired to any screen yet, so no Kotlin twin exists (add one before it is shown to anyone).

public enum WhoopStress {

    // MARK: - Tuning

    public struct Tuning: Equatable, Sendable {
        /// Step between epochs, seconds.
        public var epochSeconds = 300
        /// Trailing window each epoch reads, seconds (at least `epochSeconds`).
        public var windowSeconds = 600
        /// HR samples an epoch window needs before its mean is trusted.
        public var minHRSamples = 120
        /// Clean beats an epoch window needs before its RMSSD is used; below it the HRV term is dropped.
        public var minCleanBeats = 150
        /// Largest share of the window's beats that cleaning may throw away before the RMSSD is not trusted.
        public var maxRejectedFraction = 0.30
        /// Whether the HRV term is used at all (false = heart rate only, to show what the HRV term adds or costs).
        public var useHRV = true
        /// Weights of the two z-scores in the sum, and the weight a heart-rate-only epoch gives its single term.
        public var hrWeight = 0.9
        public var hrvWeight = 0.6
        public var hrOnlyWeight = 1.2
        /// A z-score is clamped to this magnitude before it is summed, so one wild reading cannot swing the score by the whole band.
        public var zClamp = 3.0
        /// How far above the typical resting heart rate a calm, sedentary waking minute sits (bpm), and a night's mean above it.
        public var wakeHROffsetBPM = 20.0
        public var sleepHROffsetBPM = 3.0
        /// Daytime RMSSD as a fraction of the nightly one when calm and sedentary.
        public var wakeHRVRatio = 0.6
        /// Added to the z-sum while asleep. WHOOP calls Low "calm, relaxed or sleepy" and Medium "neutral, alert", so a typical night
        /// (z = 0) must land in Low and a typical waking minute in Medium; without the shift both would sit at 1.5.
        public var sleepRawShift = -1.0
        /// Floors on the spreads the z-scores divide by, so a very steady baseline does not make everything extreme.
        public var hrSpreadFloorBPM = 6.0
        public var hrvLnSpreadFloor = 0.25
        /// An epoch is motion (activity) when this share of its gravity records clear the walk floor.
        public var activityFraction = 0.30
        /// How much of the distance to neutral an epoch spent entirely in motion loses in Total day (0 keeps it, 1 removes it).
        public var activityDamping = 0.75
        /// The epochs right after exertion stay out of Non-activity while HR is still this far above the waking reference.
        public var postActivityShadowSeconds = 1_800
        public var postActivityShadowBPM = 8.0
        public init() {}
    }

    // MARK: - Baseline

    /// What the score is measured against: the last 14 nights.
    public struct Baseline: Equatable, Sendable {
        /// Mean and spread of the natural log of the nightly RMSSD (ms).
        public let hrvLnMean: Double
        public let hrvLnSD: Double
        /// Mean and spread of the nightly resting heart rate (bpm).
        public let restingHR: Double
        public let restingHRSD: Double
        public let nights: Int

        public init(hrvLnMean: Double, hrvLnSD: Double, restingHR: Double, restingHRSD: Double, nights: Int) {
            self.hrvLnMean = hrvLnMean; self.hrvLnSD = hrvLnSD
            self.restingHR = restingHR; self.restingHRSD = restingHRSD; self.nights = nights
        }

        /// From the nightly figures, oldest first; uses the newest `window` (14) of them. nil with fewer than 4 of either.
        public static func from(nightlyRMSSD: [Double], nightlyRestingHR: [Double], window: Int = 14) -> Baseline? {
            let hrv = Array(nightlyRMSSD.filter { $0 > 0 }.suffix(window)).map { log($0) }
            let rhr = Array(nightlyRestingHR.filter { $0 > 0 }.suffix(window))
            guard hrv.count >= 4, rhr.count >= 4 else { return nil }
            func mean(_ x: [Double]) -> Double { x.reduce(0, +) / Double(x.count) }
            func sd(_ x: [Double]) -> Double { let m = mean(x); return (x.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(x.count)).squareRoot() }
            return Baseline(hrvLnMean: mean(hrv), hrvLnSD: sd(hrv), restingHR: mean(rhr), restingHRSD: sd(rhr), nights: min(hrv.count, rhr.count))
        }
    }

    // MARK: - Output

    public enum Kind: String, Sendable { case sleep, activity, waking }

    public struct Epoch: Equatable, Sendable {
        /// Start of the epoch, wall-clock unix seconds.
        public let ts: Int
        /// The 0 to 3 stress of the epoch, or nil when there was too little heart rate to score.
        public let level: Double?
        public let meanHR: Double?
        /// RMSSD of the window's clean R-R (ms), or nil when it was not trusted.
        public let rmssd: Double?
        public let kind: Kind
        /// Share of the window spent in motion, 0 to 1.
        public let motion: Double
        /// Whether the HRV term went into the score.
        public let usedHRV: Bool
    }

    public struct Zones: Equatable, Sendable {
        public var low = 0.0, medium = 0.0, high = 0.0
        public var total: Double { low + medium + high }
        public init(low: Double = 0, medium: Double = 0, high: Double = 0) { self.low = low; self.medium = medium; self.high = high }
        mutating func add(_ level: Double, minutes: Double) {
            if level < 1 { low += minutes } else if level < 2 { medium += minutes } else { high += minutes }
        }
    }

    public struct Result: Equatable, Sendable {
        public let epochs: [Epoch]
        /// Time in each band, in minutes, for the three categories.
        public let total: Zones
        public let nonActivity: Zones
        public let sleep: Zones
        /// The reading "right now": the mean of the last three scored epochs, or nil.
        public let current: Double?
    }

    // MARK: - Analysis

    /// - Parameters:
    ///   - sleep: the hours asleep, as ranges of wall-clock seconds.
    ///   - activities: the Strain activities (workouts), as ranges of wall-clock seconds.
    ///   - from / to: the span to read, wall-clock seconds; defaults to the first to the last heart rate sample.
    public static func analyze(hr: [HRSample], rr: [RRInterval], gravity: [GravitySample] = [],
                               sleep: [ClosedRange<Int>] = [], activities: [ClosedRange<Int>] = [],
                               baseline: Baseline, from: Int? = nil, to: Int? = nil,
                               tuning t: Tuning = Tuning()) -> Result {
        let empty = Result(epochs: [], total: Zones(), nonActivity: Zones(), sleep: Zones(), current: nil)
        guard !hr.isEmpty else { return empty }
        let hrs = hr.sorted { $0.ts < $1.ts }
        let rrs = rr.sorted { $0.ts < $1.ts }
        let start0 = from ?? hrs.first!.ts, end = to ?? hrs.last!.ts
        let step = t.epochSeconds
        let first = (start0 + step - 1) / step * step

        // Motion per gravity record, once.
        let motionPts = gravity.isEmpty ? [] : WorkoutDetector.activitySeries(gravity)

        func lowerBound<T>(_ a: [T], _ ts: Int, _ key: (T) -> Int) -> Int {
            var lo = 0, hi = a.count
            while lo < hi { let m = (lo + hi) / 2; if key(a[m]) < ts { lo = m + 1 } else { hi = m } }
            return lo
        }
        func inAny(_ ranges: [ClosedRange<Int>], _ ts: Int) -> Bool { ranges.contains { $0.contains(ts) } }

        var epochs: [Epoch] = []
        var lastActivityEnd = Int.min
        var ts = first
        while ts + step <= end + 1 {
            let wEnd = ts + step, wStart = wEnd - t.windowSeconds
            let hi = lowerBound(hrs, wEnd) { $0.ts }, lo = lowerBound(hrs, wStart) { $0.ts }
            let hrSlice = hrs[lo..<hi]
            let mid = ts + step / 2

            // Motion share of the window.
            var motion = 0.0
            if !motionPts.isEmpty {
                let mlo = lowerBound(motionPts, wStart) { $0.ts }, mhi = lowerBound(motionPts, wEnd) { $0.ts }
                if mhi > mlo {
                    let active = motionPts[mlo..<mhi].filter { $0.intensity > WorkoutDetector.motionThreshold }.count
                    motion = Double(active) / Double(mhi - mlo)
                }
            }
            let asleep = inAny(sleep, mid)
            let workout = inAny(activities, mid) || inAny(activities, wEnd - 1)
            if workout { motion = 1 }

            var kind: Kind = asleep ? .sleep : (workout || motion >= t.activityFraction ? .activity : .waking)
            if kind == .activity { lastActivityEnd = wEnd }

            guard hrSlice.count >= t.minHRSamples else {
                epochs.append(Epoch(ts: ts, level: nil, meanHR: nil, rmssd: nil, kind: kind, motion: motion, usedHRV: false))
                ts += step; continue
            }
            let meanHR = Double(hrSlice.reduce(0) { $0 + $1.bpm }) / Double(hrSlice.count)

            // RMSSD of the window's clean R-R.
            var rmssd: Double?
            if t.useHRV {
                let rlo = lowerBound(rrs, wStart) { $0.ts }, rhi = lowerBound(rrs, wEnd) { $0.ts }
                let raw = rrs[rlo..<rhi].map { Double($0.rrMs) }
                if raw.count >= t.minCleanBeats {
                    let res = HRVAnalyzer.analyze(rawRR: raw, maxRejectedFraction: t.maxRejectedFraction)
                    if res.nClean >= t.minCleanBeats, let r = res.rmssd, r > 0 { rmssd = r }
                }
            }

            // z-scores against the baseline, shifted for waking or asleep.
            let hrOffset = asleep ? t.sleepHROffsetBPM : t.wakeHROffsetBPM
            let hrRef = baseline.restingHR + hrOffset
            let hrSD = max(baseline.restingHRSD * 1.5, t.hrSpreadFloorBPM)
            let zHR = clamp((meanHR - hrRef) / hrSD, t.zClamp)
            var raw = 0.0
            var usedHRV = false
            if let rmssd {
                let ratio = asleep ? 1.0 : t.wakeHRVRatio
                let ref = baseline.hrvLnMean + log(ratio)
                let sd = max(baseline.hrvLnSD, t.hrvLnSpreadFloor)
                let zHRV = clamp((ref - log(rmssd)) / sd, t.zClamp)
                raw = zHR * t.hrWeight + zHRV * t.hrvWeight
                usedHRV = true
            } else {
                raw = zHR * t.hrOnlyWeight
            }
            if asleep { raw += t.sleepRawShift }
            var level = 3.0 / (1.0 + exp(-raw))

            // Exercise is limited, not read as stress: pulled toward neutral by the share of the window spent in motion.
            if kind != .sleep, motion > 0 { level = 1.5 + (level - 1.5) * (1 - t.activityDamping * motion) }
            // The epochs right after exertion, while the heart rate is still up, are shadow: out of Non-activity.
            if kind == .waking, lastActivityEnd != Int.min, wEnd - lastActivityEnd <= t.postActivityShadowSeconds,
               meanHR > hrRef + t.postActivityShadowBPM { kind = .activity }

            epochs.append(Epoch(ts: ts, level: level, meanHR: meanHR, rmssd: rmssd, kind: kind, motion: motion, usedHRV: usedHRV))
            ts += step
        }

        let minutes = Double(step) / 60
        var total = Zones(), non = Zones(), slp = Zones()
        for e in epochs {
            guard let l = e.level else { continue }
            total.add(l, minutes: minutes)
            switch e.kind {
            case .sleep: slp.add(l, minutes: minutes)
            case .waking: non.add(l, minutes: minutes)
            case .activity: break
            }
        }
        let recent = epochs.compactMap(\.level).suffix(3)
        let current = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        return Result(epochs: epochs, total: total, nonActivity: non, sleep: slp, current: current)
    }

    private static func clamp(_ x: Double, _ m: Double) -> Double { min(max(x, -m), m) }
}
