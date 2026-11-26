// === PHM OVERLAY (PHMNOOP) ===
// Blood pressure from Apple Health, READ-ONLY: what a cuff (or its app) saves to Health is copied into the Lab Book, where the typed readings already
// live, so the Blood pressure page, the Lab Book, the dashboard and the exports all show one list. Nothing is ever written back to Health, and nothing
// is estimated from the strap.
//
// Authorization is part of HealthKitBridge's single consolidated read request (systolic and diastolic were added to `quantityReadIds`); this file never
// prompts. A denied or undetermined status just yields no samples.

import Foundation
import HealthKit
import WhoopStore
import StrandImport
import StrandAnalytics

enum PHMBloodPressureImport {
    /// The Lab Book source of the copied readings, and the prefix of their ids (typed and file-imported rows never carry it).
    static let source = "apple-health"
    static let idPrefix = "bp-hk-"
    private static let dismissedKey = "applehealth.bloodPressure.dismissed"
    /// A reading typed by hand within this many seconds of a Health sample with the same two figures is the same reading.
    private static let sameReadingSeconds = 300

    struct Reading: Equatable {
        let uuid: String
        let takenAt: Int
        let systolic: Double
        let diastolic: Double
    }

    /// The blood-pressure pairs Health holds since `since`, oldest first; nil when they could not be read at all.
    static func fetch(since: Date) async -> [Reading]? {
        guard HKHealthStore.isHealthDataAvailable(),
              let pair = HKCorrelationType.correlationType(forIdentifier: .bloodPressure),
              let systolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return nil }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        return await withCheckedContinuation { (cont: CheckedContinuation<[Reading]?, Never>) in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let query = HKSampleQuery(sampleType: pair, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                guard error == nil else { cont.resume(returning: nil); return }
                let unit = HKUnit.millimeterOfMercury()
                let readings: [Reading] = (samples ?? []).compactMap { sample in
                    guard let c = sample as? HKCorrelation,
                          let s = c.objects(for: systolic).first as? HKQuantitySample,
                          let d = c.objects(for: diastolic).first as? HKQuantitySample else { return nil }
                    return Reading(uuid: c.uuid.uuidString, takenAt: Int(c.startDate.timeIntervalSince1970),
                                   systolic: s.quantity.doubleValue(for: unit).rounded(), diastolic: d.quantity.doubleValue(for: unit).rounded())
                }
                cont.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    /// A copied reading the person deleted in PHMN stays deleted, although Health still holds it.
    static func dismiss(ids: [String]) {
        let uuids = ids.filter { $0.hasPrefix(idPrefix) }.map { String($0.dropFirst(idPrefix.count + 4)) }
        guard !uuids.isEmpty else { return }
        var set = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        set.formUnion(uuids)
        UserDefaults.standard.set(Array(set), forKey: dismissedKey)
    }

    /// Brings the Lab Book in line with Health: new readings are added, changed ones updated, and copies whose sample is gone from Health removed.
    /// Returns true when the Lab Book changed.
    @MainActor
    @discardableResult
    static func sync(repo: Repository, days: Int = 730) async -> Bool {
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let fetched = await fetch(since: since), let store = await repo.storeHandle() else { return false }
        let existing = (try? await store.labMarkers(deviceId: repo.deviceId, category: LabMarkerCategory.bloodPressure.rawValue)) ?? []
        let sys = LabBookProjection.bpSystolicKey, dia = LabBookProjection.bpDiastolicKey
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        // Two apps may save the same moment twice; the Lab Book keeps one reading per moment and source, so the first stands.
        var moments = Set<Int>()
        let readings = fetched.filter { moments.insert($0.takenAt).inserted }

        let typed = existing.filter { !$0.id.hasPrefix(idPrefix) }
        func alreadyTyped(_ r: Reading) -> Bool {
            typed.contains { row in
                row.markerKey == sys && abs(row.takenAt - r.takenAt) <= sameReadingSeconds && row.value == r.systolic
                    && typed.contains { $0.markerKey == dia && $0.takenAt == row.takenAt && $0.value == r.diastolic }
            }
        }
        let copied = Dictionary(existing.filter { $0.id.hasPrefix(idPrefix) }.map { ("\($0.markerKey)|\($0.takenAt)", $0) }, uniquingKeysWith: { l, _ in l })

        var upserts: [LabMarkerRow] = []
        for r in readings where !dismissed.contains(r.uuid) && !alreadyTyped(r) {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(r.takenAt)))
            for (key, tag, value) in [(sys, "sys-", r.systolic), (dia, "dia-", r.diastolic)] {
                if copied["\(key)|\(r.takenAt)"]?.value == value { continue }
                upserts.append(LabMarkerRow(id: idPrefix + tag + r.uuid, deviceId: repo.deviceId, markerKey: key,
                                            category: LabMarkerCategory.bloodPressure.rawValue, day: day, takenAt: r.takenAt, value: value,
                                            valueText: nil, unit: "mmHg", source: source, note: nil, referenceText: nil))
            }
        }
        // Health never says whether reading was allowed: an empty answer may only mean "not allowed", so nothing is removed on one.
        let gone: [String] = readings.isEmpty ? [] : copied.values
            .filter { $0.takenAt >= Int(since.timeIntervalSince1970) && !moments.contains($0.takenAt) }
            .map(\.id)

        guard !upserts.isEmpty || !gone.isEmpty else { return false }
        if !upserts.isEmpty { _ = try? await store.upsertLabMarkers(upserts) }
        for id in gone { _ = try? await store.deleteLabMarker(id: id) }
        await repo.refresh()
        NunaDataChanges.shared.bump()
        return true
    }
}
