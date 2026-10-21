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

    func status(_ v: Double) -> Status { v < low ? .below : (v > high ? .above : .within) }

    static func tint(_ s: Status) -> Color { s == .within ? NunaPalette.charge : NunaPalette.warning }

    static func word(_ s: Status) -> LocalizedStringKey {
        switch s { case .within: "Within your range"; case .above: "Above your range"; case .below: "Below your range" }
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

    var id: String { key }
    var isPressure: Bool { key == LabBookProjection.bpSystolicKey }
    var unit: String { readings.last?.unit ?? MarkerCatalog.definition(for: key)?.canonicalUnit ?? "" }
    var numeric: [LabMarkerRow] { readings.filter { $0.value != nil } }
    var latest: LabMarkerRow? { readings.last }
    var range: NunaLabRange? { NunaLabRange.parse(readings.last(where: { $0.referenceText?.isEmpty == false })?.referenceText) }
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
        return distNow < distBefore ? NunaPalette.charge : NunaPalette.warning
    }
}

enum NunaLabGrouping {
    static let categoryOrder: [LabMarkerCategory] = [.bloodPanel, .bloodPressure, .bodyMeasurement, .imaging, .appointmentNote, .other]

    static func markers(_ rows: [LabMarkerRow]) -> [NunaLabMarker] {
        let diastolicRows = rows.filter { $0.markerKey == LabBookProjection.bpDiastolicKey }
        let diastolic = Dictionary(diastolicRows.map { ($0.takenAt, $0) }, uniquingKeysWith: { _, l in l })
        let grouped = Dictionary(grouping: rows.filter { $0.markerKey != LabBookProjection.bpDiastolicKey }, by: \.markerKey)
        return grouped.map { key, list in
            let sorted = list.sorted { $0.takenAt < $1.takenAt }
            let cat = LabMarkerCategory(rawValue: sorted.last?.category ?? "") ?? MarkerCatalog.definition(for: key)?.category ?? .other
            let name = key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure")
                : (MarkerCatalog.definition(for: key)?.displayName ?? LabBookView.humanise(key))
            return NunaLabMarker(key: key, name: name, category: cat, readings: sorted, diastolic: key == LabBookProjection.bpSystolicKey ? diastolic : [:])
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
    }

    static func delete(ids: [String], repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        for id in ids { _ = try? await store.deleteLabMarker(id: id) }
        await repo.refresh()
    }

    /// Reads a markers CSV (a WHOOP biomarker export or the generic date, marker, value, unit file) and adds its readings. Returns the line to show.
    static func importCsv(url: URL, repo: Repository, log: (String) -> Void) async -> (summary: String, failed: Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let isWhoop = WhoopBiomarkerExportParser.matches(data: data)
            let result = isWhoop ? WhoopBiomarkerExportParser.parse(data: data) : LabMarkerCsvImport.parse(data: data)
            let sourceId = isWhoop ? WhoopBiomarkerExportParser.sourceId : LabMarkerCsvImport.sourceId
            guard !result.fileTooLarge else { return (String(localized: "That file is too large for a markers CSV import."), true) }
            guard result.importedReadings > 0 else {
                log("Lab Book CSV: no usable rows (\(result.skippedRows) skipped)")
                return (String(localized: "No usable rows found. Check the file has date, marker and value columns."), true)
            }
            guard let store = await repo.storeHandle() else { return (String(localized: "Couldn't open the local store."), true) }
            let rows = result.rows.map { r -> LabMarkerRow in
                // Noon of the row's own day, so importing the same file again updates in place instead of adding a copy.
                let epoch = LabBookFormat.noonEpoch(r.day)
                return LabMarkerRow(id: "\(r.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: repo.deviceId, markerKey: r.markerKey,
                                    category: r.category.rawValue, day: r.day, takenAt: epoch, value: r.value, valueText: nil, unit: r.unit,
                                    source: sourceId, note: r.note, referenceText: nil)
            }
            try await store.upsertLabMarkers(rows)
            await repo.refresh()
            var msg = String(localized: "Imported \(result.importedReadings) readings (\(result.distinctMarkers) markers)")
            if let a = result.earliestDay, let b = result.latestDay, a != b { msg += " · \(a)-\(b)" }
            if result.skippedRows > 0 {
                msg += " · " + (result.skippedRows == 1 ? String(localized: "1 row skipped") : String(localized: "\(result.skippedRows) rows skipped"))
            }
            if result.notMeasured > 0 {
                msg += " · " + (result.notMeasured == 1 ? String(localized: "1 not measured") : String(localized: "\(result.notMeasured) not measured"))
            }
            log("Lab Book CSV: \(result.importedReadings) readings, \(result.distinctMarkers) markers, \(result.skippedRows) rejected")
            return (msg, false)
        } catch {
            log("Lab Book CSV failed: \(error.localizedDescription)")
            return (String(localized: "Import failed: \(error.localizedDescription)"), true)
        }
    }
}

// MARK: - The gauge

/// A half circle laid out like the range from the report: amber below it, green inside it, amber above it, with a dot where the reading is.
struct NunaRangeGauge: View {
    let value: Double
    let range: NunaLabRange

    private var domain: (lo: Double, hi: Double) {
        let span = max(range.high - range.low, 0.000_1)
        var lo = max(0, range.low - span * 0.6), hi = range.high + span * 0.6
        lo = min(lo, value - span * 0.08)
        hi = max(hi, value + span * 0.08)
        return (max(0, lo), hi)
    }

    var body: some View {
        let d = domain
        let span = max(d.hi - d.lo, 0.000_1)
        let f: (Double) -> Double = { max(0, min(1, ($0 - d.lo) / span)) }
        return Canvas { ctx, size in
            let lw: CGFloat = 14
            let r = min(size.width / 2 - lw / 2, size.height - lw)
            let c = CGPoint(x: size.width / 2, y: size.height - lw / 2)
            func arc(_ a: Double, _ b: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(180 + 180 * a), endAngle: .degrees(180 + 180 * b), clockwise: false)
                return p
            }
            let gap = 0.008
            let lowEnd = f(range.low), highStart = f(range.high)
            if lowEnd > gap { ctx.stroke(arc(0, lowEnd - gap), with: .color(NunaPalette.warning.opacity(0.5)), style: StrokeStyle(lineWidth: lw, lineCap: .butt)) }
            ctx.stroke(arc(lowEnd + (lowEnd > gap ? gap : 0), highStart - (highStart < 1 - gap ? gap : 0)), with: .color(NunaPalette.charge.opacity(0.85)), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            if highStart < 1 - gap { ctx.stroke(arc(highStart + gap, 1), with: .color(NunaPalette.warning.opacity(0.5)), style: StrokeStyle(lineWidth: lw, lineCap: .butt)) }
            let a = Angle.degrees(180 + 180 * f(value)).radians
            let inner = CGPoint(x: c.x + (r - 22) * CGFloat(cos(a)), y: c.y + (r - 22) * CGFloat(sin(a)))
            let outer = CGPoint(x: c.x + (r + 4) * CGFloat(cos(a)), y: c.y + (r + 4) * CGFloat(sin(a)))
            var needle = Path(); needle.move(to: inner); needle.addLine(to: outer)
            ctx.stroke(needle, with: .color(NunaPalette.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The chart

/// The readings of a window as dots over time, joined by a thin line, on a green band where the range from the report sits. A dot is green inside the
/// range and amber outside it. Blood pressure draws the diastolic value too, joined to the systolic one by a bar.
struct NunaLabChart: View {
    struct Point: Identifiable { let id: String; let date: Date; let value: Double; let second: Double?; let status: NunaLabRange.Status? }

    let points: [Point]
    let range: NunaLabRange?
    let from: Date
    let to: Date
    let format: (Double) -> String

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 8, right: CGFloat = 8, top: CGFloat = 26, bottom: CGFloat = 50
            let w = size.width - left - right, h = size.height - top - bottom
            var lo = points.flatMap { [$0.value, $0.second ?? $0.value] }.min() ?? 0
            var hi = points.flatMap { [$0.value, $0.second ?? $0.value] }.max() ?? 1
            if let range { lo = min(lo, range.low); hi = max(hi, range.high) }
            let pad = max((hi - lo) * 0.14, abs(hi) * 0.02, 0.000_1)
            lo -= pad; hi += pad
            let t0 = from.timeIntervalSince1970, t1 = max(to.timeIntervalSince1970, t0 + 1)
            let x: (Date) -> CGFloat = { left + CGFloat(($0.timeIntervalSince1970 - t0) / (t1 - t0)) * w }
            let y: (Double) -> CGFloat = { top + h - CGFloat(($0 - lo) / (hi - lo)) * h }

            // Faint lines at the top, the middle and the bottom, as in the figure it follows.
            for k in 0...2 {
                var p = Path(); let yy = top + h * CGFloat(k) / 2
                p.move(to: CGPoint(x: left, y: yy)); p.addLine(to: CGPoint(x: left + w, y: yy))
                ctx.stroke(p, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
            }
            if let range {
                let band = CGRect(x: left, y: y(range.high), width: w, height: max(2, y(range.low) - y(range.high)))
                ctx.fill(Path(roundedRect: band, cornerRadius: 6), with: .color(NunaPalette.charge.opacity(0.14)))
                for edge in [range.low, range.high] {
                    var p = Path(); p.move(to: CGPoint(x: left, y: y(edge))); p.addLine(to: CGPoint(x: left + w, y: y(edge)))
                    ctx.stroke(p, with: .color(NunaPalette.charge.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            // The top and bottom values, named like the lines of the figure.
            ctx.draw(Text(verbatim: format(hi - pad)).font(.nuna(size: 11, weight: .bold)).foregroundColor(NunaPalette.warning), at: CGPoint(x: left + 2, y: top - 12), anchor: .leading)
            ctx.draw(Text(verbatim: format(lo + pad)).font(.nuna(size: 11, weight: .bold)).foregroundColor(NunaPalette.charge), at: CGPoint(x: left + 2, y: top + h + 12), anchor: .leading)

            let sorted = points.sorted { $0.date < $1.date }
            if sorted.count > 1 {
                var line = Path()
                for (i, p) in sorted.enumerated() { let pt = CGPoint(x: x(p.date), y: y(p.value)); i == 0 ? line.move(to: pt) : line.addLine(to: pt) }
                ctx.stroke(line, with: .color(NunaPalette.textSecondary.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            var lastLabel: CGFloat = -1000
            for p in sorted {
                let px = x(p.date)
                let tint = p.status.map(NunaLabRange.tint) ?? NunaPalette.textPrimary
                if let s = p.second {
                    let bar = CGRect(x: px - 6, y: min(y(p.value), y(s)) - 2, width: 12, height: abs(y(p.value) - y(s)) + 4)
                    ctx.fill(Path(roundedRect: bar, cornerRadius: 6), with: .color(NunaPalette.ink.opacity(0.13)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: px - 4, y: y(s) - 4, width: 8, height: 8)), with: .color(tint), lineWidth: 2)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: px - 7, y: y(p.value) - 7, width: 14, height: 14)), with: .color(tint))
                ctx.stroke(Path(ellipseIn: CGRect(x: px - 7, y: y(p.value) - 7, width: 14, height: 14)), with: .color(NunaPalette.card), lineWidth: 2)
                if px - lastLabel > 62 {
                    lastLabel = px
                    ctx.draw(Text(verbatim: Self.dayFormat.string(from: p.date)).font(.nuna(size: 11, weight: .semibold)).foregroundColor(NunaPalette.textSecondary),
                             at: CGPoint(x: min(max(px, left + 24), left + w - 24), y: top + h + 36), anchor: .center)
                }
            }
        }
        .frame(height: 240)
        .accessibilityHidden(true)
    }
}
#endif
