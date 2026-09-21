// === PHM OVERLAY (PHMNOOP) ===
// Apple Health integration for WAIST CIRCUMFERENCE (lingkar pinggang), read-only.
//
// Upstream NOOP already reads steps (.stepCount) and weight (.bodyMass) from Apple Health; waist was
// only a MANUAL profile value (`profile.waistCm`, entered in Settings) that sharpens the VO₂max /
// Fitness Age estimate. This overlay closes that gap: it pulls the most-recent `.waistCircumference`
// sample and fills `profile.waistCm`, so the estimate can use it without hand entry.
//
// Read-only by design (mirrors NOOP's body-composition policy — never written back). Authorization is
// granted through HealthKitBridge's single consolidated read request (`.waistCircumference` was added
// to `quantityReadIds`); this file never prompts on its own — a denied/undetermined status just yields
// no samples. Living entirely in a new file (+ two one-line, marked core edits) keeps upstream sync smooth.

import Foundation
import HealthKit

enum PHMWaistHealthImport {
    /// The single most-recent `.waistCircumference` reading in centimetres, or nil when Health is
    /// unavailable, the type is unknown, the read scope was not granted, or there are no samples.
    static func latestWaistCm() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .waistCircumference) else { return nil }
        let store = HKHealthStore()
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: s.quantity.doubleValue(for: .meterUnit(with: .centi)))
            }
            store.execute(q)
        }
    }
}

@MainActor
extension ProfileStore {
    /// PHMNOOP: fill `waistCm` from Apple Health's latest reading when one exists. Health is treated as
    /// authoritative; a manual entry is preserved only while Health has no sample. Clamped to the same
    /// range the Settings stepper enforces (≤ 160 cm), and only assigned on a real change so the
    /// `didSet` UserDefaults write (and any dependent re-score) does not fire needlessly.
    func phmImportWaistFromHealth() async {
        guard let cm = await PHMWaistHealthImport.latestWaistCm(), cm > 0 else { return }
        let clamped = min(160, cm)
        if abs(clamped - waistCm) >= 0.5 { waistCm = clamped }
    }
}
