#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// One "Weekly trends" card: a title with a chevron, then the seven days ending on the day shown, drawn bare. Nothing but the figures: a few
/// hairlines, a value above each reading, and the weekday and date under it, with the last day lifted on a lighter column. A line with
/// rings for the vitals, bars for a score. The whole card opens that metric's own page.
struct NunaWeeklyTrendCard: View {
    enum Style { case line, bars }

    let title: LocalizedStringKey
    let key: String
    var source = "my-whoop"
    let style: Style
    var decimals = 0
    /// Shown with a sign (skin temperature is a deviation from the wearer's usual).
    var signed = false
    let color: Color
    /// The colour of the figures over the readings, when it should differ from the drawing's own.
    var labelColor: Color?
    /// Per reading (and whether it is the last day): the fill of a bar and the colour of its figure, for a score whose colour follows its value.
    var barFill: ((Double, Bool) -> Color)?
    var labelFill: ((Double, Bool) -> Color)?
    /// Opens this screen instead of the metric's own page.
    var destination: (() -> AnyView)?
    /// Daily values the caller already has (the minutes in a heart-rate zone, which is not a stored series); nil reads the stored series `key`.
    var points: [(day: String, value: Double)]?
    /// How a reading is written over its point or bar, when not with `decimals`.
    var valueText: ((Double) -> String)?
    /// Bars scaled to the tallest in view instead of 0 to 100 (minutes, not a score).
    var autoScale = false
    /// 0 for the week that ends today; the day picked on Today moves it.
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSeriesModel()

    private let plotHeight: CGFloat = 148
    private let labelHeight: CGFloat = 44

    var body: some View {
        let card = NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                NunaTitleRow(title: title) {
                    Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                }
                chart
            }
        }
        Group {
            if let destination {
                NavigationLink { destination() } label: { card }.buttonStyle(.plain)
            } else if let metric = MetricCatalog.metric(key: key, source: source) {
                NavigationLink(value: NunaTodayRoute.metric(metric)) { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
        .task(id: "\(repo.refreshSeq)-\(points.map { $0.reduce(0) { $0 + $1.value } } ?? -1)") {
            if let points { model.set(points) } else { await model.load(repo: repo, key: key, source: source, days: 60) }
        }
    }

    private var slots: [(date: Date, value: Double?)] { model.window(7, endingDaysAgo: endingDaysAgo) }

    private func text(_ v: Double) -> String {
        valueText?(v) ?? (signed ? nunaSigned(v, decimals) : String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v))
    }

    @ViewBuilder private var chart: some View {
        let s = slots
        if model.loaded && s.allSatisfy({ $0.value == nil }) {
            Text("No readings in this week yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .frame(maxWidth: .infinity, minHeight: plotHeight + labelHeight, alignment: .center)
        } else {
            VStack(spacing: 6) {
                plot(s).frame(height: plotHeight)
                HStack(spacing: 0) {
                    ForEach(Array(s.enumerated()), id: \.offset) { i, slot in dayLabel(slot.date, last: i == s.count - 1) }
                }
                .frame(height: labelHeight)
            }
            .background(highlight)
        }
    }

    /// The last day sits on a lighter column that reaches from the top of the plot down through its label.
    private var highlight: some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NunaPalette.glassStrong.opacity(0.55))
                .frame(width: g.size.width / 7 - 4, height: g.size.height)
                .offset(x: g.size.width * 6 / 7 + 2)
        }
    }

    private func dayLabel(_ date: Date, last: Bool) -> some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(spacing: 2) {
            Text(verbatim: f.string(from: date)).font(.nuna(size: 13, weight: last ? .heavy : .semibold))
            Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.nuna(size: 13, weight: last ? .heavy : .semibold))
        }
        .foregroundStyle(last ? NunaPalette.textPrimary : NunaPalette.textSecondary)
        .frame(maxWidth: .infinity)
    }

    private func plot(_ s: [(date: Date, value: Double?)]) -> some View {
        NunaWeeklyPlot(values: s.map(\.value), style: style, autoScale: autoScale, fill: barFill ?? { _, _ in color }, labelColor: labelFill ?? { _, _ in labelColor ?? color },
                       lineColor: color, label: text)
    }
}

/// The plot of a weekly card: seven columns, hairlines, and either a line with rings or bars, a value over each reading.
private struct NunaWeeklyPlot: View {
    let values: [Double?]
    let style: NunaWeeklyTrendCard.Style
    let autoScale: Bool
    let fill: (Double, Bool) -> Color
    let labelColor: (Double, Bool) -> Color
    let lineColor: Color
    let label: (Double) -> String

    private var present: [Double] { values.compactMap { $0 } }

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack(alignment: .topLeading) {
                grid(size)
                if style == .line {
                    areaShape(size).fill(LinearGradient(colors: [lineColor.opacity(0.22), lineColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    lineShape(size).stroke(lineColor.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                marks(size)
            }
        }
    }

    private func x(_ i: Int, _ size: CGSize) -> CGFloat { size.width / 7 * (CGFloat(i) + 0.5) }

    /// A line keeps its points between the labels' room and the baseline; bars stand on a 0 to 100 scale.
    private func y(_ v: Double, _ size: CGSize) -> CGFloat {
        let h = size.height
        if style == .bars {
            let top = autoScale ? max(present.max() ?? 1, 1) : 100
            return h - h * 0.84 * CGFloat(min(max(v, 0), top) / top)
        }
        let lo = present.min() ?? 0, hi = present.max() ?? 1
        let t: Double = hi - lo < 0.0001 ? 0.5 : (v - lo) / (hi - lo)
        return h * (0.76 - 0.50 * CGFloat(t))
    }

    private func grid(_ size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let atBottom = i == 3
                Rectangle().fill(NunaPalette.hairline.opacity(atBottom ? 1 : 0.55)).frame(height: 1)
                    .position(x: size.width / 2, y: atBottom ? size.height - 0.5 : size.height * CGFloat(i) / 3 + 0.5)
            }
        }
    }

    /// The line, broken where a day has no reading.
    private func lineShape(_ size: CGSize) -> Path {
        var p = Path()
        var open = false
        for (i, value) in values.enumerated() {
            guard let v = value else { open = false; continue }
            let pt = CGPoint(x: x(i, size), y: y(v, size))
            if open { p.addLine(to: pt) } else { p.move(to: pt); open = true }
        }
        return p
    }

    /// A faint wash under each unbroken stretch of the line.
    private func areaShape(_ size: CGSize) -> Path {
        var p = Path()
        var run: [CGPoint] = []
        func close() {
            if run.count >= 2, let first = run.first, let last = run.last {
                p.move(to: CGPoint(x: first.x, y: size.height)); p.addLine(to: first)
                for pt in run.dropFirst() { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: last.x, y: size.height)); p.closeSubpath()
            }
            run = []
        }
        for (i, value) in values.enumerated() {
            if let v = value { run.append(CGPoint(x: x(i, size), y: y(v, size))) } else { close() }
        }
        close()
        return p
    }

    /// A reading lower than the days on either side of it.
    private func isLow(_ i: Int, _ v: Double) -> Bool {
        let before = i > 0 ? values[i - 1] : nil
        let after = i + 1 < values.count ? values[i + 1] : nil
        guard before != nil || after != nil else { return false }
        return v < (before ?? .infinity) && v < (after ?? .infinity)
    }

    private func marks(_ size: CGSize) -> some View {
        ZStack {
            ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                if let v = value { mark(i, v, size) }
            }
        }
    }

    @ViewBuilder private func mark(_ i: Int, _ v: Double, _ size: CGSize) -> some View {
        let top = y(v, size)
        let cx = x(i, size)
        let isLast = i == values.count - 1
        if style == .bars {
            let barHeight = max(2, size.height - top)
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3, style: .continuous)
                .fill(fill(v, isLast)).frame(width: size.width / 7 * 0.36, height: barHeight).position(x: cx, y: top + barHeight / 2)
        } else {
            Circle().fill(NunaPalette.canvas).overlay(Circle().strokeBorder(lineColor, lineWidth: 2.5)).frame(width: 11, height: 11).position(x: cx, y: top)
        }
        // The figure sits above its point, and under it at a low point, where the line comes in from both sides.
        let below = style == .line && isLow(i, v) && top + 19 < size.height - 6
        Text(verbatim: label(v)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(labelColor(v, isLast))
            .fixedSize().position(x: cx, y: below ? top + 17 : max(9, top - 17))
    }
}

/// A weekly card for time in heart-rate zones: each day one bar stacked by zone in the zone's own colour, the total over it as h:mm, and a
/// key of the zones in the corner. A day with no time in these zones shows 0:00 on the baseline.
struct NunaZoneWeeklyCard: View {
    let title: LocalizedStringKey
    /// Which of the five zones this card stacks (0 is Zone 1).
    let zones: [Int]
    /// Minutes per zone for each day key.
    let byDay: [String: [Double]]
    var endingDaysAgo = 0
    var destination: (() -> AnyView)?

    private let plotHeight: CGFloat = 148
    private let labelHeight: CGFloat = 44

    /// Zone 1 to 5, soft: grey-blue, blue, teal, then light and deep orange for the hard zones.
    fileprivate static func color(_ zone: Int) -> Color {
        [Color(hex: "#A9BAC6"), Color(hex: "#4A9FC8"), Color(hex: "#5BB89A"), Color(hex: "#F5A860"), Color(hex: "#F26B2D")][min(max(zone, 0), 4)]
    }

    private var slots: [(date: Date, minutes: [Double]?)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -(i + endingDaysAgo), to: today) ?? today
            let all = byDay[Repository.localDayKey(d)]
            return (d, all.map { m in zones.map { m[$0] } })
        }
    }

    var body: some View {
        let card = NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                NunaTitleRow(title: title) {
                    Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                }
                legend
                chart
            }
        }
        if let destination {
            NavigationLink { destination() } label: { card }.buttonStyle(.plain)
        } else { card }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            ForEach(zones, id: \.self) { z in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaZoneWeeklyCard.color(z)).frame(width: 12, height: 12)
                    Text("Zone \(z + 1)").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary)
                }
            }
        }
    }

    private var chart: some View {
        let s = slots
        return VStack(spacing: 6) {
            NunaZonePlot(days: s.map(\.minutes), colors: zones.map { Self.color($0) }).frame(height: plotHeight)
            HStack(spacing: 0) {
                ForEach(Array(s.enumerated()), id: \.offset) { i, slot in label(slot.date, last: i == s.count - 1) }
            }
            .frame(height: labelHeight)
        }
        .background(GeometryReader { g in
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NunaPalette.glassStrong.opacity(0.55))
                .frame(width: g.size.width / 7 - 4, height: g.size.height).offset(x: g.size.width * 6 / 7 + 2)
        })
    }

    private func label(_ date: Date, last: Bool) -> some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(spacing: 2) {
            Text(verbatim: f.string(from: date)).font(.nuna(size: 13, weight: last ? .heavy : .semibold))
            Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.nuna(size: 13, weight: last ? .heavy : .semibold))
        }
        .foregroundStyle(last ? NunaPalette.textPrimary : NunaPalette.textSecondary)
        .frame(maxWidth: .infinity)
    }
}

struct NunaZonePlot: View {
    /// Minutes in each stacked part for each of the seven days; nil where nothing was recorded.
    let days: [[Double]?]
    /// The colour of each part, the first at the bottom of a bar.
    let colors: [Color]

    private func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let totals = days.map { $0?.reduce(0, +) ?? 0 }
            let top = max((totals.max() ?? 0) * 1.15, 30)
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { i in
                    let atBottom = i == 3
                    Rectangle().fill(NunaPalette.hairline.opacity(atBottom ? 1 : 0.55)).frame(height: 1)
                        .position(x: size.width / 2, y: atBottom ? size.height - 0.5 : size.height * CGFloat(i) / 3 + 0.5)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { i, minutes in
                    if let minutes { column(i, minutes, total: totals[i], top: top, size: size) }
                }
            }
        }
    }

    @ViewBuilder private func column(_ i: Int, _ minutes: [Double], total: Double, top: Double, size: CGSize) -> some View {
        let cx = size.width / 7 * (CGFloat(i) + 0.5)
        let usable = size.height * 0.84
        let barHeight = usable * CGFloat(total / top)
        let width = size.width / 7 * 0.36
        VStack(spacing: 1) {
            ForEach(Array(colors.enumerated().reversed()), id: \.offset) { k, color in
                if k < minutes.count, minutes[k] > 0 {
                    Rectangle().fill(color).frame(height: max(1.5, usable * CGFloat(minutes[k] / top)))
                }
            }
        }
        .frame(width: width, height: barHeight, alignment: .bottom)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3, style: .continuous))
        .position(x: cx, y: size.height - barHeight / 2)
        Text(verbatim: hm(total)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            .fixedSize().position(x: cx, y: max(9, size.height - barHeight - 14))
    }
}
#endif
