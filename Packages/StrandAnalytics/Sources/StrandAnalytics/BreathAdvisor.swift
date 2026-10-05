import Foundation

// BreathAdvisor.swift — which breathing exercise fits right now, from the numbers the strap already gives.
//
// PURE and unit-tested. Rule based, on the phone, with no provider: it weighs the live heart rate against the
// resting one, the short-window HRV, the day's stress, how recovered the wearer is, the time of day and what has
// worked for them before, then names a goal, a template and the figures behind the choice. The view layer turns the
// reasons into sentences. It is a relaxation aid, not a medical tool, and it never picks a forceful protocol on its own.

public enum BreathGoal: String, CaseIterable, Equatable, Sendable {
    case calm, sleep, focus, energize, recover
}

/// A ready-made session: a goal, a catalogue protocol and a length in minutes.
public struct BreathTemplate: Equatable, Sendable, Identifiable {
    public let id: String
    public let goal: BreathGoal
    public let protocolId: String
    public let minutes: Int
    /// Offered by the advisor on its own. Forceful techniques are listed for the wearer to choose but never suggested.
    public let advisable: Bool
}

public enum BreathTemplates {
    public static let all: [BreathTemplate] = [
        .init(id: "calm_slow", goal: .calm, protocolId: "relax_4_6", minutes: 5, advisable: true),
        .init(id: "calm_coherence", goal: .calm, protocolId: "coherence_5_5", minutes: 10, advisable: true),
        .init(id: "calm_deep", goal: .calm, protocolId: "deep_4_2_6", minutes: 5, advisable: true),
        .init(id: "sleep_478", goal: .sleep, protocolId: "four_seven_eight", minutes: 5, advisable: true),
        .init(id: "sleep_exhale", goal: .sleep, protocolId: "relax_4_6", minutes: 10, advisable: true),
        .init(id: "sleep_belly", goal: .sleep, protocolId: "diaphragmatic_4_2_6", minutes: 10, advisable: true),
        .init(id: "focus_box", goal: .focus, protocolId: "box_4_4_4_4", minutes: 5, advisable: true),
        .init(id: "focus_alternate", goal: .focus, protocolId: "nadi_shodhana", minutes: 5, advisable: true),
        .init(id: "focus_66", goal: .focus, protocolId: "coherent_6_6", minutes: 5, advisable: true),
        .init(id: "energize_ocean", goal: .energize, protocolId: "ujjayi", minutes: 5, advisable: true),
        .init(id: "energize_box", goal: .energize, protocolId: "box_4_4_4_4", minutes: 3, advisable: true),
        .init(id: "energize_bhastrika", goal: .energize, protocolId: "bhastrika", minutes: 3, advisable: false),
        .init(id: "recover_66", goal: .recover, protocolId: "coherent_6_6", minutes: 10, advisable: true),
        .init(id: "recover_belly", goal: .recover, protocolId: "diaphragmatic_4_2_6", minutes: 5, advisable: true),
        .init(id: "recover_coherence", goal: .recover, protocolId: "coherence_5_5", minutes: 10, advisable: true),
    ]

    public static func templates(for goal: BreathGoal) -> [BreathTemplate] { all.filter { $0.goal == goal } }
    public static func template(id: String) -> BreathTemplate? { all.first { $0.id == id } }
}

public struct BreathAdvisorInput: Equatable, Sendable {
    /// Live heart rate from the strap, if it is on the wrist and streaming.
    public var bpm: Int?
    /// RMSSD over the last few dozen beats (ms), if enough beats have come in.
    public var liveRmssd: Double?
    public var restingHr: Double?
    /// Last night's HRV against the wearer's own baseline (ms, positive = above).
    public var hrvDelta: Double?
    public var restingHrDelta: Double?
    /// Charge, 0 to 100.
    public var charge: Double?
    /// Day stress on the 0 to 3 scale.
    public var stress: Double?
    public var hour: Int
    /// For each template id, the mean percentage move in RMSSD over the wearer's past sessions with it.
    public var pastEffect: [String: Double]

    public init(bpm: Int? = nil, liveRmssd: Double? = nil, restingHr: Double? = nil, hrvDelta: Double? = nil,
                restingHrDelta: Double? = nil, charge: Double? = nil, stress: Double? = nil, hour: Int,
                pastEffect: [String: Double] = [:]) {
        self.bpm = bpm; self.liveRmssd = liveRmssd; self.restingHr = restingHr; self.hrvDelta = hrvDelta
        self.restingHrDelta = restingHrDelta; self.charge = charge; self.stress = stress; self.hour = hour
        self.pastEffect = pastEffect
    }
}

public enum BreathReason: Equatable, Sendable {
    case heartRateHigh(bpm: Int, aboveResting: Int)
    case liveHrvLow(ms: Int)
    case stressHigh(level: Double)
    case lateEvening(hour: Int)
    case lowCharge(pct: Int)
    case hrvDown(ms: Int)
    case restingHrUp(bpm: Int)
    case goodChargeMorning(pct: Int)
    case daytime(hour: Int)
    case noLiveData
    case workedBefore(pct: Int)
}

public struct BreathAdvice: Equatable, Sendable {
    public let goal: BreathGoal
    public let template: BreathTemplate
    public let reasons: [BreathReason]
    public let scores: [BreathGoal: Int]
}

public enum BreathAdvisor {
    public static func advise(_ i: BreathAdvisorInput) -> BreathAdvice {
        var score: [BreathGoal: Int] = Dictionary(uniqueKeysWithValues: BreathGoal.allCases.map { ($0, 0) })
        var why: [(BreathGoal, BreathReason, Int)] = []
        func add(_ g: BreathGoal, _ pts: Int, _ r: BreathReason) { score[g, default: 0] += pts; why.append((g, r, pts)) }

        if let bpm = i.bpm, let rhr = i.restingHr, rhr > 0 {
            let above = bpm - Int(rhr.rounded())
            if above >= 18 { add(.calm, 3, .heartRateHigh(bpm: bpm, aboveResting: above)) }
            else if above >= 10 { add(.calm, 1, .heartRateHigh(bpm: bpm, aboveResting: above)) }
        }
        if let r = i.liveRmssd, r > 0, r < 20 { add(.calm, 1, .liveHrvLow(ms: Int(r.rounded()))) }
        if let s = i.stress {
            if s >= 2 { add(.calm, 3, .stressHigh(level: s)) } else if s >= 1 { add(.calm, 1, .stressHigh(level: s)) }
        }
        if i.hour >= 21 || i.hour < 5 { add(.sleep, 3, .lateEvening(hour: i.hour)) }
        else if i.hour >= 19 { add(.sleep, 1, .lateEvening(hour: i.hour)) }

        var recoverPts = 0
        if let c = i.charge, c < 34 { recoverPts += 2; why.append((.recover, .lowCharge(pct: Int(c.rounded())), 2)) }
        if let d = i.hrvDelta, d <= -8 { recoverPts += 1; why.append((.recover, .hrvDown(ms: Int(abs(d).rounded())), 1)) }
        if let d = i.restingHrDelta, d >= 4 { recoverPts += 1; why.append((.recover, .restingHrUp(bpm: Int(d.rounded())), 1)) }
        score[.recover, default: 0] += recoverPts

        if i.hour >= 5 && i.hour < 11 {
            if let c = i.charge, c >= 67 { add(.energize, 2, .goodChargeMorning(pct: Int(c.rounded()))) }
            add(.focus, 1, .daytime(hour: i.hour))
        } else if i.hour >= 11 && i.hour < 19 {
            add(.focus, 1, .daytime(hour: i.hour))
        }
        if i.bpm == nil && i.liveRmssd == nil { why.append((.calm, .noLiveData, 0)) }

        // Highest score wins; ties go to calm, then the order of the cases.
        let order: [BreathGoal] = [.calm, .sleep, .recover, .focus, .energize]
        let best = order.max { (score[$0] ?? 0) < (score[$1] ?? 0) } ?? .calm
        // `max` keeps the last of equal elements, so walk the order to prefer the earliest.
        let top = score[best] ?? 0
        let goal = order.first { (score[$0] ?? 0) == top } ?? .calm

        var reasons = why.filter { $0.0 == goal && $0.2 > 0 }.map(\.1)
        let options = BreathTemplates.templates(for: goal).filter(\.advisable)
        var chosen = options.first ?? BreathTemplates.templates(for: goal)[0]

        // What worked before wins among the templates of the same goal.
        if let (t, pct) = options.compactMap({ t in i.pastEffect[t.id].map { (t, $0) } }).max(by: { $0.1 < $1.1 }), pct >= 5 {
            chosen = t
            reasons.append(.workedBefore(pct: Int(pct.rounded())))
        } else if goal == .calm, let bpm = i.bpm, let rhr = i.restingHr, bpm - Int(rhr.rounded()) >= 10,
                  let slow = options.first(where: { $0.id == "calm_slow" }) {
            chosen = slow   // a long exhale brings an elevated rate down fastest
        }
        if reasons.isEmpty {
            reasons = i.bpm == nil && i.liveRmssd == nil ? [.noLiveData] : [.daytime(hour: i.hour)]
        }
        return BreathAdvice(goal: goal, template: chosen, reasons: reasons, scores: score)
    }

    /// Mean percentage move of RMSSD for each template over past sessions: `(templateId, percent)` pairs.
    public static func pastEffect(_ sessions: [(templateId: String, startRmssd: Double?, meanRmssd: Double?)]) -> [String: Double] {
        var sums: [String: (Double, Int)] = [:]
        for s in sessions {
            guard let a = s.startRmssd, a > 0, let b = s.meanRmssd else { continue }
            let pct = (b - a) / a * 100
            let cur = sums[s.templateId] ?? (0, 0)
            sums[s.templateId] = (cur.0 + pct, cur.1 + 1)
        }
        var out: [String: Double] = [:]
        for (k, v) in sums where v.1 >= 2 { out[k] = v.0 / Double(v.1) }
        return out
    }
}
