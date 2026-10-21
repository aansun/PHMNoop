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

    static func tint(_ s: Status) -> Color { s == .within ? NunaPalette.charge : NunaPalette.warning }

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
        return distNow < distBefore ? NunaPalette.charge : NunaPalette.warning
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
    }

    static func delete(ids: [String], repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        for id in ids { _ = try? await store.deleteLabMarker(id: id) }
        await repo.refresh()
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

// MARK: - The gauge

/// The latest reading as a needle on a ring that curls in at both ends: amber below the range from the report, green inside it, amber above. The ring
/// glows, a soft tint fills the space inside it, and whatever the screen puts in `content` sits in the middle of it.
struct NunaRangeGauge<Content: View>: View {
    let value: Double
    let range: NunaLabRange
    let content: Content

    init(value: Double, range: NunaLabRange, @ViewBuilder content: () -> Content) {
        self.value = value; self.range = range; self.content = content()
    }

    /// How far round the ring goes, in degrees, and where it starts: centred on the top, so both ends droop below the middle.
    private static var sweep: Double { 220 }
    private static var start: Double { 270 - sweep / 2 }

    private var domain: (lo: Double, hi: Double) {
        let span = max(range.high - range.low, 0.000_1)
        var lo = max(0, range.low - span * 0.6), hi = range.high + span * 0.6
        lo = min(lo, value - span * 0.08)
        hi = max(hi, value + span * 0.08)
        return (max(0, lo), hi)
    }

    var body: some View {
        GeometryReader { geo in
            let lw: CGFloat = 16
            let tail = CGFloat(sin((Self.start + Self.sweep - 360) * .pi / 180)) // how far the ends fall below the centre, in radii
            let r = min((geo.size.width - lw) / 2 - 12, (geo.size.height - lw - 12) / (1 + tail))
            let c = CGPoint(x: geo.size.width / 2, y: lw / 2 + 6 + r)
            ZStack {
                Canvas { ctx, _ in draw(ctx, c: c, r: r, lw: lw) }
                content.frame(width: r * 1.5).position(x: c.x, y: c.y + r * 0.08)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, c: CGPoint, r: CGFloat, lw: CGFloat) {
        let d = domain
        let span = max(d.hi - d.lo, 0.000_1)
        let f: (Double) -> Double = { max(0, min(1, ($0 - d.lo) / span)) }
        func angle(_ t: Double) -> Angle { .degrees(Self.start + Self.sweep * t) }
        func arc(_ a: Double, _ b: Double, radius: CGFloat) -> Path {
            var p = Path(); p.addArc(center: c, radius: radius, startAngle: angle(a), endAngle: angle(b), clockwise: false); return p
        }
        let gap = 0.012
        let lowEnd = f(range.low), highStart = f(range.high)
        var segments: [(Double, Double, Color)] = []
        if lowEnd > gap { segments.append((0, lowEnd - gap / 2, NunaPalette.warning)) }
        segments.append((lowEnd > gap ? lowEnd + gap / 2 : 0, highStart < 1 - gap ? highStart - gap / 2 : 1, NunaPalette.charge))
        if highStart < 1 - gap { segments.append((highStart + gap / 2, 1, NunaPalette.warning)) }
        // A soft dish inside the ring, tinted by where the reading sits.
        let dishTint = value < range.low || value > range.high ? NunaPalette.warning : NunaPalette.charge
        let dish = Path(ellipseIn: CGRect(x: c.x - (r - lw / 2), y: c.y - (r - lw / 2), width: 2 * (r - lw / 2), height: 2 * (r - lw / 2)))
        let floor = c.y + r * CGFloat(sin((Self.start + Self.sweep - 360) * .pi / 180))
        ctx.drawLayer { layer in
            layer.clipToLayer { mask in
                mask.fill(Path(CGRect(x: 0, y: 0, width: c.x * 2, height: floor + 8)),
                          with: .linearGradient(Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)]),
                                                startPoint: CGPoint(x: 0, y: c.y - r), endPoint: CGPoint(x: 0, y: floor + 8)))
            }
            layer.fill(dish, with: .radialGradient(Gradient(colors: [dishTint.opacity(0), dishTint.opacity(0), dishTint.opacity(0.16)]), center: c, startRadius: 0, endRadius: r - lw / 2))
        }
        for (a, b, color) in segments {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 3))
                layer.stroke(arc(a, b, radius: r), with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
        }
        let t = f(value), a = angle(t).radians
        func point(_ radius: CGFloat) -> CGPoint { CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a))) }
        var trail = Path(); trail.move(to: point(r - lw / 2)); trail.addLine(to: point(r * 0.62))
        ctx.stroke(trail, with: .linearGradient(Gradient(colors: [NunaPalette.ink.opacity(0.4), NunaPalette.ink.opacity(0)]), startPoint: point(r - lw / 2), endPoint: point(r * 0.62)),
                   style: StrokeStyle(lineWidth: 13, lineCap: .round))
        var needle = Path(); needle.move(to: point(r - lw * 0.95)); needle.addLine(to: point(r + lw * 0.95))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2))
            layer.stroke(needle, with: .color(NunaPalette.ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
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
