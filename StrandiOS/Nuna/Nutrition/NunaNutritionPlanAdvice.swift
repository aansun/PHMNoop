#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// "Ask Anya for a plan": the figures are worked out here by rule (`NutritionPlanner`), and Anya is asked only to explain them. Her words are used
/// when they quote nothing but those figures; otherwise the app's own explanation stands. The reasons and cautions are always the app's.
@MainActor
enum NunaNutritionPlanAdvice {
    private static let kidneyMarkers = ["creatinine", "egfr", "urea", "bun", "albumin_urine", "uacr"]

    static func make(repo: Repository, profile: ProfileStore, coach: AICoachEngine) async -> AnyaPlanSpec? {
        let weights = await NunaFoodStore.weights(days: 120, repo: repo)
        let trend = NutritionMath.trend(weights)
        let month = await NunaFoodStore.intakeByDay(days: 30, repo: repo)
        guard let burn = NunaFoodStore.maintenance(intake: month, weights: weights, profile: profile) else { return nil }
        guard let weight = NunaFoodStore.planWeightKg(weights: weights, profile: profile) else { return nil }
        let goal = UserDefaults.standard.double(forKey: NunaGoals.targetWeightKg)
        var kidney = false
        if coach.includeOnDeviceSignals {
            kidney = NunaLabGrouping.markers(await NunaLabStore.load(repo)).contains { m in
                guard kidneyMarkers.contains(where: { m.key.lowercased().contains($0) }), let status = m.latestStatus else { return false }
                return status != .within
            }
        }
        let plan = NutritionPlanner.make(.init(maintenanceKcal: burn.kcal, weightKg: weight, heightCm: profile.heightCm, goalKg: goal > 0 ? goal : nil, kidneyResultOutOfRange: kidney))

        let logged = (await NunaFoodStore.intakeByDay(days: 14, repo: repo)).count
        let burnSource = burn.source == .foodAndWeight ? String(localized: "from your food and weight") : String(localized: "a rough estimate from your profile")

        var reasons = [
            String(localized: "Weight \(number(weight, 1)) kg\(trend.last.map { " (\(date($0.day)))" } ?? "")"),
            String(localized: "Daily burn about \(number(burn.kcal)) kcal, \(burnSource)"),
        ]
        if goal > 0 {
            if let weeks = plan.weeksToGoal { reasons.append(String(localized: "Goal \(number(goal, 1)) kg: about \(weeks) weeks at \(number(abs(plan.paceKgPerWeek), 2)) kg a week")) }
            else { reasons.append(String(localized: "Goal \(number(goal, 1)) kg: the plan holds your weight for now")) }
        } else {
            reasons.append(String(localized: "No goal weight set, so the plan holds your weight. Set one to get a pace."))
        }
        reasons.append(String(localized: "Protein \(number(plan.macros.proteinG)) g (\(plan.proteinPercent)%), fat \(number(plan.macros.fatG)) g (\(plan.fatPercent)%), carbs \(number(plan.macros.carbsG)) g (\(plan.carbsPercent)%)"))

        var cautions: [String] = []
        if logged < 10 { cautions.append(String(localized: "Food is logged on \(logged) of the last 14 days. Check the target again after two full weeks.")) }
        if plan.heldBecauseUnderweight { cautions.append(String(localized: "Your weight is already under the usual adult range, so no loss is planned. Talk to a clinician before losing weight.")) }
        if plan.easedForFloor { cautions.append(String(localized: "A faster pace would go under \(number(NutritionMath.floorKcal)) kcal a day, so the pace is gentler.")) }
        if kidney { cautions.append(String(localized: "A kidney result on your report is outside its range, so protein is kept modest. Please ask your clinician.")) }

        var explanation = goal > 0 && plan.paceKgPerWeek != 0
            ? String(localized: "Your target is \(number(plan.targetKcal)) kcal a day: your daily burn of about \(number(burn.kcal)) kcal, adjusted for \(number(abs(plan.paceKgPerWeek), 2)) kg a week toward \(number(goal, 1)) kg. Protein follows your body weight, fat is \(plan.fatPercent)% of the energy and carbs are the rest.")
            : String(localized: "Your target is \(number(plan.targetKcal)) kcal a day, your estimated daily burn, to hold your weight. Protein follows your body weight, fat is \(plan.fatPercent)% of the energy and carbs are the rest.")

        // Anya's words, only where there is a pace to talk about and only if they quote the figures given.
        if plan.paceKgPerWeek != 0, goal > 0 {
            let bmi = NutritionPlanner.bodyMassIndex(weightKg: weight, heightCm: profile.heightCm)
            var facts = [
                "Daily target \(Int(plan.targetKcal)) kcal. Daily burn about \(Int(burn.kcal.rounded())) kcal (\(burn.source == .foodAndWeight ? "worked out from food and weight" : "a rough estimate from the profile")).",
                "Difference \(Int(abs(burn.kcal - plan.targetKcal).rounded())) kcal a day, \(plan.paceKgPerWeek < 0 ? "to lose" : "to gain") \(abs(plan.paceKgPerWeek)) kg a week.",
                String(format: "Weight %.1f kg, goal %.1f kg, to go %.1f kg, about %d weeks.", weight, goal, abs(goal - weight), plan.weeksToGoal ?? 0),
                String(format: "Protein %.1f g per kg = %d g (%d%% of energy; WHO safe level 0.83 g per kg).", plan.proteinPerKg, Int(plan.macros.proteinG), plan.proteinPercent),
                "Fat \(Int(plan.macros.fatG)) g (\(plan.fatPercent)% of energy; \(within(plan.fatPercent, 20, 35)) the WHO range 20 to 35%).",
                "Carbohydrate \(Int(plan.macros.carbsG)) g (\(plan.carbsPercent)% of energy; \(within(plan.carbsPercent, 55, 75)) the WHO range 55 to 75%).",
                "Food logged on \(logged) of the last 14 days.",
            ]
            if let bmi { facts.append(String(format: "BMI %.1f (WHO adult range 18.5 to 24.9).", bmi)) }
            let given = facts.joined(separator: "\n")
            if let words = await coach.explainNutritionPlan(facts: given), FigureGuard.unknownFigures(in: words, facts: given).isEmpty {
                let language = UserDefaults.standard.string(forKey: AICoachEngine.responseLanguageKey) ?? "app"
                let separator = language == "id" ? "," : (language == "en" ? "." : AppLanguage.activeLocale.decimalSeparator ?? ".")
                let unit = language == "id" ? "kkal" : (language == "en" ? "kcal" : String(localized: "kcal"))
                explanation = FigureGuard.localised(words, decimalSeparator: separator).replacingOccurrences(of: "kcal", with: unit)
            }
        }

        return AnyaPlanSpec(targetKcal: plan.targetKcal, paceKgPerWeek: plan.paceKgPerWeek, proteinPerKg: plan.proteinPerKg, fatShare: plan.fatShare,
                            explanation: explanation, reasons: reasons, cautions: cautions)
    }

    /// The plan on show as the provider is told it, so a follow-up question is answered about these figures.
    static func told(_ spec: AnyaPlanSpec) -> String {
        let button = String(localized: "Apply this plan")
        var lines = ["A nutrition plan is on show; nothing is set until the person taps the button labelled \"\(button)\". Daily target \(Int(spec.targetKcal.rounded())) kcal."]
        if let pace = spec.paceKgPerWeek { lines.append("Pace \(pace) kg a week.") }
        if let protein = spec.proteinPerKg { lines.append(String(format: "Protein %.1f g per kg.", protein)) }
        if let fat = spec.fatShare { lines.append("Fat \(Int((fat * 100).rounded()))% of energy; carbohydrate is the rest.") }
        return (lines + spec.reasons + spec.cautions).joined(separator: "\n")
    }

    /// A stored day key as the person reads a date.
    private static func date(_ key: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: key) else { return key }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: day)
    }

    private static func within(_ value: Int, _ low: Int, _ high: Int) -> String { value < low ? "below" : (value > high ? "above" : "inside") }

    private static func number(_ value: Double, _ decimals: Int = 0) -> String {
        let f = NumberFormatter(); f.locale = AppLanguage.activeLocale; f.numberStyle = .decimal
        f.maximumFractionDigits = decimals; f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
#endif
