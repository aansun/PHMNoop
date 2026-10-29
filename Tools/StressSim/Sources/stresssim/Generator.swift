import Foundation
import WhoopProtocol

/// Deterministic random numbers, so a run can be repeated and two methods see exactly the same data.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func normal() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

enum Body: UInt8 { case sleep = 0, sedentary, walk, exercise }

/// One second of the invented life: the true stress, what the body was doing, and the physiology that follows from both.
struct Moment {
    var s: Double        // the true stress, 0 to 3 (for exercise: the underlying, non-physical stress)
    var body: Body
    /// Things that move the heart rate and RMSSD without being stress: how this person ran that day or night (caffeine, a cold room, wear).
    var hrBias = 0.0
    var hrvScale = 1.0
}

/// The physiology the generator gives each moment. It is the generator's own model and the two methods never see it.
enum Physio {
    static func hr(_ m: Moment) -> Double { base(m) + m.hrBias }
    static func rmssd(_ m: Moment) -> Double { baseRMSSD(m) * m.hrvScale }
    private static func base(_ m: Moment) -> Double {
        switch m.body {
        case .sleep: return 52 + 3 * m.s
        case .sedentary: return 62 + 9 * m.s
        case .walk: return 62 + 9 * m.s + 18
        case .exercise: return 145
        }
    }
    private static func baseRMSSD(_ m: Moment) -> Double {
        switch m.body {
        case .sleep: return 85 * exp(-0.3 * (m.s - 0.5))
        case .sedentary: return 55 * exp(-0.35 * (m.s - 1.5))
        case .walk: return 0.8 * 55 * exp(-0.35 * (m.s - 1.5))
        case .exercise: return 10
        }
    }
}

struct SimData {
    var t0 = 0
    var hr: [HRSample] = []
    var rr: [RRInterval] = []
    var gravity: [GravitySample] = []
    var truth: [Moment] = []
    var sleep: [ClosedRange<Int>] = []
    var workouts: [ClosedRange<Int>] = []
}

enum Generator {
    /// Builds `seconds` of data from `moment(i)`. `artifact` is how often daytime R-R goes wrong: the chance per minute that a burst of
    /// bad beats starts (posture, motion, talking), lasting 30 to 120 s in which 70% of the beats are plausible-looking but random intervals. Asleep it is a tenth of that. A
    /// small steady rate of single bad beats runs underneath.
    static func build(seconds: Int, t0: Int, seed: UInt64, artifact: Double, gravity withGravity: Bool, moment: (Int) -> Moment) -> SimData {
        var rng = SplitMix(seed: seed)
        var d = SimData(); d.t0 = t0
        d.hr.reserveCapacity(seconds); d.rr.reserveCapacity(seconds + seconds / 8)
        d.truth.reserveCapacity(seconds)
        var wander = 0.0
        var nextBeat = 0.0
        var burstUntil = -1
        var g = (x: 0.02, y: 0.03, z: 1.0)
        for i in 0..<seconds {
            let m = moment(i)
            d.truth.append(m)
            wander = 0.98 * wander + 0.2 * rng.normal()
            let hrNow = Physio.hr(m) + wander * 1.2 + rng.normal() * 0.5
            d.hr.append(HRSample(ts: t0 + i, bpm: max(35, Int(hrNow.rounded()))))

            let rmssd = Physio.rmssd(m)
            let sd = rmssd / 2.0.squareRoot()
            let scale = m.body == .sleep ? 0.1 : (m.body == .exercise ? 1.5 : 1.0)
            if i >= burstUntil, rng.uniform() < artifact * scale / 60 { burstUntil = i + 30 + Int(rng.uniform() * 90) }
            let inBurst = i < burstUntil
            let pArt = 0.005 * scale
            while nextBeat < Double(i + 1) {
                var rr = 60_000 / hrNow + rng.normal() * sd
                var beats = [rr]
                if inBurst, rng.uniform() < 0.7 {
                    // Motion or talking: the optical signal gives plausible-looking but unrelated intervals. They sit inside the
                    // normal range and mostly agree with their neighbours within 20% often enough to survive the cleaning.
                    rr = 420 + 530 * rng.uniform(); beats = [rr]
                } else if rng.uniform() < pArt {
                    let k = rng.uniform()
                    if k < 0.4 { beats = [rr * 2] }                          // a missed beat
                    else if k < 0.7 { beats = [rr * 0.45, rr * 0.55] }       // an extra beat
                    else { rr += rng.normal() * 180; beats = [rr] }          // noise on the beat
                }
                for b in beats {
                    let clamped = min(max(b, 250), 2_600)
                    d.rr.append(RRInterval(ts: t0 + Int(nextBeat), rrMs: Int(clamped.rounded())))
                    nextBeat += clamped / 1000
                }
            }
            if withGravity {
                let move: Double
                switch m.body { case .sleep: move = 0.004; case .sedentary: move = 0.01; case .walk: move = 0.28; case .exercise: move = 0.6 }
                g.x += rng.normal() * move; g.y += rng.normal() * move; g.z += rng.normal() * move
                // Keep the vector near rest so it does not drift away: gravity is a unit vector, orientation changes are what move it.
                g.x = 0.95 * g.x + 0.05 * 0.02; g.y = 0.95 * g.y + 0.05 * 0.03; g.z = 0.95 * g.z + 0.05 * 1.0
                d.gravity.append(GravitySample(ts: t0 + i, x: g.x, y: g.y, z: g.z))
            }
        }
        return d
    }
}

// MARK: - The three days

/// The invented timeline: three days and the nights between and before them, with what truly happened.
///   Day 1  calm. A short walk to lunch.
///   Day 2  a stressful morning meeting, a workout at 17:30, a tense evening.
///   Day 3  poor sleep behind it, a steady mild strain, a deadline at 14:00, a walk to work.
/// Nights: night 0 (before day 1, calm), night 1 (calm), night 2 (a little raised), night 3 (poor).
enum Scenario {
    static let day: Int = 86_400
    static let totalSeconds = 3 * 86_400 + Int(6.5 * 3600) + 1

    /// The hours asleep: 23:00 to 06:30, and the 00:00 to 06:30 before day 1.
    static let sleepRanges: [ClosedRange<Int>] = [
        0...Int(6.5 * 3600),
        (23 * 3600)...((24 + 6) * 3600 + 1800),
        (47 * 3600)...((48 + 6) * 3600 + 1800),
        (71 * 3600)...((72 + 6) * 3600 + 1800),
    ]
    static let nightStress = [0.4, 0.4, 0.9, 1.8]
    /// How each night and day ran for reasons that are not stress.
    static let nightBias = [0.0, 0.8, -0.6, 0.4], nightScale = [1.0, 0.95, 1.05, 0.90]
    static let dayBias = [-1.0, 2.0, 1.5], dayScale = [1.0, 0.92, 0.95]

    static let workouts: [ClosedRange<Int>] = [(Int(41.5 * 3600))...(Int(42.5 * 3600))]
    static let walks: [ClosedRange<Int>] = [
        Int(12.5 * 3600)...Int(12.75 * 3600),
        Int(32.17 * 3600)...Int(32.5 * 3600),
        Int(56.0 * 3600)...Int(56.33 * 3600),
    ]

    /// A smooth window: 0 outside, 1 inside, with soft edges (hours).
    private static func window(_ h: Double, _ a: Double, _ b: Double, edge: Double = 0.25) -> Double {
        1 / (1 + exp(-(h - a) / (edge / 4))) * (1 - 1 / (1 + exp(-(h - b) / (edge / 4))))
    }
    private static func bump(_ h: Double, _ c: Double, _ w: Double) -> Double { exp(-pow((h - c) / w, 2)) }

    static func moment(_ t: Int) -> Moment {
        for (k, r) in sleepRanges.enumerated() where r.contains(t) { return Moment(s: nightStress[k], body: .sleep, hrBias: nightBias[k], hrvScale: nightScale[k]) }
        let dayIndex = t / day
        let h = Double(t % day) / 3600
        var s: Double
        switch dayIndex {
        case 0:
            s = 0.8 + 0.15 * sin(2 * .pi * (h - 8) / 12) + 0.5 * bump(h, 12.9, 0.35) - (h >= 21 ? 0.25 : 0)
        case 1:
            s = 0.9 + 1.5 * window(h, 9.0, 11.0) + 0.3 * bump(h, 12.5, 0.4) + 1.3 * window(h, 20.25, 21.0, edge: 0.15)
        default:
            s = 1.5 + 1.2 * bump(h, 14.4, 0.4) - (h >= 21 ? 0.2 : 0)
        }
        s = min(max(s, 0.05), 2.95)
        let bias = dayBias[min(dayIndex, 2)], scale = dayScale[min(dayIndex, 2)]
        if workouts.contains(where: { $0.contains(t) }) { return Moment(s: 1.0, body: .exercise, hrBias: bias, hrvScale: scale) }
        if walks.contains(where: { $0.contains(t) }) { return Moment(s: s, body: .walk, hrBias: bias, hrvScale: scale) }
        return Moment(s: s, body: .sedentary, hrBias: bias, hrvScale: scale)
    }

    static func generate(artifact: Double, seed: UInt64 = 2026) -> SimData {
        var d = Generator.build(seconds: totalSeconds, t0: 1_793_000_000 - (1_793_000_000 % 86_400), seed: seed,
                                artifact: artifact, gravity: true, moment: moment)
        d.sleep = sleepRanges.map { ($0.lowerBound + d.t0)...($0.upperBound + d.t0) }
        d.workouts = workouts.map { ($0.lowerBound + d.t0)...($0.upperBound + d.t0) }
        return d
    }

    /// Thirty past nights, each at its own mild stress, hr and R-R only. The nightly figures the baselines are folded from.
    static func history(artifact: Double, nights: Int = 30, seed: UInt64 = 7) -> [(rhr: Double, rmssd: Double)] {
        var rng = SplitMix(seed: seed)
        var out: [(Double, Double)] = []
        for n in 0..<nights {
            let s = min(max(0.7 + 0.45 * rng.normal(), 0.1), 1.9)
            let bias = 1.5 * rng.normal(), scale = exp(0.12 * rng.normal())
            let d = Generator.build(seconds: 27_000, t0: 1_700_000_000 + n * 86_400, seed: seed &+ UInt64(n) &* 977,
                                    artifact: artifact, gravity: false) { _ in Moment(s: s, body: .sleep, hrBias: bias, hrvScale: scale) }
            out.append(NightMetrics.measure(hr: d.hr, rr: d.rr, from: d.t0, to: d.t0 + 27_000))
        }
        return out
    }
}
