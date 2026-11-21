import Foundation

// EnvironmentTraining.swift - what the weather and the air mean for the day's Strain: how suitable each stretch of the day is for time outdoors,
// how much load the person has room for, and which activities fit both.
//
// PURE (Foundation only) and unit-tested. It reads an `EnvironmentSnapshot` and the Strain target; it invents no figure. The sentences are composed in the
// app layer, where they are localised. General guidance for a healthy adult, not medical advice.

/// How much the day has room for, from the Strain the person's Recovery supports (the band on the 0-21 axis) and the Strain already done.
public enum TrainingLoad: Int, Equatable, Sendable, Comparable {
    case recover, easy, moderate, hard
    public static func < (a: TrainingLoad, b: TrainingLoad) -> Bool { a.rawValue < b.rawValue }

    /// `targetHigh` is the top of the Strain band today's Recovery supports (0-21 axis); `soFar` the Strain done today on the same axis.
    /// Without a band, Recovery alone decides (under 34 an easy day, from 67 a day with room for a hard one). Nothing known: a moderate day.
    public static func of(recoveryPct: Double?, targetHigh: Double?, soFar: Double?) -> TrainingLoad {
        var load: TrainingLoad
        if let hi = targetHigh {
            if let soFar, soFar >= hi - 0.5 { return .recover }   // the band is already used
            if hi <= 10 { load = TrainingLoad.easy } else if hi <= 14 { load = TrainingLoad.moderate } else { load = TrainingLoad.hard }
        } else if let r = recoveryPct {
            if r < 34 { load = TrainingLoad.easy } else if r < 67 { load = TrainingLoad.moderate } else { load = TrainingLoad.hard }
        } else {
            return .moderate
        }
        if let r = recoveryPct, r < 34, load > TrainingLoad.easy { load = TrainingLoad.easy }
        return load
    }
}

/// How well a stretch of the day suits time outdoors.
public enum OutdoorFit: Int, Equatable, Sendable, Comparable {
    case good, adjust, indoors
    public static func < (a: OutdoorFit, b: OutdoorFit) -> Bool { a.rawValue < b.rawValue }

    /// The same thresholds the advice uses, applied to one step of the forecast.
    public static func of(feelsLikeC: Double?, humidityPct: Double?, usAqi: Int?, rainChance: Double, windMps: Double?, conditionId: Int?) -> OutdoorFit {
        var fit = OutdoorFit.good
        func raise(_ f: OutdoorFit) { if f > fit { fit = f } }
        if let t = feelsLikeC {
            if t >= EnvironmentAdvice.veryHotC || t <= EnvironmentAdvice.freezingC { raise(.indoors) }
            else if t >= EnvironmentAdvice.hotC || (t >= 30 && (humidityPct ?? 0) >= 70) || t <= EnvironmentAdvice.coldC { raise(.adjust) }
        }
        if let aqi = usAqi {
            switch AirQuality.band(usAqi: aqi) {
            case .good, .moderate: break
            case .unhealthyForSensitive: raise(.adjust)
            default: raise(.indoors)
            }
        }
        if let id = conditionId {
            if (200..<300).contains(id) { raise(.indoors) } else if (300..<600).contains(id) { raise(.adjust) }
        }
        if rainChance >= 0.5 { raise(.adjust) }
        if let w = windMps, w >= EnvironmentAdvice.windMps { raise(.adjust) }
        return fit
    }
}

/// One activity the conditions and the Strain room agree on.
public struct ActivityPick: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case easyWalk, run, intervalRun, ride, strength, treadmill, indoorRide, mobility, breathwork
    }

    /// Why it is on the list, in the order that matters.
    public enum Why: Equatable, Sendable {
        case coolWindow(feelsLikeC: Double)
        case cleanAir(usAqi: Int)
        case airTooPoor(usAqi: Int)
        case tooHot(feelsLikeC: Double)
        case rainLikely(chance: Double)
        case storm
        case windStrong
        case fitsTarget
        case targetReached
        case recoveryLow
        case shortenedForHeat
    }

    public var id: String { kind.rawValue }
    public let kind: Kind
    public let outdoors: Bool
    public let minutes: Int
    /// When to go, for an outdoor pick: the kindest stretch of the day.
    public let window: EnvironmentOutlook.Window?
    public let whys: [Why]
}

public enum EnvironmentTraining {
    /// Up to three activities for the load and the conditions, the best first. Outdoor ones only when the kindest stretch of the day is not an indoor day.
    public static func picks(_ s: EnvironmentSnapshot, outlook: EnvironmentOutlook?, load: TrainingLoad) -> [ActivityPick] {
        // An activity for today is planned in today's own hours; tomorrow's kind morning is not a place for it.
        let best = outlook?.bestToday
        let fit = best.map { w in
            OutdoorFit.of(feelsLikeC: w.feelsLikeC, humidityPct: s.humidityPct, usAqi: w.usAqi, rainChance: w.rainChance, windMps: w.windMps, conditionId: w.conditionId)
        } ?? .indoors
        let outdoorOK = best != nil && fit != .indoors
        let hot = (best?.feelsLikeC ?? s.effectiveC ?? 0) >= EnvironmentAdvice.hotC - 3
        let shorten = hot || fit == .adjust

        // The reasons that go with a choice outdoors, or with staying in.
        var outdoorWhys: [ActivityPick.Why] = []
        var indoorWhys: [ActivityPick.Why] = []
        if let w = best, outdoorOK {
            outdoorWhys.append(.coolWindow(feelsLikeC: w.feelsLikeC))
            if let aqi = w.usAqi, AirQuality.band(usAqi: aqi) <= .moderate { outdoorWhys.append(.cleanAir(usAqi: aqi)) }
            if shorten, hot { outdoorWhys.append(.shortenedForHeat) }
        } else {
            let a = s.usAqi ?? 0
            if let w = best, w.usAqi.map({ $0 >= 151 }) == true || a >= 151 { indoorWhys.append(.airTooPoor(usAqi: w.usAqi ?? a)) }
            if let t = best?.feelsLikeC ?? s.effectiveC, t >= EnvironmentAdvice.veryHotC { indoorWhys.append(.tooHot(feelsLikeC: t)) }
            if let id = best?.conditionId ?? s.conditionId, (200..<300).contains(id) { indoorWhys.append(.storm) }
            if indoorWhys.isEmpty, let w = best, w.rainChance >= 0.5 { indoorWhys.append(.rainLikely(chance: w.rainChance)) }
            if indoorWhys.isEmpty, (s.usAqi ?? 0) >= 101 { indoorWhys.append(.airTooPoor(usAqi: s.usAqi ?? 0)) }
        }
        func pick(_ kind: ActivityPick.Kind, outdoors: Bool, minutes: Int, extra: [ActivityPick.Why] = []) -> ActivityPick {
            let base = outdoors ? outdoorWhys : indoorWhys
            // Each reason once, in the order given (a pick is handed the indoor reasons both by its case and by the base).
            var whys: [ActivityPick.Why] = []
            for w in extra + base where !whys.contains(w) { whys.append(w) }
            return ActivityPick(kind: kind, outdoors: outdoors, minutes: minutes, window: outdoors ? best : nil, whys: whys)
        }
        func cut(_ m: Int) -> Int { shorten ? Int((Double(m) * 0.75 / 5).rounded()) * 5 : m }

        var out: [ActivityPick] = []
        switch load {
        case .recover:
            let why: ActivityPick.Why = .targetReached
            if outdoorOK { out.append(pick(.easyWalk, outdoors: true, minutes: 25, extra: [why])) }
            out.append(pick(.mobility, outdoors: false, minutes: 20, extra: outdoorOK ? [why] : [why] + indoorWhys))
            out.append(pick(.breathwork, outdoors: false, minutes: 10, extra: [why]))
        case .easy:
            let why: ActivityPick.Why = .recoveryLow
            if outdoorOK { out.append(pick(.easyWalk, outdoors: true, minutes: cut(40), extra: [why])) }
            if outdoorOK, (s.windMps ?? 0) < EnvironmentAdvice.windMps { out.append(pick(.ride, outdoors: true, minutes: cut(40), extra: [why])) }
            out.append(pick(.mobility, outdoors: false, minutes: 25, extra: outdoorOK ? [why] : [why] + indoorWhys))
        case .moderate:
            if outdoorOK {
                out.append(pick(.run, outdoors: true, minutes: cut(40), extra: [.fitsTarget]))
                if (s.windMps ?? 0) < EnvironmentAdvice.windMps { out.append(pick(.ride, outdoors: true, minutes: cut(60), extra: [.fitsTarget])) }
                out.append(pick(.strength, outdoors: false, minutes: 40, extra: [.fitsTarget]))
            } else {
                out.append(pick(.treadmill, outdoors: false, minutes: 40, extra: [.fitsTarget] + indoorWhys))
                out.append(pick(.strength, outdoors: false, minutes: 40, extra: [.fitsTarget] + indoorWhys))
                out.append(pick(.indoorRide, outdoors: false, minutes: 45, extra: [.fitsTarget] + indoorWhys))
            }
        case .hard:
            if outdoorOK, fit == .good {
                out.append(pick(.intervalRun, outdoors: true, minutes: 45, extra: [.fitsTarget]))
                if (s.windMps ?? 0) < EnvironmentAdvice.windMps { out.append(pick(.ride, outdoors: true, minutes: 75, extra: [.fitsTarget])) }
                out.append(pick(.strength, outdoors: false, minutes: 45, extra: [.fitsTarget]))
            } else if outdoorOK {
                // Room for a hard day, but the heat, the air or the rain says not to spend it outside at full gas: steady outside, the hard work inside.
                out.append(pick(.strength, outdoors: false, minutes: 45, extra: [.fitsTarget] + outdoorWhys.filter { if case .shortenedForHeat = $0 { return true }; return false }))
                out.append(pick(.run, outdoors: true, minutes: cut(40), extra: [.fitsTarget]))
                out.append(pick(.indoorRide, outdoors: false, minutes: 40, extra: [.fitsTarget]))
            } else {
                out.append(pick(.strength, outdoors: false, minutes: 50, extra: [.fitsTarget] + indoorWhys))
                out.append(pick(.indoorRide, outdoors: false, minutes: 40, extra: [.fitsTarget] + indoorWhys))
                out.append(pick(.treadmill, outdoors: false, minutes: 35, extra: [.fitsTarget] + indoorWhys))
            }
        }
        return Array(out.prefix(3))
    }
}
