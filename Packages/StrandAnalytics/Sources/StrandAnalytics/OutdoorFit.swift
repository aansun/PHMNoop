import Foundation

// OutdoorFit.swift - how well a stretch of the day suits time outdoors, by the same thresholds the advice uses.
//
// PURE (Foundation only) and unit-tested. General guidance for a healthy adult, not medical advice.

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
