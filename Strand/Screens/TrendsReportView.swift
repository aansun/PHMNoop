import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Trends Report (#436)
//
// A shareable, offline one-page "trends report" over a chosen date range: per-metric
// mean / min / max / trend for Recovery, Sleep, HRV, Resting HR and Strain, a short set
// of plain-English headlines, and a simple sparkline for each metric. Everything is
// computed on-device by the pure, unit-tested `RangeReportEngine` (no network), then
// rendered to a PDF the user saves to Files / shares via the system share sheet.
//
// This file owns three things:
//   • `TrendsReportData` — pulls the five metric series out of the Repository's
//     DailyMetric history and calls RangeReportEngine.build for a range.
//   • `TrendsReportDocument` (its own file) — the laid-out multi-page A4 document rendered to PDF.
//   • `TrendsReportSheet` — the in-app range picker + "Export" CTA presented from Trends.
//
// Honesty: an empty range (no metric carried a reading) renders a friendly
// "not enough data in this range yet" state, never a blank or fabricated page.

// MARK: - Range options

/// The export window choices offered in the picker. Mirrors the Trends range ethos
/// (trailing N days, or all history) but is its own type so the report's wording is
/// self-contained.
enum ReportRange: Int, CaseIterable, Identifiable {
    case days30 = 30, days90 = 90, days180 = 180, days365 = 365, all = 0
    var id: Int { rawValue }

    /// Short pill label.
    var label: String {
        switch self {
        case .days30:  return String(localized: "30d")
        case .days90:  return String(localized: "90d")
        case .days180: return String(localized: "6M")
        case .days365: return String(localized: "1Y")
        case .all:     return String(localized: "All")
        }
    }

    /// Long human label for the report title / picker description.
    var longName: String {
        switch self {
        case .days30:  return String(localized: "Last 30 days")
        case .days90:  return String(localized: "Last 90 days")
        case .days180: return String(localized: "Last 6 months")
        case .days365: return String(localized: "Last year")
        case .all:     return String(localized: "All history")
        }
    }

    /// Trailing-day window, or nil for "all history".
    var days: Int? { self == .all ? nil : rawValue }
}

// MARK: - Report data builder (pure glue over the engine)

/// Builds a `RangeReport` for a `ReportRange` from a DailyMetric history, plus the raw
/// per-metric sparkline series the page draws. Pure: no Repository, no I/O — give it the
/// `days` array and today's local day key.
enum TrendsReportData {

    /// The nine day→value maps the engine consumes, keyed by ReportMetric.
    ///
    /// `stressByDay` is the persisted daily stress series ("yyyy-MM-dd" → 0–3), the same
    /// stored series the Stress screen prioritises (#457). It isn't carried on `DailyMetric`,
    /// so the caller loads it and passes it in; absent days simply stay out of the report.
    static func metricMaps(from days: [DailyMetric],
                           stressByDay: [String: Double] = [:]) -> [ReportMetric: [String: Double]] {
        var workouts: [String: Double] = [:]
        var recovery: [String: Double] = [:]
        var sleepHours: [String: Double] = [:]
        var hrv: [String: Double] = [:]
        var restingHr: [String: Double] = [:]
        var strain: [String: Double] = [:]
        var respRate: [String: Double] = [:]
        var skinTempDev: [String: Double] = [:]
        for d in days {
            // Workouts logged that day (#457). The count is always present on a recorded day
            // (0 on a rest day), so the row reflects the full window's activity cadence.
            if let c = d.exerciseCount { workouts[d.day] = Double(c) }
            if let v = d.recovery { recovery[d.day] = v }
            // Sleep is reported in HOURS to match the metric's unit; totalSleepMin is the
            // persisted minutes asleep. Days with no in-bed sleep stay absent.
            if let m = d.totalSleepMin, m > 0 { sleepHours[d.day] = m / 60.0 }
            if let v = d.avgHrv { hrv[d.day] = v }
            if let v = d.restingHr { restingHr[d.day] = Double(v) }
            if let v = d.strain { strain[d.day] = v }
            // In-sleep physiology (v7 columns). Absent on days the strap didn't measure them.
            if let v = d.respRateBpm { respRate[d.day] = v }
            if let v = d.skinTempDevC { skinTempDev[d.day] = v }
        }
        // Daily stress score (#457), clamped to its 0–3 scale. Stored-only — the report never
        // re-derives a stress value (unlike the live Stress screen), so a day with no banked
        // stress simply has no Stress row contribution.
        let stress = stressByDay.mapValues { Swift.min(Swift.max($0, 0), 3) }
        return [
            .workouts: workouts, .stress: stress,
            .recovery: recovery, .sleepHours: sleepHours, .hrv: hrv,
            .restingHr: restingHr, .strain: strain,
            .respRate: respRate, .skinTempDev: skinTempDev,
        ]
    }

    /// The inclusive [start, end] "yyyy-MM-dd" window for a range, anchored to today's
    /// LOCAL day (so a 30-day export is the last 30 calendar days, not the last 30 rows —
    /// matching TrendsView's window rule). For `.all`, start is the earliest day present.
    static func window(for range: ReportRange, days: [DailyMetric],
                       today: String) -> (start: String, end: String) {
        let end = today
        guard let n = range.days else {
            // All history: from the earliest recorded day (or today if the history is empty).
            let start = days.map(\.day).min() ?? today
            return (start, end)
        }
        // Trailing N calendar days ending today, computed via the local-day key so the
        // window matches TrendsView (Calendar-based, phone-local), then clamped to the
        // ISO string the engine compares on.
        let startDate = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
        // Local-zone "yyyy-MM-dd" matching Repository.localDayKey, but self-contained so this stays a
        // nonisolated static (localDayKey is @MainActor-isolated and this runs off the main actor).
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let start = f.string(from: startDate)
        return (start, end)
    }

    /// Build the full report for a range from a DailyMetric history (+ the stored daily
    /// stress series, for the Stress row — #457).
    static func report(for range: ReportRange, days: [DailyMetric],
                       today: String, stressByDay: [String: Double] = [:],
                       units: ReportDisplayUnits = .stored) -> RangeReport {
        let (start, end) = window(for: range, days: days, today: today)
        return RangeReportEngine.build(metrics: metricMaps(from: days, stressByDay: stressByDay),
                                       start: start, end: end, units: units)
    }

    /// The user's display preferences (°C/°F, Effort axis) resolved from the same three keys every other screen reads, so the
    /// exported figures agree with what they have been looking at all month (#1637). Handed to the engine AND the document, so the
    /// headline sentences and the tables can never disagree.
    static func units(systemRaw: String, temperatureRaw: String, effortScaleRaw: String) -> ReportDisplayUnits {
        let system = UnitSystem(rawValue: systemRaw) ?? .metric
        let temp = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        // Name the canonical constant rather than deriving it from `effortValue(1.0,)`: the report multiplies by this factor,
        // which is only equivalent while the mapping stays linear.
        return ReportDisplayUnits(fahrenheit: temp == .fahrenheit,
                                  effortFactor: scale == .whoop ? UnitFormatter.effortScaleFactor : 1.0)
    }

    /// The whole document for a range: the engine's report, the readings behind it, and the label for when it was made.
    @MainActor
    static func document(range: ReportRange, days: [DailyMetric], stressByDay: [String: Double],
                         units: ReportDisplayUnits) -> TrendsReportDocument {
        let rpt = report(for: range, days: days, today: Repository.localDayKey(Date()), stressByDay: stressByDay, units: units)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return TrendsReportDocument(report: rpt, range: range,
                                    points: points(from: days, start: rpt.start, end: rpt.end, stressByDay: stressByDay),
                                    generatedOn: f.string(from: Date()), units: units)
    }

    /// The in-range readings of every metric with the day each fell on, oldest first, for the document's charts and daily table.
    static func points(from days: [DailyMetric], start: String, end: String,
                       stressByDay: [String: Double] = [:]) -> [ReportMetric: [ReportPoint]] {
        var out: [ReportMetric: [ReportPoint]] = [:]
        for (metric, map) in metricMaps(from: days, stressByDay: stressByDay) {
            let pts = map.filter { $0.key >= start && $0.key <= end }
                .sorted { $0.key < $1.key }
                .map { ReportPoint(day: $0.key, value: $0.value) }
            if !pts.isEmpty { out[metric] = pts }
        }
        return out
    }

    /// The in-range sparkline series (chronological values) for one metric — the same
    /// window the engine summarised, so the line and the stats agree.
    static func series(_ metric: ReportMetric, from days: [DailyMetric],
                       start: String, end: String, stressByDay: [String: Double] = [:]) -> [Double] {
        let map = metricMaps(from: days, stressByDay: stressByDay)[metric] ?? [:]
        return map.filter { $0.key >= start && $0.key <= end }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }
}

// MARK: - Export sheet (range picker + CTA)

/// The in-app sheet: pick a range, preview the page, export to PDF. Presented from the
/// Trends screen's "Export trends report" button.
struct TrendsReportSheet: View {
    let days: [DailyMetric]
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var range: ReportRange = .days90
    @State private var exporting = false
    /// Stored daily stress series ("yyyy-MM-dd" → 0–3), for the Stress row (#457). Loaded
    /// once from the same "my-whoop" series the Stress screen reads; empty until it arrives.
    @State private var stressByDay: [String: Double] = [:]
    // The same three keys every other screen reads, so the exported page agrees with what the user
    // has been looking at all month (#1637). Temperature has its own override on top of the
    // length/mass system, which is why both are needed to resolve it.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var units: ReportDisplayUnits {
        TrendsReportData.units(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw, effortScaleRaw: effortScaleRaw)
    }

    private func document() -> TrendsReportDocument {
        TrendsReportData.document(range: range, days: days, stressByDay: stressByDay, units: units)
    }

    var body: some View {
        let doc = document()
        let pageCount = doc.pageCount
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Export trends report")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("A readable PDF of your trends over a date range: a summary table, a chart for each metric and a day-by-day table of every reading, so you can analyse it further. Saved on your \(Platform.deviceNoun). Nothing leaves the device.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Range").strandOverline()
                    SegmentedPillControl(ReportRange.allCases, selection: $range) { $0.label }
                    Text(range.longName)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }

                // A scaled-down live preview of the page so the user sees exactly what
                // they'll get before exporting.
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Preview").strandOverline()
                    Text(verbatim: String(localized: "\(pageCount) pages · first page shown"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    (doc.pages().first ?? AnyView(EmptyView()))
                        .scaleEffect(0.5, anchor: .topLeading)
                        .frame(width: TrendsReportDocument.pageSize.width * 0.5,
                               height: TrendsReportDocument.pageSize.height * 0.5, alignment: .topLeading)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: 1)
                        )
                }

                // WHOOP primary action — routed through the unified button system (filled blue accent,
                // white ink, no glow). The label swaps to "Preparing…" while a PDF is being written.
                NoopButton(exporting ? "Preparing…" : "Export PDF",
                           systemImage: "square.and.arrow.up", kind: .primary, fullWidth: true) {
                    export(doc)
                }
                .disabled(exporting)

                Text("Tip: the share sheet can save the PDF to Files, AirDrop it, or send it on.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .screenPadding()
            .padding(.vertical, NoopMetrics.space6)
        }
        #if os(iOS)
        // #697/#horizontal-swipe parity, see ScreenScaffold.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        #endif
        .background(StrandPalette.surfaceBase)
        #if os(macOS)
        .frame(width: 460, height: 640)
        #endif
        #if os(iOS)
        .noopSheetPresentation(largeFirst: true)
        #endif
        // Load the stored daily stress series for the Stress row (#457). The same
        // "my-whoop" series the Stress screen prioritises; the report never re-derives it.
        .task {
            let pts = await repo.series(key: "stress", source: "my-whoop")
            stressByDay = Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
    }

    @MainActor
    private func export(_ doc: TrendsReportDocument) {
        guard !exporting else { return }
        exporting = true
        let name = "NOOP-trends-\(doc.report.start)_to_\(doc.report.end).pdf"
        TrendsReportRenderer.exportPDF(pages: doc.pages(), size: TrendsReportDocument.pageSize, suggestedName: name)
        exporting = false
        #if os(macOS)
        // macOS NSSavePanel is modal and has already returned by now, so closing the report sheet is fine.
        dismiss()
        #endif
        // iOS (#455): do NOT dismiss here. The share sheet is presented ON TOP of this report sheet; calling
        // dismiss() would tear this sheet — and the share sheet with it — straight back down, so the user
        // saw nothing. Leave the report up; the share sheet sits over it and returns here when closed.
    }
}

#if DEBUG
@MainActor
private func previewDays() -> [DailyMetric] {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let cal = Calendar(identifier: .gregorian)
    var out: [DailyMetric] = []
    for i in stride(from: 119, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
        let p = Double(119 - i)
        out.append(DailyMetric(
            day: fmt.string(from: d),
            totalSleepMin: 380 + 60 * sin(p / 9), efficiency: 0.9,
            deepMin: 90, remMin: 110, lightMin: 200, disturbances: 6,
            restingHr: Int((52 + 4 * sin(p / 7)).rounded()),
            avgHrv: 55 + 14 * sin(p / 8) + p * 0.1,
            recovery: max(2, min(99, 58 + 26 * sin(p / 11) + p * 0.15)),
            strain: max(0, min(100, 50 + 18 * sin(p / 5))),
            exerciseCount: 1))
    }
    return out
}

#Preview("Trends report — sheet") {
    TrendsReportSheet(days: previewDays())
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 480, height: 640)
        .preferredColorScheme(.dark)
}
#endif
