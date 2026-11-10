import Foundation
import StrandAnalytics

// The vital-sign range and the early warning over six months.
//
// Part 1 reads the nights of the three six-month people (resting heart rate and RMSSD measured from their generated heart rate and R-R).
// Part 2 is a population: 300 people, 182 nights each, with all five vitals drawn night by night from a statistical model. The model's
// spreads are the tool's own choice, set in the range the literature reports for night-to-night variation in healthy adults; the fixed
// thresholds (skin temperature and blood oxygen) depend directly on them, so those two are shown across a range of sensor noise.

/// How a reading is judged against the earlier ones.
struct RangeRule {
    let name: String
    /// Spreads either side of the centre that count as in range.
    var k = 1.0
    var window = VitalRange.windowNights
    /// The app's other banding (`VitalBands`: a Winsorized EWMA, in range within 2 sigma), used by the Default look.
    var ewma = false
}

enum VitalKind: Int, CaseIterable { case hrv, rhr, resp }

func rangeVerdict(_ value: Double, history: [Double], floor: Double, rule: RangeRule, cfgKey: String) -> VitalRange.Verdict? {
    if rule.ewma {
        guard history.count + 1 >= VitalRange.calibrationNights, let cfg = Baselines.metricCfg[cfgKey] else { return nil }
        let state = Baselines.foldHistory(history.map { Optional($0) }, cfg: cfg)
        let z = Baselines.deviation(value, state: state).z
        return abs(z) <= VitalBands.sigmaK ? .inRange : (z > 0 ? .above : .below)
    }
    if rule.k == 1, rule.window == VitalRange.windowNights {
        return VitalRange.band(history: history).map { VitalRange.verdict(value, in: $0, floor: floor) }
    }
    let values = Array(history.suffix(rule.window))
    let nights = values.count + 1
    guard nights >= VitalRange.calibrationNights else { return nil }
    func med(_ x: [Double]) -> Double { let s = x.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
    let c = med(values), mad = med(values.map { abs($0 - c) })
    let widen = nights >= VitalRange.trustedNights ? 1.0
        : 1 + (VitalRange.widestFactor - 1) * Double(VitalRange.trustedNights - nights) / Double(VitalRange.trustedNights - VitalRange.calibrationNights)
    let tol = max(1.4826 * mad * widen * rule.k, floor)
    if abs(value - c) <= tol { return .inRange }
    return value > c ? .above : .below
}

let rangeRules = [
    RangeRule(name: "app: median ± 1.0 spread"),
    RangeRule(name: "median ± 1.5 spread", k: 1.5),
    RangeRule(name: "median ± 2.0 spread", k: 2.0),
    RangeRule(name: "median ± 2.0, 60 nights", k: 2.0, window: 60),
    RangeRule(name: "EWMA ± 2 sigma (VitalBands)", ewma: true),
]

private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "   – " : String(format: "%4.0f%%", 100 * Double(a) / Double(b)) }

func runVitals(_ people: [(persona: String, rows: [NightRow], tags: [Tag])]) {
    print("\n\n################ Vital-sign range (Health monitor) ################")
    print("""
    A night is 'ordinary' when nothing was written into it, 'ill' on the illness nights, 'alcohol' after a drink.
    False alarm = an ordinary night called outside its range. A good range is quiet on ordinary nights and speaks on ill ones.
    """)

    print("\nPart 1. The three six-month people: HRV and resting heart rate measured from their own heart rate and R-R")
    print(pad("rule", 30) + pad("person", 22) + "ordinary: HRV out  RHR out  either |  ill: either out  adverse |  alcohol: adverse")
    for rule in rangeRules {
        for p in people {
            var ordN = 0, hOut = 0, rOut = 0, either = 0, illN = 0, illEither = 0, illAdverse = 0, alcN = 0, alcAdverse = 0
            for (i, row) in p.rows.enumerated() where i >= 14 {
                let hist = Array(p.rows[..<i])
                guard let vh = rangeVerdict(row.rmssd, history: hist.map(\.rmssd), floor: 1, rule: rule, cfgKey: "hrv"),
                      let vr = rangeVerdict(row.meanHR, history: hist.map(\.meanHR), floor: 1, rule: rule, cfgKey: "resting_hr") else { continue }
                let adverse = vh == .below || vr == .above
                switch p.tags[row.j] {
                case .ill: illN += 1; if vh != .inRange || vr != .inRange { illEither += 1 }; if adverse { illAdverse += 1 }
                case .alcohol: alcN += 1; if adverse { alcAdverse += 1 }
                case .normal, .holiday:
                    ordN += 1
                    if vh != .inRange { hOut += 1 }; if vr != .inRange { rOut += 1 }; if vh != .inRange || vr != .inRange { either += 1 }
                default: break
                }
            }
            print(pad(rule.name, 30) + pad(p.persona, 22) + "           \(pct(hOut, ordN))    \(pct(rOut, ordN))   \(pct(either, ordN)) |            \(pct(illEither, illN))    \(pct(illAdverse, illN)) |             \(pct(alcAdverse, alcN))")
        }
    }

    population()
}

// MARK: - Population

private struct Night {
    var hrv = 0.0, rhr = 0.0, resp = 0.0, skin = 0.0, spo2 = 0.0
    var tag = Tag.normal
    var worn = true
}

private func person(seed: UInt64, skinSD: Double?, spo2SD: Double?) -> [Night] {
    var rng = SplitMix(seed: seed)
    let lnHRV = log(50.0) + 0.4 * rng.normal(), hrvSD = 0.10 + 0.12 * rng.uniform()
    let rhr0 = 58 + 7 * rng.normal(), rhrSD = 1.5 + 1.5 * rng.uniform()
    let resp0 = 15 + 1.5 * rng.normal(), respSD = 0.25 + 0.25 * rng.uniform()
    let sSD = skinSD ?? (0.2 + 0.2 * rng.uniform())
    let ox0 = 96.5 + 0.8 * rng.normal(), oxSD = spo2SD ?? (0.5 + 0.5 * rng.uniform())
    let ill1 = 30 + Int(rng.uniform() * 50), ill2 = 110 + Int(rng.uniform() * 55)
    var ar = [0.0, 0.0, 0.0, 0.0], slow = [0.0, 0.0]
    let phi = 0.35, inn = (1 - phi * phi).squareRoot()
    var out: [Night] = []
    for j in 0..<182 {
        // A shared night-to-night factor (a good or a poor night moves HRV and heart rate together) plus each vital's own.
        let common = rng.normal()
        ar[0] = phi * ar[0] + inn * (0.6 * common + 0.8 * rng.normal())
        ar[1] = phi * ar[1] + inn * (-0.6 * common + 0.8 * rng.normal())
        ar[2] = phi * ar[2] + inn * (-0.3 * common + 0.954 * rng.normal())
        ar[3] = phi * ar[3] + inn * rng.normal()
        slow[0] += 0.006 * rng.normal(); slow[1] += 0.06 * rng.normal()          // a slow wander: season, fitness
        var n = Night()
        n.hrv = exp(lnHRV + slow[0] + hrvSD * ar[0])
        n.rhr = rhr0 + slow[1] + rhrSD * ar[1]
        n.resp = resp0 + respSD * ar[2]
        n.skin = sSD * ar[3]
        n.spo2 = min(100, ox0 + oxSD * rng.normal())
        let evening = j % 7 == 4 || j % 7 == 5
        let u = rng.uniform(), v = rng.uniform()
        if (ill1..<(ill1 + 4)).contains(j) || (ill2..<(ill2 + 4)).contains(j) {
            n.tag = .ill; n.hrv *= 0.70; n.rhr += 6; n.resp += 1.5; n.skin += 0.8; n.spo2 -= 1
        } else if u < (evening ? 0.25 : 0.02) {
            n.tag = .alcohol; n.hrv *= 0.75; n.rhr += 5; n.resp += 0.5; n.skin += 0.2
        } else if v < 0.10 {
            n.tag = .crunch; n.hrv *= 0.88; n.rhr += 2.5                        // a hard or late training day
        }
        n.worn = rng.uniform() > 0.05
        out.append(n)
    }
    return out
}

private func population() {
    let peopleN = 300
    print("\nPart 2. A population: \(peopleN) people, 182 nights each, all five vitals. Nights 1-14 are left out (the range is still forming).")
    print("   Each person has their own level and their own night-to-night spread (HRV 10-22%, resting HR 1.5-3 bpm, respiratory rate")
    print("   0.25-0.5, skin temperature 0.2-0.4 C, blood oxygen 0.5-1 point). Two illnesses of four nights; a drink on some weekends.")

    print("\n   2a. Each vital on its own: share of ORDINARY nights called outside the range, and of ILL nights called outside on the adverse side")
    print("   " + pad("rule", 30) + "ordinary: HRV   RHR   resp |  ill, adverse side: HRV   RHR   resp | people whose ordinary HRV is out > 40% of nights")
    for rule in rangeRules {
        var ord = [0, 0, 0], ordOut = [0, 0, 0], ill = [0, 0, 0], illOut = [0, 0, 0], noisy = 0
        for p in 0..<peopleN {
            let nights = person(seed: 5_000 + UInt64(p), skinSD: nil, spo2SD: nil)
            var mine = 0, mineOut = 0
            var hist: [[Double]] = [[], [], []]
            for (j, n) in nights.enumerated() where n.worn {
                let vals = [n.hrv, n.rhr, n.resp], floors = [1.0, 1.0, 0.3], keys = ["hrv", "resting_hr", "resp"]
                if j >= 14 {
                    for k in 0..<3 {
                        guard let v = rangeVerdict(vals[k], history: hist[k], floor: floors[k], rule: rule, cfgKey: keys[k]) else { continue }
                        let adverse = k == 0 ? v == .below : v == .above
                        if n.tag == .normal { ord[k] += 1; if v != .inRange { ordOut[k] += 1 }; if k == 0 { mine += 1; if v != .inRange { mineOut += 1 } } }
                        if n.tag == .ill { ill[k] += 1; if adverse { illOut[k] += 1 } }
                    }
                }
                for k in 0..<3 { hist[k].append(vals[k]) }
            }
            if mine > 0, Double(mineOut) / Double(mine) > 0.4 { noisy += 1 }
        }
        print("   " + pad(rule.name, 30) + "        \(pct(ordOut[0], ord[0])) \(pct(ordOut[1], ord[1])) \(pct(ordOut[2], ord[2])) |                   \(pct(illOut[0], ill[0])) \(pct(illOut[1], ill[1])) \(pct(illOut[2], ill[2])) |   \(pct(noisy, peopleN))")
    }

    print("\n   2b. The Today tile (all five vitals; skin temperature within 0.5 C, blood oxygen at least 95%, as the app has them)")
    print("   " + pad("rule", 30) + "ordinary days shown 'Outside range' | ill days shown outside | ill days with 2+ vitals adverse | ordinary days with 2+ adverse")
    for rule in rangeRules {
        var ord = 0, ordOut = 0, ill = 0, illOut = 0, ill2 = 0, ord2 = 0
        for p in 0..<peopleN {
            let nights = person(seed: 5_000 + UInt64(p), skinSD: nil, spo2SD: nil)
            var hist: [[Double]] = [[], [], []]
            for (j, n) in nights.enumerated() where n.worn {
                let vals = [n.hrv, n.rhr, n.resp], floors = [1.0, 1.0, 0.3], keys = ["hrv", "resting_hr", "resp"]
                if j >= 14 {
                    var out = 0, adverse = 0
                    for k in 0..<3 {
                        guard let v = rangeVerdict(vals[k], history: hist[k], floor: floors[k], rule: rule, cfgKey: keys[k]) else { continue }
                        if v != .inRange { out += 1 }
                        if k == 0 ? v == .below : v == .above { adverse += 1 }
                    }
                    if abs(n.skin) >= 0.5 { out += 1; if n.skin > 0 { adverse += 1 } }
                    if n.spo2 < 95 { out += 1; adverse += 1 }
                    if n.tag == .normal { ord += 1; if out > 0 { ordOut += 1 }; if adverse >= 2 { ord2 += 1 } }
                    if n.tag == .ill { ill += 1; if out > 0 { illOut += 1 }; if adverse >= 2 { ill2 += 1 } }
                }
                for k in 0..<3 { hist[k].append(vals[k]) }
            }
        }
        print("   " + pad(rule.name, 30) + "              \(pct(ordOut, ord))                 |        \(pct(illOut, ill))          |             \(pct(ill2, ill))               |          \(pct(ord2, ord))")
    }

    print("\n   2c. The two fixed thresholds, by how noisy the sensor is from night to night (share of ORDINARY nights called outside)")
    print("       skin temperature, |deviation| >= 0.5 C:")
    for sd in [0.15, 0.2, 0.25, 0.3, 0.4] {
        var n = 0, out = 0, ill = 0, illOut = 0
        for p in 0..<peopleN { for x in person(seed: 5_000 + UInt64(p), skinSD: sd, spo2SD: nil) where x.worn {
            if x.tag == .normal { n += 1; if abs(x.skin) >= 0.5 { out += 1 } }
            if x.tag == .ill { ill += 1; if abs(x.skin) >= 0.5 { illOut += 1 } }
        } }
        print(String(format: "         night-to-night SD %.2f C: ordinary nights outside %@, ill nights (+0.8 C) outside %@", sd, pct(out, n), pct(illOut, ill)))
    }
    print("       blood oxygen, below 95%:")
    for sd in [0.5, 0.75, 1.0, 1.5] {
        var n = 0, out = 0
        for p in 0..<peopleN { for x in person(seed: 5_000 + UInt64(p), skinSD: nil, spo2SD: sd) where x.worn && x.tag == .normal { n += 1; if x.spo2 < 95 { out += 1 } } }
        print(String(format: "         night-to-night SD %.2f points (personal level 96.5 ± 0.8): ordinary nights outside %@", sd, pct(out, n)))
    }

    // The early warning, built the way AppModel builds it: the mean of the last two days against the 28 days that end three days ago.
    print("\n   2d. The early warning (IllnessSignalEngine, wired as in the app; no journal entries, so nothing is suppressed)")
    var illEpisodes = 0, caught = 0, caughtMild = 0, delay: [Int] = [], ordDays = 0, falseRaised = 0, falseMild = 0, alcDays = 0, alcRaised = 0
    for p in 0..<peopleN {
        let nights = person(seed: 5_000 + UInt64(p), skinSD: nil, spo2SD: nil)
        var levels: [IllnessSignalEngine.Level?] = Array(repeating: nil, count: nights.count)
        for j in 20..<nights.count {
            let recent = nights[(j - 1)...j].filter(\.worn)
            let base = Array(nights[max(0, j - 30)...(j - 3)])
            guard !recent.isEmpty else { continue }
            func z(_ kp: (Night) -> Double, _ key: String, up: Bool) -> (IllnessSignalEngine.SignalReading, Bool)? {
                guard let cfg = Baselines.metricCfg[key] else { return nil }
                let state = Baselines.foldHistory(base.map { $0.worn ? Optional(kp($0)) : nil }, cfg: cfg)
                guard state.usable else { return (IllnessSignalEngine.SignalReading(zIllnessward: 0, present: false), false) }
                let m = recent.map(kp).reduce(0, +) / Double(recent.count)
                let d = Baselines.deviation(m, state: state).z
                return (IllnessSignalEngine.SignalReading(zIllnessward: up ? d : -d), state.trusted)
            }
            let r = z({ $0.rhr.rounded() }, "resting_hr", up: true), h = z({ $0.hrv }, "hrv", up: false), q = z({ $0.resp }, "resp", up: true)
            let skin = recent.map(\.skin).reduce(0, +) / Double(recent.count) / 0.3
            let inputs = IllnessSignalEngine.Inputs(restingHR: r?.0, skinTemp: IllnessSignalEngine.SignalReading(zIllnessward: skin), hrv: h?.0, respiration: q?.0)
            let res = IllnessSignalEngine.evaluate(inputs, context: IllnessSignalEngine.Context(baselineTrusted: (r?.1 ?? false) || (h?.1 ?? false)))
            levels[j] = res.level
        }
        // Episodes: runs of ill nights. Caught when raised on an ill night or the night after the run.
        var j = 20
        while j < nights.count {
            if nights[j].tag == .ill, j == 0 || nights[j - 1].tag != .ill {
                var end = j; while end + 1 < nights.count, nights[end + 1].tag == .ill { end += 1 }
                illEpisodes += 1
                if let first = (j...min(end + 1, nights.count - 1)).first(where: { levels[$0] == .raised }) { caught += 1; delay.append(first - j + 1) }
                else if (j...min(end + 1, nights.count - 1)).contains(where: { levels[$0] == .mild }) { caughtMild += 1 }
                j = end + 1
            } else { j += 1 }
        }
        for j in 20..<nights.count {
            guard let l = levels[j] else { continue }
            let nearIll = (max(0, j - 3)...j).contains { nights[$0].tag == .ill }
            if nearIll { continue }
            if nights[j].tag == .alcohol || nights[j - 1].tag == .alcohol { alcDays += 1; if l == .raised { alcRaised += 1 }; continue }
            ordDays += 1
            if l == .raised { falseRaised += 1 } else if l == .mild { falseMild += 1 }
        }
    }
    let meanDelay = delay.isEmpty ? 0 : Double(delay.reduce(0, +)) / Double(delay.count)
    print("       illness episodes \(illEpisodes): raised in \(pct(caught, illEpisodes)) (on night \(String(format: "%.1f", meanDelay)) of the illness on average), mild only in \(pct(caughtMild, illEpisodes))")
    print(String(format: "       ordinary days %d: raised on %.2f%% (about %.1f a year), mild on %.2f%%", ordDays, 100 * Double(falseRaised) / Double(max(ordDays, 1)),
                 365 * Double(falseRaised) / Double(max(ordDays, 1)), 100 * Double(falseMild) / Double(max(ordDays, 1))))
    print("       days after a drink \(alcDays): raised on \(pct(alcRaised, alcDays)) (the journal's alcohol entry is what suppresses these)")
}
