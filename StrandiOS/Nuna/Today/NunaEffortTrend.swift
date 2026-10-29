#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

extension NunaSeriesModel {
    /// The mean of the last 30 readings before a day (nil with fewer than five): what a figure on that day is compared with.
    func average30(before key: String) -> Double? {
        let recent = byDay.filter { $0.key < key }.sorted { $0.key > $1.key }.prefix(30).map(\.value)
        return recent.count >= 5 ? recent.reduce(0, +) / Double(recent.count) : nil
    }
}

/// Minutes in the easy (1 to 3) and hard (4 and 5) heart-rate zones for each day, worked out from that day's heart rate, for the Effort page's
/// 30-day comparison and its weekly zone cards. Zone time is not a stored series, so it is read and binned here. A finished day never changes,
/// so it is worked out once per session and kept; today is always read again.
@MainActor
final class NunaEffortZoneHistory: ObservableObject {
    /// Minutes in each of the five zones.
    struct Minutes {
        var zones: [Double]
        var easy: Double { zones[0] + zones[1] + zones[2] }
        var hard: Double { zones[3] + zones[4] }
    }

    @Published private(set) var byDay: [String: Minutes] = [:]
    private static var finished: [String: Minutes?] = [:]

    /// The days from `endingOffset` days ago back `days` days, filled in as each is read so the page does not wait for all of them.
    func load(repo: Repository, profile: ProfileStore, endingOffset: Int, days: Int = 36) async {
        let cal = Calendar.current
        let todayKey = Repository.localDayKey(Date())
        let maxHR = profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : Double(StrainScorer.defaultMaxHR())
        var out: [String: Minutes] = [:]
        for back in 0..<days {
            let date = NunaSelectedDay.date(offset: endingOffset + back)
            let key = Repository.localDayKey(date)
            let resting = repo.days.first { $0.day == key }?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
            let cacheKey = "\(key)|\(Int(resting))|\(Int(maxHR))"
            if key != todayKey, let cached = Self.finished[cacheKey] {
                if let cached { out[key] = cached }
                continue
            }
            let from = Int(date.timeIntervalSince1970)
            let to = Int((cal.date(byAdding: .day, value: 1, to: date) ?? date).timeIntervalSince1970)
            let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
            var minutes: Minutes?
            if hr.count >= 300 {
                let t = HRZones.timeInZone(hr, zoneSet: .reserveBands(maxHR: maxHR, restingHR: resting))
                minutes = Minutes(zones: t.seconds.prefix(5).map { $0 / 60 })
            }
            if key != todayKey { Self.finished[cacheKey] = .some(minutes) }
            if let minutes { out[key] = minutes; byDay = out }
        }
        byDay = out
    }

    /// The mean of the last 30 days that have heart rate before a day (nil with fewer than three).
    func average(easy: Bool, before key: String) -> Double? {
        let v = byDay.filter { $0.key < key }.sorted { $0.key > $1.key }.prefix(30).map { easy ? $0.value.easy : $0.value.hard }
        return v.count >= 3 ? v.reduce(0, +) / Double(v.count) : nil
    }

    /// Minutes per zone for each day, for the weekly stacked bars.
    var zonesByDay: [String: [Double]] { byDay.mapValues(\.zones) }
}

#endif
