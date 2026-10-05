#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// The figures of a running session that more than one surface draws (the live screen and the Live Activity), computed once from
/// the session's own heart-rate samples so the two cannot disagree.
enum NunaLiveMetrics {
    /// Calories so far, with the same estimate the saved workout uses. nil until two samples exist.
    @MainActor static func kcal(_ w: AppModel.ActiveWorkout, model: AppModel) -> Int? {
        guard w.samples.count >= 2 else { return nil }
        let rhr = model.repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let up = UserProfile(weightKg: model.profile.weightKg, heightCm: model.profile.heightCm, age: Double(model.profile.age), sex: model.profile.sex)
        let v = Calories.estimateBoutCalories(w.samples, profile: up, hrmax: Double(model.profile.hrMax), restingHR: rhr).0
        return v > 0 ? Int(v.rounded()) : nil
    }

    /// Seconds spent in each of the five zones, from the gaps between samples (a gap over 10 s counts as 10 s).
    static func zoneSeconds(_ w: AppModel.ActiveWorkout, zoneSet: HRZoneSet) -> [Int] {
        var out = [Double](repeating: 0, count: 5)
        let s = w.samples
        if s.count >= 2 {
            for i in 0..<(s.count - 1) {
                let dt = min(Double(s[i + 1].ts - s[i].ts), 10)
                let z = zoneSet.zoneNumber(forBPM: Double(s[i].bpm))
                if dt > 0, z >= 1 { out[min(z, 5) - 1] += dt }
            }
        }
        return out.map { Int($0.rounded()) }
    }

    /// Where a heart rate sits across the five-zone bar, 0 to 1: the zone's own segment, and how far through that zone's range.
    static func barPosition(bpm: Int, zoneSet: HRZoneSet) -> Double {
        let zone = zoneSet.zoneNumber(forBPM: Double(bpm))
        guard zone >= 1, let z = zoneSet.zones.first(where: { $0.number == min(zone, 5) }), z.upper > z.lower else { return 0 }
        let frac = min(max((Double(bpm) - z.lower) / (z.upper - z.lower), 0), 1)
        return (Double(zone - 1) + frac) / 5
    }
}
#endif
