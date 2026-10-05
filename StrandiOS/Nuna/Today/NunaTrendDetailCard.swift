#if os(iOS)
import SwiftUI
import StrandDesign

/// The one card of a metric detail screen: the latest reading at the top left, the W / M / 6M switch and the date
/// stepper at the top right, a sentence about the period, the chart, and the average, lowest and highest as plain text.
/// Every figure is computed from the stored readings of the window the wearer is looking at.
struct NunaTrendDetailCard: View {
    let caption: LocalizedStringKey
    /// The big figure. Nil with `averageHero` shows the average of the window instead (the Trends screens).
    var valueText: String?
    var unit = ""
    var chip: (text: LocalizedStringKey, color: Color)?
    var note: String?
    /// Readings of `days` days ending `endingDaysAgo` days before today, oldest first.
    let readings: (_ days: Int, _ endingDaysAgo: Int) -> [(date: Date, value: Double)]
    /// Whether anything older than this date is stored, so the back arrow knows when to stop.
    let hasOlder: (_ windowStart: Date) -> Bool
    var loaded = true
    var band: ClosedRange<Double>?
    var reference: Double?
    var lineColor: Color = NunaPalette.charge
    var decimals = 0
    var higherIsBetter = true
    var directional = true
    var averageHero = false
    var levelChip: ((Double) -> (text: LocalizedStringKey, color: Color)?)?
    /// Replaces the generic sentence about the period (average and the average before it).
    var sentence: ((_ avg: Double?, _ prev: Double?) -> String?)?
    @Binding var range: Int
    @Binding var page: Int

    private static let ranges: [(value: Int, title: String)] = [(7, "W"), (30, "M"), (180, "6M")]

    /// The card for a single stored series (`NunaSeriesModel`).
    init(caption: LocalizedStringKey, valueText: String?, unit: String = "", chip: (text: LocalizedStringKey, color: Color)? = nil, note: String? = nil,
         series: NunaSeriesModel, showsBand: Bool = true, reference: Double? = nil, lineColor: Color = NunaPalette.charge, decimals: Int = 0,
         higherIsBetter: Bool = true, directional: Bool = true, range: Binding<Int>, page: Binding<Int>) {
        self.caption = caption; self.valueText = valueText; self.unit = unit; self.chip = chip; self.note = note
        self.readings = { series.readings($0, endingDaysAgo: $1) }
        self.hasOlder = { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false }
        self.loaded = series.loaded
        self.band = showsBand ? series.band.map { $0.lo...$0.hi } : nil
        self.reference = reference; self.lineColor = lineColor; self.decimals = decimals
        self.higherIsBetter = higherIsBetter; self.directional = directional
        self._range = range; self._page = page
    }

    /// The card for the Trends screens, which hold their own daily series.
    init(caption: LocalizedStringKey, unit: String = "", readings: @escaping (Int, Int) -> [(date: Date, value: Double)],
         hasOlder: @escaping (Date) -> Bool, lineColor: Color, decimals: Int, directional: Bool,
         levelChip: ((Double) -> (text: LocalizedStringKey, color: Color)?)?, sentence: ((Double?, Double?) -> String?)?,
         range: Binding<Int>, page: Binding<Int>) {
        self.caption = caption; self.valueText = nil; self.unit = unit
        self.readings = readings; self.hasOlder = hasOlder
        self.lineColor = lineColor; self.decimals = decimals; self.directional = directional
        self.averageHero = true; self.levelChip = levelChip; self.sentence = sentence
        self._range = range; self._page = page
    }

    private func fmt(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    private var windowEnd: Date { Calendar.current.date(byAdding: .day, value: -page * range, to: Date()) ?? Date() }
    private var windowStart: Date { Calendar.current.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }
    private var canGoBack: Bool { hasOlder(windowStart) }

    private var dateLabel: String {
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("d MMM")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("d MMM yy")
        return "\(a.string(from: windowStart)) – \(b.string(from: windowEnd))"
    }

    private func average(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    var body: some View {
        let pts = readings(range, page * range)
        let vals = pts.map(\.value)
        let avg = average(vals)
        let prev = average(readings(range, (page + 1) * range).map(\.value))
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                header(avg: avg, prev: prev)
                if let s = (sentence?(avg, prev)) ?? summary(avg: avg, prev: prev) {
                    Text(verbatim: s).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pts.isEmpty {
                    Text(loaded ? "No data in this period" : " ").font(.nuna(size: 14, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    NunaSegmentedChart(points: pts, color: lineColor, decimals: decimals, band: band, reference: reference,
                                       higherIsBetter: higherIsBetter, directional: directional)
                }
                if let avg, let lo = vals.min(), let hi = vals.max() {
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        stat("Average", fmt(avg)); stat("Lowest", fmt(lo)); stat("Highest", fmt(hi))
                    }
                }
            }
        }
    }

    private func header(avg: Double?, prev: Double?) -> some View {
        let shownValue: String = averageHero ? (avg.map(fmt) ?? "–") : (valueText ?? "–")
        let shownChip: (text: LocalizedStringKey, color: Color)? = averageHero ? avg.flatMap { levelChip?($0) } : chip
        let shownNote: String? = averageHero ? prev.map { String(localized: "Previous period \(fmt($0))\(unit)") } : note
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shownValue).font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let shownChip { NunaChip(shownChip.text, color: shownChip.color) }
                if let shownNote {
                    Text(verbatim: shownNote).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
    /// A dashed reference line (a weight target).
    var reference: Double?
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
        // A series with fewer than a reading every other day (weight) keeps every stretch that has a reading; a dense one
        // leaves out a stretch with only a few days in it, which would be a cramped mark at the edge.
        let sparse = Double(points.count) < max(days, 1) / 2
        if days <= 40 {
            minCount = sparse ? 1 : 3
            let byWeek = Dictionary(grouping: points) { Int((last.timeIntervalSince($0.date) / 86400 / 7).rounded(.down)) }
            groups = byWeek.keys.sorted(by: >).map { byWeek[$0]!.sorted { $0.date < $1.date } }
        } else {
            minCount = sparse ? 1 : 7
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
                delta = pct.rounded() == 0 ? "0%" : String(format: "%+.0f%%", locale: AppLanguage.activeLocale, pct)
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
                    valueRange: (min(floor, reference ?? floor) - pad * 0.6)...(max(ceil, reference ?? ceil) + pad * 1.6),
                    showsArea: false,
                    showsPointValues: false,
                    baselineValue: reference,
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
