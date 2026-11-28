import Foundation

/// A daily nutrition plan worked out by rule from the person's own figures: pace, calories and macros. A language model asked for the same plan
/// twice gave two different answers, one of which contradicted its own arithmetic, so the figures are decided here and a model, when there is one,
/// only puts them into words. An estimate for a healthy adult, not medical advice. Pure.
public enum NutritionPlanner {
    public static let fatShare = 0.28
    public static let proteinHolding = 1.6
    public static let proteinChanging = 1.8
    /// With a kidney result outside the range on the person's own report, protein is kept modest.
    public static let proteinCautious = 1.0
    /// Within this of the goal weight the plan is to hold it.
    public static let atGoalKg = 1.0

    public struct Input: Equatable, Sendable {
        public var maintenanceKcal: Double
        public var weightKg: Double
        public var heightCm: Double
        public var goalKg: Double?
        public var kidneyResultOutOfRange: Bool

        public init(maintenanceKcal: Double, weightKg: Double, heightCm: Double, goalKg: Double?, kidneyResultOutOfRange: Bool = false) {
            self.maintenanceKcal = maintenanceKcal; self.weightKg = weightKg; self.heightCm = heightCm
            self.goalKg = goalKg; self.kidneyResultOutOfRange = kidneyResultOutOfRange
        }
    }

    public struct Plan: Equatable, Sendable {
        public var targetKcal: Double
        public var paceKgPerWeek: Double
        public var proteinPerKg: Double
        public var fatShare: Double
        public var macros: NutritionMath.Macros
        public var weeksToGoal: Int?
        /// The person asked to lose weight while already under the usual adult range, so the plan holds instead.
        public var heldBecauseUnderweight: Bool
        /// The pace the goal called for would have gone under the lowest daily figure, so a gentler one is used.
        public var easedForFloor: Bool

        /// Share of the day's energy each macro gives, in whole percent.
        public var proteinPercent: Int { percent(macros.proteinG * 4) }
        public var fatPercent: Int { percent(macros.fatG * 9) }
        public var carbsPercent: Int { percent(macros.carbsG * 4) }
        private func percent(_ kcal: Double) -> Int { targetKcal > 0 ? Int((kcal / targetKcal * 100).rounded()) : 0 }
    }

    public static func bodyMassIndex(weightKg: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, heightCm > 100 else { return nil }
        let metres = heightCm / 100
        return weightKg / (metres * metres)
    }

    public static func make(_ input: Input) -> Plan {
        var pace = 0.0
        var underweight = false, eased = false
        if let goal = input.goalKg, goal > 0, abs(goal - input.weightKg) >= atGoalKg {
            let change = goal - input.weightKg
            if change < 0 {
                if let bmi = bodyMassIndex(weightKg: input.weightKg, heightCm: input.heightCm), bmi < 18.5 {
                    underweight = true
                } else {
                    // Half a kilo a week with a way to go, a quarter near the goal, and never more than 0.7 percent of body weight.
                    pace = -((abs(change) >= 3 && 0.5 <= input.weightKg * 0.007) ? 0.5 : 0.25)
                }
            } else {
                pace = 0.25
            }
        }
        while pace < 0 && input.maintenanceKcal + pace * NutritionMath.kcalPerKg / 7 < NutritionMath.floorKcal {
            pace += 0.25
            eased = true
        }
        let target = NutritionMath.dailyTarget(maintenanceKcal: input.maintenanceKcal, weeklyChangeKg: pace)
        let protein = input.kidneyResultOutOfRange ? proteinCautious : (pace == 0 ? proteinHolding : proteinChanging)
        let weeks = pace == 0 ? nil : input.goalKg.map { Int((abs($0 - input.weightKg) / abs(pace)).rounded(.up)) }
        return Plan(targetKcal: target, paceKgPerWeek: pace, proteinPerKg: protein, fatShare: fatShare,
                    macros: NutritionMath.macroTargets(kcal: target, weightKg: input.weightKg, proteinPerKg: protein, fatShare: fatShare),
                    weeksToGoal: weeks, heldBecauseUnderweight: underweight, easedForFloor: eased)
    }
}

/// Checks that a model's explanation quotes only figures it was given.
public enum FigureGuard {
    /// The numbers in a text. "2.464" and "2,464" are read as thousands, "79,3" and "79.3" as a decimal.
    public static func figures(in text: String) -> [Double] {
        let pattern = try! NSRegularExpression(pattern: #"\d{1,3}(?:[.,]\d{3})+(?!\d)|\d+(?:[.,]\d+)?"#)
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            var s = ns.substring(with: m.range)
            if s.range(of: #"^\d{1,3}(?:[.,]\d{3})+$"#, options: .regularExpression) != nil, !s.hasPrefix("0") {
                s.removeAll { $0 == "." || $0 == "," }
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
            return Double(s)
        }
    }

    /// The text with its decimal points written as `decimalSeparator`, to match the figures shown beside it. Only a point followed by one or two
    /// digits is a decimal; three digits are a thousands group and stay as they are.
    public static func localised(_ text: String, decimalSeparator: String) -> String {
        guard decimalSeparator == "," else { return text }
        return text.replacingOccurrences(of: #"(?<=\d)\.(?=\d{1,2}(?!\d))"#, with: ",", options: .regularExpression)
    }

    /// Figures of `text` that the facts do not hold, allowing for rounding. Small counts ("two weeks", "7 days") are let through.
    public static func unknownFigures(in text: String, facts: String) -> [Double] {
        let known = figures(in: facts)
        return figures(in: text).filter { value in
            if value <= 14 && value == value.rounded() { return false }
            return !known.contains { abs($0 - value) <= max(0.51, $0 * 0.015) }
        }
    }
}
