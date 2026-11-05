// === PHM OVERLAY (PHMNOOP) ===
// Apple Health integration for the BODY MEASURES of the profile: waist circumference (lingkar pinggang),
// weight and height, read-only.
//
// Upstream NOOP reads steps (.stepCount) and weight (.bodyMass) from Apple Health into the daily series,
// but the PROFILE values (`profile.waistCm`, `weightKg`, `heightCm`) were MANUAL, typed on the Persona page.
// They feed the VO₂max / Fitness Age estimate, calorie estimates and BMI. This overlay pulls the most-recent
// `.waistCircumference`, `.bodyMass` and `.height` samples into the profile, so nothing has to be typed.
//
// Read-only by design (mirrors NOOP's body-composition policy — never written back). Authorization is
// granted through HealthKitBridge's single consolidated read request (`.waistCircumference` was added
// to `quantityReadIds`); this file never prompts on its own — a denied/undetermined status just yields
// no samples. Living entirely in a new file (+ two one-line, marked core edits) keeps upstream sync smooth.

import Foundation
import HealthKit

enum PHMWaistHealthImport {
    /// The single most-recent sample of a quantity type in `unit`, or nil when Health is unavailable, the type is
    /// unknown, the read scope was not granted, or there are no samples.
    static func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(), let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let store = HKHealthStore()
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: s.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    static func latestWaistCm() async -> Double? { await latest(.waistCircumference, unit: .meterUnit(with: .centi)) }
    static func latestWeightKg() async -> Double? { await latest(.bodyMass, unit: .gramUnit(with: .kilo)) }
    static func latestHeightCm() async -> Double? { await latest(.height, unit: .meterUnit(with: .centi)) }
}

@MainActor
extension ProfileStore {
    /// PHMNOOP: fill `waistCm`, `weightKg` and `heightCm` from Apple Health's latest readings when they exist. Health is
    /// treated as authoritative; the stored value stays only while Health has no sample. Each is clamped to the range the
    /// steppers on the Persona page used to enforce, and only assigned on a real change so the `didSet` UserDefaults write
    /// (and any dependent re-score) does not fire needlessly.
    func phmImportBodyFromHealth() async {
        if let cm = await PHMWaistHealthImport.latestWaistCm(), cm > 0 {
            let v = min(160, cm)
            if abs(v - waistCm) >= 0.5 { waistCm = v }
        }
        if let kg = await PHMWaistHealthImport.latestWeightKg(), kg > 0 {
            let v = min(max(kg, 30), 250)
            if abs(v - weightKg) >= 0.1 { weightKg = v }
        }
        if let cm = await PHMWaistHealthImport.latestHeightCm(), cm > 0 {
            let v = min(max(cm, 120), 230)
            if abs(v - heightCm) >= 0.5 { heightCm = v }
        }
    }
}
