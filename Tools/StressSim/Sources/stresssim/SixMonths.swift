import Foundation
import StrandAnalytics
import WhoopProtocol

// --sixmonths: 182 invented days for each of three people, read the way the app reads them: the calibration is rebuilt every morning
// from the newest 14 readable nights, and each day is scored with the calibration it would have had that day. What twenty days cannot
// show and this can: a baseline that moves with fitness, a hard month and a holiday, two illnesses, nights the strap was not worn, and
// whether a rolling baseline quietly absorbs what it is meant to measure.
//
// The same nights feed the vital-sign range (`VitalRange`) so its false alarms and its misses are counted on the same life.

struct Persona {
    let name: String
    /// How this person's heart runs against the generator's stock person (bpm, and a factor on RMSSD).
    let hrBias: Double
    let hrvScale: Double
    /// Day-to-day movement that is not stress: bpm and ln(RMSSD), waking and asleep.
    let dayBiasSD: Double, dayScaleSD: Double, nightBiasSD: Double, nightScaleSD: Double
    let seed: UInt64
}

enum Tag: String { case normal, holiday, crunch, ill, afterIll, afterCrunch, alcohol, unworn }

struct LongLife {
    static let dayCount = 182
    static let ill: [ClosedRange<Int>] = [40...43, 140...144]
    static let holiday = 60...73
    static let crunch = 100...120
    static let gap = 80...84

    var days: [DayPlan] = []
    /// nights[j] ends on the morning of day j; night `dayCount` only has its evening.
    var nights: [NightPlan] = []
    var bed: [Int] = []          // bed[j]: second of day j-1 at which night j starts
    var wake: [Int] = []         // wake[j]: second of day j at which night j ends
    var nightWorn: [Bool] = []
    var dayTag: [Tag] = []
    var nightTag: [Tag] = []
    var workouts: [ClosedRange<Int>] = []      // absolute seconds from the start
    private var walks: [[ClosedRange<Int>]] = []
    let persona: Persona

    static func drift(_ d: Int) -> (bias: Double, scale: Double) {
        let f = Double(d) / Double(dayCount - 1)
        return (-4.0 * f, exp(0.15 * f))          // fitter over the half year: 4 bpm lower, RMSSD 16% higher
    }

    init(persona p: Persona) {
        persona = p
        var rng = SplitMix(seed: p.seed)
        func clampd(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
        func illDay(_ d: Int) -> Int? { for r in Self.ill where r.contains(d) { return d - r.lowerBound }; return nil }

        for d in 0..<Self.dayCount {
            let weekend = d % 7 >= 5
            var plan = DayPlan(base: clampd(1.0 + (weekend ? -0.2 : 0.08) + 0.25 * rng.normal(), 0.4, 1.6))
            var tag = Tag.normal
            var eventChance = (none: 0.35, one: 0.8), workoutChance = 0.4
            var peak = (lo: 1.9, span: 0.8)
            if Self.holiday.contains(d) { tag = .holiday; plan.base = clampd(0.6 + 0.15 * rng.normal(), 0.3, 1.0); eventChance = (0.85, 0.98); workoutChance = 0.5 }
            if Self.crunch.contains(d) { tag = .crunch; plan.base = clampd(1.5 + 0.2 * rng.normal(), 1.1, 2.0); eventChance = (0.05, 0.4); workoutChance = 0.2; peak = (2.2, 0.7) }
            if Self.ill.contains(where: { ($0.upperBound + 1)...($0.upperBound + 7) ~= d }) { tag = .afterIll }
            if ((Self.crunch.upperBound + 1)...(Self.crunch.upperBound + 7)).contains(d) { tag = .afterCrunch }
            let r = rng.uniform()
            let n = r < eventChance.none ? 0 : (r < eventChance.one ? 1 : 2)
            for _ in 0..<n {
                let a = 8.5 + 10.5 * rng.uniform(), len = 0.5 + 1.5 * rng.uniform()
                plan.events.append(Event(a: a, b: a + len, peak: peak.lo + peak.span * rng.uniform()))
            }
            if rng.uniform() < workoutChance { let a = 8 + 11 * rng.uniform(); plan.workout = a...(a + 0.75 + 0.5 * rng.uniform()) }
            for _ in 0..<(1 + Int(rng.uniform() * 2)) { let a = 8 + 12 * rng.uniform(); plan.walks.append(a...(a + 0.17 + 0.17 * rng.uniform())) }
            plan.bias = p.dayBiasSD * rng.normal(); plan.scale = exp(p.dayScaleSD * rng.normal())
            if let k = illDay(d) {
                tag = .ill
                let last = Self.ill.first { $0.contains(d) }!.count - 1
                let edge = k == 0 || k == last
                plan.base = edge ? 1.6 : 2.05; plan.events = []; plan.workout = nil
                plan.bias += edge ? 3 : 5; plan.scale *= edge ? 0.85 : 0.75
            }
            days.append(plan); dayTag.append(tag)
        }

        // Nights. Night j follows day j-1.
        for j in 0...Self.dayCount {
            let before = j == 0 ? nil : Optional(j - 1)
            var s = clampd(0.65 + 0.35 * rng.normal() + 0.25 * ((before.map { days[$0].base } ?? 1.0) - 1.0), 0.1, 1.9)
            var bias = p.nightBiasSD * rng.normal(), scale = exp(p.nightScaleSD * rng.normal())
            var tag = Tag.normal
            let drink = rng.uniform()
            if let b = before {
                if Self.crunch.contains(b) { s = clampd(s + 0.4, 0.1, 2.2); tag = .crunch }
                if Self.holiday.contains(b) { tag = .holiday }
                let evening = b % 7 == 4 || b % 7 == 5
                if drink < (evening ? 0.3 : (Self.holiday.contains(b) ? 0.25 : 0.02)) { s = 1.3; bias += 4; scale *= 0.75; tag = .alcohol }
                if illDay(b) != nil || illDay(j) != nil { s = 1.8; bias += 4; scale *= 0.8; tag = .ill }
            }
            nights.append(NightPlan(s: s, bias: bias, scale: scale)); nightTag.append(tag)
            bed.append(22 * 3600 + 900 + Int(rng.uniform() * 5400))
            wake.append(Int(5.75 * 3600) + Int(rng.uniform() * 1.75 * 3600))
            let worn = !(Self.gap.contains(j) || Self.gap.contains(j - 1)) && rng.uniform() > 0.04 && j > 0
            nightWorn.append(worn)
            if !worn { nightTag[j] = .unworn }
        }
        for (d, plan) in days.enumerated() {
            let base = d * 86_400
            if let w = plan.workout { workouts.append((base + Int(w.lowerBound * 3600))...(base + Int(w.upperBound * 3600))) }
            walks.append(plan.walks.map { (base + Int($0.lowerBound * 3600))...(base + Int($0.upperBound * 3600)) })
        }
    }

    private static func window(_ h: Double, _ a: Double, _ b: Double, edge: Double = 0.25) -> Double {
        1 / (1 + exp(-(h - a) / (edge / 4))) * (1 - 1 / (1 + exp(-(h - b) / (edge / 4))))
    }

    func dayWorn(_ d: Int) -> Bool { !Self.gap.contains(d) }

    /// The moment at second `sod` of day `d`.
    func moment(day d: Int, sod: Int) -> Moment {
        let drift = Self.drift(d)
        func night(_ j: Int) -> Moment {
            let n = nights[j]
            return Moment(s: n.s, body: .sleep, hrBias: persona.hrBias + drift.bias + n.bias, hrvScale: persona.hrvScale * drift.scale * n.scale)
        }
        if sod < wake[d] { return night(d) }
        if sod >= bed[d + 1] { return night(d + 1) }
        let p = days[d]
        let h = Double(sod) / 3600
        var s = p.base + 0.12 * sin(2 * .pi * (h - 8) / 14) - (h >= 21 ? 0.2 : 0)
        for e in p.events { s += (e.peak - p.base) * Self.window(h, e.a, e.b) }
        s = min(max(s, 0.05), 2.95)
        let t = d * 86_400 + sod
        let bias = persona.hrBias + drift.bias + p.bias, scale = persona.hrvScale * drift.scale * p.scale
        if let w = p.workout, Int(w.lowerBound * 3600)...Int(w.upperBound * 3600) ~= sod { return Moment(s: 1.0, body: .exercise, hrBias: bias, hrvScale: scale) }
        if walks[d].contains(where: { $0.contains(t) }) { return Moment(s: s, body: .walk, hrBias: bias, hrvScale: scale) }
        return Moment(s: s, body: .sedentary, hrBias: bias, hrvScale: scale)
    }
}

/// How a calibration is built each morning. The app's own is the first.
struct CalRule {
    let name: String
    var nights = 14           // newest readable nights in the baseline
    var robust = false        // median and scaled MAD instead of mean and SD
    var frozen = false        // built once from the first 14 nights and never again
    var wakeDays: Int?        // days the two waking constants are read from; nil = the days the baseline nights span
    var stock = false         // stock waking constants, no personal calibration
}

struct NightRow { let j: Int; let rhr: Double; let rmssd: Double; let meanHR: Double }

struct Pair { let d: Int; let t: Double; let e: Double }

struct SixResult {
    var pairs: [Pair] = []
    var nightLevel: [Int: (sum: Double, n: Int)] = [:]
    var trace: [(d: Int, rhr: Double, hrv: Double, offset: Double, ratio: Double)] = []
    var calibratingDays = 0
    var estZones: [Int: [Double]] = [:]
}

func stats(_ p: [Pair]) -> (n: Int, r: Double, dayR: Double, bias: Double, resid: Double, agree: Double, prec: Double, rec: Double) {
    guard !p.isEmpty else { return (0, 0, 0, 0, 0, 0, 0, 0) }
    let n = Double(p.count)
    let bias = p.map { $0.e - $0.t }.reduce(0, +) / n
    let resid = (p.map { ($0.e - $0.t - bias) * ($0.e - $0.t - bias) }.reduce(0, +) / n).squareRoot()
    var dt: [Double] = [], de: [Double] = []
    for (_, g) in Dictionary(grouping: p, by: \.d).sorted(by: { $0.key < $1.key }) {
        dt.append(g.map(\.t).reduce(0, +) / Double(g.count)); de.append(g.map(\.e).reduce(0, +) / Double(g.count))
    }
    let called = p.filter { $0.e >= 2 }.count, real = p.filter { $0.t >= 2 }.count, hit = p.filter { $0.e >= 2 && $0.t >= 2 }.count
    return (p.count, pearson(p.map(\.t), p.map(\.e)), pearson(dt, de), bias, resid,
            Double(p.filter { band($0.t) == band($0.e) }.count) / n,
            called == 0 ? 0 : Double(hit) / Double(called), real == 0 ? 0 : Double(hit) / Double(real))
}

func runSixMonths(outDir: String?) throws {
    let personas = [
        Persona(name: "average", hrBias: 0, hrvScale: 1.0, dayBiasSD: 2.0, dayScaleSD: 0.10, nightBiasSD: 1.5, nightScaleSD: 0.12, seed: 101),
        Persona(name: "low HRV, higher HR", hrBias: 8, hrvScale: 0.45, dayBiasSD: 2.5, dayScaleSD: 0.14, nightBiasSD: 2.0, nightScaleSD: 0.16, seed: 202),
        Persona(name: "athlete, variable", hrBias: -6, hrvScale: 1.5, dayBiasSD: 2.0, dayScaleSD: 0.16, nightBiasSD: 1.5, nightScaleSD: 0.20, seed: 303),
    ]
    let rules = [
        CalRule(name: "app: 14 nights, wake const 60 d", wakeDays: WhoopStress.Calibration.wakeDays),
        CalRule(name: "before: both from 14 days"),
        CalRule(name: "frozen first 14 nights", frozen: true),
        CalRule(name: "rolling 14, stock wake const", stock: true),
        CalRule(name: "rolling 30 nights + 30 days", nights: 30, wakeDays: 30),
        CalRule(name: "rolling 30 robust + 30 days", nights: 30, robust: true, wakeDays: 30),
    ]
    print("""
    StressSim, six months (182 days) for three people. Each morning the calibration is rebuilt as the app does and the day is scored with it.
    Written into the life: fitness improves over the half year (resting HR -4 bpm, RMSSD +16%); illness on days 41-44 and 141-145;
    a holiday on days 61-74; a hard three weeks on days 101-121; the strap off on days 81-85 and on about 4% of other nights;
    a drink on some Friday and Saturday evenings. Daytime R-R artifacts: moderate (a burst about every 12 minutes).
    Bands: Low < 1, Medium 1 to 2, High >= 2. Hours compared: sedentary waking hours 06-22.
    """)

    var json: [String: Any] = [:]
    var allNights: [(persona: String, rows: [NightRow], tags: [Tag])] = []

    for p in personas {
        let life = LongLife(persona: p)
        let t0 = 1_793_000_000 - (1_793_000_000 % 86_400)
        var results = rules.map { _ in SixResult() }
        var frozenCal: [Int: (WhoopStress.Baseline, WhoopStress.Tuning)] = [:]
        var readable: [NightRow] = []
        var stockEpochs: [Int: [WhoopStress.Epoch]] = [:]
        var tailHR: [HRSample] = [], tailRR: [RRInterval] = [], tailG: [GravitySample] = []
        var truthZones: [Int: [Double]] = [:]
        var dayTruth: [Int: Double] = [:]

        for d in 0..<LongLife.dayCount {
            let dayStart = t0 + d * 86_400
            let gen = Generator.build(seconds: 86_400, t0: dayStart, seed: p.seed &* 7919 &+ UInt64(d), artifact: 0.08, gravity: true) { i in life.moment(day: d, sod: i) }
            let wakeTs = dayStart + life.wake[d], bedTs = dayStart + life.bed[d + 1]
            func keep(_ ts: Int) -> Bool {
                if !life.dayWorn(d) { return false }
                if ts < wakeTs { return life.nightWorn[d] }
                if ts >= bedTs { return life.nightWorn[d + 1] }
                return true
            }
            let hr = tailHR + gen.hr.filter { keep($0.ts) }
            let rr = tailRR + gen.rr.filter { keep($0.ts) }
            let g = tailG + gen.gravity.filter { keep($0.ts) }

            // The night that ended this morning.
            if d >= 1, life.nightWorn[d] {
                let from = dayStart - 86_400 + life.bed[d]
                if let f = WhoopStress.nightFigures(hr: hr, rr: rr, from: from, to: wakeTs) {
                    var s = 0, n = 0
                    for x in hr where x.ts >= from && x.ts < wakeTs { s += x.bpm; n += 1 }
                    readable.append(NightRow(j: d, rhr: f.rhr, rmssd: f.rmssd, meanHR: n > 0 ? Double(s) / Double(n) : f.rhr))
                }
            }

            var sleeps: [ClosedRange<Int>] = []
            if d >= 1, life.nightWorn[d] { sleeps.append((dayStart - 86_400 + life.bed[d])...wakeTs) }
            if d == 0 { sleeps.append(dayStart...wakeTs) }
            if life.nightWorn[d + 1] { sleeps.append(bedTs...(dayStart + 86_400 + life.wake[min(d + 1, LongLife.dayCount)])) }
            let works = life.workouts.map { ($0.lowerBound + t0)...($0.upperBound + t0) }.filter { $0.upperBound >= dayStart && $0.lowerBound < dayStart + 86_400 }

            // The truth of the day: per hour (sedentary), and minutes per band while sedentary.
            var hourTruth: [Int: Double] = [:]
            var tz = [0.0, 0.0, 0.0], sum = 0.0, cnt = 0
            for h in 6..<22 {
                var s = 0.0, n = 0
                for i in (h * 3600)..<((h + 1) * 3600) where gen.truth[i].body == .sedentary { s += gen.truth[i].s; n += 1 }
                if n >= 1800 { hourTruth[h] = s / Double(n) }
            }
            for i in 0..<86_400 where gen.truth[i].body == .sedentary { tz[band(gen.truth[i].s)] += 1.0 / 60; sum += gen.truth[i].s; cnt += 1 }
            truthZones[d] = tz; dayTruth[d] = cnt > 0 ? sum / Double(cnt) : 0

            func baseline(_ rows: [NightRow], robust: Bool) -> WhoopStress.Baseline? {
                guard rows.count >= 4 else { return nil }
                if !robust { return WhoopStress.Baseline.from(nightlyRMSSD: rows.map(\.rmssd), nightlyRestingHR: rows.map(\.rhr), window: rows.count) }
                func med(_ x: [Double]) -> Double { let s = x.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
                let ln = rows.map { log($0.rmssd) }, r = rows.map(\.rhr)
                let ml = med(ln), mr = med(r)
                return WhoopStress.Baseline(hrvLnMean: ml, hrvLnSD: 1.4826 * med(ln.map { abs($0 - ml) }), restingHR: mr,
                                            restingHRSD: 1.4826 * med(r.map { abs($0 - mr) }), nights: rows.count)
            }

            // The stock pass: the day's epochs with stock constants, the store the waking constants are later read from.
            let recent = readable.filter { $0.j > d - 40 }
            let provisional = baseline(Array(recent.suffix(14)), robust: false)
                ?? WhoopStress.Baseline(hrvLnMean: log(60 * p.hrvScale), hrvLnSD: 0.2, restingHR: 55 + p.hrBias, restingHRSD: 3, nights: 0)
            if life.dayWorn(d) {
                stockEpochs[d] = WhoopStress.analyze(hr: hr, rr: rr, gravity: g, sleep: sleeps, activities: works, baseline: provisional,
                                                     from: dayStart, to: dayStart + 86_399).epochs
            }

            for (ri, rule) in rules.enumerated() {
                var cal: (WhoopStress.Baseline, WhoopStress.Tuning)?
                if rule.frozen, let c = frozenCal[ri] { cal = c }
                else if recent.count >= 14 {
                    let rows = Array(recent.suffix(rule.nights))
                    if let b = baseline(rows, robust: rule.robust) {
                        var tuning = WhoopStress.Tuning()
                        if !rule.stock {
                            let firstDay = rule.wakeDays.map { d - $0 } ?? (rows.first!.j - 1)
                            var eps: [WhoopStress.Epoch] = []
                            for k in max(firstDay, 0)..<d { if let e = stockEpochs[k] { eps.append(contentsOf: e) } }
                            tuning = WhoopStress.calibrated(tuning, from: eps, baseline: b)
                        }
                        cal = (b, tuning)
                        if rule.frozen { frozenCal[ri] = cal }
                    }
                }
                guard let (b, tuning) = cal, life.dayWorn(d) else { if life.dayWorn(d) { results[ri].calibratingDays += 1 }; continue }
                results[ri].trace.append((d, b.restingHR, exp(b.hrvLnMean), tuning.wakeHROffsetBPM, tuning.wakeHRVRatio))
                let res = WhoopStress.analyze(hr: hr, rr: rr, gravity: g, sleep: sleeps, activities: works, baseline: b,
                                              from: dayStart, to: dayStart + 86_399, tuning: tuning)
                var buckets: [Int: [Double]] = [:]
                var ez = [0.0, 0.0, 0.0]
                for e in res.epochs {
                    guard let l = e.level else { continue }
                    switch e.kind {
                    case .waking: buckets[(e.ts - dayStart) / 3600, default: []].append(l); ez[band(l)] += 5
                    case .sleep:
                        let j = e.ts < wakeTs ? d : d + 1
                        let cur = results[ri].nightLevel[j] ?? (0, 0)
                        results[ri].nightLevel[j] = (cur.sum + l, cur.n + 1)
                    case .activity: break
                    }
                }
                results[ri].estZones[d] = ez
                for (h, t) in hourTruth { if let v = buckets[h], v.count >= 6 { results[ri].pairs.append(Pair(d: d, t: t, e: v.reduce(0, +) / Double(v.count))) } }
            }

            // What tomorrow needs of today: from ten minutes before bed.
            let cut = bedTs - 600
            tailHR = hr.filter { $0.ts >= cut }; tailRR = rr.filter { $0.ts >= cut }; tailG = g.filter { $0.ts >= cut }
            if d >= 61 { stockEpochs[d - 61] = nil }
        }

        allNights.append((p.name, readable, life.nightTag))

        // MARK: Report

        print("\n================ \(p.name) ================")
        let n0 = readable.prefix(14), n1 = readable.suffix(14)
        func avg(_ x: [Double]) -> Double { x.reduce(0, +) / Double(max(x.count, 1)) }
        print(String(format: "nights read %d of 182. First 14 nights: resting HR %.1f, RMSSD %.0f ms. Last 14: resting HR %.1f, RMSSD %.0f ms.",
                     readable.count, avg(n0.map(\.rhr)), avg(n0.map(\.rmssd)), avg(n1.map(\.rhr)), avg(n1.map(\.rmssd))))

        print("\nA. Hour by hour over the whole half year (r, resid SD and day r do not depend on where the scale is anchored; bias does)")
        print(pad("calibration", 32) + "   hours     r   day r  residSD    bias  agree  highPrec highRec")
        for (ri, rule) in rules.enumerated() {
            let s = stats(results[ri].pairs)
            print(pad(rule.name, 32) + String(format: "  %6d  %5.2f  %5.2f   %5.2f  %+6.2f  %4.0f%%    %4.0f%%   %4.0f%%", s.n, s.r, s.dayR, s.resid, s.bias, s.agree * 100, s.prec * 100, s.rec * 100))
        }

        print("\nB. Month by month, the app's rule: does the reading drift as the person changes?")
        print("   month   hours     r   day r    bias | baseline RHR  RMSSD | wake offset  HRV ratio")
        for m in 0..<6 {
            let lo = 14 + m * 28, hi = m == 5 ? LongLife.dayCount : lo + 28
            let s = stats(results[0].pairs.filter { $0.d >= lo && $0.d < hi })
            let tr = results[0].trace.filter { $0.d >= lo && $0.d < hi }
            print(String(format: "   %d (%3d-%3d) %5d  %5.2f  %5.2f  %+6.2f |     %5.1f   %5.0f |      %5.1f      %5.2f", m + 1, lo + 1, hi, s.n, s.r, s.dayR, s.bias,
                         avg(tr.map(\.rhr)), avg(tr.map(\.hrv)), avg(tr.map(\.offset)), avg(tr.map(\.ratio))))
        }

        print("\nC. Periods: the mean sedentary waking stress of the days in each period, truth and reading (difference from the ordinary days in brackets)")
        let order: [Tag] = [.normal, .holiday, .crunch, .afterCrunch, .ill, .afterIll]
        var header = pad("calibration", 32)
        for t in order { header += pad("  " + t.rawValue, 16) }
        print(header)
        func periodMean(_ pairs: [Pair], _ tag: Tag, truth: Bool) -> Double {
            let x = pairs.filter { life.dayTag[$0.d] == tag && $0.d >= 14 }
            return avg(x.map { truth ? $0.t : $0.e })
        }
        var line = pad("truth", 32)
        let tn = periodMean(results[0].pairs, .normal, truth: true)
        for t in order { let v = periodMean(results[0].pairs, t, truth: true); line += pad(String(format: "  %.2f (%+.2f)", v, v - tn), 16) }
        print(line)
        for (ri, rule) in rules.enumerated() {
            var l = pad(rule.name, 32)
            let en = periodMean(results[ri].pairs, .normal, truth: false)
            for t in order { let v = periodMean(results[ri].pairs, t, truth: false); l += pad(String(format: "  %.2f (%+.2f)", v, v - en), 16) }
            print(l)
        }

        print("\nD. Inside the hard three weeks (days 101-121), week by week: does the reading fade while the stress stays?")
        print(pad("calibration", 32) + "  week 1 truth/read   week 2 truth/read   week 3 truth/read   week after")
        for (ri, rule) in rules.enumerated() {
            var l = pad(rule.name, 32)
            for w in 0..<4 {
                let x = results[ri].pairs.filter { $0.d >= 100 + w * 7 && $0.d < 107 + w * 7 }
                l += String(format: "     %.2f / %.2f    ", avg(x.map(\.t)), avg(x.map(\.e)))
            }
            print(l)
        }

        print("\nE. Nights: sleep stress of each night against the truth")
        print(pad("calibration", 32) + "  nights   r    normal  alcohol     ill   crunch   (truth: normal \(String(format: "%.2f", avg((1..<LongLife.dayCount).filter { life.nightTag[$0] == .normal }.map { life.nights[$0].s }))), alcohol 1.30, ill 1.80)")
        for (ri, rule) in rules.enumerated() {
            var t: [Double] = [], e: [Double] = []
            var by: [Tag: [Double]] = [:]
            for (j, v) in results[ri].nightLevel where j >= 15 && j < LongLife.dayCount && v.n >= 40 {
                t.append(life.nights[j].s); e.append(v.sum / Double(v.n)); by[life.nightTag[j], default: []].append(v.sum / Double(v.n))
            }
            print(pad(rule.name, 32) + String(format: "   %4d  %5.2f   %5.2f    %5.2f   %5.2f    %5.2f", t.count, pearson(t, e), avg(by[.normal] ?? []), avg(by[.alcohol] ?? []), avg(by[.ill] ?? []), avg(by[.crunch] ?? [])))
        }

        print("\nF. Time in each band while awake and still, mean minutes a day (Low / Medium / High)")
        func zmean(_ z: [Int: [Double]], _ days: [Int]) -> String {
            let v = days.compactMap { z[$0] }
            guard !v.isEmpty else { return "–" }
            return zones((avg(v.map { $0[0] }), avg(v.map { $0[1] }), avg(v.map { $0[2] })))
        }
        let scored = results[0].estZones.keys.sorted()
        for t in order {
            let ds = scored.filter { life.dayTag[$0] == t }
            print(pad("   " + t.rawValue, 16) + "truth \(zmean(truthZones, ds))    app \(zmean(results[0].estZones, ds))    before \(zmean(results[1].estZones, ds))")
        }

        json[p.name] = [
            "days": results[0].trace.map { [$0.d, $0.rhr, $0.hrv, $0.offset, $0.ratio] },
            "daily": rules.enumerated().map { ri, rule -> [String: Any] in
                var rows: [[Double]] = []
                for (d, g) in Dictionary(grouping: results[ri].pairs, by: \.d).sorted(by: { $0.key < $1.key }) {
                    rows.append([Double(d), avg(g.map(\.t)), avg(g.map(\.e))])
                }
                return ["rule": rule.name, "rows": rows]
            },
            "nights": readable.map { [Double($0.j), $0.rhr, $0.rmssd, $0.meanHR] },
            "nightTags": life.nightTag.map(\.rawValue),
        ]
    }

    runVitals(allNights)

    if let outDir {
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: outDir + "/sixmonths.json"))
        print("\nWrote \(outDir)/sixmonths.json")
    }
}
