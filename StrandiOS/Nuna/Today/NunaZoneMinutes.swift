#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopProtocol

/// Minutes in each of the five heart-rate zones, read from the stored heart-rate samples. One reader for the HR zones pages and the plan, so the
/// time one of them states is the time the other states.
enum NunaZoneMinutes {
    /// The zones are the bands the Effort is scored in (50–60 … 90–100% of the heart-rate reserve), each day against its own resting heart rate.
    @MainActor private static func reserve(repo: Repository, age: Int) -> (maxHR: Double, resting: [String: Double], latest: Double) {
        let maxHR = age > 0 ? StrainScorer.tanakaHRmax(age: Double(age)) : Double(StrainScorer.defaultMaxHR())
        let restingByDay = Dictionary(repo.days.compactMap { d in d.restingHr.map { (d.day, Double($0)) } }, uniquingKeysWith: { _, l in l })
        let latest = repo.days.last(where: { $0.restingHr != nil })?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        return (maxHR, restingByDay, latest)
    }

    /// Every day's five zone totals, read one day at a time so a long window is never cut short by the sample limit of a single read.
    @MainActor static func perDay(repo: Repository, age: Int, days: [Date]) async -> [Date: [Double]] {
        await ZoneMinutes.perDay(repo: repo, age: age, days: days)
    }

    /// The five zone totals inside one window (a workout), against the resting heart rate of the day it belongs to.
    @MainActor static func inWindow(repo: Repository, age: Int, from: Int, to: Int, day: Date) async -> [Double] {
        let (maxHR, restingByDay, latestResting) = reserve(repo: repo, age: age)
        let resting = restingByDay[Repository.localDayKey(day)] ?? latestResting
        let samples = await repo.hrSamples(from: from, to: to, limit: 50_000)
        return HRZones.timeInZone(samples, zoneSet: .reserveBands(maxHR: maxHR, restingHR: resting)).seconds.map { $0 / 60 }
    }
}
#endif
