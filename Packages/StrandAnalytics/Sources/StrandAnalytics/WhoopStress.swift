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
// Pure and deterministic. It is the reading the iOS app shows (through `StressEngine`), and only once `Calibration.requiredNights` nights are in.
// `DaytimeStress` stays beside it as the previous formula. There is no Kotlin twin yet: the Android app still uses the previous formula.

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
    public struct Baseline: Equatable, Sendable, Codable {
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

    // MARK: - Personal calibration

    /// Sets the two waking constants from the person's own days instead of fixed numbers: `wakeHROffsetBPM` becomes how far their
    /// typical (median) waking, sedentary heart rate sits above their resting heart rate, and `wakeHRVRatio` how their typical waking RMSSD
    /// compares with their nightly one. Their usual waking state then scores as neutral (Medium), which is what "neutral, alert" means.
    ///
    /// `epochs` are those of an `analyze` over the baseline days (any tuning: the heart rate and the RMSSD they carry do not depend on it).
    /// Returns `base` unchanged when there are fewer than `minEpochs` waking epochs to take a median from.
    public static func calibrated(_ base: Tuning, from epochs: [Epoch], baseline: Baseline, minEpochs: Int = 100) -> Tuning {
        let w = wakingReadings(epochs)
        return calibrated(base, wakingHR: w.hr, wakingRMSSD: w.rmssd, baseline: baseline, minEpochs: minEpochs)
    }

    /// The heart rates and the trusted RMSSDs of the waking, sedentary epochs that were scored: what the two waking constants are read from.
    /// Kept apart so a day's readings can be stored and a long window put together without reading its raw samples again.
    public static func wakingReadings(_ epochs: [Epoch]) -> (hr: [Double], rmssd: [Double]) {
        let waking = epochs.filter { $0.kind == .waking && $0.level != nil }
        return (waking.compactMap(\.meanHR), waking.compactMap(\.rmssd))
    }

    /// The same calibration from the readings themselves (`wakingReadings`), pooled over as many days as the caller keeps.
    public static func calibrated(_ base: Tuning, wakingHR: [Double], wakingRMSSD: [Double], baseline: Baseline, minEpochs: Int = 100) -> Tuning {
        guard wakingHR.count >= minEpochs else { return base }
        func median(_ x: [Double]) -> Double? {
            guard !x.isEmpty else { return nil }
            let s = x.sorted(); return s[s.count / 2]
        }
        var t = base
        if let hr = median(wakingHR) { t.wakeHROffsetBPM = min(max(hr - baseline.restingHR, 5), 40) }
        if wakingRMSSD.count >= minEpochs / 2, let r = median(wakingRMSSD) { t.wakeHRVRatio = min(max(r / exp(baseline.hrvLnMean), 0.25), 1.2) }
        return t
    }

    // MARK: - Calibration record

    /// Everything the reading needs about one person, kept between runs: the 14-night baseline and the two waking constants, set from
    /// the last `wakeDays` days. It exists only once `requiredNights` nights are in; before that the reading is calibrating and shows nothing.
    public struct Calibration: Equatable, Sendable, Codable {
        /// Bumped when the method changes, so an older record is rebuilt rather than trusted.
        public static let version = 2
        public static let requiredNights = 14
        /// Days the two waking constants are read from: the newest 60 that have data, not the 14 of the baseline. With 14 the constants
        /// followed the person so closely that a hard fortnight became the new normal: three hard weeks read as ordinary by the second week,
        /// and the week after read as unusually calm. Over 60 days a hard or an easy spell stays visible, and the constants still follow a
        /// slow change in fitness (through the 14-night baseline they are measured against). Measured with `Tools/StressSim --sixmonths`.
        public static let wakeDays = 60

        public var version: Int
        public var baseline: Baseline
        public var wakeHROffsetBPM: Double
        public var wakeHRVRatio: Double
        /// Day key (yyyy-MM-dd) of the newest night in the baseline, so a new night triggers a rebuild.
        public var newestNight: String

        public init(baseline: Baseline, tuning: Tuning, newestNight: String) {
            self.version = Calibration.version
            self.baseline = baseline
            self.wakeHROffsetBPM = tuning.wakeHROffsetBPM
            self.wakeHRVRatio = tuning.wakeHRVRatio
            self.newestNight = newestNight
        }

        /// The stock tuning with this person's two waking constants.
        public var tuning: Tuning {
            var t = Tuning()
            t.wakeHROffsetBPM = wakeHROffsetBPM
            t.wakeHRVRatio = wakeHRVRatio
            return t
        }
    }

    // MARK: - The figures of one night

    /// The resting heart rate and RMSSD of a night, the way the baseline reads them: the resting heart rate is the mean of the lowest tenth
    /// of the 5-minute mean heart rates, the RMSSD the mean of the 5-minute RMSSDs (each from cleaned R-R). nil when the night has too
    /// little of either to read.
    public static func nightFigures(hr: [HRSample], rr: [RRInterval], from: Int, to: Int) -> (rhr: Double, rmssd: Double)? {
        var means: [Double] = [], rmssds: [Double] = []
        let hrs = hr.sorted { $0.ts < $1.ts }, rrs = rr.sorted { $0.ts < $1.ts }
        var hi = 0, ri = 0
        var t = from
        while t + 300 <= to {
            var sum = 0, n = 0
            while hi < hrs.count, hrs[hi].ts < t + 300 { if hrs[hi].ts >= t { sum += hrs[hi].bpm; n += 1 }; hi += 1 }
            var raw: [Double] = []
            while ri < rrs.count, rrs[ri].ts < t + 300 { if rrs[ri].ts >= t { raw.append(Double(rrs[ri].rrMs)) }; ri += 1 }
            if n > 50 { means.append(Double(sum) / Double(n)) }
            if raw.count >= 60, let v = HRVAnalyzer.analyze(rawRR: raw).rmssd, v > 0 { rmssds.append(v) }
            t += 300
        }
        guard !means.isEmpty, !rmssds.isEmpty else { return nil }
        let low = means.sorted().prefix(max(1, means.count / 10))
        return (low.reduce(0, +) / Double(low.count), rmssds.reduce(0, +) / Double(rmssds.count))
    }

    // MARK: - The shape the existing screens read

    /// A reading in the shape the existing stress surfaces already draw (`DaytimeStress.Result`): hourly and half-hourly points, the
    /// minutes in the High band, the day's mean and peak. Every epoch counts, asleep and in motion included, which is the Total day reading;
    /// the three categories stay on the `Result` itself. A point needs a few scored epochs, so a bucket with almost nothing is left out.
    public static func daytimeResult(_ r: Result, tzOffsetSeconds: Int = 0) -> DaytimeStress.Result {
        func floorDiv(_ a: Int, _ b: Int) -> Int { let q = a / b, m = a % b; return (m != 0 && (m < 0) != (b < 0)) ? q - 1 : q }
        func points(_ width: Int, minimum: Int) -> [DaytimeStress.HourPoint] {
            var buckets: [Int: [Epoch]] = [:]
            for e in r.epochs where e.level != nil { buckets[floorDiv(e.ts + tzOffsetSeconds, width), default: []].append(e) }
            return buckets.keys.sorted().compactMap { k -> DaytimeStress.HourPoint? in
                let es = buckets[k]!
                guard es.count >= minimum else { return nil }
                let levels = es.compactMap(\.level), hrs = es.compactMap(\.meanHR)
                let start = k * width - tzOffsetSeconds
                let hour = floorDiv(k * width, 3600) % 24
                return DaytimeStress.HourPoint(hour: (hour + 24) % 24, startTs: start, level: levels.reduce(0, +) / Double(levels.count),
                                               meanHR: hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count), rmssd: nil)
            }
        }
        let hours = points(3_600, minimum: 3)
        let timeline = points(1_800, minimum: 2)
        let scored = hours.compactMap { h in h.level.map { (h, $0) } }
        var run = 0
        for (_, l) in scored.reversed() { if l >= DaytimeStress.highBandFloor { run += 1 } else { break } }
        let high = r.epochs.filter { ($0.level ?? 0) >= DaytimeStress.highBandFloor }.count * (r.epochs.isEmpty ? 0 : 5)
        return DaytimeStress.Result(hours: hours, sustainedHigh: run >= DaytimeStress.sustainedHours, sustainedRun: run >= DaytimeStress.sustainedHours ? run : 0,
                                    dayMean: scored.isEmpty ? nil : scored.map(\.1).reduce(0, +) / Double(scored.count),
                                    peak: scored.max { $0.1 < $1.1 }?.0, activityMaskedHours: 0, highStressMinutes: high,
                                    hrOnlyFallback: false, timeline: timeline)
    }

    private static func clamp(_ x: Double, _ m: Double) -> Double { min(max(x, -m), m) }
}
