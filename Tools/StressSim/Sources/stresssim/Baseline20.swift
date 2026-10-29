import Foundation
import StrandAnalytics
import WhoopProtocol

// --baseline20: twenty days. The first 14 are the baseline period (the WHOOP-ver learns its baseline and calibrates itself from them,
// the legacy personal-baseline mode folds them into its daytime baseline). Days 15 to 20 are the test: nothing is tuned on them.

/// Everything one run of the twenty days needs, computed once.
struct B20 {
    let life: Life
    let data: SimData
    let nightMetrics: [(rhr: Double, rmssd: Double)]          // nights 0...20, measured from the data the way a night is read
    let baseline: WhoopStress.Baseline                         // nights 1...14
    let calibrated: WhoopStress.Tuning                         // personal, from days 1...14
    let legacyHR: BaselineState                                // the app's own opt-in personal daytime baseline, from days 1...14
    let artifact: Double

    init(artifact: Double) {
        self.artifact = artifact
        let life = Life.build()
        let data = life.generate(artifact: artifact)
        self.life = life; self.data = data
        var nm: [(rhr: Double, rmssd: Double)] = []
        for j in 0...Life.dayCount {
            let r = Life.sleepRange(j)
            nm.append(NightMetrics.measure(hr: data.hr, rr: data.rr, from: data.t0 + r.lowerBound, to: data.t0 + r.upperBound))
        }
        nightMetrics = nm
        let base = Array(nm[1...Life.baselineDays])
        let b = WhoopStress.Baseline.from(nightlyRMSSD: base.map(\.rmssd), nightlyRestingHR: base.map(\.rhr))!
        baseline = b
        // The baseline days' epochs, scored with the stock tuning, are what the personal calibration reads its medians from.
        let end = data.t0 + Life.baselineDays * 86_400 + Int(6.5 * 3600)
        let first = WhoopStress.analyze(hr: data.hr, rr: data.rr, gravity: data.gravity, sleep: data.sleep, activities: data.workouts,
                                        baseline: b, from: data.t0 + Int(6.5 * 3600), to: end)
        calibrated = WhoopStress.calibrated(WhoopStress.Tuning(), from: first.epochs, baseline: b)
        // The legacy personal-baseline mode: each baseline day reduced to the P10 of its waking-hour mean HR, folded like a nightly baseline.
        var aggs: [Double?] = []
        for d in 0..<Life.baselineDays { aggs.append(B20.dayHRFloor(data, day: d)) }
        legacyHR = Baselines.foldHistory(aggs, cfg: Baselines.daytimeHRCfg)
    }

    /// P10 of the waking-hour mean heart rates of one day, as `DaytimeBaselines.dayDaytimeAggregate` defines it.
    static func dayHRFloor(_ d: SimData, day: Int) -> Double? {
        let a = d.t0 + day * 86_400
        var sums = [Int](repeating: 0, count: 24), counts = [Int](repeating: 0, count: 24)
        for s in d.hr where s.ts >= a && s.ts < a + 86_400 { let h = (s.ts - a) / 3600; sums[h] += s.bpm; counts[h] += 1 }
        let means = (6..<22).compactMap { counts[$0] >= 300 ? Double(sums[$0]) / Double(counts[$0]) : nil }.sorted()
        guard !means.isEmpty else { return nil }
        let pos = 0.10 * Double(means.count - 1), lo = Int(pos), hi = min(lo + 1, means.count - 1)
        return means[lo] + (pos - Double(lo)) * (means[hi] - means[lo])
    }

    func legacyDay(_ d: Int, personal: Bool) -> DaytimeStress.Result {
        let a = data.t0 + d * 86_400, b = a + 86_400
        return DaytimeStress.analyze(hr: data.hr.filter { $0.ts >= a && $0.ts < b }, rr: data.rr.filter { $0.ts >= a && $0.ts < b },
                                     gravity: data.gravity.filter { $0.ts >= a && $0.ts < b }, tzOffsetSeconds: 0,
                                     mode: personal ? .baselineRelative(hr: legacyHR, rmssd: nil) : .dayRelative)
    }

    func whoop(_ t: WhoopStress.Tuning) -> WhoopStress.Result {
        // The test days only: from the morning of day 15 to the morning after day 20.
        let from = data.t0 + Life.baselineDays * 86_400 + Int(6.5 * 3600) + 1
        return WhoopStress.analyze(hr: data.hr, rr: data.rr, gravity: data.gravity, sleep: data.sleep, activities: data.workouts,
                                   baseline: baseline, from: from, to: data.t0 + Life.totalSeconds - 1, tuning: t)
    }

    func waking(_ d: Int) -> Range<Int> { (Life.sleepRange(d).upperBound + 1)..<Life.sleepRange(d + 1).lowerBound }
    func night(_ j: Int) -> Range<Int> { let r = Life.sleepRange(j); return r.lowerBound..<(r.upperBound + 1) }

    func truthZones(_ w: Range<Int>, keep: (Moment, Int) -> Bool) -> [Double] {
        var z = [0.0, 0.0, 0.0]
        for i in w where keep(data.truth[i], i) { z[band(data.truth[i].s)] += 1.0 / 60 }
        return z
    }
}

/// How many minutes an estimate puts in the wrong band, as a share of the minutes the truth has: half the L1 distance between the two
/// band distributions.
func misallocated(_ est: [Double], _ truth: [Double]) -> Double {
    let t = truth.reduce(0, +)
    guard t > 0 else { return 0 }
    return 0.5 * zip(est, truth).map { abs($0 - $1) }.reduce(0, +) / t
}

struct Score {
    var hourly = Accuracy()
    var highPrecision = 0.0, highRecall = 0.0
    /// Tracking that does not depend on where the scale is anchored: the spread of the error, and how well the six daily means and the
    /// six nights follow the truth.
    var residSD = 0.0, dayR = 0.0, nightR = 0.0
    var nightMAE = 0.0, nightBand = 0.0
    var nonActivity = 0.0, sleep = 0.0, total = 0.0      // minutes misallocated, share of truth minutes, mean over the test days
}

/// The test days' hours that can be compared: sedentary at least half the hour, hours 06 to 22.
func testHours(_ run: B20) -> [(day: Int, hour: Int, truth: Double)] {
    var out: [(Int, Int, Double)] = []
    for d in Life.baselineDays..<Life.dayCount {
        for h in 6..<22 {
            let a = d * 86_400 + h * 3600
            var s = 0.0, n = 0
            for i in a..<(a + 3600) where run.data.truth[i].body == .sedentary { s += run.data.truth[i].s; n += 1 }
            if n >= 1800 { out.append((d, h, s / Double(n))) }
        }
    }
    return out
}

func pearson(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count > 1, a.count == b.count else { return 0 }
    let n = Double(a.count), ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
    let c = zip(a, b).map { ($0 - ma) * ($1 - mb) }.reduce(0, +)
    let va = a.map { ($0 - ma) * ($0 - ma) }.reduce(0, +), vb = b.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
    return va > 0 && vb > 0 ? c / (va * vb).squareRoot() : 0
}

struct HourlyResult { var acc = Accuracy(); var precision = 0.0, recall = 0.0, residSD = 0.0, dayR = 0.0 }

func hourlyScore(_ run: B20, _ est: (Int, Int) -> Double?) -> HourlyResult {
    var out = HourlyResult()
    let hours = testHours(run)
    var pairs: [(d: Int, t: Double, e: Double)] = []
    for h in hours { if let e = est(h.day, h.hour) { pairs.append((h.day, h.truth, e)) } }
    out.acc.n = pairs.count; out.acc.covered = hours.count
    guard !pairs.isEmpty else { return out }
    let n = Double(pairs.count)
    out.acc.mae = pairs.map { abs($0.e - $0.t) }.reduce(0, +) / n
    out.acc.bias = pairs.map { $0.e - $0.t }.reduce(0, +) / n
    out.acc.r = pearson(pairs.map(\.t), pairs.map(\.e))
    out.acc.agree = Double(pairs.filter { band($0.t) == band($0.e) }.count) / n
    out.acc.falseHighH = pairs.filter { $0.e >= 2 && $0.t < 2 }.count
    out.acc.missedHighH = pairs.filter { $0.e < 2 && $0.t >= 2 }.count
    let called = pairs.filter { $0.e >= 2 }.count, real = pairs.filter { $0.t >= 2 }.count
    let hit = pairs.filter { $0.e >= 2 && $0.t >= 2 }.count
    out.precision = called == 0 ? 0 : Double(hit) / Double(called); out.recall = real == 0 ? 0 : Double(hit) / Double(real)
    let resid = pairs.map { $0.e - $0.t }, mr = resid.reduce(0, +) / n
    out.residSD = (resid.map { ($0 - mr) * ($0 - mr) }.reduce(0, +) / n).squareRoot()
    var dt: [Double] = [], de: [Double] = []
    for d in Set(pairs.map(\.d)).sorted() {
        let p = pairs.filter { $0.d == d }
        dt.append(p.map(\.t).reduce(0, +) / Double(p.count)); de.append(p.map(\.e).reduce(0, +) / Double(p.count))
    }
    out.dayR = pearson(dt, de)
    return out
}

func whoopHourlyB(_ run: B20, _ r: WhoopStress.Result) -> (Int, Int) -> Double? {
    var buckets: [Int: [Double]] = [:]
    for e in r.epochs where e.kind == .waking { if let l = e.level { buckets[(e.ts - run.data.t0) / 3600, default: []].append(l) } }
    return { d, h in
        guard let v = buckets[d * 24 + h], v.count >= 6 else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }
}

func legacyHourlyB(_ results: [Int: DaytimeStress.Result]) -> (Int, Int) -> Double? {
    { d, h in results[d]?.hours.first { $0.hour == h }?.level }
}

func runBaseline20(outDir: String?) throws {
    print("""
    StressSim, twenty days. Days 1-14: ordinary life at random (the baseline). Days 15-20 are the test, none of it used to tune anything:
      15 calm | 16 meeting 09-11 (2.4), workout 17:30, tense evening (2.2) | 17 after a poorer night, steady 1.4 and a deadline 14:00 (2.7)
      18 ill: stressed all day (2.0), body hotter and flatter (+5 bpm, HRV x0.75) | 19 recovery, long morning workout | 20 mixed: two spikes
    "Day k" is the waking day plus the night after it. Bands: Low < 1, Medium 1 to 2, High >= 2.
    Methods: legacy = the app's existing reading as shipped (day's own calm reference; nights against the trailing nights);
             legacy+personal = the app's own opt-in personal daytime-HR baseline mode, folded from days 1-14;
             WHOOP-ver fixed = WhoopStress with its stock constants; WHOOP-ver calibrated = the same, constants set from days 1-14.
    """)

    var summary: [(artifact: Double, rows: [(String, Score)])] = []
    var mainSeries: [String: Any] = [:]
    for artifact in [0.0, 0.08, 0.3] {
        let run = B20(artifact: artifact)
        let b = run.baseline
        print(String(format: "\n######## daytime artifacts %@ ########", artifact == 0 ? "none" : (artifact == 0.08 ? "moderate (burst every ~12 min)" : "heavy (burst every ~3 min)")))
        print(String(format: "baseline from days 1-14: resting HR %.1f bpm (sd %.1f), nightly RMSSD %.0f ms (ln sd %.2f)", b.restingHR, b.restingHRSD, exp(b.hrvLnMean), b.hrvLnSD))
        print(String(format: "personal calibration read from days 1-14: waking HR offset %.1f bpm (stock %.0f), daytime HRV ratio %.2f (stock %.2f); legacy personal daytime HR floor %.1f bpm",
                     run.calibrated.wakeHROffsetBPM, WhoopStress.Tuning().wakeHROffsetBPM, run.calibrated.wakeHRVRatio, WhoopStress.Tuning().wakeHRVRatio, run.legacyHR.baseline))

        var naive = run.calibrated; naive.hrWeight = 1; naive.hrvWeight = 1; naive.zClamp = 10; naive.minCleanBeats = 30; naive.maxRejectedFraction = 1.0
        var hrOnly = run.calibrated; hrOnly.useHRV = false
        let testDays = Array(Life.baselineDays..<Life.dayCount)
        var leg: [Int: DaytimeStress.Result] = [:], legP: [Int: DaytimeStress.Result] = [:]
        for d in testDays { leg[d] = run.legacyDay(d, personal: false); legP[d] = run.legacyDay(d, personal: true) }
        let wFixed = run.whoop(WhoopStress.Tuning()), wCal = run.whoop(run.calibrated), wHR = run.whoop(hrOnly), wNaive = run.whoop(naive)
        let methods: [(String, WhoopStress.Result?, [Int: DaytimeStress.Result]?)] = [
            ("legacy (as shipped)", nil, leg), ("legacy + personal baseline", nil, legP),
            ("WHOOP-ver fixed constants", wFixed, nil), ("WHOOP-ver calibrated (HR+HRV)", wCal, nil),
            ("WHOOP-ver calibrated, HR only", wHR, nil), ("WHOOP-ver calibrated, naive HRV", wNaive, nil)]

        let histNights = Array(run.nightMetrics[1...Life.baselineDays])
        var rows: [(String, Score)] = []
        for (name, w, legacy) in methods {
            var sc = Score()
            let est: (Int, Int) -> Double? = w.map { whoopHourlyB(run, $0) } ?? legacyHourlyB(legacy!)
            let hs = hourlyScore(run, est)
            sc.hourly = hs.acc; sc.highPrecision = hs.precision; sc.highRecall = hs.recall; sc.residSD = hs.residSD; sc.dayR = hs.dayR
            var nErr: [Double] = [], nBand = 0, nEst: [Double] = [], nTruth: [Double] = []
            for k in 15...20 {
                let truth = run.life.nights[k].s
                let level: Double
                if let w {
                    let w0 = run.night(k)
                    let l = w.epochs.filter { $0.kind == .sleep && w0.contains($0.ts + 150 - run.data.t0) }.compactMap(\.level)
                    level = l.reduce(0, +) / Double(max(l.count, 1))
                } else {
                    level = Legacy.nightLevel(rhr: run.nightMetrics[k].rhr, rmssd: run.nightMetrics[k].rmssd, history: histNights)
                }
                nErr.append(abs(level - truth)); if band(level) == band(truth) { nBand += 1 }
                nEst.append(level); nTruth.append(truth)
            }
            sc.nightR = pearson(nTruth, nEst)
            sc.nightMAE = nErr.reduce(0, +) / Double(nErr.count); sc.nightBand = Double(nBand) / Double(nErr.count)
            var na: [Double] = [], sl: [Double] = [], to: [Double] = []
            for k in 15...20 {
                let d = k - 1
                let wk = run.waking(d), ng = run.night(k)
                let tNon = run.truthZones(wk) { m, _ in m.body == .sedentary }
                let tNon0622 = run.truthZones(wk) { m, i in m.body == .sedentary && (i % 86_400) >= 6 * 3600 && (i % 86_400) < 22 * 3600 }
                let tSleep = run.truthZones(ng) { m, _ in m.body == .sleep }
                let tTotal = run.truthZones(wk.lowerBound..<ng.upperBound) { _, _ in true }
                func zoneOf(_ w: WhoopStress.Result, _ win: Range<Int>, _ kinds: Set<WhoopStress.Kind>) -> [Double] {
                    var z = [0.0, 0.0, 0.0]
                    for e in w.epochs { let mid = e.ts + 150 - run.data.t0; if win.contains(mid), kinds.contains(e.kind), let l = e.level { z[band(l)] += 5 } }
                    return z
                }
                if let w {
                    na.append(misallocated(zoneOf(w, wk, [.waking]), tNon))
                    sl.append(misallocated(zoneOf(w, ng, [.sleep]), tSleep))
                    to.append(misallocated(zoneOf(w, wk.lowerBound..<ng.upperBound, [.waking, .activity, .sleep]), tTotal))
                } else if let legacy {
                    var lz = [0.0, 0.0, 0.0]
                    for h in legacy[d]!.hours { if let l = h.level { lz[band(l)] += 60 } }
                    na.append(misallocated(lz, tNon0622))
                    let lvl = Legacy.nightLevel(rhr: run.nightMetrics[k].rhr, rmssd: run.nightMetrics[k].rmssd, history: histNights)
                    var sz = [0.0, 0.0, 0.0]; sz[band(lvl)] = Double(ng.count) / 60
                    sl.append(misallocated(sz, tSleep))
                    to.append(misallocated([lz[0] + sz[0], lz[1] + sz[1], lz[2] + sz[2]], tTotal))
                }
            }
            sc.nonActivity = na.reduce(0, +) / Double(na.count); sc.sleep = sl.reduce(0, +) / Double(sl.count); sc.total = to.reduce(0, +) / Double(to.count)
            rows.append((name, sc))
        }
        summary.append((artifact, rows))

        print("\nHour by hour on the test days (sedentary waking hours 06-22), against the truth:")
        print("   (MAE and bias depend on where the scale is anchored; r, resid SD and day r do not)")
        print(pad("method", 36) + " n/cov   MAE   bias     r  residSD  day r  agree  highPrec highRec")
        for (name, sc) in rows {
            let a = sc.hourly
            print(pad(name, 36) + String(format: "%3d/%-3d %5.2f %+6.2f %5.2f   %5.2f  %5.2f %5.0f%%   %5.0f%%  %5.0f%%", a.n, a.covered, a.mae, a.bias, a.r, sc.residSD, sc.dayR, a.agree * 100, sc.highPrecision * 100, sc.highRecall * 100))
        }
        print("\nNights 15-20 (level against the truth) and time in the wrong band (share of the truth's minutes, mean of the 6 days):")
        print(pad("method", 36) + " night MAE  night r  night band   non-act    sleep    total")
        for (name, sc) in rows {
            print(pad(name, 36) + String(format: "   %5.2f     %5.2f     %4.0f%%     %5.0f%%   %5.0f%%   %5.0f%%", sc.nightMAE, sc.nightR, sc.nightBand * 100, sc.nonActivity * 100, sc.sleep * 100, sc.total * 100))
        }

        if artifact == 0.08 {
            print("\nDay by day, High minutes in Non-activity (truth / legacy / legacy+personal / WHOOP-ver calibrated):")
            for k in 15...20 {
                let d = k - 1
                let truth = run.truthZones(run.waking(d)) { m, _ in m.body == .sedentary }[2]
                func lh(_ r: DaytimeStress.Result) -> Double { Double(r.hours.filter { ($0.level ?? 0) >= 2 }.count * 60) }
                var wh = 0.0
                for e in wCal.epochs where e.kind == .waking { if run.waking(d).contains(e.ts + 150 - run.data.t0), (e.level ?? 0) >= 2 { wh += 5 } }
                print(String(format: "  Day %d   %5@ / %5@ / %5@ / %5@", k, hm(truth) as NSString, hm(lh(leg[d]!)) as NSString, hm(lh(legP[d]!)) as NSString, hm(wh) as NSString))
            }
            print("\nDay 18 (ill, truth High all day): what each method calls the waking day (Low / Medium / High)")
            let d18 = 17
            let tz = run.truthZones(run.waking(d18)) { m, _ in m.body == .sedentary }
            func lz(_ r: DaytimeStress.Result) -> String { var z = [0.0, 0.0, 0.0]; for h in r.hours { if let l = h.level { z[band(l)] += 60 } }; return zones((z[0], z[1], z[2])) }
            func wz(_ w: WhoopStress.Result) -> String {
                var z = [0.0, 0.0, 0.0]
                for e in w.epochs where e.kind == .waking { if run.waking(d18).contains(e.ts + 150 - run.data.t0), let l = e.level { z[band(l)] += 5 } }
                return zones((z[0], z[1], z[2]))
            }
            print("  truth \(zones((tz[0], tz[1], tz[2])))")
            print("  legacy \(lz(leg[d18]!))   legacy+personal \(lz(legP[d18]!))")
            print("  WHOOP-ver fixed \(wz(wFixed))   calibrated \(wz(wCal))")

            if outDir != nil {
                func epochs(_ r: WhoopStress.Result) -> [[Any]] {
                    r.epochs.map { e in
                        let a = e.ts - run.data.t0
                        var s = 0.0, n = 0
                        for i in max(a, 0)..<min(a + 300, run.data.truth.count) { s += run.data.truth[i].s; n += 1 }
                        let lvl: Any = e.level.map { (($0 * 100).rounded() / 100) as Any } ?? NSNull()
                        return [Double(a) / 3600 - Double(Life.baselineDays * 24), (s / Double(max(n, 1)) * 100).rounded() / 100, lvl, e.kind.rawValue]
                    }
                }
                mainSeries["calibrated"] = epochs(wCal)
                mainSeries["fixed"] = epochs(wFixed)
                func hours(_ m: [Int: DaytimeStress.Result]) -> [[Any]] {
                    var out: [[Any]] = []
                    for d in testDays { for h in m[d]!.hours { out.append([Double((d - Life.baselineDays) * 24 + h.hour), h.level.map { (($0 * 100).rounded() / 100) as Any } ?? NSNull()]) } }
                    return out
                }
                mainSeries["legacy"] = hours(leg); mainSeries["legacyPersonal"] = hours(legP)
                let off = Double(Life.baselineDays * 24)
                mainSeries["legacyNights"] = (15...20).map { k -> [Double] in
                    let r = Life.sleepRange(k)
                    return [Double(r.lowerBound) / 3600 - off, Double(r.upperBound) / 3600 - off,
                            Legacy.nightLevel(rhr: run.nightMetrics[k].rhr, rmssd: run.nightMetrics[k].rmssd, history: histNights)]
                }
                mainSeries["sleep"] = (14...20).map { k -> [Double] in let r = Life.sleepRange(k); return [Double(r.lowerBound) / 3600 - off, Double(r.upperBound) / 3600 - off] }
                mainSeries["workouts"] = run.life.workouts.filter { $0.lowerBound >= Life.baselineDays * 86_400 }.map { [Double($0.lowerBound) / 3600 - off, Double($0.upperBound) / 3600 - off] }
            }
        }
    }

    print("\n######## Across noise levels: hour residual SD / hour r / night r / hour MAE ########")
    print(pad("method", 36) + "   none                moderate            heavy")
    let names = summary[0].rows.map(\.0)
    for (i, n) in names.enumerated() {
        var line = pad(n, 36)
        for s in summary {
            let sc = s.rows[i].1
            line += String(format: " %4.2f/%4.2f/%5.2f/%4.2f   ", sc.residSD, sc.hourly.r, sc.nightR, sc.hourly.mae)
        }
        print(line)
    }

    if let outDir {
        let data = try JSONSerialization.data(withJSONObject: mainSeries)
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: outDir + "/series20.json"))
        print("\nWrote \(outDir)/series20.json")
    }
}
