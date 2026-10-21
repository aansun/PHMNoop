#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Rings when the diary or the Lab Book is written to. `Repository.refresh()` only bumps `refreshSeq` for what it caches, so a screen that shows
/// these rows watches this as well to reload the moment something is added or removed.
@MainActor
final class NunaDataChanges: ObservableObject {
    static let shared = NunaDataChanges()
    @Published private(set) var seq = 0
    func bump() { seq += 1 }
}

/// A number for the screen: no decimals unless asked, a dash for nothing.
func nutFmt(_ v: Double?, _ digits: Int = 0) -> String {
    v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

/// The meals of the diary, in the order of the day.
enum NunaMeal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .breakfast: "Breakfast"; case .lunch: "Lunch"; case .dinner: "Dinner"; case .snack: "Snacks" }
    }
    var singular: LocalizedStringKey {
        switch self { case .breakfast: "Breakfast"; case .lunch: "Lunch"; case .dinner: "Dinner"; case .snack: "Snack" }
    }

    /// The meal it most likely is at this hour, for a new entry.
    static func suggested(at date: Date = Date()) -> NunaMeal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

/// What the person set in Strategy: the pace they want, how protein and fat are worked out, and the daily target that came of it.
enum NunaNutritionPrefs {
    static let hasPlan = "nuna.nutrition.hasPlan"
    /// Kg of body weight per week, negative to lose.
    static let paceKgPerWeek = "nuna.nutrition.paceKgPerWeek"
    static let proteinPerKg = "nuna.nutrition.proteinPerKg"
    static let fatShare = "nuna.nutrition.fatShare"
    /// The daily target in kcal; 0 until a plan is saved. A check-in can move it.
    static let targetKcal = "nuna.nutrition.targetKcal"
    /// `yyyy-MM-dd` of the last weekly check-in the person answered.
    static let lastCheckIn = "nuna.nutrition.lastCheckIn"

    static var defaultProteinPerKg: Double { 1.8 }
    static var defaultFatShare: Double { 0.28 }
}

/// One day of the diary: the entries and what they add up to.
struct NunaFoodDay {
    var entries: [FoodEntryRow] = []
    var kcal: Double { entries.reduce(0) { $0 + $1.kcal } }
    var proteinG: Double { entries.reduce(0) { $0 + ($1.proteinG ?? 0) } }
    var carbsG: Double { entries.reduce(0) { $0 + ($1.carbsG ?? 0) } }
    var fatG: Double { entries.reduce(0) { $0 + ($1.fatG ?? 0) } }
    func entries(_ meal: NunaMeal) -> [FoodEntryRow] { entries.filter { $0.meal == meal.rawValue } }
}

/// Reads and writes of the diary, kept out of the views.
@MainActor
enum NunaFoodStore {
    static func day(_ day: String, repo: Repository) async -> NunaFoodDay {
        guard let store = await repo.storeHandle() else { return NunaFoodDay() }
        return NunaFoodDay(entries: (try? await store.foodEntries(deviceId: repo.deviceId, fromDay: day, toDay: day)) ?? [])
    }

    static func entry(day: String, meal: NunaMeal, name: String, kcal: Double, proteinG: Double?, carbsG: Double?, fatG: Double?, source: String, repo: Repository) -> FoodEntryRow {
        FoodEntryRow(id: UUID().uuidString, deviceId: repo.deviceId, day: day, meal: meal.rawValue, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                     kcal: max(0, kcal), proteinG: proteinG.map { max(0, $0) }, carbsG: carbsG.map { max(0, $0) }, fatG: fatG.map { max(0, $0) }, source: source,
                     createdAt: Int(Date().timeIntervalSince1970))
    }

    static func add(_ entries: [FoodEntryRow], repo: Repository) async {
        guard !entries.isEmpty, let store = await repo.storeHandle() else { return }
        _ = try? await store.upsertFoodEntries(entries)
        await repo.refresh()
        NunaDataChanges.shared.bump()
    }

    static func delete(id: String, repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteFoodEntry(id: id)
        await repo.refresh()
        NunaDataChanges.shared.bump()
    }

    static func savedFoods(repo: Repository) async -> [SavedFoodRow] {
        guard let store = await repo.storeHandle() else { return [] }
        return (try? await store.savedFoods(deviceId: repo.deviceId)) ?? []
    }

    static func recentFoods(repo: Repository) async -> [FoodEntryRow] {
        guard let store = await repo.storeHandle() else { return [] }
        return (try? await store.recentFoods(deviceId: repo.deviceId, limit: 30)) ?? []
    }

    static func keep(name: String, kcal: Double, proteinG: Double?, carbsG: Double?, fatG: Double?, repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        try? await store.upsertSavedFood(SavedFoodRow(id: UUID().uuidString, deviceId: repo.deviceId, name: String(name.prefix(80)), kcal: kcal, proteinG: proteinG, carbsG: carbsG,
                                                      fatG: fatG, useCount: 0, updatedAt: Int(Date().timeIntervalSince1970)))
    }

    static func bump(_ id: String, repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        try? await store.bumpSavedFood(id: id, at: Int(Date().timeIntervalSince1970))
    }

    static func deleteSaved(id: String, repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteSavedFood(id: id)
    }

    // MARK: Intake and weight over time

    /// What was eaten each day for the last `days`: the diary where a day has entries, otherwise the daily total of an imported CSV.
    static func intakeByDay(days: Int, repo: Repository) async -> [String: Double] {
        var out: [String: Double] = [:]
        for p in await repo.exploreSeries(key: "calories_in", source: "nutrition-csv", days: days) where p.value > 0 { out[p.day] = p.value }
        guard let store = await repo.storeHandle() else { return out }
        let now = Date()
        let from = Repository.localDayKey(now.addingTimeInterval(-Double(days) * 86_400)), to = Repository.localDayKey(now)
        let rows = (try? await store.foodEntries(deviceId: repo.deviceId, fromDay: from, toDay: to)) ?? []
        for (d, list) in Dictionary(grouping: rows, by: \.day) { out[d] = list.reduce(0) { $0 + $1.kcal } }
        return out
    }

    /// Weigh-ins from Apple Health, typed in by hand and an imported nutrition CSV; a typed value wins for its day.
    static func weights(days: Int, repo: Repository) async -> [NutritionMath.WeightPoint] {
        var map: [String: Double] = [:]
        for src in ["apple-health", "nutrition-csv", nunaManualSource] {
            for p in await repo.exploreSeries(key: "weight", source: src, days: days) where p.value > 0 { map[p.day] = p.value }
        }
        return map.map { NutritionMath.WeightPoint(day: $0.key, kg: $0.value) }.sorted { $0.day < $1.day }
    }

    /// What the body spends per day and where that figure came from.
    enum MaintenanceSource { case foodAndWeight, profile }

    static func maintenance(intake: [String: Double], weights: [NutritionMath.WeightPoint], profile: ProfileStore, today: String = Repository.localDayKey(Date())) -> (kcal: Double, source: MaintenanceSource)? {
        if let e = NutritionMath.expenditure(intake: intake, trend: NutritionMath.trend(weights), endDay: today) { return (e, .foodAndWeight) }
        let age = Calendar.current.dateComponents([.year], from: profile.dateOfBirth, to: Date()).year.map(Double.init) ?? 0
        let kg = NutritionMath.trend(weights).last?.kg ?? profile.weightKg
        if let m = NutritionMath.profileMaintenance(sex: profile.sex, ageYears: age, weightKg: kg, heightCm: profile.heightCm) { return (m, .profile) }
        return nil
    }
}
#endif
