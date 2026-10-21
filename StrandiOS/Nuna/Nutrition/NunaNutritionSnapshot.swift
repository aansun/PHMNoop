#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandImport
import WhoopStore

/// What Anya is given besides the general health context when she is asked for a nutrition plan: the person, their weight and food, the plan they have now
/// and, when they share it, every Lab Book value with the range from their own report. Plain text, built here, so what leaves the phone is readable in one place.
@MainActor
enum NunaNutritionSnapshot {
    static func build(repo: Repository, profile: ProfileStore, includeLabBook: Bool) async -> String {
        let defaults = UserDefaults.standard
        var lines: [String] = []
        let age = Calendar.current.dateComponents([.year], from: profile.dateOfBirth, to: Date()).year ?? 0
        let weights = await NunaFoodStore.weights(days: 120, repo: repo)
        let trend = NutritionMath.trend(weights)
        let goal = defaults.double(forKey: NunaGoals.targetWeightKg)
        lines.append("PROFILE: \(profile.sex), \(age) years, \(Int(profile.heightCm)) cm")
        if let last = trend.last {
            var w = "WEIGHT: trend \(String(format: "%.1f", last.kg)) kg on \(last.day)"
            if let a = trend.last(where: { (NutritionMath.dayIndex(last.day) ?? 0) - (NutritionMath.dayIndex($0.day) ?? 0) >= 14 }), let i = NutritionMath.dayIndex(last.day), let j = NutritionMath.dayIndex(a.day), i > j {
                w += String(format: ", %+.2f kg a week over the last %d days", (last.kg - a.kg) / Double(i - j) * 7, i - j)
            }
            lines.append(w)
        } else if profile.weightKg > 0 { lines.append("WEIGHT: \(String(format: "%.1f", profile.weightKg)) kg (from the profile, no weigh-ins)") }
        lines.append(goal > 0 ? "GOAL WEIGHT: \(String(format: "%.1f", goal)) kg" : "GOAL WEIGHT: not set")
        if goal > 0, let now = trend.last?.kg ?? (profile.weightKg > 0 ? profile.weightKg : nil), abs(goal - now) < 1.0 {
            lines.append("AT GOAL: the person is already within 1 kg of their goal weight, so the pace should be maintenance (0 kg a week)")
        }

        let intake = await NunaFoodStore.intakeByDay(days: 14, repo: repo)
        if intake.isEmpty { lines.append("FOOD DIARY: nothing logged in the last 14 days") }
        else { lines.append("FOOD DIARY: \(intake.count) of the last 14 days logged, average \(Int(intake.values.reduce(0, +) / Double(intake.count))) kcal a day") }
        if let m = NunaFoodStore.maintenance(intake: await NunaFoodStore.intakeByDay(days: 30, repo: repo), weights: weights, profile: profile) {
            lines.append("ESTIMATED DAILY ENERGY USE: \(Int(m.kcal)) kcal (\(m.source == .foodAndWeight ? "worked out from food and weight" : "from the profile, a rough estimate"))")
        }
        if defaults.bool(forKey: NunaNutritionPrefs.hasPlan) {
            let pace = defaults.object(forKey: NunaNutritionPrefs.paceKgPerWeek) as? Double ?? -0.5
            let protein = defaults.object(forKey: NunaNutritionPrefs.proteinPerKg) as? Double ?? NunaNutritionPrefs.defaultProteinPerKg
            let fat = defaults.object(forKey: NunaNutritionPrefs.fatShare) as? Double ?? NunaNutritionPrefs.defaultFatShare
            lines.append("CURRENT PLAN: \(Int(defaults.double(forKey: NunaNutritionPrefs.targetKcal))) kcal, pace \(pace) kg a week, protein \(protein) g/kg, fat \(Int(fat * 100))% of calories")
        } else { lines.append("CURRENT PLAN: none yet") }

        if includeLabBook {
            let rows = await NunaLabStore.load(repo)
            let markers = NunaLabGrouping.markers(rows)
            var labLines: [String] = []
            for m in markers where m.category != .bodyMeasurement {
                guard let latest = m.latest else { continue }
                var line = "  \(m.name) \(m.text(latest)) \(m.unit) on \(LabBookFormat.dayFromKey(latest.day))"
                if let r = m.ownRange { line += " (range on the person's own report \(r.label(key: m.key)) \(m.unit)" + {
                    switch m.latestStatus { case .within?: return ", inside it"; case .above?: return ", above it"; case .below?: return ", below it"; case nil: return "" }
                }() + ")" } else { line += " (no range on file)" }
                labLines.append(line)
            }
            if labLines.isEmpty { lines.append("LAB BOOK: shared, but no results logged") }
            else { lines.append("LAB BOOK (the person's own results; ranges are the ones copied from their own reports):"); lines.append(contentsOf: labLines) }
        } else {
            lines.append("LAB BOOK: not shared (the person has not turned on Share patterns and Lab Book)")
        }
        return lines.joined(separator: "\n")
    }
}
#endif
