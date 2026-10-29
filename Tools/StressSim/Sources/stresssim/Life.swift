import Foundation
import WhoopProtocol

/// Twenty invented days. Days 1 to 14 are ordinary life drawn at random (the baseline period); days 15 to 20 are written out so the truth is
/// known and varied: a calm day, a hard day with a workout, the day after a bad night, an ill day, a recovery day and a mixed one.
/// Night j follows day j (night 0 comes before day 1).
struct Event { var a: Double; var b: Double; var peak: Double }       // hours of the day

struct DayPlan {
    var base: Double
    var events: [Event] = []
    var workout: ClosedRange<Double>?
    var walks: [ClosedRange<Double>] = []
    var bias = 0.0
    var scale = 1.0
}

struct NightPlan { var s: Double; var bias = 0.0; var scale = 1.0 }

struct Life {
    static let dayCount = 20
    static let baselineDays = 14
    var days: [DayPlan] = []
    var nights: [NightPlan] = []
    private var workoutSeconds: [ClosedRange<Int>] = []
    private var walkSeconds: [[ClosedRange<Int>]] = []

    static let totalSeconds = dayCount * 86_400 + Int(6.5 * 3600) + 1

    /// Hours asleep in night j, in seconds from the start.
    static func sleepRange(_ j: Int) -> ClosedRange<Int> {
        j == 0 ? 0...Int(6.5 * 3600) : (((j - 1) * 24 + 23) * 3600)...((j * 24 + 6) * 3600 + 1800)
    }

    static func build(seed: UInt64 = 11) -> Life {
        var rng = SplitMix(seed: seed)
        var life = Life()
        func clampd(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

        life.nights.append(NightPlan(s: 0.5))
        for _ in 0..<baselineDays {
            var d = DayPlan(base: clampd(1.0 + 0.25 * rng.normal(), 0.5, 1.5))
            let r = rng.uniform()
            let n = r < 0.35 ? 0 : (r < 0.8 ? 1 : 2)
            for _ in 0..<n {
                let a = 8 + 11 * rng.uniform(), len = 0.5 + 1.5 * rng.uniform()
                d.events.append(Event(a: a, b: a + len, peak: 1.9 + 0.8 * rng.uniform()))
            }
            if rng.uniform() < 0.3 { let a = 6 + 13 * rng.uniform(); d.workout = a...(a + 0.75 + 0.5 * rng.uniform()) }
            for _ in 0..<(1 + Int(rng.uniform() * 2)) { let a = 7 + 12 * rng.uniform(); d.walks.append(a...(a + 0.17 + 0.17 * rng.uniform())) }
            d.bias = 2.0 * rng.normal(); d.scale = exp(0.1 * rng.normal())
            life.days.append(d)
            life.nights.append(NightPlan(s: clampd(0.65 + 0.35 * rng.normal(), 0.1, 1.7), bias: 1.5 * rng.normal(), scale: exp(0.12 * rng.normal())))
        }
        // Day 15: calm.
        life.days.append(DayPlan(base: 0.8, walks: [12.5...12.75], bias: 0.5, scale: 1.0))
        life.nights.append(NightPlan(s: 0.5))
        // Day 16: a meeting, a workout, a tense evening.
        life.days.append(DayPlan(base: 0.9, events: [Event(a: 9, b: 11, peak: 2.4), Event(a: 20.25, b: 21, peak: 2.2)],
                                 workout: 17.5...18.5, walks: [8.17...8.5], bias: -1.5, scale: 0.95))
        life.nights.append(NightPlan(s: 1.2, bias: 0.6, scale: 0.95))
        // Day 17: after that night, a steady mild strain and a deadline.
        life.days.append(DayPlan(base: 1.4, events: [Event(a: 14, b: 14.75, peak: 2.7)], walks: [8.0...8.33], bias: 1.0, scale: 0.97))
        life.nights.append(NightPlan(s: 0.8, bias: -0.4, scale: 1.02))
        // Day 18: ill: stressed all day, and the body runs hotter and flatter for it.
        life.days.append(DayPlan(base: 2.0, walks: [12.5...12.75], bias: 5, scale: 0.75))
        life.nights.append(NightPlan(s: 1.9, bias: 4, scale: 0.8))
        // Day 19: recovery, a long workout in the morning.
        life.days.append(DayPlan(base: 0.7, workout: 7.0...8.5, walks: [12.5...12.7], bias: -1, scale: 1.05))
        life.nights.append(NightPlan(s: 0.4, bias: -1, scale: 1.05))
        // Day 20: mixed.
        life.days.append(DayPlan(base: 1.1, events: [Event(a: 10, b: 10.75, peak: 2.3), Event(a: 15, b: 16, peak: 2.0)],
                                 walks: [8.0...8.3, 13.0...13.2], bias: 0.5, scale: 0.98))
        life.nights.append(NightPlan(s: 0.9, bias: 0.3, scale: 0.97))

        for (d, p) in life.days.enumerated() {
            let base = d * 86_400
            if let w = p.workout { life.workoutSeconds.append((base + Int(w.lowerBound * 3600))...(base + Int(w.upperBound * 3600))) }
            life.walkSeconds.append(p.walks.map { (base + Int($0.lowerBound * 3600))...(base + Int($0.upperBound * 3600)) })
        }
        return life
    }

    var sleepRanges: [ClosedRange<Int>] { (0...Life.dayCount).map(Life.sleepRange) }
    var workouts: [ClosedRange<Int>] { workoutSeconds }

    private static func window(_ h: Double, _ a: Double, _ b: Double, edge: Double = 0.25) -> Double {
        1 / (1 + exp(-(h - a) / (edge / 4))) * (1 - 1 / (1 + exp(-(h - b) / (edge / 4))))
    }

    func moment(_ t: Int) -> Moment {
        let d = min(t / 86_400, Life.dayCount - 1 + (t >= Life.dayCount * 86_400 ? 1 : 0))
        let sod = t - (t / 86_400) * 86_400
        let dayIndex = t / 86_400
        // Night: the early hours of this day belong to the night before it, the late hours to the one after.
        if sod <= Int(6.5 * 3600) { let n = nights[min(dayIndex, nights.count - 1)]; return Moment(s: n.s, body: .sleep, hrBias: n.bias, hrvScale: n.scale) }
        if sod >= 23 * 3600 { let n = nights[min(dayIndex + 1, nights.count - 1)]; return Moment(s: n.s, body: .sleep, hrBias: n.bias, hrvScale: n.scale) }
        let p = days[min(d, days.count - 1)]
        let h = Double(sod) / 3600
        var s = p.base + 0.12 * sin(2 * .pi * (h - 8) / 14) - (h >= 21 ? 0.2 : 0)
        for e in p.events { s += (e.peak - p.base) * Life.window(h, e.a, e.b) }
        s = min(max(s, 0.05), 2.95)
        if workoutSeconds.contains(where: { $0.contains(t) }) { return Moment(s: 1.0, body: .exercise, hrBias: p.bias, hrvScale: p.scale) }
        if walkSeconds[min(d, walkSeconds.count - 1)].contains(where: { $0.contains(t) }) { return Moment(s: s, body: .walk, hrBias: p.bias, hrvScale: p.scale) }
        return Moment(s: s, body: .sedentary, hrBias: p.bias, hrvScale: p.scale)
    }

    func generate(artifact: Double, seed: UInt64 = 2026) -> SimData {
        let t0 = 1_793_000_000 - (1_793_000_000 % 86_400)
        var d = Generator.build(seconds: Life.totalSeconds, t0: t0, seed: seed, artifact: artifact, gravity: true, moment: moment)
        d.sleep = sleepRanges.map { ($0.lowerBound + t0)...($0.upperBound + t0) }
        d.workouts = workouts.map { ($0.lowerBound + t0)...($0.upperBound + t0) }
        return d
    }
}
