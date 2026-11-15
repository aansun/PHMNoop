#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// The latest week as the fitness age page reads it: the nine inputs (the ones a week has; the others are nil), what each adds or takes away, and the Body Age
/// they make, which is the one age the page shows.
struct NunaHealthspanResult {
    let inputs: VitalityEngine.Inputs
    let contributions: [VitalityEngine.Contribution]
    /// nil until three of the nine inputs are there.
    let bodyAge: Double?

    /// The years the input `key` adds (older, positive) or takes away (younger, negative), as the Body Age counts them; nil for an input with no data.
    func years(_ key: String) -> Double? { contributions.first { $0.key == key }.map(VitalityEngine.years(of:)) }

    /// How many of the nine inputs have data.
    var inputsUsed: Int { contributions.count }
}

/// Reads the week through `VitalityWeekReader` (the reader the weekly job that stores `body_age` and the Health screen use too) and runs it through `VitalityEngine`, so
/// the figures here are the stored ones.
enum NunaHealthspan {
    /// The result for the last read, so the Health tab's card and the fitness age page, which both ask for the latest age, read the week once and show the same figure.
    @MainActor private static var cached: (key: String, result: NunaHealthspanResult?)?

    /// The age of the latest 7 days. Read once for the same days, profile and VO₂ max, and shared by every screen that shows the age.
    @MainActor static func latest(repo: Repository, profile: ProfileStore) async -> NunaHealthspanResult? {
        let days = Array(repo.days.sorted { $0.day < $1.day }.suffix(7))
        let vo2 = (await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: 400)).last?.value
        let key = "\(days.last?.day ?? "")-\(days.count)-\(repo.refreshSeq)-\(profile.age)-\(profile.sex)-\(profile.waistCm)-\(vo2 ?? -1)"
        if let cached, cached.key == key { return cached.result }
        let result = await compute(days: days, vo2: vo2, repo: repo, profile: profile)
        cached = (key, result)
        return result
    }

    @MainActor static func compute(days: [DailyMetric], vo2: Double?, repo: Repository, profile: ProfileStore) async -> NunaHealthspanResult? {
        guard profile.age > 0 else { return nil }
        let week = await VitalityWeekReader.read(repo: repo, days: days, age: profile.age, sex: profile.sex, waistCm: profile.waistCm, vo2Estimate: vo2)
        let inputs = VitalityEngine.weeklyInputs(week)
        return NunaHealthspanResult(inputs: inputs, contributions: VitalityEngine.contributions(inputs), bodyAge: VitalityEngine.compute(inputs)?.bodyAge)
    }
}
#endif
