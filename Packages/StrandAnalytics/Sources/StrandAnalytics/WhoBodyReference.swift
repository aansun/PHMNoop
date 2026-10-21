import Foundation

// WhoBodyReference.swift — the World Health Organization reference ranges for body measurements, worked out for the person.
//
// PURE and unit-tested. Two published references, nothing else:
//  • Weight: the WHO adult BMI classification puts "normal weight" at a BMI of 18.5 up to (not including) 25, so the weight range
//    for a height is BMI 18.5 × height² up to BMI 24.99 × height² (WHO, Obesity: preventing and managing the global epidemic, 2000;
//    BMI classification, WHO Global Database on BMI).
//  • Waist: the WHO expert consultation on waist circumference (2008) names a waist of 94 cm or more for men and 80 cm or more for
//    women as increased risk of metabolic complications, so the reference is below those values.
// These are population references for adults, not a diagnosis, and the app says where they come from. They apply to adults only and
// to the units they are defined in (kg, cm); a reading in another unit is left without a reference rather than converted.

public enum WhoBodyReference {
    /// The weight, in kg, a WHO normal BMI (18.5 to under 25) allows at this height. nil without a believable adult height.
    public static func weightRangeKg(heightCm: Double) -> (low: Double, high: Double)? {
        guard heightCm.isFinite, (100...250).contains(heightCm) else { return nil }
        let m = heightCm / 100
        return (18.5 * m * m, 24.99 * m * m)
    }

    /// The waist, in cm, below which the WHO sees no increased risk: 94 for men, 80 for women. nil when the sex on the profile is neither.
    public static func waistCeilingCm(sex: String) -> Double? {
        switch sex.lowercased() {
        case "male": return 94
        case "female": return 80
        default: return nil
        }
    }
}

/// The WHO references a nutrition plan is measured against, each with where it comes from. Population references for healthy adults, not a diagnosis.
public enum WhoNutritionReference {
    /// WHO adult BMI classification (WHO 2000; the 18.5 and 25 cut-offs are unchanged since).
    public enum BmiClass: String, Sendable { case underweight, normal, overweight, obese }

    public static func bmiClass(_ bmi: Double) -> BmiClass {
        bmi < 18.5 ? .underweight : (bmi < 25 ? .normal : (bmi < 30 ? .overweight : .obese))
    }

    /// Safe level of protein intake for adults, g per kg of body weight a day (WHO/FAO/UNU 2007).
    public static let proteinSafeGPerKg = 0.83
    /// Total fat, share of energy (WHO/FAO 2008 fats and fatty acids consultation).
    public static let fatShareRange = 0.20...0.35
    /// Carbohydrate, share of energy (WHO Technical Report 916, 2003).
    public static let carbShareRange = 0.55...0.75

    public struct Shares: Equatable, Sendable {
        public var protein: Double
        public var carbs: Double
        public var fat: Double
    }

    /// Where the energy comes from in a plan (4 / 4 / 9 kcal per gram), as shares of the calories those macros add up to. nil when they add up to nothing.
    public static func shares(proteinG: Double, carbsG: Double, fatG: Double) -> Shares? {
        let total = proteinG * 4 + carbsG * 4 + fatG * 9
        guard total > 0 else { return nil }
        return Shares(protein: proteinG * 4 / total, carbs: carbsG * 4 / total, fat: fatG * 9 / total)
    }
}
