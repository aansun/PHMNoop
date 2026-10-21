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
