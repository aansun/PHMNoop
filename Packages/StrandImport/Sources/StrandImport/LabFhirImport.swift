import Foundation

// MARK: - FHIR lab file import (source "lab-fhir")
//
// LabFhirImport.swift — reads the lab results out of a FHIR R4 JSON file a lab or a patient portal hands out: a `Bundle` of `Observation`
// resources, a single `Observation`, or a plain array of them. Each Observation with a numeric `valueQuantity` becomes one reading; a blood
// pressure panel (LOINC 85354-9, with the systolic 8480-6 and diastolic 8462-4 components) becomes the systolic/diastolic pair.
//
// The marker is the catalog marker when its LOINC code is one of the few the catalog knows, else when its name matches the catalog by
// `LabMarkerCsvImport.resolveMarker`, else a custom marker. The unit is kept VERBATIM, the range comes from `referenceRange` exactly as the
// lab printed it, and nothing is converted, judged or guessed: an Observation with a text, coded or missing value, or without a date, is
// skipped and counted. The result is the same `LabMarkerCsvResult` the CSV import returns, so both land through one path in the app.
//
// Pure and deterministic — no DB, no I/O. Size and row bounds as for the CSV import.

public enum LabFhirImport {

    /// Provenance/source id stored on every imported reading (`LabMarker.source`).
    public static let sourceId = "lab-fhir"

    /// True when the bytes look like FHIR JSON the app should read with this importer (a Bundle, an Observation or an array of them).
    public static func matches(data: Data) -> Bool {
        guard data.count <= LabMarkerCsvImport.maxBytes,
              let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let o = root as? [String: Any] {
            let type = o["resourceType"] as? String
            return type == "Bundle" || type == "Observation"
        }
        if let a = root as? [Any] { return a.contains { ($0 as? [String: Any])?["resourceType"] as? String == "Observation" } }
        return false
    }

    public static func parse(data: Data) -> LabMarkerCsvResult {
        guard data.count <= LabMarkerCsvImport.maxBytes else {
            return LabMarkerCsvResult(rows: [], skippedRows: 0, customMarkerKeys: [], earliestDay: nil, latestDay: nil, truncated: false, fileTooLarge: true)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return LabMarkerCsvResult(rows: [], skippedRows: 0, customMarkerKeys: [], earliestDay: nil, latestDay: nil, truncated: false, fileTooLarge: false)
        }
        var observations: [[String: Any]] = []
        func collect(_ any: Any) {
            guard let o = any as? [String: Any] else { return }
            switch o["resourceType"] as? String {
            case "Observation": observations.append(o)
            case "Bundle": for e in (o["entry"] as? [Any]) ?? [] { if let r = (e as? [String: Any])?["resource"] { collect(r) } }
            default: break
            }
        }
        if let a = root as? [Any] { a.forEach(collect) } else { collect(root) }

        var byCell: [String: LabMarkerCsvRow] = [:]
        var skipped = 0
        var truncated = false
        for (index, o) in observations.enumerated() {
            if index >= LabMarkerCsvImport.maxRows { skipped += observations.count - index; truncated = true; break }
            let made = rows(from: o)
            if made.isEmpty { skipped += 1; continue }
            for r in made { byCell[r.markerKey + "\u{1}" + r.day] = r }
        }
        let rows = byCell.values.sorted { $0.day == $1.day ? $0.markerKey < $1.markerKey : $0.day < $1.day }
        let days = rows.map(\.day)
        return LabMarkerCsvResult(rows: rows, skippedRows: skipped,
                                  customMarkerKeys: Set(rows.filter(\.isCustomMarker).map(\.markerKey)).sorted(),
                                  earliestDay: days.min(), latestDay: days.max(), truncated: truncated, fileTooLarge: false)
    }

    // MARK: One Observation

    /// The LOINC codes the catalog has a marker for. A code only counts when the key is in the catalog.
    static let loinc: [String: String] = [
        "2093-3": "total_cholesterol", "13457-7": "ldl", "18262-6": "ldl", "2089-1": "ldl", "2085-9": "hdl", "2571-8": "triglycerides",
        "1558-6": "fasting_glucose", "2345-7": "fasting_glucose", "4548-4": "hba1c", "2276-4": "ferritin", "2498-4": "iron",
        "718-7": "haemoglobin", "1989-3": "vitamin_d", "62292-8": "vitamin_d", "2132-9": "vitamin_b12", "2284-8": "folate",
        "3016-3": "tsh", "3024-7": "free_t4", "1988-5": "crp", "30522-7": "crp", "2160-0": "creatinine", "33914-3": "egfr",
        "1742-6": "alt", "1920-8": "ast", "2324-2": "ggt", "2951-2": "sodium", "2823-3": "potassium",
        "8867-4": "resting_pulse", "29463-7": "weight", "41982-0": "body_fat", "56115-9": "waist", "8302-2": "height",
    ]

    static func rows(from o: [String: Any]) -> [LabMarkerCsvRow] {
        if let status = (o["status"] as? String)?.lowercased(), status == "entered-in-error" || status == "cancelled" { return [] }
        guard let day = day(of: o) else { return [] }
        let range = rangeText(of: o["referenceRange"])
        let code = o["code"] as? [String: Any]

        // A blood pressure panel carries the pair as two components.
        if let comps = o["component"] as? [Any], !comps.isEmpty {
            var out: [LabMarkerCsvRow] = []
            for c in comps {
                guard let co = c as? [String: Any], let cc = co["code"] as? [String: Any] else { continue }
                let key: String?
                switch codes(of: cc).first(where: { $0 == "8480-6" || $0 == "8462-4" }) {
                case "8480-6": key = "bp_systolic"
                case "8462-4": key = "bp_diastolic"
                default: key = nil
                }
                guard let key, let q = co["valueQuantity"] as? [String: Any], let v = number(q["value"]),
                      let r = LabMarkerCsvImport.makeRow(name: key, value: v, unit: (q["unit"] as? String) ?? (q["code"] as? String), day: day,
                                                         referenceText: rangeText(of: co["referenceRange"]))
                else { continue }
                out.append(r)
            }
            if !out.isEmpty { return out }
        }

        guard let q = o["valueQuantity"] as? [String: Any], let v = number(q["value"]) else { return [] }
        let unit = (q["unit"] as? String) ?? (q["code"] as? String)
        let name = (code?["text"] as? String) ?? display(of: code)
        var key: String?
        if let code { key = codes(of: code).compactMap { loinc[$0] }.first(where: { MarkerCatalog.definition(for: $0) != nil }) }
        guard let label = key ?? name else { return [] }
        guard var row = LabMarkerCsvImport.makeRow(name: label, value: v, unit: unit, day: day, referenceText: range) else { return [] }
        if let name { row.markerName = name }
        return [row]
    }

    private static func codes(of codeable: [String: Any]) -> [String] {
        ((codeable["coding"] as? [Any]) ?? []).compactMap { c in
            guard let co = c as? [String: Any], let system = (co["system"] as? String)?.lowercased(), system.contains("loinc") else { return nil }
            return co["code"] as? String
        }
    }

    private static func display(of codeable: [String: Any]?) -> String? {
        for c in (codeable?["coding"] as? [Any]) ?? [] {
            if let d = (c as? [String: Any])?["display"] as? String, !d.trimmingCharacters(in: .whitespaces).isEmpty { return d }
        }
        return nil
    }

    private static func day(of o: [String: Any]) -> String? {
        let raw = (o["effectiveDateTime"] as? String) ?? (o["effectiveInstant"] as? String)
            ?? ((o["effectivePeriod"] as? [String: Any])?["start"] as? String) ?? (o["issued"] as? String)
        guard let raw, raw.count >= 10 else { return nil }
        return LabMarkerCsvImport.canonicalDay(String(raw.prefix(10)))
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double, d.isFinite { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    /// "low - high", "<high" or the lab's own text, from the first reference range.
    private static func rangeText(of any: Any?) -> String? {
        guard let first = (any as? [Any])?.first as? [String: Any] else { return nil }
        let low = number((first["low"] as? [String: Any])?["value"]), high = number((first["high"] as? [String: Any])?["value"])
        func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        if let low, let high { return "\(fmt(low)) - \(fmt(high))" }
        if let high { return "<\(fmt(high))" }
        if let low { return ">\(fmt(low))" }
        if let t = (first["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return nil
    }
}
