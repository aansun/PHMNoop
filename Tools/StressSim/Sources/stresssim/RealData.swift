import Foundation
import SQLite3
import StrandAnalytics
import WhoopProtocol

// --real PATH: the same methods on a real NOOP backup database (the `noop-backup.sqlite` inside a `.noopbak`, unzipped). Opened read-only;
// nothing is written. The first 14 main nights are the baseline; every day after them is a test day, and nothing is tuned on those.
//
// There is no ground truth here. The comparison is between the methods, against the person's own events (workouts, nights), and, weakly,
// against the daily mood they logged.

struct RealDB {
    var hr: [HRSample] = []
    var rr: [RRInterval] = []
    var gravity: [GravitySample] = []
    var sleep: [(start: Int, end: Int)] = []
    var workouts: [(start: Int, end: Int, sport: String)] = []
    var mood: [String: Double] = [:]
    var appNightly: [String: (rhr: Double?, hrv: Double?)] = [:]
}

func sqliteRows(_ db: OpaquePointer, _ sql: String, _ row: (OpaquePointer) -> Void) {
    var st: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { print("sql error: \(String(cString: sqlite3_errmsg(db)))"); return }
    defer { sqlite3_finalize(st) }
    while sqlite3_step(st) == SQLITE_ROW { row(st) }
}

func loadReal(_ path: String) -> RealDB {
    var db: OpaquePointer?
    // immutable=1: the file is never touched, not even by a journal.
    guard sqlite3_open_v2("file:\(path)?mode=ro&immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
        fatalError("cannot open \(path)")
    }
    defer { sqlite3_close(db) }
    var r = RealDB()
    sqliteRows(db, "select ts, bpm from hrSample order by ts") { r.hr.append(HRSample(ts: Int(sqlite3_column_int64($0, 0)), bpm: Int(sqlite3_column_int($0, 1)))) }
    sqliteRows(db, "select ts, rrMs from rrInterval where coalesce(tsSuspect, 0) = 0 order by ts, seq") {
        r.rr.append(RRInterval(ts: Int(sqlite3_column_int64($0, 0)), rrMs: Int(sqlite3_column_int($0, 1))))
    }
    sqliteRows(db, "select ts, x, y, z from gravitySample order by ts") {
        r.gravity.append(GravitySample(ts: Int(sqlite3_column_int64($0, 0)), x: sqlite3_column_double($0, 1), y: sqlite3_column_double($0, 2), z: sqlite3_column_double($0, 3)))
    }
    sqliteRows(db, "select coalesce(startTsAdjusted, startTs), endTs from sleepSession order by startTs") {
        r.sleep.append((Int(sqlite3_column_int64($0, 0)), Int(sqlite3_column_int64($0, 1))))
    }
    sqliteRows(db, "select startTs, endTs, sport from workout order by startTs") {
        r.workouts.append((Int(sqlite3_column_int64($0, 0)), Int(sqlite3_column_int64($0, 1)), sqlite3_column_text($0, 2).map { String(cString: $0) } ?? ""))
    }
    sqliteRows(db, "select day, value from metricSeries where key = 'mood'") {
        if let d = sqlite3_column_text($0, 0) { r.mood[String(cString: d)] = sqlite3_column_double($0, 1) }
    }
    sqliteRows(db, "select day, restingHr, avgHrv from dailyMetric where restingHr is not null or avgHrv is not null") {
        guard let d = sqlite3_column_text($0, 0) else { return }
        let key = String(cString: d)
        let rhr: Double? = sqlite3_column_type($0, 1) == SQLITE_NULL ? nil : sqlite3_column_double($0, 1)
        let hrv: Double? = sqlite3_column_type($0, 2) == SQLITE_NULL ? nil : sqlite3_column_double($0, 2)
        let old = r.appNightly[key]
        r.appNightly[key] = (rhr ?? old?.rhr, hrv ?? old?.hrv)
    }
    return r
}

func floorDivInt(_ a: Int, _ b: Int) -> Int {
    let q = a / b, r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q
}

func lowerBoundIndex<T>(_ a: [T], _ ts: Int, _ key: (T) -> Int) -> Int {
    var lo = 0, hi = a.count
    while lo < hi { let m = (lo + hi) / 2; if key(a[m]) < ts { lo = m + 1 } else { hi = m } }
    return lo
}

func spearman(_ a: [Double], _ b: [Double]) -> Double {
    func ranks(_ x: [Double]) -> [Double] {
        let idx = x.indices.sorted { x[$0] < x[$1] }
        var r = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < idx.count {
            var j = i
            while j + 1 < idx.count, x[idx[j + 1]] == x[idx[i]] { j += 1 }
            let avg = Double(i + j) / 2 + 1
            for k in i...j { r[idx[k]] = avg }
            i = j + 1
        }
        return r
    }
    return pearson(ranks(a), ranks(b))
}

func runReal(path: String, outDir: String?) throws {
    let tz = TimeZone.current.secondsFromGMT()
    func dayIndex(_ ts: Int) -> Int { floorDivInt(ts + tz, 86_400) }
    func dayKey(_ idx: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(idx * 86_400)))
    }
    print("Reading \(path) read-only, local time UTC\(tz >= 0 ? "+" : "")\(tz / 3600)...")
    let real = loadReal(path)
    print("loaded: hr \(real.hr.count), rr \(real.rr.count), gravity \(real.gravity.count), sleep sessions \(real.sleep.count), workouts \(real.workouts.count), mood days \(real.mood.count)")

    // Main night of each local day: the longest session of at least 4 hours that ends on it.
    var mainNight: [Int: (start: Int, end: Int)] = [:]
    for s in real.sleep where s.end - s.start >= 4 * 3600 {
        let d = dayIndex(s.end)
        if let cur = mainNight[d], cur.end - cur.start >= s.end - s.start { continue }
        mainNight[d] = s
    }
    // Nights whose raw heart rate is really there (a gap in wear makes a night unreadable).
    func hrCount(_ a: Int, _ b: Int) -> Int { lowerBoundIndex(real.hr, b) { $0.ts } - lowerBoundIndex(real.hr, a) { $0.ts } }
    var nights: [(day: Int, start: Int, end: Int, rhr: Double, rmssd: Double)] = []
    for d in mainNight.keys.sorted() {
        let n = mainNight[d]!
        guard hrCount(n.start, n.end) > Int(0.6 * Double(n.end - n.start)) else { continue }
        let m = NightMetrics.measure(hr: real.hr, rr: real.rr, from: n.start, to: n.end)
        if m.rhr > 0, m.rmssd > 0 { nights.append((d, n.start, n.end, m.rhr, m.rmssd)) }
    }
    print("main nights with readable heart rate and HRV: \(nights.count)")
    guard nights.count >= Life.baselineDays + 2 else { print("not enough nights for a 14-night baseline and a test"); return }
    let base = Array(nights.prefix(Life.baselineDays))
    let baseline = WhoopStress.Baseline.from(nightlyRMSSD: base.map(\.rmssd), nightlyRestingHR: base.map(\.rhr))!
    let baselineEnd = base.last!.end
    let lastBaselineDay = dayIndex(baselineEnd)
    print(String(format: "baseline = the first %d nights (%@ to %@): resting HR %.1f bpm (sd %.1f), nightly RMSSD %.0f ms (ln sd %.2f)",
                 base.count, dayKey(base.first!.day), dayKey(base.last!.day), baseline.restingHR, baseline.restingHRSD, exp(baseline.hrvLnMean), baseline.hrvLnSD))

    // Sanity: the nightly figures measured here against the ones the app stored for the same days.
    var mine: [Double] = [], theirs: [Double] = [], mineH: [Double] = [], theirsH: [Double] = []
    for n in nights { if let a = real.appNightly[dayKey(n.day)] {
        if let r = a.rhr { mine.append(n.rhr); theirs.append(r) }
        if let h = a.hrv { mineH.append(n.rmssd); theirsH.append(h) }
    } }
    print(String(format: "nightly figures here vs the app's stored ones: resting HR r=%.2f (n=%d, mean gap %+.1f bpm), HRV r=%.2f (n=%d, mean gap %+.0f ms)",
                 pearson(mine, theirs), mine.count, zip(mine, theirs).map { $0 - $1 }.reduce(0, +) / Double(max(mine.count, 1)),
                 pearson(mineH, theirsH), mineH.count, zip(mineH, theirsH).map { $0 - $1 }.reduce(0, +) / Double(max(mineH.count, 1))))

    // Test days: every local day after the baseline's last night with at least 12 hours of heart rate.
    let lastTs = real.hr.last!.ts
    var testDays: [Int] = []
    for d in (lastBaselineDay + 1)...dayIndex(lastTs) {
        let a = d * 86_400 - tz
        if hrCount(a, a + 86_400) >= 12 * 3600 { testDays.append(d) }
    }
    print("test days: \(testDays.count) (\(dayKey(testDays.first!)) to \(dayKey(testDays.last!)))")

    let sleepRanges = real.sleep.filter { $0.end - $0.start >= 20 * 60 }.map { $0.start...$0.end }
    let workoutRanges = real.workouts.filter { $0.end > $0.start }.map { $0.start...$0.end }
    let tuningStock = WhoopStress.Tuning()

    // The baseline period's epochs calibrate the two waking constants.
    let bStart = base.first!.start
    let first = WhoopStress.analyze(hr: real.hr, rr: real.rr, gravity: real.gravity, sleep: sleepRanges, activities: workoutRanges,
                                    baseline: baseline, from: bStart, to: baselineEnd, tuning: tuningStock)
    let calibrated = WhoopStress.calibrated(tuningStock, from: first.epochs, baseline: baseline)
    var hrOnly = calibrated; hrOnly.useHRV = false
    print(String(format: "personal calibration from the baseline days: waking HR sits %.1f bpm above resting (stock %.0f); daytime RMSSD is %.2f of the nightly (stock %.2f)",
                 calibrated.wakeHROffsetBPM, tuningStock.wakeHROffsetBPM, calibrated.wakeHRVRatio, tuningStock.wakeHRVRatio))

    let testFrom = testDays.first! * 86_400 - tz, testTo = (testDays.last! + 1) * 86_400 - tz - 1
    func whoop(_ t: WhoopStress.Tuning) -> WhoopStress.Result {
        WhoopStress.analyze(hr: real.hr, rr: real.rr, gravity: real.gravity, sleep: sleepRanges, activities: workoutRanges,
                            baseline: baseline, from: testFrom, to: min(testTo, lastTs), tuning: t)
    }
    let wFixed = whoop(tuningStock), wCal = whoop(calibrated), wHR = whoop(hrOnly)

    // The legacy readings, one local day at a time.
    func slice<T>(_ a: [T], _ from: Int, _ to: Int, _ key: (T) -> Int) -> ArraySlice<T> {
        a[lowerBoundIndex(a, from, key)..<lowerBoundIndex(a, to, key)]
    }
    var floors: [Double?] = []
    for d in (dayIndex(bStart)...lastBaselineDay) {
        let a = d * 86_400 - tz
        var sums = [Int](repeating: 0, count: 24), counts = [Int](repeating: 0, count: 24)
        for s in slice(real.hr, a, a + 86_400, { $0.ts }) { let h = (s.ts + tz - (d * 86_400)) / 3600; sums[h] += s.bpm; counts[h] += 1 }
        let means = (6..<22).compactMap { counts[$0] >= 300 ? Double(sums[$0]) / Double(counts[$0]) : nil }.sorted()
        if means.isEmpty { floors.append(nil); continue }
        let pos = 0.10 * Double(means.count - 1), lo = Int(pos), hi = min(lo + 1, means.count - 1)
        floors.append(means[lo] + (pos - Double(lo)) * (means[hi] - means[lo]))
    }
    let legacyHR = Baselines.foldHistory(floors, cfg: Baselines.daytimeHRCfg)
    print(String(format: "legacy personal daytime HR floor from the baseline days: %.1f bpm (%d days)", legacyHR.baseline, floors.compactMap { $0 }.count))
    var leg: [Int: DaytimeStress.Result] = [:], legP: [Int: DaytimeStress.Result] = [:]
    for d in testDays {
        let a = d * 86_400 - tz, b = a + 86_400
        let h = Array(slice(real.hr, a, b) { $0.ts }), r = Array(slice(real.rr, a, b) { $0.ts }), g = Array(slice(real.gravity, a, b) { $0.ts })
        leg[d] = DaytimeStress.analyze(hr: h, rr: r, gravity: g, tzOffsetSeconds: tz)
        legP[d] = DaytimeStress.analyze(hr: h, rr: r, gravity: g, tzOffsetSeconds: tz, mode: .baselineRelative(hr: legacyHR, rmssd: nil))
    }

    // Per local hour (06-22) levels of each method.
    func whoopHour(_ r: WhoopStress.Result) -> [Int: [Int: Double]] {
        var b: [Int: [Int: [Double]]] = [:]
        for e in r.epochs where e.kind == .waking {
            guard let l = e.level else { continue }
            let local = e.ts + tz, d = floorDivInt(local, 86_400), h = (local - d * 86_400) / 3600
            if h >= 6, h < 22 { b[d, default: [:]][h, default: []].append(l) }
        }
        var out: [Int: [Int: Double]] = [:]
        for (d, hs) in b { for (h, v) in hs where v.count >= 6 { out[d, default: [:]][h] = v.reduce(0, +) / Double(v.count) } }
        return out
    }
    func legacyHour(_ m: [Int: DaytimeStress.Result]) -> [Int: [Int: Double]] {
        var out: [Int: [Int: Double]] = [:]
        for (d, r) in m { for h in r.hours { if let l = h.level { out[d, default: [:]][h.hour] = l } } }
        return out
    }
    let H: [(String, [Int: [Int: Double]])] = [("legacy", legacyHour(leg)), ("legacy+personal", legacyHour(legP)), ("WHOOP-ver fixed", whoopHour(wFixed)),
                                              ("WHOOP-ver calibrated", whoopHour(wCal)), ("WHOOP-ver HR only", whoopHour(wHR))]

    // 1. How the methods spend the waking hours.
    print("\n== 1. Share of the waking hours (06-22) each method puts in each band, over the \(testDays.count) test days ==")
    print(pad("method", 24) + "hours   Low  Medium   High   mean level")
    for (name, m) in H {
        var z = [0, 0, 0], sum = 0.0, n = 0
        for d in testDays { for (_, l) in m[d] ?? [:] { z[band(l)] += 1; sum += l; n += 1 } }
        let t = Double(max(n, 1))
        print(pad(name, 24) + String(format: "%5d  %4.0f%%  %5.0f%%  %4.0f%%   %5.2f", n, Double(z[0]) / t * 100, Double(z[1]) / t * 100, Double(z[2]) / t * 100, sum / t))
    }

    // 2. How much the methods agree, hour by hour and day by day.
    print("\n== 2. Agreement between methods (correlation of the hourly levels / of the daily means) ==")
    func agree(_ a: [Int: [Int: Double]], _ b: [Int: [Int: Double]]) -> (Double, Double, Int) {
        var x: [Double] = [], y: [Double] = [], dx: [Double] = [], dy: [Double] = []
        for d in testDays {
            var sx = 0.0, sy = 0.0, n = 0
            for h in 6..<22 { if let p = a[d]?[h], let q = b[d]?[h] { x.append(p); y.append(q); sx += p; sy += q; n += 1 } }
            if n >= 6 { dx.append(sx / Double(n)); dy.append(sy / Double(n)) }
        }
        return (pearson(x, y), pearson(dx, dy), x.count)
    }
    let pairs: [(Int, Int)] = [(0, 3), (1, 3), (0, 1), (2, 3), (3, 4)]
    for (i, j) in pairs {
        let (hr, dr, n) = agree(H[i].1, H[j].1)
        print(pad("\(H[i].0)  vs  \(H[j].0)", 52) + String(format: "hourly r=%5.2f   daily r=%5.2f   (n=%d hours)", hr, dr, n))
    }

    // 3. Day by day.
    print("\n== 3. Test days: mean waking level per method, High hours, the logged mood (higher is better) and workouts ==")
    print(pad("day", 12) + pad("legacy", 8) + pad("+personal", 10) + pad("WHOOP fix", 10) + pad("WHOOP cal", 10) + pad("HR only", 8) + pad("High h (cal)", 13) + pad("mood", 6) + "workouts")
    var dailyRows: [[String]] = []
    var moodX: [Double] = [], moodY: [[Double]] = [[], [], [], [], []]
    for d in testDays {
        func mean(_ m: [Int: [Int: Double]]) -> Double? { let v = Array((m[d] ?? [:]).values); return v.count >= 6 ? v.reduce(0, +) / Double(v.count) : nil }
        let means = H.map { mean($0.1) }
        let highH = (H[3].1[d] ?? [:]).values.filter { $0 >= 2 }.count
        let a = d * 86_400 - tz
        let wk = real.workouts.filter { $0.start >= a && $0.start < a + 86_400 }.map { "\($0.sport) \(max(1, ($0.end - $0.start) / 60))m" }.joined(separator: ", ")
        let mood = real.mood[dayKey(d)]
        func f(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "–" }
        print(pad(dayKey(d), 12) + pad(f(means[0]), 8) + pad(f(means[1]), 10) + pad(f(means[2]), 10) + pad(f(means[3]), 10) + pad(f(means[4]), 8)
              + pad("\(highH)", 13) + pad(mood.map { String(format: "%.0f", $0) } ?? "–", 6) + wk)
        dailyRows.append([dayKey(d)] + means.map { f($0) } + ["\(highH)", mood.map { String(format: "%.0f", $0) } ?? "", wk])
        if let mood, means.allSatisfy({ $0 != nil }) { moodX.append(mood); for k in 0..<5 { moodY[k].append(means[k]!) } }
    }
    print("\nDaily mean level against the mood logged that day (Spearman, n=\(moodX.count) days; a good stress reading should go DOWN as mood goes up):")
    for k in 0..<5 { print(pad("  " + H[k].0, 26) + String(format: "rho = %+.2f", spearman(moodX, moodY[k]))) }
    print("  (a small n: |rho| under about 0.5 cannot be told from chance at this size)")

    // 4. Nights.
    print("\n== 4. Sleep: the WHOOP-ver's mean level over each test night, against the legacy nightly level and the night's own heart rate and HRV ==")
    print(pad("night ending", 14) + pad("WHOOP sleep", 13) + pad("legacy", 8) + pad("RHR", 6) + "RMSSD")
    let histN = base.map { (rhr: $0.rhr, rmssd: $0.rmssd) }
    var wN: [Double] = [], lN: [Double] = [], rN: [Double] = []
    for n in nights where testDays.contains(n.day) {
        let epochs = wFixed.epochs.filter { $0.kind == .sleep && $0.ts >= n.start && $0.ts < n.end }.compactMap(\.level)
        guard epochs.count >= 12 else { continue }
        let w = epochs.reduce(0, +) / Double(epochs.count)
        let l = Legacy.nightLevel(rhr: n.rhr, rmssd: n.rmssd, history: histN)
        print(pad(dayKey(n.day), 14) + pad(String(format: "%.2f", w), 13) + pad(String(format: "%.2f", l), 8) + pad(String(format: "%.0f", n.rhr), 6) + String(format: "%.0f", n.rmssd))
        wN.append(w); lN.append(l); rN.append(n.rhr)
    }
    print(String(format: "  nights: WHOOP-ver vs legacy r=%.2f; each against the night's resting HR: WHOOP r=%.2f, legacy r=%.2f (n=%d)", pearson(wN, lN), pearson(wN, rN), pearson(lN, rN), wN.count))

    // 5. What the daytime data looks like against the two assumptions.
    let waking = wFixed.epochs.filter { $0.kind == .waking && $0.level != nil }
    let usedHRV = waking.filter(\.usedHRV).count
    let rm = waking.compactMap(\.rmssd).sorted(), hrs = waking.compactMap(\.meanHR).sorted()
    print("\n== 5. The daytime signal ==")
    print(String(format: "waking epochs scored: %d; with a trusted daytime RMSSD: %d (%.0f%%)", waking.count, usedHRV, Double(usedHRV) * 100 / Double(max(waking.count, 1))))
    if !rm.isEmpty { print(String(format: "daytime RMSSD (ms): 5th %.0f, median %.0f, 95th %.0f against a nightly %.0f; waking heart rate (bpm): 5th %.0f, median %.0f, 95th %.0f against resting %.0f",
                                  rm[rm.count / 20], rm[rm.count / 2], rm[rm.count * 19 / 20], exp(baseline.hrvLnMean), hrs[hrs.count / 20], hrs[hrs.count / 2], hrs[hrs.count * 19 / 20], baseline.restingHR)) }

    // 6. Workouts.
    var wo: [Double] = [], nonAct = 0, inWorkoutEpochs = 0
    for e in wCal.epochs { if let l = e.level, workoutRanges.contains(where: { $0.contains(e.ts + 150) }) { wo.append(l); inWorkoutEpochs += 1; if e.kind == .waking { nonAct += 1 } } }
    print("\n== 6. Workouts in the test period ==")
    print(String(format: "WHOOP-ver epochs inside a workout: %d, mean level %.2f (damped toward neutral), of which counted as Non-activity: %d", inWorkoutEpochs, wo.reduce(0, +) / Double(max(wo.count, 1)), nonAct))
    var maskedLegacy = 0, totalLegacy = 0
    for d in testDays { for h in leg[d]!.hours where h.maskedForActivity { maskedLegacy += 1 }; totalLegacy += leg[d]!.hours.count }
    print("legacy hours masked for motion: \(maskedLegacy) of \(totalLegacy) waking hours")

    // 7. The app's own way: the calibration rebuilt every morning from the newest 14 nights, each day scored with that morning's record.
    print("\n== 7. As the app runs it: rolling calibration, time in each band per day ==")
    var stockByDay: [Int: [WhoopStress.Epoch]] = [:]
    for e in first.epochs + wFixed.epochs { stockByDay[dayIndex(e.ts), default: []].append(e) }
    struct Try { let wakeDays: Int; let floor: Double; let personalSleep: Bool }
    let tries = [Try(wakeDays: 14, floor: 6, personalSleep: false), Try(wakeDays: 60, floor: 6, personalSleep: false), Try(wakeDays: 60, floor: 6, personalSleep: true),
                 Try(wakeDays: 60, floor: 8, personalSleep: true), Try(wakeDays: 60, floor: 10, personalSleep: true), Try(wakeDays: 60, floor: 12, personalSleep: true)]
    for tr in tries {
        let wakeDays = tr.wakeDays
        var non = [0.0, 0.0, 0.0], total = [0.0, 0.0, 0.0], slp = [0.0, 0.0, 0.0]
        var worstHigh = 0.0, daysScored = 0, offs: [Double] = [], ratios: [Double] = [], highPerDay: [Double] = [], sleepOffs: [Double] = []
        for d in testDays {
            let known = nights.filter { $0.day <= d }.suffix(14)
            guard known.count >= 14, let b = WhoopStress.Baseline.from(nightlyRMSSD: known.map(\.rmssd), nightlyRestingHR: known.map(\.rhr)) else { continue }
            let firstDay = wakeDays == 14 ? dayIndex(known.first!.start) : d - wakeDays + 1
            var eps: [WhoopStress.Epoch] = []
            for k in firstDay..<d { eps.append(contentsOf: stockByDay[k] ?? []) }
            var t = WhoopStress.calibrated(tuningStock, from: eps, baseline: b)
            t.hrSpreadFloorBPM = tr.floor
            if tr.personalSleep {
                let sl = eps.filter { $0.kind == .sleep }.compactMap(\.meanHR).sorted()
                if sl.count >= 100 { t.sleepHROffsetBPM = min(max(sl[sl.count / 2] - b.restingHR, 0), 20) }
                sleepOffs.append(t.sleepHROffsetBPM)
            }
            offs.append(t.wakeHROffsetBPM); ratios.append(t.wakeHRVRatio)
            let a = d * 86_400 - tz
            let r = WhoopStress.analyze(hr: real.hr, rr: real.rr, gravity: real.gravity, sleep: sleepRanges, activities: workoutRanges,
                                        baseline: b, from: a, to: min(a + 86_399, lastTs), tuning: t)
            non[0] += r.nonActivity.low; non[1] += r.nonActivity.medium; non[2] += r.nonActivity.high
            total[0] += r.total.low; total[1] += r.total.medium; total[2] += r.total.high
            slp[0] += r.sleep.low; slp[1] += r.sleep.medium; slp[2] += r.sleep.high
            worstHigh = max(worstHigh, r.nonActivity.high); highPerDay.append(r.nonActivity.high); daysScored += 1
        }
        guard daysScored > 0 else { continue }
        func share(_ z: [Double]) -> String { let s = max(z.reduce(0, +), 1); return String(format: "%2.0f%% / %2.0f%% / %2.0f%%", z[0] / s * 100, z[1] / s * 100, z[2] / s * 100) }
        func perDay(_ z: [Double]) -> String { zones((z[0] / Double(daysScored), z[1] / Double(daysScored), z[2] / Double(daysScored))) }
        let sortedHigh = highPerDay.sorted()
        print("-- HR spread floor \(Int(tr.floor)) bpm, sleep offset \(tr.personalSleep ? String(format: "personal %.1f-%.1f bpm", sleepOffs.min() ?? 0, sleepOffs.max() ?? 0) : "stock 3 bpm")")
        print("waking constants from \(wakeDays) days (\(daysScored) days scored; offset \(String(format: "%.1f-%.1f", offs.min()!, offs.max()!)) bpm, HRV ratio \(String(format: "%.2f-%.2f", ratios.min()!, ratios.max()!)))")
        print("   Non-activity  Low / Medium / High: \(share(non))   a day \(perDay(non))   High on the median day \(hm(sortedHigh[sortedHigh.count / 2])), on the worst \(hm(worstHigh))")
        print("   Sleep         Low / Medium / High: \(share(slp))   a night \(perDay(slp))")
        print("   Total day     Low / Medium / High: \(share(total))   a day \(perDay(total))")
    }

    if let outDir {
        var json: [String: Any] = [:]
        json["days"] = dailyRows
        json["labels"] = H.map(\.0)
        var hourly: [[Any]] = []
        for d in testDays { for h in 6..<22 { hourly.append([dayKey(d), h] + H.map { m in m.1[d]?[h].map { (($0 * 100).rounded() / 100) as Any } ?? NSNull() }) } }
        json["hourly"] = hourly
        let data = try JSONSerialization.data(withJSONObject: json)
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: outDir + "/real.json"))
        print("\nWrote \(outDir)/real.json (aggregates only)")
    }
}
