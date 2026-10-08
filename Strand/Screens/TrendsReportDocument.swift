import SwiftUI
import StrandAnalytics
import Foundation

// MARK: - Trends report document
//
// The exported PDF. A light, print-friendly A4 document made for reading and for analysing further:
//   1. a summary page: what changed, then one table with the average, lowest, highest, latest and the
//      first-half → second-half change of every metric;
//   2. chart pages: a large chart per metric with a value axis, a date axis, the average as a dashed line and the
//      lowest and highest days marked;
//   3. daily data pages: every day in the range as a row, one column per metric, so the figures can be checked
//      against the charts or copied out.
// Everything comes from the same `RangeReport` the app computes on-device; the document only lays it out.

/// One day's reading of one metric, in the stored unit.
struct ReportPoint: Equatable {
    let day: String
    let value: Double
}

// MARK: - Formatting shared by the page, the tests and the sheet

enum ReportFormat {
    /// Whole-number for the 0–100 scores + bpm + ms; one decimal for sleep hours, respiratory rate, skin-temp Δ, the
    /// 0–3 stress score and the workout rate. Skin temp is a signed deviation, so a positive reading gets an explicit
    /// "+". Both the value and its unit go through `RangeReportEngine`, the same conversion the headline sentences use,
    /// so the document cannot print a unit the app disagrees with (#1637).
    static func valueText(_ v: Double, _ metric: ReportMetric, units: ReportDisplayUnits, withUnit: Bool = true) -> String {
        let unit = RangeReportEngine.displayUnit(metric, units: units)
        let shown = RangeReportEngine.displayValue(v, metric: metric, units: units)
        let oneDecimal = metric.usesOneDecimal || (metric == .strain && units.effortFactor != 1.0)
        var num = oneDecimal ? round1Text(shown) : "\(Int(shown.rounded()))"
        if metric == .skinTempDev && shown > 0 { num = "+\(num)" }
        return (unit.isEmpty || !withUnit) ? num : "\(num) \(unit)"
    }

    /// Half away from zero, the rule the engine and the Android page share.
    static func round1Text(_ x: Double) -> String {
        let t = String(format: "%.1f", (x * 10).rounded() / 10)
        return t == "-0.0" ? "0.0" : t   // a reading too small to show is zero, not a signed zero
    }

    /// "Jun 15" from "2026-06-15", via a pure ISO parse (no Calendar/locale).
    static func prettyDate(_ ymd: String) -> String {
        guard let (_, m, d) = WeeklyDigestEngine.parseYMD(ymd) else { return ymd }
        let months = [String(localized: "Jan"), String(localized: "Feb"), String(localized: "Mar"),
                      String(localized: "Apr"), String(localized: "May"), String(localized: "Jun"),
                      String(localized: "Jul"), String(localized: "Aug"), String(localized: "Sep"),
                      String(localized: "Oct"), String(localized: "Nov"), String(localized: "Dec")]
        let name = (1...12).contains(m) ? months[m - 1] : "\(m)"
        return "\(name) \(d)"
    }

    /// A label that fits a narrow table column on one line.
    static func shortLabel(_ m: ReportMetric) -> String {
        m == .respRate ? "Resp. rate" : m.label
    }

    /// "Jun 15, 2026" for the table's date column, which spans years.
    static func fullDate(_ ymd: String) -> String {
        guard let (y, _, _) = WeeklyDigestEngine.parseYMD(ymd) else { return ymd }
        return "\(prettyDate(ymd)), \(y)"
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    /// Seconds since 1970 of a "yyyy-MM-dd" day at UTC midnight, for placing a day on the chart's date axis.
    static func dayTime(_ ymd: String) -> TimeInterval? {
        guard let (y, m, d) = WeeklyDigestEngine.parseYMD(ymd),
              let date = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        return date.timeIntervalSince1970
    }

    /// The "yyyy-MM-dd" key of a time made by `dayTime`.
    static func dayKey(_ t: TimeInterval) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: t))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Print palette

/// Ink on white. A printed sheet is not part of the app's dark canvas, so the document carries its own few colours.
private enum Ink {
    static let text = Color(white: 0.09)
    static let secondary = Color(white: 0.38)
    static let tertiary = Color(white: 0.55)
    static let hairline = Color(white: 0.86)
    static let zebra = Color(white: 0.965)
    static let brand = Color(red: 0.12, green: 0.38, blue: 0.86)
    static let good = Color(red: 0.08, green: 0.58, blue: 0.28)
    static let bad = Color(red: 0.80, green: 0.20, blue: 0.30)

    static func metric(_ m: ReportMetric) -> Color {
        switch m {
        case .recovery:    return Color(red: 0.08, green: 0.58, blue: 0.28)
        case .strain:      return Color(red: 0.15, green: 0.40, blue: 0.85)
        case .workouts:    return Color(red: 0.25, green: 0.50, blue: 0.90)
        case .stress:      return Color(red: 0.85, green: 0.52, blue: 0.08)
        case .sleepHours:  return Color(red: 0.32, green: 0.35, blue: 0.80)
        case .hrv:         return Color(red: 0.55, green: 0.30, blue: 0.75)
        case .restingHr:   return Color(red: 0.82, green: 0.22, blue: 0.38)
        case .respRate:    return Color(red: 0.08, green: 0.58, blue: 0.64)
        case .skinTempDev: return Color(red: 0.90, green: 0.42, blue: 0.12)
        }
    }
}

// MARK: - The document

struct TrendsReportDocument {
    let report: RangeReport
    let range: ReportRange
    /// The in-range readings of each metric, oldest first.
    let points: [ReportMetric: [ReportPoint]]
    let generatedOn: String
    var units: ReportDisplayUnits = .stored

    static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static let chartsPerPage = 3
    private static let rowHeight: CGFloat = 13.5
    private static let firstDataRows = 41
    private static let dataRows = 54

    private var stats: [MetricRangeStat] { report.metrics }

    /// Every day that carries at least one reading, oldest first.
    private var days: [String] {
        Set(points.values.flatMap { $0.map(\.day) }).sorted()
    }

    private var lookup: [ReportMetric: [String: Double]] {
        points.mapValues { Dictionary($0.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b }) }
    }

    private var dataPageCount: Int {
        let n = days.count
        if n <= Self.firstDataRows { return 1 }
        return 1 + Int((Double(n - Self.firstDataRows) / Double(Self.dataRows)).rounded(.up))
    }

    private var chartPageCount: Int { Int((Double(stats.count) / Double(Self.chartsPerPage)).rounded(.up)) }

    var pageCount: Int { report.isEmpty ? 1 : 1 + chartPageCount + dataPageCount }

    /// The pages in reading order, each exactly `pageSize`.
    func pages() -> [AnyView] {
        if report.isEmpty { return [frame(1, content: AnyView(VStack(alignment: .leading, spacing: 18) { masthead; emptyState }))] }
        var out: [AnyView] = []
        out.append(frame(1, content: AnyView(VStack(alignment: .leading, spacing: 20) { masthead; findings; summary })))
        for p in 0..<chartPageCount {
            let slice = Array(stats.dropFirst(p * Self.chartsPerPage).prefix(Self.chartsPerPage))
            out.append(frame(2 + p, content: AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(p == 0 ? "Charts" : "Charts (continued)")
                        .padding(.bottom, 4)
                    ForEach(slice, id: \.metric) { metricBlock($0) }
                })))
        }
        for p in 0..<dataPageCount {
            let from = p == 0 ? 0 : Self.firstDataRows + (p - 1) * Self.dataRows
            let count = p == 0 ? Self.firstDataRows : Self.dataRows
            let slice = Array(days.dropFirst(from).prefix(count))
            out.append(frame(2 + chartPageCount + p, content: AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(p == 0 ? "Daily data" : "Daily data (continued)")
                    if p == 0 { notes }
                    dataTable(slice)
                })))
        }
        return out
    }

    // MARK: Page frame

    private func frame(_ index: Int, content: AnyView) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    HStack {
                        Text(verbatim: "PHMN · " + String(localized: "Trends report") + " · " + range.longName)
                        Spacer()
                        Text(verbatim: String(localized: "Page \(index) of \(pageCount)"))
                    }
                    .font(.system(size: 8, weight: .medium)).foregroundColor(Ink.tertiary)
                }
            }
            .padding(Self.margin)
            .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            // A preview inside the app inherits the surrounding screen's capitals; the sheet of paper must not.
            .textCase(nil)
        )
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    brandIcon
                    Text(verbatim: "PHMN").font(.system(size: 12, weight: .heavy)).tracking(2.4).foregroundColor(Ink.brand)
                }
                Spacer()
                Text(verbatim: String(localized: "Generated \(generatedOn)")).font(.system(size: 9)).foregroundColor(Ink.tertiary)
            }
            Text("Trends report").font(.system(size: 28, weight: .bold)).foregroundColor(Ink.text)
            Text(verbatim: rangeLabel).font(.system(size: 12.5, weight: .medium)).foregroundColor(Ink.secondary)
            if !report.isEmpty {
                Text(verbatim: coverageLabel).font(.system(size: 10)).foregroundColor(Ink.tertiary)
            }
        }
    }

    /// The app icon beside the name. The picture lives in the iOS asset catalogue, so other platforms show the name alone.
    @ViewBuilder private var brandIcon: some View {
        #if os(iOS)
        Image("PHMNMark").resizable().scaledToFit().frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.5))
        #else
        EmptyView()
        #endif
    }

    private var rangeLabel: String {
        let span = report.totalDays
        let dates = "\(ReportFormat.fullDate(report.start)) – \(ReportFormat.fullDate(report.end))"
        return span == 1 ? dates + "  ·  " + String(localized: "1 day") : dates + "  ·  " + String(localized: "\(span) days")
    }

    private var coverageLabel: String {
        String(localized: "\(days.count) of \(report.totalDays) days have readings · \(stats.count) metrics")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not enough data in this range yet").font(.system(size: 15, weight: .bold)).foregroundColor(Ink.text)
            Text("No readings fell inside this range. Wear your strap a few more days, or pick a wider range, then export again.")
                .font(.system(size: 11)).foregroundColor(Ink.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.zebra, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Sections

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.4).textCase(.uppercase).foregroundColor(Ink.secondary)
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Key findings")
            ForEach(Array(report.headlines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Ink.brand).frame(width: 4, height: 4).offset(y: -2)
                    Text(verbatim: line).font(.system(size: 10.5)).foregroundColor(Ink.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Summary table

    private static let summaryWidths: [CGFloat] = [118, 62, 80, 80, 62, 81, 40]

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Summary").padding(.bottom, 6)
            HStack(spacing: 0) {
                head("Metric", 0, .leading); head("Average", 1, .trailing); head("Lowest", 2, .trailing); head("Highest", 3, .trailing)
                head("Latest", 4, .trailing); head("Change", 5, .trailing); head("Days", 6, .trailing)
            }
            .padding(.bottom, 5)
            Rectangle().fill(Ink.text.opacity(0.7)).frame(height: 1)
            ForEach(Array(stats.enumerated()), id: \.element.metric) { i, s in
                summaryRow(s).background(i % 2 == 1 ? Ink.zebra : Color.clear)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }

    private func head(_ t: LocalizedStringKey, _ i: Int, _ align: Alignment) -> some View {
        Text(t).font(.system(size: 8, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundColor(Ink.secondary)
            .frame(width: Self.summaryWidths[i], alignment: align)
    }

    private func summaryRow(_ s: MetricRangeStat) -> some View {
        let m = s.metric
        let w = Self.summaryWidths
        let change = changeInfo(s)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Ink.metric(m)).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(m.label)).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Ink.text)
                    let u = RangeReportEngine.displayUnit(m, units: units)
                    if !u.isEmpty { Text(verbatim: u).font(.system(size: 7.5)).foregroundColor(Ink.tertiary) }
                }
            }.frame(width: w[0], alignment: .leading)
            Text(verbatim: ReportFormat.valueText(s.mean, m, units: units, withUnit: false))
                .font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundColor(Ink.text).frame(width: w[1], alignment: .trailing)
            valueWithDate(s.min, m).frame(width: w[2], alignment: .trailing)
            valueWithDate(s.max, m).frame(width: w[3], alignment: .trailing)
            valueWithDate(s.latest, m).frame(width: w[4], alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: change.text).font(.system(size: 10.5, weight: .bold).monospacedDigit()).foregroundColor(change.color)
                Text(verbatim: "\(ReportFormat.valueText(s.firstHalfMean, m, units: units, withUnit: false)) → \(ReportFormat.valueText(s.secondHalfMean, m, units: units, withUnit: false))")
                    .font(.system(size: 7.5).monospacedDigit()).foregroundColor(Ink.tertiary)
            }.frame(width: w[5], alignment: .trailing)
            Text(verbatim: "\(s.n)/\(report.totalDays)").font(.system(size: 9).monospacedDigit()).foregroundColor(Ink.secondary)
                .frame(width: w[6], alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func valueWithDate(_ dv: DayValue, _ m: ReportMetric) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: ReportFormat.valueText(dv.value, m, units: units, withUnit: false))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundColor(Ink.text)
            Text(verbatim: ReportFormat.prettyDate(dv.day)).font(.system(size: 7.5)).foregroundColor(Ink.tertiary)
        }
    }

    /// The first-half → second-half move, with a good/bad colour only for metrics where direction has a meaning.
    private func changeInfo(_ s: MetricRangeStat) -> (text: String, color: Color) {
        let d = s.halfDelta
        if s.trend == .flat || abs(d) < 0.05 { return ("→ " + String(localized: "steady"), Ink.tertiary) }
        let up = d > 0
        let shown = abs(RangeReportEngine.displayValue(d, metric: s.metric, units: units))
        let color: Color = s.metric.framesGoodBad ? (up == s.metric.higherIsBetter ? Ink.good : Ink.bad) : Ink.secondary
        return ((up ? "↑ +" : "↓ −") + ReportFormat.round1Text(shown), color)
    }

    // MARK: Chart blocks

    private func metricBlock(_ s: MetricRangeStat) -> some View {
        let m = s.metric
        let u = RangeReportEngine.displayUnit(m, units: units)
        let change = changeInfo(s)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(Ink.metric(m)).frame(width: 8, height: 8)
                Text(LocalizedStringKey(m.label)).font(.system(size: 13.5, weight: .bold)).foregroundColor(Ink.text)
                if !u.isEmpty { Text(verbatim: u).font(.system(size: 9.5)).foregroundColor(Ink.tertiary) }
                Spacer()
                Text(verbatim: change.text).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundColor(change.color)
                Text("first half to second half").font(.system(size: 8)).foregroundColor(Ink.tertiary)
            }
            HStack(alignment: .top, spacing: 0) {
                figure("Average", ReportFormat.valueText(s.mean, m, units: units, withUnit: false), nil)
                figure("Lowest", ReportFormat.valueText(s.min.value, m, units: units, withUnit: false), ReportFormat.prettyDate(s.min.day))
                figure("Highest", ReportFormat.valueText(s.max.value, m, units: units, withUnit: false), ReportFormat.prettyDate(s.max.day))
                figure("Latest", ReportFormat.valueText(s.latest.value, m, units: units, withUnit: false), ReportFormat.prettyDate(s.latest.day))
                figure("Days with readings", "\(s.n) / \(report.totalDays)", nil)
            }
            ReportChart(points: points[m] ?? [], metric: m, mean: s.mean, color: Ink.metric(m),
                        start: report.start, end: report.end, units: units)
                .frame(height: 118)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    private func figure(_ label: LocalizedStringKey, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 7.5, weight: .heavy)).tracking(0.7).textCase(.uppercase).foregroundColor(Ink.secondary)
            Text(verbatim: value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(Ink.text)
            if let sub { Text(verbatim: sub).font(.system(size: 7.5)).foregroundColor(Ink.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Daily data

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to read this").font(.system(size: 9, weight: .bold)).foregroundColor(Ink.text)
            Text("HRV, resting HR, sleep duration, respiratory rate and skin temperature are measured from the strap (skin temperature is the deviation from your own baseline). Workouts is the number of activities logged or detected per day. Recovery, Effort and Stress are PHMN's own on-device scores, not clinical measures: Recovery is a daily readiness composite of HRV, resting HR, sleep and skin-temperature trend; Effort is cardiovascular load derived from heart rate; Stress is a 0-3 autonomic-load index. A dash means no reading that day.")
                .font(.system(size: 8)).foregroundColor(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Generated by PHMN, all on-device, no account, no cloud. Informational only, not medical advice.")
                .font(.system(size: 8)).foregroundColor(Ink.tertiary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.zebra, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var dateColumnWidth: CGFloat { 74 }
    private var valueColumnWidth: CGFloat {
        stats.isEmpty ? 40 : (Self.contentWidth - dateColumnWidth) / CGFloat(stats.count)
    }

    private func dataTable(_ rows: [String]) -> some View {
        let lookup = self.lookup
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("Date").font(.system(size: 7.5, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundColor(Ink.secondary)
                    .frame(width: dateColumnWidth, alignment: .leading)
                ForEach(stats, id: \.metric) { s in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(LocalizedStringKey(ReportFormat.shortLabel(s.metric))).font(.system(size: 7.5, weight: .heavy)).foregroundColor(Ink.text)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        let u = RangeReportEngine.displayUnit(s.metric, units: units)
                        Text(verbatim: u.isEmpty ? " " : u).font(.system(size: 7)).foregroundColor(Ink.tertiary)
                    }
                    .frame(width: valueColumnWidth - 4, alignment: .trailing).padding(.trailing, 4)
                }
            }
            .padding(.bottom, 4)
            Rectangle().fill(Ink.text.opacity(0.7)).frame(height: 1)
            ForEach(Array(rows.enumerated()), id: \.element) { i, day in
                HStack(spacing: 0) {
                    Text(verbatim: ReportFormat.fullDate(day)).font(.system(size: 8.5).monospacedDigit()).foregroundColor(Ink.text)
                        .frame(width: dateColumnWidth, alignment: .leading)
                    ForEach(stats, id: \.metric) { s in
                        let v = lookup[s.metric]?[day]
                        Text(verbatim: v.map { ReportFormat.valueText($0, s.metric, units: units, withUnit: false) } ?? "–")
                            .font(.system(size: 8.5).monospacedDigit()).foregroundColor(v == nil ? Ink.tertiary : Ink.text)
                            .frame(width: valueColumnWidth - 4, alignment: .trailing).padding(.trailing, 4)
                    }
                }
                .frame(height: Self.rowHeight)
                .background(i % 2 == 1 ? Ink.zebra : Color.clear)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }
}

// MARK: - Chart

/// A metric over the range: gridlines with values on the left, dates along the bottom, the average as a dashed line, the lowest
/// and highest days marked. A gap of more than three days breaks the line instead of drawing across days with no reading.
private struct ReportChart: View {
    let points: [ReportPoint]
    let metric: ReportMetric
    let mean: Double
    let color: Color
    let start: String
    let end: String
    let units: ReportDisplayUnits

    var body: some View {
        Canvas { gc, size in
            let left: CGFloat = 36, right: CGFloat = 8, top: CGFloat = 14, bottom: CGFloat = 18
            let plot = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
            guard plot.width > 10, plot.height > 10, !points.isEmpty,
                  let t0 = ReportFormat.dayTime(start), let t1 = ReportFormat.dayTime(end) else { return }
            let shown = points.map { RangeReportEngine.displayValue($0.value, metric: metric, units: units) }
            var lo = shown.min() ?? 0, hi = shown.max() ?? 1
            let shownMean = RangeReportEngine.displayValue(mean, metric: metric, units: units)
            lo = min(lo, shownMean); hi = max(hi, shownMean)
            if hi - lo < 1e-9 { lo -= 1; hi += 1 }
            let pad = (hi - lo) * 0.14
            let nonNegative = lo >= 0
            lo -= pad; hi += pad
            // A reading that cannot go below zero, or above the top of its scale, gets an axis that cannot either.
            if nonNegative { lo = max(lo, 0) }
            switch metric {
            case .recovery, .strain: hi = min(hi, max(RangeReportEngine.displayValue(100, metric: metric, units: units), lo + 1e-6))
            case .stress:            hi = min(hi, 3)
            default:                 break
            }
            let span = max(t1 - t0, 86_400)
            func y(_ v: Double) -> CGFloat { plot.maxY - CGFloat((v - lo) / (hi - lo)) * plot.height }
            func x(_ t: TimeInterval) -> CGFloat { plot.minX + CGFloat((t - t0) / span) * plot.width }

            let grey = Color(white: 0.55), grid = Color(white: 0.88)
            let step = (hi - lo) / 3
            let decimals = step >= 5 ? 0 : (step >= 0.5 ? 1 : 2)
            for i in 0...3 {
                let v = lo + (hi - lo) * Double(i) / 3
                var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y(v))); line.addLine(to: CGPoint(x: plot.maxX, y: y(v)))
                gc.stroke(line, with: .color(grid), lineWidth: 0.6)
                gc.draw(Text(verbatim: String(format: "%.\(decimals)f", v)).font(.system(size: 7.5)).foregroundColor(grey),
                        at: CGPoint(x: plot.minX - 5, y: y(v)), anchor: .trailing)
            }
            for k in 0...4 {
                let t = t0 + span * Double(k) / 4
                let label = ReportFormat.prettyDate(ReportFormat.dayKey(t))
                gc.draw(Text(verbatim: label).font(.system(size: 7.5)).foregroundColor(grey),
                        at: CGPoint(x: x(t), y: plot.maxY + 4), anchor: k == 0 ? .topLeading : (k == 4 ? .topTrailing : .top))
            }

            // The average.
            var avg = Path(); avg.move(to: CGPoint(x: plot.minX, y: y(shownMean))); avg.addLine(to: CGPoint(x: plot.maxX, y: y(shownMean)))
            gc.stroke(avg, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))
            gc.draw(Text("avg").font(.system(size: 7, weight: .semibold)).foregroundColor(color),
                    at: CGPoint(x: plot.maxX - 2, y: y(shownMean) - 2), anchor: .bottomTrailing)

            // A count per day reads as bars, not as a line jumping between zero and one.
            if metric == .workouts {
                let barW = max(1.5, plot.width / CGFloat(max(span / 86_400, 1)) * 0.7)
                for p in zip(points, shown) {
                    guard let t = ReportFormat.dayTime(p.0.day), p.1 > 0 else { continue }
                    let top = y(p.1), base = y(max(lo, 0))
                    gc.fill(Path(CGRect(x: x(t) - barW / 2, y: top, width: barW, height: base - top)), with: .color(color.opacity(0.85)))
                }
                return
            }

            // The readings, in runs.
            let pts: [(t: TimeInterval, v: Double)] = zip(points, shown).compactMap { p, v in ReportFormat.dayTime(p.day).map { ($0, v) } }
            var runs: [[(t: TimeInterval, v: Double)]] = []
            for p in pts {
                if let last = runs.last?.last, p.t - last.t <= 3 * 86_400 { runs[runs.count - 1].append(p) } else { runs.append([p]) }
            }
            for run in runs where run.count >= 2 {
                var area = Path()
                area.move(to: CGPoint(x: x(run[0].t), y: plot.maxY))
                for p in run { area.addLine(to: CGPoint(x: x(p.t), y: y(p.v))) }
                area.addLine(to: CGPoint(x: x(run[run.count - 1].t), y: plot.maxY)); area.closeSubpath()
                gc.fill(area, with: .color(color.opacity(0.10)))
                var line = Path(); line.move(to: CGPoint(x: x(run[0].t), y: y(run[0].v)))
                for p in run.dropFirst() { line.addLine(to: CGPoint(x: x(p.t), y: y(p.v))) }
                gc.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
            if pts.count <= 60 || runs.contains(where: { $0.count == 1 }) {
                for p in pts {
                    let r = CGRect(x: x(p.t) - 1.8, y: y(p.v) - 1.8, width: 3.6, height: 3.6)
                    gc.fill(Path(ellipseIn: r), with: .color(color))
                }
            }

            // Lowest and highest.
            if let iMax = shown.indices.max(by: { shown[$0] < shown[$1] }), let iMin = shown.indices.min(by: { shown[$0] < shown[$1] }),
               pts.indices.contains(iMax), pts.indices.contains(iMin), shown.count > 1 {
                func mark(_ i: Int, above: Bool) {
                    let p = pts[i]
                    let c = CGPoint(x: x(p.t), y: y(p.v))
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
                    gc.stroke(Path(ellipseIn: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4)), with: .color(color), lineWidth: 1.5)
                    let text = String(format: "%.\(decimals)f", p.v)
                    let lx = min(max(c.x, plot.minX + 12), plot.maxX - 12)
                    gc.draw(Text(verbatim: text).font(.system(size: 7.5, weight: .bold)).foregroundColor(color),
                            at: CGPoint(x: lx, y: above ? c.y - 6 : c.y + 6), anchor: above ? .bottom : .top)
                }
                mark(iMax, above: true)
                if iMin != iMax { mark(iMin, above: false) }
            }
        }
        .accessibilityHidden(true)
    }
}
