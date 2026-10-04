#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Header with the white Anya button

struct NunaDetailHeader: View {
    let title: LocalizedStringKey
    var onAnya: (() -> Void)?
    /// Extra control at the trailing edge (for example a "Today" chip), shown when there is no Anya button.
    var trailing: AnyView?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(NunaPalette.glassStrong, in: Circle())
                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }
            .accessibilityLabel(Text("Back"))
            Text(title).font(.system(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            if let trailing { trailing }
            if let onAnya {
                Button(action: onAnya) {
                    Image(systemName: "sparkles").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(NunaPalette.onAccent)
                        .frame(width: 44, height: 44).background(NunaPalette.accent, in: Circle())
                }
                .accessibilityLabel(Text("Ask Anya"))
            }
        }
    }
}

/// Header + scroll + background for the Today detail screens.
struct NunaDetailScreen<Content: View>: View {
    let title: LocalizedStringKey
    var onAnya: (() -> Void)?
    var trailing: AnyView?
    let content: Content
    init(_ title: LocalizedStringKey, onAnya: (() -> Void)? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.onAnya = onAnya; self.trailing = trailing; self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaDetailHeader(title: title, onAnya: onAnya, trailing: trailing)
                content
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Hero card

struct NunaHeroCard<Footer: View>: View {
    let caption: LocalizedStringKey
    var chip: LocalizedStringKey?
    var chipColor: Color?
    let number: String
    var unit: String = ""
    var suffix: String = ""
    let color: Color
    let footer: Footer

    init(caption: LocalizedStringKey, chip: LocalizedStringKey? = nil, chipColor: Color? = nil, number: String,
         unit: String = "", suffix: String = "", color: Color, @ViewBuilder footer: () -> Footer) {
        self.caption = caption; self.chip = chip; self.chipColor = chipColor; self.number = number
        self.unit = unit; self.suffix = suffix; self.color = color; self.footer = footer()
    }

    var body: some View {
        NunaCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(caption).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let chip { NunaChip(chip, color: chipColor) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: number)
                        .font(.system(size: 72, weight: .bold, design: NunaType.design))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.system(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if !suffix.isEmpty {
                        Text(verbatim: suffix).font(.system(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                footer
            }
        }
    }
}

extension NunaHeroCard where Footer == EmptyView {
    init(caption: LocalizedStringKey, chip: LocalizedStringKey? = nil, chipColor: Color? = nil, number: String,
         unit: String = "", suffix: String = "", color: Color) {
        self.init(caption: caption, chip: chip, chipColor: chipColor, number: number, unit: unit, suffix: suffix,
                  color: color) { EmptyView() }
    }
}

// MARK: - Gauge hero card

/// Top card of the Charge and Effort screens: caption and status chip, a ring gauge with the score inside,
/// and a short note beside it.
struct NunaGaugeHeroCard<Note: View>: View {
    let caption: LocalizedStringKey
    var chip: LocalizedStringKey?
    var chipColor: Color?
    let fraction: Double
    let number: String
    var unit: String = ""
    var suffix: String = ""
    let color: Color
    let note: Note

    init(caption: LocalizedStringKey, chip: LocalizedStringKey? = nil, chipColor: Color? = nil, fraction: Double,
         number: String, unit: String = "", suffix: String = "", color: Color, @ViewBuilder note: () -> Note) {
        self.caption = caption; self.chip = chip; self.chipColor = chipColor; self.fraction = fraction
        self.number = number; self.unit = unit; self.suffix = suffix; self.color = color; self.note = note()
    }

    var body: some View {
        NunaCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(caption).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let chip { NunaChip(chip, color: chipColor) }
                }
                HStack(spacing: 20) {
                    NunaRingGauge(fraction: fraction, color: color, size: 128, lineWidth: 12) {
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text(verbatim: number).font(.system(size: 34, weight: .bold, design: NunaType.design))
                                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                                if !unit.isEmpty && number != "–" {
                                    Text(verbatim: unit).font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                            }
                            if !suffix.isEmpty {
                                Text(verbatim: suffix).font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                    }
                    note
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Collapsible "How it's calculated" row

struct NunaExpandRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var systemImage = "sparkles"
    let text: LocalizedStringKey
    @State private var open = false

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(spacing: 12) {
                        NunaIconTile(systemImage)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(subtitle).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NunaPalette.textMuted).rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                if open {
                    Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Charts

/// Charge zone colour: green 67+, yellow 34 to 66, red 0 to 33.
func nunaChargeColor(_ v: Double) -> Color {
    v >= 67 ? NunaPalette.charge : (v >= 34 ? NunaPalette.warning : NunaPalette.alert)
}

/// "5 Okt"-style date for chart axes (day and month, in the app language).
func nunaAxisDate(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM")
    return f.string(from: d)
}

/// Start, middle and end dates under a chart, each with day and month.
struct NunaDateAxis: View {
    let dates: [Date]
    var body: some View {
        if let first = dates.first, let last = dates.last {
            HStack {
                Text(verbatim: nunaAxisDate(first))
                Spacer()
                if dates.count > 4 { Text(verbatim: nunaAxisDate(dates[dates.count / 2])); Spacer() }
                Text(verbatim: nunaAxisDate(last))
            }
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

/// Rounded vertical bars, one per day. Real values are written above the bars (every bar up to 14 days,
/// otherwise the highest and the latest), and the dates sit underneath.
struct NunaColorBars: View {
    let values: [Double?]
    let dates: [Date]
    let maxValue: Double
    let color: (Double) -> Color
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var height: CGFloat = 130

    var body: some View {
        let present = values.compactMap { $0 }
        let topIdx = values.indices.max(by: { (values[$0] ?? -1) < (values[$1] ?? -1) })
        let lastIdx = values.indices.last(where: { values[$0] != nil })
        let dense = values.count > 14
        let spread = values.count <= 14
        VStack(spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = values.count > 40 ? 2 : 5
                let cell = geo.size.width / CGFloat(max(values.count, 1))
                let w = spread ? min(30, max(8, cell - 6))
                               : min(28, max(2, (geo.size.width - gap * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1))))
                let barMax = height - 16
                HStack(alignment: .bottom, spacing: spread ? 0 : gap) {
                    ForEach(values.indices, id: \.self) { i in
                        VStack(spacing: 2) {
                            if let v = values[i], !dense || i == topIdx || i == lastIdx {
                                Text(verbatim: format(v)).font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(NunaPalette.textSecondary).fixedSize().frame(width: w)
                                    // keep the last label inside the card
                                    .offset(x: (dense && i >= values.count - 2) ? -8 : 0)
                            } else { Color.clear.frame(width: w, height: 12) }
                            if let v = values[i] {
                                RoundedRectangle(cornerRadius: min(5, w / 2), style: .continuous).fill(color(v))
                                    .frame(width: w, height: max(5, barMax * CGFloat(min(max(v / maxValue, 0), 1))))
                            } else {
                                RoundedRectangle(cornerRadius: min(5, w / 2), style: .continuous).fill(NunaPalette.ink.opacity(0.06))
                                    .frame(width: w, height: 5)
                            }
                        }
                        .frame(width: spread ? cell : nil)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .overlay {
                    if present.isEmpty {
                        Text("No data in this period").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
            .frame(height: height)
            if values.count <= 7, dates.count == values.count {
                HStack(spacing: 0) {
                    ForEach(dates.indices, id: \.self) { i in
                        Text(verbatim: nunaAxisDate(dates[i])).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                    }
                }
            } else if !dates.isEmpty { NunaDateAxis(dates: dates) }
        }
        .accessibilityHidden(true)
    }
}

/// Tall capsule columns for a week, one per day, with the real value above and weekday plus date below.
struct NunaColumns: View {
    struct Item: Identifiable {
        let id = UUID(); let weekday: String; let date: Date; let fraction: Double?; let valueText: String?
        var highlight = false
        /// Overrides the column colour (Charge uses its three zones).
        var color: Color?
    }
    let items: [Item]
    let color: Color
    var highlightColor: Color?
    var showsDates = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(items) { item in
                VStack(spacing: 6) {
                    Text(verbatim: item.valueText ?? "–").font(.system(size: 10.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(item.highlight ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(NunaPalette.ink.opacity(0.08)).frame(width: 30, height: 110)
                        Capsule().fill(item.color ?? (item.highlight ? (highlightColor ?? color) : color))
                            .frame(width: 30, height: max(14, 110 * CGFloat(min(max(item.fraction ?? 0, 0), 1))))
                            .opacity(item.fraction == nil ? 0 : 1)
                    }
                    VStack(spacing: 1) {
                        Text(verbatim: item.weekday).font(.system(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textPrimary.opacity(item.highlight ? 1 : 0.8))
                        if showsDates {
                            Text(verbatim: nunaAxisDate(item.date)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// NOOP's own "Line2" trend chart (`TrendChart`): a clean line with a labelled point per reading while
/// there are 60 or fewer, month-over-day labels on the axis, and a dashed personal baseline. Every value
/// drawn is a stored reading; days without one are simply absent from the line.
struct NunaLine2Chart: View {
    let points: [(date: Date, value: Double)]
    var color: Color = NunaPalette.textPrimary
    var decimals = 0
    var baseline: Double?
    var height: CGFloat = 190

    var body: some View {
        let vals = points.map(\.value)
        if vals.count >= 2, let lo = vals.min(), let hi = vals.max() {
            let pad = max((hi - lo) * 0.15, 0.5)
            TrendChart(
                points: points.map { TrendPoint(date: $0.date, value: $0.value) },
                gradient: Gradient(colors: [color, color]),
                valueRange: (lo - pad)...(hi + pad * 1.6),
                showsArea: false,
                showsPointValues: true,
                baselineValue: baseline,
                height: height,
                valueFormat: { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, $0) },
                dateFormat: { TrendChart.defaultDateString($0) },
                xAxisDateFormat: { TrendChart.line2AxisDateString($0) }
            )
            .pointValueStride(max(1, Int((Double(vals.count) / 12).rounded(.up))))
        } else {
            Text(vals.count == 1 ? "Not enough data yet" : "No data in this period")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}

// MARK: - Stress bars (one bar per timeline point, coloured by stress band)

struct NunaStressBars: View {
    let points: [DaytimeStress.HourPoint]
    var height: CGFloat = 96

    static func color(_ level: Double) -> Color {
        level < 1 ? NunaPalette.charge : (level < 2 ? NunaPalette.warning : NunaPalette.alert)
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = points.count > 30 ? 2 : 3
            let w = min(22, max(2, (geo.size.width - gap * CGFloat(max(points.count - 1, 0))) / CGFloat(max(points.count, 1))))
            ZStack(alignment: .bottomLeading) {
                // The Medium and High thresholds, as in the mockup's dashed guides.
                ForEach([1.0, 2.0], id: \.self) { lvl in
                    Path { p in
                        let y = geo.size.height * CGFloat(1 - lvl / 3)
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(NunaPalette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(points.indices, id: \.self) { i in
                        if let l = points[i].level {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.color(l).opacity(l < 1 ? 0.85 : 0.95))
                                .frame(width: w, height: max(5, geo.size.height * CGFloat(min(l, 3) / 3)))
                        } else {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaPalette.ink.opacity(points[i].maskedForActivity ? 0.14 : 0.05))
                                .frame(width: w, height: 5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Series helper

/// One metric's daily values over the last `days` days (oldest first), nil where missing.
@MainActor
final class NunaSeriesModel: ObservableObject {
    @Published private(set) var byDay: [String: Double] = [:]
    @Published private(set) var loaded = false

    /// `also` is a second source merged on top (a value typed in by hand wins over the imported one for that day).
    func load(repo: Repository, key: String, source: String, days: Int = 130, also: String? = nil) async {
        let s = await repo.exploreSeries(key: key, source: source, days: days)
        var map = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        if let also {
            for r in await repo.exploreSeries(key: key, source: also, days: days) { map[r.day] = r.value }
        }
        byDay = map
        loaded = true
    }

    /// Slots for the last `days` calendar days ending today.
    func window(_ days: Int) -> [(date: Date, value: Double?)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<days).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today) ?? today
            return (d, byDay[Repository.localDayKey(d)])
        }
    }

    /// Real readings in the last `days` days, oldest first (days without a reading are left out).
    func readings(_ days: Int) -> [(date: Date, value: Double)] {
        window(days).compactMap { s in s.value.map { (s.date, $0) } }
    }

    var latest: (day: String, value: Double)? {
        guard let k = byDay.keys.sorted().last, let v = byDay[k] else { return nil }
        return (k, v)
    }

    /// Mean of the readings in the last `days` days, leaving out the latest reading itself.
    func average(days: Int) -> Double? {
        let latestKey = latest?.day
        let v = window(days + 1).compactMap { s -> Double? in
            guard let val = s.value, Repository.localDayKey(s.date) != latestKey else { return nil }
            return val
        }
        return v.count >= 3 ? v.reduce(0, +) / Double(v.count) : nil
    }

    /// Mean, spread and extremes of the last 30 readings before the latest one.
    var band: (mean: Double, sd: Double, lo: Double, hi: Double)? {
        let v = byDay.keys.sorted().dropLast().suffix(30).compactMap { byDay[$0] }
        guard v.count >= 5 else { return nil }
        let m = v.reduce(0, +) / Double(v.count)
        let sd = (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
        return (m, sd, v.min() ?? m, v.max() ?? m)
    }

    /// Mean of the last 30 days that have a value, excluding the latest one.
    var baseline: Double? {
        let keys = byDay.keys.sorted().dropLast().suffix(30)
        let v = keys.compactMap { byDay[$0] }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}
#endif
