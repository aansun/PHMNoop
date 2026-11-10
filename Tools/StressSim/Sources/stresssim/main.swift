import Foundation
import StrandAnalytics
import WhoopProtocol

// stresssim [--out DIR]
// Runs the three-day scenario twice (clean, and with daytime R-R artifacts) and prints how the app's existing stress reading and the
// WHOOP-reference reading follow the truth. With --out, also writes series.json for plotting.

let args = CommandLine.arguments
let outDir: String? = args.firstIndex(of: "--out").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }

if let i = args.firstIndex(of: "--real"), i + 1 < args.count { try runReal(path: args[i + 1], outDir: outDir); exit(0) }
if args.contains("--baseline20") { try runBaseline20(outDir: outDir); exit(0) }
if args.contains("--sixmonths") { try runSixMonths(outDir: outDir); exit(0) }

// MARK: Helpers

func band(_ x: Double) -> Int { x < 1 ? 0 : (x < 2 ? 1 : 2) }
func f1(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "  – " }
func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func hm(_ minutes: Double) -> String { let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60) }
func zones(_ z: (Double, Double, Double)) -> String { "\(hm(z.0)) / \(hm(z.1)) / \(hm(z.2))" }

struct Run {
    let data: SimData
    let history: [(rhr: Double, rmssd: Double)]
    let legacyDays: [DaytimeStress.Result]
    let baseline: WhoopStress.Baseline
    let artifact: Double

    init(artifact: Double) {
        self.artifact = artifact
        let d = Scenario.generate(artifact: artifact)
        let h = Scenario.history(artifact: artifact)
        data = d
        history = h
        legacyDays = (0..<3).map { Legacy.daytime(d, day: $0) }
        baseline = WhoopStress.Baseline.from(nightlyRMSSD: h.map(\.rmssd), nightlyRestingHR: h.map(\.rhr))!
    }

    func whoop(_ v: Variant) -> WhoopStress.Result {
        WhoopStress.analyze(hr: data.hr, rr: data.rr, gravity: data.gravity, sleep: data.sleep, activities: data.workouts,
                            baseline: baseline, from: data.t0, to: data.t0 + Scenario.totalSeconds - 1, tuning: v.tuning)
    }

    // Windows in seconds from the start: the waking day d, the night after it, and both together.
    func waking(_ d: Int) -> Range<Int> { (Scenario.sleepRanges[d].upperBound + 1)..<Scenario.sleepRanges[d + 1].lowerBound }
    func night(_ k: Int) -> Range<Int> { Scenario.sleepRanges[k].lowerBound..<(Scenario.sleepRanges[k].upperBound + 1) }

    /// Minutes of the truth in each band over a window, for the seconds `keep` accepts.
    func truthZones(_ w: Range<Int>, keep: (Moment, Int) -> Bool) -> (Double, Double, Double) {
        var z = [0.0, 0.0, 0.0]
        for i in w where keep(data.truth[i], i) { z[band(data.truth[i].s)] += 1.0 / 60 }
        return (z[0], z[1], z[2])
    }

    func whoopZones(_ r: WhoopStress.Result, _ w: Range<Int>, kinds: Set<WhoopStress.Kind>) -> (Double, Double, Double) {
        var z = [0.0, 0.0, 0.0]
        for e in r.epochs {
            let mid = e.ts + 150 - data.t0
            guard w.contains(mid), kinds.contains(e.kind), let l = e.level else { continue }
            z[band(l)] += 5
        }
        return (z[0], z[1], z[2])
    }

    func legacyWakingZones(_ d: Int) -> (Double, Double, Double) {
        var z = [0.0, 0.0, 0.0]
        for h in legacyDays[d].hours { if let l = h.level { z[band(l)] += 60 } }
        return (z[0], z[1], z[2])
    }

    func legacyNight(_ k: Int) -> Double {
        let w = night(k)
        let m = NightMetrics.measure(hr: data.hr, rr: data.rr, from: data.t0 + w.lowerBound, to: data.t0 + w.upperBound)
        return Legacy.nightLevel(rhr: m.rhr, rmssd: m.rmssd, history: history)
    }
}

/// Hour-by-hour agreement with the truth, over the sedentary waking hours 06:00 to 22:00.
struct Accuracy { var n = 0; var mae = 0.0; var bias = 0.0; var r = 0.0; var agree = 0.0; var falseHighH = 0; var missedHighH = 0; var covered = 0 }

func hourly(_ run: Run, estimate: (Int, Int) -> Double?) -> Accuracy {
    var pairs: [(Double, Double)] = []
    var total = 0
    for d in 0..<3 {
        for h in 6..<22 {
            let a = d * 86_400 + h * 3600
            var s = 0.0, n = 0
            for i in a..<(a + 3600) where run.data.truth[i].body == .sedentary { s += run.data.truth[i].s; n += 1 }
            guard n >= 1800 else { continue }
            total += 1
            if let e = estimate(d, h) { pairs.append((s / Double(n), e)) }
        }
    }
    var acc = Accuracy(); acc.n = pairs.count; acc.covered = total
    guard !pairs.isEmpty else { return acc }
    let n = Double(pairs.count)
    acc.mae = pairs.map { abs($0.1 - $0.0) }.reduce(0, +) / n
    acc.bias = pairs.map { $0.1 - $0.0 }.reduce(0, +) / n
    let mt = pairs.map(\.0).reduce(0, +) / n, me = pairs.map(\.1).reduce(0, +) / n
    let cov = pairs.map { ($0.0 - mt) * ($0.1 - me) }.reduce(0, +)
    let vt = pairs.map { ($0.0 - mt) * ($0.0 - mt) }.reduce(0, +), ve = pairs.map { ($0.1 - me) * ($0.1 - me) }.reduce(0, +)
    acc.r = vt > 0 && ve > 0 ? cov / (vt * ve).squareRoot() : 0
    acc.agree = Double(pairs.filter { band($0.0) == band($0.1) }.count) / n
    acc.falseHighH = pairs.filter { $0.1 >= 2 && $0.0 < 2 }.count
    acc.missedHighH = pairs.filter { $0.1 < 2 && $0.0 >= 2 }.count
    return acc
}

func whoopHourly(_ run: Run, _ r: WhoopStress.Result) -> (Int, Int) -> Double? {
    var buckets: [Int: [Double]] = [:]
    for e in r.epochs where e.kind == .waking { if let l = e.level { buckets[(e.ts - run.data.t0) / 3600, default: []].append(l) } }
    return { d, h in
        guard let v = buckets[d * 24 + h], v.count >= 6 else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }
}

func legacyHourly(_ run: Run) -> (Int, Int) -> Double? {
    return { d, h in
        run.legacyDays[d].hours.first { $0.hour == h }?.level
    }
}

func accRow(_ name: String, _ a: Accuracy) -> String {
    pad(name, 40) + String(format: "%4d/%-3d %6.2f %+7.2f %6.2f %6.0f%% %5d %5d", a.n, a.covered, a.mae, a.bias, a.r, a.agree * 100, a.falseHighH, a.missedHighH)
}

// MARK: Runs

let variants: [Variant] = [.standard, .hrOnly, .naiveHRV]
var runs: [Double: Run] = [:]
for artifact in [0.0, 0.08, 0.3, 0.8] { runs[artifact] = Run(artifact: artifact) }

print("""
StressSim: three invented days and nights, truth known.
  Day 1  calm; a short walk at lunch.
  Day 2  stressful meeting 09:00-11:00 (truth 2.4), workout 17:30-18:30, a tense evening 20:15-21:00 (truth 2.2).
  Day 3  after a poor night; steady mild strain (1.5), a deadline at 14:00 (peak 2.7), a walk at 08:00.
  Nights: 1 calm (0.4), 2 raised (0.9), 3 poor (1.8).
  "Day k" is the waking day plus the night after it. Bands: Low < 1, Medium 1 to 2, High >= 2. Minutes shown as Low / Medium / High.
""")

// MARK: 1. Per day and night, with daytime artifacts

let main = runs[0.08]!
let wMain = main.whoop(.standard)
print("\n== 1. Time in each band, with daytime R-R artifacts (a burst starts about every 12 min, 30-120 s, 70% of beats random) ==\n")
print("Non-activity (waking, outside motion). Legacy reads 06:00-22:00 only, so its truth is that window.")
for d in 0..<3 {
    let truthAll = main.truthZones(main.waking(d)) { m, _ in m.body == .sedentary }
    let truth0622 = main.truthZones(main.waking(d)) { m, i in m.body == .sedentary && (i % 86_400) >= 6 * 3600 && (i % 86_400) < 22 * 3600 }
    print("  Day \(d + 1)  truth(all waking) \(zones(truthAll))   truth(06-22) \(zones(truth0622))")
    print("         legacy        \(zones(main.legacyWakingZones(d)))")
    print("         WHOOP-ver     \(zones(main.whoopZones(wMain, main.waking(d), kinds: [.waking])))")
}
print("\nSleep (the night after each day). Legacy gives the whole night one level.")
for k in 1...3 {
    let w = main.night(k)
    let truth = main.truthZones(w) { m, _ in m.body == .sleep }
    let lvl = main.legacyNight(k)
    let mins = Double(w.count) / 60
    var lz = [0.0, 0.0, 0.0]; lz[band(lvl)] = mins
    let sleepEpochs = wMain.epochs.filter { $0.kind == .sleep && w.contains($0.ts + 150 - main.data.t0) }.compactMap(\.level)
    let wl = sleepEpochs.reduce(0, +) / Double(max(sleepEpochs.count, 1))
    print("  Night \(k)  truth s=\(String(format: "%.1f", Scenario.nightStress[k]))  \(zones(truth))")
    print("         legacy        level \(f1(lvl))  \(zones((lz[0], lz[1], lz[2])))")
    print("         WHOOP-ver     mean  \(f1(wl))  \(zones(main.whoopZones(wMain, w, kinds: [.sleep])))")
}
print("\nTotal day (waking day plus the night after). Truth counts every second, exercise at its underlying stress.")
for d in 0..<3 {
    let start = Scenario.sleepRanges[d].upperBound + 1, end = Scenario.sleepRanges[d + 1].upperBound + 1
    let w = start..<end
    let truth = main.truthZones(w) { _, _ in true }
    let lw = main.legacyWakingZones(d)
    let lvl = main.legacyNight(d + 1); let nm = Double(main.night(d + 1).count) / 60
    var l = [lw.0, lw.1, lw.2]; l[band(lvl)] += nm
    print("  Day \(d + 1)  truth \(zones(truth))")
    print("         legacy        \(zones((l[0], l[1], l[2])))   (waking 06-22 plus the night; workouts and motion hours left out)")
    print("         WHOOP-ver     \(zones(main.whoopZones(wMain, w, kinds: [.waking, .activity, .sleep])))")
}

// MARK: 2. Hourly accuracy by method and noise

print("\n== 2. Hour by hour against the truth, sedentary waking hours 06-22 (48 hours) ==")
print("   n/covered = hours the method produced of the hours that could be compared; MAE and bias in stress points (0-3);")
print("   r = correlation; agree = same band; FH / MH = hours called High that were not, and High hours missed.\n")
print(pad("method / noise", 40) + "  n/cov    MAE    bias      r   agree    FH    MH")
for artifact in [0.0, 0.08, 0.3, 0.8] {
    let run = runs[artifact]!
    print("-- daytime artifacts: \(artifact == 0 ? "none" : "a burst starts every \(Int(1 / artifact * 60 / 60 * 10) / 10 == 0 ? 1 : Int((1 / artifact).rounded())) min on average")")
    print(accRow("legacy (DaytimeStress)", hourly(run, estimate: legacyHourly(run))))
    for v in variants { print(accRow(v.name, hourly(run, estimate: whoopHourly(run, run.whoop(v))))) }
}

// MARK: 3. Calibration

print("\n== 3. How much the WHOOP-ver depends on the waking heart-rate offset (artifacts on) ==")
print("   The offset says how far above the resting heart rate a calm waking minute sits. It is the number to calibrate on real data.\n")
print(pad("method / noise", 40) + "  n/cov    MAE    bias      r   agree    FH    MH")
for delta in [-6.0, -3.0, 0.0, 3.0, 6.0] {
    let v = Variant.miscalibrated(delta)
    print(accRow(v.name, hourly(main, estimate: whoopHourly(main, main.whoop(v)))))
}

print("")
for ratio in [0.5, 0.6, 0.7] {
    var t = WhoopStress.Tuning(); t.wakeHRVRatio = ratio
    let v = Variant(name: String(format: "WHOOP-ver (daytime HRV ratio %.1f)", ratio), tuning: t)
    print(accRow(v.name, hourly(main, estimate: whoopHourly(main, main.whoop(v)))))
}

// MARK: 4. Exercise

print("\n== 4. The workout, day 2, 17:30-18:30 (truth underlying stress 1.0, heart rate about 145) ==\n")
let wk = Scenario.workouts[0]
let inWorkout = wMain.epochs.filter { wk.contains($0.ts + 150 - main.data.t0) }.compactMap(\.level)
print("  WHOOP-ver (total day): mean \(f1(inWorkout.reduce(0, +) / Double(max(inWorkout.count, 1)))), highest \(f1(inWorkout.max())) over \(inWorkout.count) epochs; left out of Non-activity")
let wkHours = main.legacyDays[1].hours.filter { $0.hour == 17 || $0.hour == 18 }
print("  legacy: hours 17 and 18 → " + wkHours.map { $0.level.map { String(format: "%.2f", $0) } ?? ($0.maskedForActivity ? "masked" : "no data") }.joined(separator: ", "))
let naiveWk = main.whoop(.naiveHRV).epochs.filter { wk.contains($0.ts + 150 - main.data.t0) }.compactMap(\.level)
print("  WHOOP-ver naive HRV: mean \(f1(naiveWk.reduce(0, +) / Double(max(naiveWk.count, 1)))), highest \(f1(naiveWk.max()))")

// MARK: 5. How many daytime epochs trusted the HRV

let sed = wMain.epochs.filter { $0.kind == .waking && $0.level != nil }
print("\n== 5. Daytime epochs where the HRV term was trusted (filtered version) ==\n")
for artifact in [0.0, 0.08, 0.3, 0.8] {
    let e = runs[artifact]!.whoop(.standard).epochs.filter { $0.kind == .waking && $0.level != nil }
    let u = e.filter(\.usedHRV).count
    let rm = e.compactMap(\.rmssd).sorted()
    let span = rm.isEmpty ? "–" : String(format: "%.0f to %.0f ms (median %.0f)", rm.first!, rm.last!, rm[rm.count / 2])
    print("  artifacts \(artifact): \(u) of \(e.count) epochs (\(e.isEmpty ? 0 : u * 100 / e.count)%), daytime RMSSD read \(span)")
}

// MARK: Series for plotting

if let outDir {
    func epochSeries(_ r: WhoopStress.Result, _ run: Run) -> [[Any]] {
        r.epochs.map { e in
            let a = e.ts - run.data.t0
            var s = 0.0, n = 0
            for i in max(a, 0)..<min(a + 300, run.data.truth.count) { s += run.data.truth[i].s; n += 1 }
            let lvl: Any = e.level.map { (($0 * 100).rounded() / 100) as Any } ?? NSNull()
            return [Double(a) / 3600, (s / Double(max(n, 1)) * 100).rounded() / 100, lvl, e.kind.rawValue, e.usedHRV ? 1 : 0]
        }
    }
    var json: [String: Any] = [:]
    json["standard"] = epochSeries(wMain, main)
    json["hrOnly"] = epochSeries(main.whoop(.hrOnly), main)
    json["naive"] = epochSeries(main.whoop(.naiveHRV), main)
    var leg: [[Any]] = []
    for d in 0..<3 { for h in main.legacyDays[d].hours { leg.append([Double(d * 24 + h.hour), h.level.map { (($0 * 100).rounded() / 100) as Any } ?? NSNull(), h.maskedForActivity ? 1 : 0]) } }
    json["legacy"] = leg
    json["legacyNights"] = (1...3).map { [Double(Scenario.sleepRanges[$0].lowerBound) / 3600, Double(Scenario.sleepRanges[$0].upperBound) / 3600, main.legacyNight($0)] }
    json["sleep"] = Scenario.sleepRanges.map { [Double($0.lowerBound) / 3600, Double($0.upperBound) / 3600] }
    json["workouts"] = Scenario.workouts.map { [Double($0.lowerBound) / 3600, Double($0.upperBound) / 3600] }
    json["walks"] = Scenario.walks.map { [Double($0.lowerBound) / 3600, Double($0.upperBound) / 3600] }
    let data = try JSONSerialization.data(withJSONObject: json)
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: outDir + "/series.json"))
    print("\nWrote \(outDir)/series.json")
}
