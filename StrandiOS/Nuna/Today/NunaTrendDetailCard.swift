#if os(iOS)
import SwiftUI
import StrandDesign

/// The one card of a metric detail screen: the latest reading at the top left, the W / M / 6M switch and the date
/// stepper at the top right, a sentence about the period, the chart, and the average, lowest and highest as plain text.
/// Every figure is computed from the stored readings of the window the wearer is looking at.
struct NunaTrendDetailCard: View {
    let title: String
    let caption: LocalizedStringKey
    let valueText: String
    var unit = ""
    var chip: (text: LocalizedStringKey, color: Color)?
    var note: String?
    @ObservedObject var series: NunaSeriesModel
    var lineColor: Color = NunaPalette.charge
    var decimals = 0
    var higherIsBetter = true

    @State private var range = 7
    @State private var page = 0

    private static let ranges: [(value: Int, title: String)] = [(7, "W"), (30, "M"), (180, "6M")]

    private func fmt(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    private var windowEnd: Date { Calendar.current.date(byAdding: .day, value: -page * range, to: Date()) ?? Date() }
    private var windowStart: Date { Calendar.current.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }
    private var canGoBack: Bool {
        guard let first = series.byDay.keys.min() else { return false }
        return Repository.localDayKey(windowStart) > first
    }

    private var dateLabel: String {
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("d MMM")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("d MMM yy")
        return "\(a.string(from: windowStart)) – \(b.string(from: windowEnd))"
    }

    private func average(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    var body: some View {
        let pts = series.readings(range, endingDaysAgo: page * range)
        let vals = pts.map(\.value)
        let prev = average(series.readings(range, endingDaysAgo: (page + 1) * range).map(\.value))
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let s = summary(avg: average(vals), prev: prev) {
                    Text(verbatim: s).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pts.isEmpty {
                    Text(series.loaded ? "No data in this period" : " ").font(.nuna(size: 14, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    NunaSegmentedChart(points: pts, color: lineColor, decimals: decimals,
                                       band: series.band.map { $0.lo...$0.hi }, higherIsBetter: higherIsBetter)
                }
                if let avg = average(vals), let lo = vals.min(), let hi = vals.max() {
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        stat("Average", fmt(avg)); stat("Lowest", fmt(lo)); stat("Highest", fmt(hi))
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: valueText).font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let chip { NunaChip(chip.text, color: chip.color) }
                if let note {
                    Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 12) {
                rangeSwitch
                dateStepper
            }
        }
    }

    private var rangeSwitch: some View {
        HStack(spacing: 2) {
            ForEach(Self.ranges, id: \.value) { r in
                let on = range == r.value
                Button { range = r.value; page = 0 } label: {
                    Text(verbatim: r.title).font(.nuna(size: 13, weight: .bold))
                        .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(width: 48, height: 34)
                        .background(on ? NunaPalette.glassStrong : Color.clear, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(NunaPalette.shade.opacity(0.28), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    private var dateStepper: some View {
        HStack(spacing: 4) {
            Button { page += 1 } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 14, weight: .bold)).frame(width: 26, height: 30)
            }.disabled(!canGoBack).opacity(canGoBack ? 1 : 0.3)
            Text(verbatim: dateLabel).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Button { page = max(0, page - 1) } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).frame(width: 26, height: 30)
            }.disabled(page == 0).opacity(page == 0 ? 0.3 : 1)
        }
        .foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A sentence about the window against the one before it, from the same stored readings.
    private func summary(avg: Double?, prev: Double?) -> String? {
        guard let avg else { return nil }
        guard let prev, prev != 0 else { return String(localized: "Your average over this period was \(fmt(avg)).") }
        let pct = Int(((avg - prev) / abs(prev) * 100).rounded())
        if pct == 0 { return String(localized: "Your average over this period (\(fmt(avg))) matched the period before (\(fmt(prev))).") }
        return pct > 0
            ? String(localized: "Your average over this period (\(fmt(avg))) was \(pct)% above the period before (\(fmt(prev))).")
            : String(localized: "Your average over this period (\(fmt(avg))) was \(-pct)% below the period before (\(fmt(prev))).")
    }
}

/// The trend chart of the one-card detail screens: the raw readings drawn thin and faint, and over them one short line
/// per stretch with its average above and the move against the stretch before below it. A week has one stretch per day,
/// a month one per week (counted back from the latest reading) and six months one per calendar month, so the same
/// design reads the same at every range, and the x axis carries the same "day over month" label under each stretch.
struct NunaSegmentedChart: View {
    let points: [(date: Date, value: Double)]
    var color: Color = NunaPalette.charge
    var decimals = 0
    var band: ClosedRange<Double>?
    var higherIsBetter = true
    /// Colour the moves green or amber by which way is better; false draws them in the plain text colour (Effort).
    var directional = true
    var height: CGFloat = 270

    private func format(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    /// "29" over "Sep", the label under every stretch at every range.
    static func dayOverMonth(_ d: Date) -> String {
        let m = DateFormatter(); m.locale = AppLanguage.activeLocale; m.setLocalizedDateFormatFromTemplate("MMM")
        return String(Calendar.current.component(.day, from: d)) + "\n" + m.string(from: d)
    }

    private struct Bucket { let start: Date; let end: Date; let values: [Double] }

    private var buckets: [Bucket] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let cal = Calendar.current
        let days = last.timeIntervalSince(first) / 86400
        if days <= 8 {
            return points.map { Bucket(start: $0.date, end: $0.date, values: [$0.value]) }
        }
        let groups: [[(date: Date, value: Double)]]
        let minCount: Int
        if days <= 40 {
            minCount = 3
            let byWeek = Dictionary(grouping: points) { Int((last.timeIntervalSince($0.date) / 86400 / 7).rounded(.down)) }
            groups = byWeek.keys.sorted(by: >).map { byWeek[$0]!.sorted { $0.date < $1.date } }
        } else {
            minCount = 7
            let byMonth = Dictionary(grouping: points) { cal.dateComponents([.year, .month], from: $0.date) }
            groups = byMonth.values.map { $0.sorted { $0.date < $1.date } }.sorted { ($0.first?.date ?? .distantPast) < ($1.first?.date ?? .distantPast) }
        }
        return groups.compactMap { g in
            guard g.count >= minCount, let a = g.first?.date, let b = g.last?.date else { return nil }
            return Bucket(start: a, end: b, values: g.map(\.value))
        }
    }

    private func segments(_ buckets: [Bucket]) -> [TrendSegmentAverage] {
        var out: [TrendSegmentAverage] = []
        var prev: Double?
        for b in buckets {
            let avg = b.values.reduce(0, +) / Double(b.values.count)
            var delta: String?
            var deltaColor = NunaPalette.textPrimary
            // With many stretches (a year) the percentages would run into each other, so only the averages are written.
            if buckets.count <= 8, let p = prev, p != 0 {
                let pct = (avg - p) / abs(p) * 100
                delta = String(format: "%+.0f%%", locale: AppLanguage.activeLocale, pct)
                if directional { deltaColor = (pct >= 0) == higherIsBetter ? NunaPalette.charge : NunaPalette.warning }
            }
            // A single-day stretch is drawn as a short mark centred on its day.
            let single = b.start == b.end
            let from = single ? b.start.addingTimeInterval(-0.3 * 86400) : b.start
            let to = single ? b.end.addingTimeInterval(0.3 * 86400) : b.end
            out.append(TrendSegmentAverage(start: from, end: to, value: avg, valueText: format(avg), deltaText: delta, deltaColor: deltaColor))
            prev = avg
        }
        return out
    }

    var body: some View {
        let vals = points.map(\.value)
        if vals.count >= 2, let lo = vals.min(), let hi = vals.max() {
            let bs = buckets
            let floor = min(lo, band?.lowerBound ?? lo), ceil = max(hi, band?.upperBound ?? hi)
            let pad = max((ceil - floor) * 0.2, 1)
            VStack(alignment: .leading, spacing: 8) {
                if band != nil {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.textSecondary.opacity(0.35)).frame(width: 9, height: 9)
                        Text("Typical range").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                TrendChart(
                    points: points.map { TrendPoint(date: $0.date, value: $0.value) },
                    gradient: Gradient(colors: [color, color]),
                    valueRange: (floor - pad * 0.6)...(ceil + pad * 1.6),
                    showsArea: false,
                    showsPointValues: false,
                    height: height,
                    valueFormat: { format($0) },
                    dateFormat: { TrendChart.defaultDateString($0) },
                    xAxisDateFormat: { Self.dayOverMonth($0) }
                )
                .typicalRange(band)
                .withoutPoints()
                .axisLine()
                .line(width: 1.2, opacity: 0.6)
                .segmentAverages(segments(bs))
                .perReadingAxis(bs.map(\.start))
            }
        } else {
            Text(vals.count == 1 ? "Not enough data yet" : "No data in this period")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}
#endif
