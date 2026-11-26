#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// The pieces the Nuna Lab Book is made of: the range a person copies from their own report, one marker with its readings, the gauge and the chart
// that show where a reading sits, and the reads and writes of the readings. Nothing here decides what is normal: a range is whatever the person typed,
// shown back, and a reading is "within" or "outside" only against that range.

// MARK: - The range from the person's own report

struct NunaLabRange: Equatable {
    let low: Double
    let high: Double

    enum Status { case below, within, above }

    /// "2.0 - 5.0", "0,5–1,2" or "<5.7" read as a range; anything else is not one.
    static func parse(_ text: String?) -> NunaLabRange? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        let nums = cleaned.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        if nums.count >= 2, nums[0] < nums[1] { return NunaLabRange(low: nums[0], high: nums[1]) }
        if nums.count == 1, cleaned.contains("<"), nums[0] > 0 { return NunaLabRange(low: 0, high: nums[0]) }
        return nil
    }

    /// "3.9–5.6", or "<3.4" for a range that starts at zero.
    func label(key: String) -> String {
        low <= 0 ? "<" + LabBookFormat.value(high, key: key) : LabBookFormat.value(low, key: key) + "–" + LabBookFormat.value(high, key: key)
    }

    func status(_ v: Double) -> Status { v < low ? .below : (v > high ? .above : .within) }

    static func tint(_ s: Status) -> Color { s == .within ? NunaPalette.charge : NunaPalette.caution }

    static func word(_ s: Status, who: Bool = false) -> LocalizedStringKey {
        if who { switch s { case .within: return "Within WHO range"; case .above: return "Above WHO range"; case .below: return "Below WHO range" } }
        switch s { case .within: return "Within your range"; case .above: return "Above your range"; case .below: return "Below your range" }
    }
}

// MARK: - One marker with its readings

struct NunaLabMarker: Identifiable {
    let key: String
    let name: String
    let category: LabMarkerCategory
    /// Oldest first.
    let readings: [LabMarkerRow]
    /// For blood pressure: the diastolic value of each systolic reading, by the time it was taken.
    let diastolic: [Int: LabMarkerRow]
    /// The WHO reference for this marker (weight from the height, waist by sex), used only when no report gave a range of its own.
    var whoRange: NunaLabRange? = nil

    var id: String { key }
    var isPressure: Bool { key == LabBookProjection.bpSystolicKey }
    var unit: String { readings.last?.unit ?? MarkerCatalog.definition(for: key)?.canonicalUnit ?? "" }
    var numeric: [LabMarkerRow] { readings.filter { $0.value != nil } }
    var latest: LabMarkerRow? { readings.last }
    /// The range from the person's own report. It always wins over the WHO reference.
    var ownRange: NunaLabRange? { NunaLabRange.parse(readings.last(where: { $0.referenceText?.isEmpty == false })?.referenceText) }
    var range: NunaLabRange? { ownRange ?? whoRange }
    var rangeIsWho: Bool { ownRange == nil && whoRange != nil }
    var diastolicRange: NunaLabRange? {
        NunaLabRange.parse(diastolic.values.sorted { $0.takenAt < $1.takenAt }.last(where: { $0.referenceText?.isEmpty == false })?.referenceText)
    }

    func text(_ row: LabMarkerRow) -> String {
        if let v = row.value {
            if isPressure, let d = diastolic[row.takenAt]?.value { return LabBookFormat.value(v, key: key) + "/" + LabBookFormat.value(d, key: LabBookProjection.bpDiastolicKey) }
            return LabBookFormat.value(v, key: key)
        }
        return row.valueText ?? "—"
    }

    func status(_ row: LabMarkerRow) -> NunaLabRange.Status? {
        guard let v = row.value, let r = range else { return nil }
        return r.status(v)
    }

    /// Blood pressure is worse on either side of the range only when a reading is outside both.
    var latestStatus: NunaLabRange.Status? {
        guard let row = latest else { return nil }
        guard isPressure, let sys = row.value, let dia = diastolic[row.takenAt]?.value else { return status(row) }
        let a = range?.status(sys), b = diastolicRange?.status(dia)
        if let a, a != .within { return a }
        if let b, b != .within { return b }
        return (a == nil && b == nil) ? nil : .within
    }

    /// The way the latest reading moved from the one before it, as a signed number, its percentage and the date it moved from.
    var change: (delta: Double, percent: Double?, since: Int)? {
        let nums = numeric
        guard nums.count >= 2, let last = nums.last?.value, let prev = nums[nums.count - 2].value else { return nil }
        return (last - prev, prev != 0 ? (last - prev) / abs(prev) * 100 : nil, nums[nums.count - 2].takenAt)
    }

    /// Green when the change heads towards the range, amber when it heads away, neutral without a range or a clear direction.
    func changeTone(_ delta: Double) -> Color {
        guard let r = range, let last = latest?.value, abs(delta) > 0.000_001 else { return NunaPalette.textSecondary }
        let before = last - delta
        let distNow = last < r.low ? r.low - last : (last > r.high ? last - r.high : 0)
        let distBefore = before < r.low ? r.low - before : (before > r.high ? before - r.high : 0)
        if distNow == distBefore { return NunaPalette.textSecondary }
        return distNow < distBefore ? NunaPalette.charge : NunaPalette.caution
    }
}

enum NunaLabGrouping {
    /// What a marker is called: the catalog name, "Blood pressure" for the pair, or the words of a custom marker's key without its prefix.
    static func markerName(_ key: String) -> String {
        if key == LabBookProjection.bpSystolicKey { return String(localized: "Blood pressure") }
        if let def = MarkerCatalog.definition(for: key) { return def.displayName }
        return LabBookView.humanise(key.hasPrefix("custom_") ? String(key.dropFirst(7)) : key)
    }

    static let categoryOrder: [LabMarkerCategory] = [.bloodPanel, .bloodPressure, .bodyMeasurement, .imaging, .appointmentNote, .other]

    /// What the WHO reference needs to know about the person.
    struct Reference { var heightCm: Double; var sex: String }

    /// The WHO reference range for a marker whose latest reading is in the unit it is defined in.
    static func whoRange(key: String, unit: String, reference: Reference?) -> NunaLabRange? {
        guard let reference else { return nil }
        switch (key, unit.lowercased()) {
        case ("weight", "kg"):
            return WhoBodyReference.weightRangeKg(heightCm: reference.heightCm).map { NunaLabRange(low: $0.low, high: $0.high) }
        case ("waist", "cm"):
            return WhoBodyReference.waistCeilingCm(sex: reference.sex).map { NunaLabRange(low: 0, high: $0) }
        default:
            return nil
        }
    }

    static func markers(_ rows: [LabMarkerRow], reference: Reference? = nil) -> [NunaLabMarker] {
        let diastolicRows = rows.filter { $0.markerKey == LabBookProjection.bpDiastolicKey }
        let diastolic = Dictionary(diastolicRows.map { ($0.takenAt, $0) }, uniquingKeysWith: { _, l in l })
        let grouped = Dictionary(grouping: rows.filter { $0.markerKey != LabBookProjection.bpDiastolicKey }, by: \.markerKey)
        return grouped.map { key, list in
            let sorted = list.sorted { $0.takenAt < $1.takenAt }
            let cat = LabMarkerCategory(rawValue: sorted.last?.category ?? "") ?? MarkerCatalog.definition(for: key)?.category ?? .other
            let name = markerName(key)
            return NunaLabMarker(key: key, name: name, category: cat, readings: sorted, diastolic: key == LabBookProjection.bpSystolicKey ? diastolic : [:],
                                 whoRange: whoRange(key: key, unit: sorted.last?.unit ?? "", reference: reference))
        }
        .sorted { ($0.latest?.takenAt ?? 0) > ($1.latest?.takenAt ?? 0) }
    }
}

// MARK: - Reads and writes

@MainActor
enum NunaLabStore {
    static func load(_ repo: Repository) async -> [LabMarkerRow] {
        guard let store = await repo.storeHandle() else { return [] }
        var all: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            all.append(contentsOf: (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? [])
        }
        return all.sorted { $0.takenAt < $1.takenAt }
    }

    static func save(_ drafts: [LabMarkerRow], repo: Repository) async {
        guard !drafts.isEmpty, let store = await repo.storeHandle() else { return }
        _ = try? await store.upsertLabMarkers(drafts)
        await repo.refresh()
        NunaDataChanges.shared.bump()
    }

    static func delete(ids: [String], repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        PHMBloodPressureImport.dismiss(ids: ids)
        for id in ids { _ = try? await store.deleteLabMarker(id: id) }
        await repo.refresh()
        NunaDataChanges.shared.bump()
    }

    /// Stored rows for parsed readings. Noon of each reading's own day, so bringing the same reading in again updates it in place instead of adding a copy.
    static func storedRows(_ rows: [LabMarkerCsvRow], source: String, deviceId: String) -> [LabMarkerRow] {
        rows.map { r in
            let epoch = LabBookFormat.noonEpoch(r.day)
            return LabMarkerRow(id: "\(r.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: deviceId, markerKey: r.markerKey,
                                category: r.category.rawValue, day: r.day, takenAt: epoch, value: r.value, valueText: nil, unit: r.unit,
                                source: source, note: r.note, referenceText: r.referenceText)
        }
    }

    /// The template file to share, so a filled-in copy reads in full.
    static func templateFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("labbook-template.csv")
        do { try LabMarkerCsvImport.template.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    /// Reads a file of lab results (the Lab Book template or any date, marker, value, unit CSV, a WHOOP biomarker export, or a FHIR JSON file) and adds its
    /// readings. Returns the line to show.
    static func importCsv(url: URL, repo: Repository, log: (String) -> Void) async -> (summary: String, failed: Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let isFhir = LabFhirImport.matches(data: data)
            let isWhoop = !isFhir && WhoopBiomarkerExportParser.matches(data: data)
            let result = isFhir ? LabFhirImport.parse(data: data) : (isWhoop ? WhoopBiomarkerExportParser.parse(data: data) : LabMarkerCsvImport.parse(data: data))
            let sourceId = isFhir ? LabFhirImport.sourceId : (isWhoop ? WhoopBiomarkerExportParser.sourceId : LabMarkerCsvImport.sourceId)
            guard !result.fileTooLarge else { return (String(localized: "That file is too large for a markers CSV import."), true) }
            guard result.importedReadings > 0 else {
                log("Lab Book file: no usable rows (\(result.skippedRows) skipped)")
                return (isFhir ? String(localized: "No usable results found in that FHIR file.") : String(localized: "No usable rows found. Check the file has date, marker and value columns."), true)
            }
            guard let store = await repo.storeHandle() else { return (String(localized: "Couldn't open the local store."), true) }
            try await store.upsertLabMarkers(storedRows(result.rows, source: sourceId, deviceId: repo.deviceId))
            await repo.refresh()
            NunaDataChanges.shared.bump()
            var msg = String(localized: "Imported \(result.importedReadings) readings (\(result.distinctMarkers) markers)")
            if let a = result.earliestDay, let b = result.latestDay, a != b { msg += " · \(a)-\(b)" }
            if result.skippedRows > 0 {
                msg += " · " + (result.skippedRows == 1 ? String(localized: "1 row skipped") : String(localized: "\(result.skippedRows) rows skipped"))
            }
            if result.notMeasured > 0 {
                msg += " · " + (result.notMeasured == 1 ? String(localized: "1 not measured") : String(localized: "\(result.notMeasured) not measured"))
            }
            log("Lab Book file: \(result.importedReadings) readings, \(result.distinctMarkers) markers, \(result.skippedRows) rejected")
            return (msg, false)
        } catch {
            log("Lab Book import failed: \(error.localizedDescription)")
            return (String(localized: "Import failed: \(error.localizedDescription)"), true)
        }
    }
}

// MARK: - The chart

/// The readings of a window over time, on bands stacked like the range from the report: orange above it, green inside it, orange below it, each with a
/// bar down its left edge and its edge values in its colour, and fading out to the right. A reading is a ring in the colour of its band with its number
/// above; with several, a thin line joins them. Blood pressure draws the diastolic value too, joined to the systolic one by a bar.
///
/// A day is one column: every reading of it keeps its ring, and the figures written are its highest (above) and, where they differ, its lowest or the
/// lowest diastolic (below). Columns stand at their dates but never closer than a label needs, and a figure or date that would still run into another
/// is left out, the latest being placed first.
struct NunaLabChart: View {
    struct Point: Identifiable { let id: String; let date: Date; let value: Double; let second: Double?; let status: NunaLabRange.Status? }

    let points: [Point]
    let range: NunaLabRange?
    let from: Date
    let to: Date
    let format: (Double) -> String

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d"); return f
    }()
    private static let yearFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("yyyy"); return f
    }()

    /// The readings of one calendar day, oldest first.
    private var columns: [[Point]] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: points) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted().map { (byDay[$0] ?? []).sorted { $0.date < $1.date } }
    }

    /// Places columns as near their wanted positions as it can with at least `gap` between neighbours, all inside `lo...hi`. When they cannot all have
    /// `gap`, they share the width evenly. `wanted` is in ascending order.
    static func spread(_ wanted: [CGFloat], lo: CGFloat, hi: CGFloat, gap: CGFloat) -> [CGFloat] {
        guard wanted.count > 1 else { return wanted.map { min(max($0, lo), hi) } }
        let room = min(gap, (hi - lo) / CGFloat(wanted.count - 1))
        var x = wanted.map { min(max($0, lo), hi) }
        for i in 1..<x.count { x[i] = max(x[i], x[i - 1] + room) }
        x[x.count - 1] = min(x[x.count - 1], hi)
        for i in stride(from: x.count - 2, through: 0, by: -1) { x[i] = min(x[i], x[i + 1] - room) }
        return x
    }

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 46, top: CGFloat = 4, bottom: CGFloat = 48, gap: CGFloat = 2
            let w = size.width - left, h = size.height - top - bottom
            var lo = points.flatMap { [$0.value, $0.second ?? $0.value] }.min() ?? 0
            var hi = points.flatMap { [$0.value, $0.second ?? $0.value] }.max() ?? 1
            if let range { lo = min(lo, range.low); hi = max(hi, range.high) }
            let pad = max((hi - lo) * 0.3, abs(hi) * 0.04, 0.000_1)
            let nonNegative = lo >= 0 && (range?.low ?? 0) >= 0
            lo -= pad; hi += pad
            if nonNegative { lo = max(lo, 0) }   // a figure that cannot go below zero does not get a stretch of axis below it
            let t0 = from.timeIntervalSince1970, t1 = max(to.timeIntervalSince1970, t0 + 1)
            let y: (Double) -> CGFloat = { top + h - CGFloat(($0 - lo) / (hi - lo)) * h }

            // The bands, top to bottom, as (upper edge, lower edge, colour).
            let bands: [(Double, Double, Color)] = range.map { r in
                [(hi, r.high, NunaPalette.caution), (r.high, r.low, NunaPalette.charge), (r.low, lo, NunaPalette.caution)]
            } ?? [(hi, lo, NunaPalette.rangeSteel)]
            for (i, band) in bands.enumerated() {
                let y0 = y(band.0) + (i == 0 ? 0 : gap / 2), y1 = y(band.1) - (i == bands.count - 1 ? 0 : gap / 2)
                guard y1 - y0 > 1 else { continue }
                let rect = CGRect(x: left, y: y0, width: w, height: y1 - y0)
                ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [band.2.opacity(0.14), band.2.opacity(0)]),
                                                           startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + w * 0.92, y: 0)))
                ctx.fill(Path(CGRect(x: left, y: y0, width: 2, height: y1 - y0)), with: .color(band.2))
                // The value at the lower edge of the band (and at the top of the first one), in the band's colour.
                if i == 0 {
                    ctx.draw(Text(verbatim: format(band.0)).font(.nuna(size: 10, weight: .bold, design: NunaType.design)).foregroundColor(band.2), at: CGPoint(x: left - 12, y: y0 + 1), anchor: .topTrailing)
                }
                ctx.draw(Text(verbatim: format(band.1)).font(.nuna(size: 10, weight: .bold, design: NunaType.design)).foregroundColor(band.2), at: CGPoint(x: left - 12, y: y1 - 1), anchor: .bottomTrailing)
            }

            let days = columns
            let wanted: [CGFloat] = days.map { d in
                left + 24 + CGFloat((d[d.count - 1].date.timeIntervalSince1970 - t0) / (t1 - t0)) * (w - 48)
            }
            let xs = days.count == 1 ? [left + w * 0.5] : Self.spread(wanted, lo: left + 24, hi: left + w - 24, gap: 50)
            // Rings shrink when the columns crowd, so neighbours stay apart.
            let closest = zip(xs.dropFirst(), xs).map(-).min() ?? w
            let ring: CGFloat = closest >= 12 ? 5 : max(2, closest / 2.4)
            let weight: CGFloat = ring >= 5 ? 2 : 1.5

            if days.count > 1 {
                var line = Path()
                for (i, d) in days.enumerated() { let pt = CGPoint(x: xs[i], y: y(d[d.count - 1].value)); i == 0 ? line.move(to: pt) : line.addLine(to: pt) }
                ctx.stroke(line, with: .color(NunaPalette.textSecondary.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            func tint(_ p: Point) -> Color { p.status.map(NunaLabRange.tint) ?? NunaPalette.textPrimary }
            for (i, d) in days.enumerated() {
                let px = xs[i]
                let all = d.flatMap { [$0.value, $0.second ?? $0.value] }
                if let high = all.max(), let low = all.min(), d.contains(where: { $0.second != nil }) {
                    let bar = CGRect(x: px - ring, y: y(high) - 2, width: ring * 2, height: y(low) - y(high) + 4)
                    ctx.fill(Path(roundedRect: bar, cornerRadius: ring), with: .color(NunaPalette.ink.opacity(0.13)))
                }
                for p in d {
                    for v in [p.second, p.value].compactMap({ $0 }) {
                        ctx.stroke(Path(ellipseIn: CGRect(x: px - ring, y: y(v) - ring, width: ring * 2, height: ring * 2)), with: .color(tint(p)), lineWidth: weight)
                    }
                }
            }

            // Words are placed after every ring, latest first, and one that would run into another already placed is left out.
            var taken: [CGRect] = []
            func place(_ text: Text, at point: CGPoint, anchor: UnitPoint) {
                let r = ctx.resolve(text)
                let s = r.measure(in: size)
                let box = CGRect(x: point.x - s.width * anchor.x, y: point.y - s.height * anchor.y, width: s.width, height: s.height)
                guard !taken.contains(where: { $0.intersects(box.insetBy(dx: -2, dy: 0)) }) else { return }
                taken.append(box)
                ctx.draw(r, at: point, anchor: anchor)
            }
            let heads = days.map { $0.map(\.value).max() ?? 0 }
            // The latest day goes first, then the highest and the lowest; the rest follow, newest first, unless there are more than ten days.
            let extremes = [heads.indices.max { heads[$0] < heads[$1] }, heads.indices.min { heads[$0] < heads[$1] }].compactMap { $0 }
            let rest = days.count <= 10 ? Array(days.indices.reversed()) : []
            var seen = Set<Int>()
            let order = (Array(days.indices.suffix(1)) + extremes + rest).filter { seen.insert($0).inserted }
            for i in order {
                let d = days[i], lx = min(max(xs[i], left + 18), left + w - 18)
                guard let top1 = d.max(by: { $0.value < $1.value }) else { continue }
                let up = y(top1.value) - 20 >= top - 6
                place(Text(verbatim: format(top1.value)).font(.nuna(size: 11, weight: .bold, design: NunaType.design)).foregroundColor(tint(top1)),
                      at: CGPoint(x: lx, y: y(top1.value) + (up ? -9 : 9)), anchor: up ? .bottom : .top)
                // Below: the lowest diastolic of the day; without one, the lowest value when the day holds more than one figure.
                let lows = d.compactMap(\.second)
                if let s = lows.min() {
                    place(Text(verbatim: format(s)).font(.nuna(size: 11, weight: .bold, design: NunaType.design)).foregroundColor(NunaPalette.textSecondary),
                          at: CGPoint(x: lx, y: y(s) + 10), anchor: .top)
                } else if let low = d.min(by: { $0.value < $1.value }), low.value < top1.value {
                    place(Text(verbatim: format(low.value)).font(.nuna(size: 11, weight: .bold, design: NunaType.design)).foregroundColor(tint(low)),
                          at: CGPoint(x: lx, y: y(low.value) + 9), anchor: .top)
                }
            }
            for (i, d) in days.enumerated().reversed() {
                let date = d[d.count - 1].date
                let lx = min(max(xs[i], left + 24), left + w - 24)
                let day = ctx.resolve(Text(verbatim: Self.dayFormat.string(from: date)).font(.nuna(size: 12, weight: .medium)).foregroundColor(NunaPalette.textSecondary))
                let year = ctx.resolve(Text(verbatim: Self.yearFormat.string(from: date)).font(.nuna(size: 12, weight: .medium)).foregroundColor(NunaPalette.textSecondary))
                let width = max(day.measure(in: size).width, year.measure(in: size).width)
                let box = CGRect(x: lx - width / 2, y: top + h + 14, width: width, height: 32)
                guard !taken.contains(where: { $0.intersects(box.insetBy(dx: -7, dy: 0)) }) else { continue }
                taken.append(box)
                ctx.draw(day, at: CGPoint(x: lx, y: top + h + 22), anchor: .center)
                ctx.draw(year, at: CGPoint(x: lx, y: top + h + 38), anchor: .center)
            }
        }
        .textCase(nil)
        .frame(height: 282)
        .accessibilityHidden(true)
    }
}
#endif
