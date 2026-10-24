#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Charts

typealias NunaDaySeries = [(day: String, value: Double)]

enum NunaDayFormat {
    static let parser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    static func parse(_ s: String) -> Date? { parser.date(from: s) }
}

/// The Trends chart. It is drawn the way `TrendChart` draws every other line in the app (Swift Charts, a smoothed 2.5 pt
/// round line, a dot per reading, hairline grid with the scale on the left, dates underneath) and the bars are rounded like
/// the other bar charts, so a line or a bar looks the same here as on Today, Health and Sleep. Each series is scaled by its own
/// maximum onto 0 to 100. Every mark is a stored reading; a day without one has no bar and the line skips it.
struct NunaTrendChart: View {
    struct Series: Identifiable {
        let id = UUID()
        let points: NunaDaySeries
        let max: Double
        let color: Color
        var bars = false
        /// Colours each day's dot by its value, the way the ring would be coloured that day; nil keeps `color`.
        var pointColor: ((Double) -> Color)? = nil
        var dashed = false
    }
    let start: String
    let days: Int
    let series: [Series]
    var height: CGFloat = 150
    /// When set, touching or dragging selects a day (yyyy-MM-dd) and draws a dashed guide there.
    var selected: Binding<String?>?

    private var origin: Date { NunaDayFormat.parse(start) ?? Date() }
    private func date(_ day: String) -> Date? { NunaDayFormat.parse(day) }
    private func scaled(_ v: Double, _ s: Series) -> Double { min(max(v / max(s.max, 0.0001), 0), 1) * 100 }
    private var window: ClosedRange<Date> {
        let cal = Calendar(identifier: .gregorian)
        let lo = cal.date(byAdding: .hour, value: -12, to: origin) ?? origin
        let hi = cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: max(days - 1, 0), to: origin) ?? origin) ?? origin
        return lo...hi
    }

    var body: some View {
        GeometryReader { geo in
            let slot = max(geo.size.width - 36, 1) / CGFloat(max(days, 1))
            let barWidth = max(2, min(12, slot * 0.62))
            Chart {
                // The bottom edge of the plot, drawn solid so the chart area is plainly bounded above the dates.
                RuleMark(y: .value("Axis", 0)).lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(NunaPalette.hairline)
                ForEach(series) { s in
                    if s.bars {
                        ForEach(s.points, id: \.day) { p in
                            if let d = date(p.day) {
                                BarMark(x: .value("Day", d, unit: .day), y: .value("Value", scaled(p.value, s)), width: .fixed(barWidth))
                                    .cornerRadius(min(4, barWidth / 2))
                                    .foregroundStyle(s.color.opacity(selected?.wrappedValue == nil || selected?.wrappedValue == p.day ? 0.6 : 0.3))
                            }
                        }
                    }
                }
                ForEach(series) { s in
                    if !s.bars {
                        // Fade-out fill under a lone line: the line colour at 35% down to nothing.
                        if series.filter({ !$0.bars }).count == 1, series.allSatisfy({ !$0.bars }) {
                            ForEach(s.points, id: \.day) { p in
                                if let d = date(p.day) {
                                    AreaMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s)), series: .value("Fill", s.id.uuidString))
                                        .interpolationMethod(.catmullRom)
                                        .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.35), s.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                                }
                            }
                        }
                        ForEach(s.points, id: \.day) { p in
                            if let d = date(p.day) {
                                LineMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s)), series: .value("Series", s.id.uuidString))
                                    .interpolationMethod(.catmullRom)
                                    .lineStyle(StrokeStyle(lineWidth: days > 120 ? 1.5 : 2.5, lineCap: .round, lineJoin: .round, dash: s.dashed ? [5, 4] : []))
                                    .foregroundStyle(s.color)
                            }
                        }
                        if s.points.count <= 60 {
                            ForEach(s.points, id: \.day) { p in
                                if let d = date(p.day) {
                                    PointMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s))).symbolSize(s.pointColor == nil ? 18 : 30).foregroundStyle(s.pointColor?(p.value) ?? s.color)
                                }
                            }
                        }
                        if selected?.wrappedValue == nil, let l = s.points.last, let d = date(l.day) {
                            PointMark(x: .value("Day", d), y: .value("Value", scaled(l.value, s))).symbolSize(70).foregroundStyle(NunaPalette.ink)
                        }
                    }
                }
                if let sel = selected?.wrappedValue, let d = date(sel) {
                    RuleMark(x: .value("Day", d)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(NunaPalette.textSecondary)
                    ForEach(series.filter { !$0.bars }) { s in
                        if let p = s.points.first(where: { $0.day == sel }) {
                            PointMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s))).symbolSize(70).foregroundStyle(NunaPalette.ink)
                        }
                    }
                }
            }
            .chartXScale(domain: window)
            // A little air above 100 and below 0: a line that touches the top of the scale, or a dot on it, is drawn whole and not cut at the edge.
            .chartYScale(domain: -3...106)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: tickDates) { value in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.4))
                    AxisTick(length: 5, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(NunaPalette.hairline)
                    if let d = value.as(Date.self) {
                        AxisValueLabel(centered: false, anchor: .top, collisionResolution: .disabled) {
                            Text(verbatim: NunaSegmentedChart.dayOverMonth(d)).multilineTextAlignment(.center).fixedSize()
                        }
                        .offset(y: 8)
                        .foregroundStyle(NunaPalette.textMuted).font(.nuna(size: 11.5, weight: .semibold))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.4))
                    AxisValueLabel().foregroundStyle(NunaPalette.textMuted).font(.nuna(size: 11.5, weight: .semibold))
                }
            }
            .chartOverlay { proxy in
                if selected != nil {
                    GeometryReader { g in
                        // A tap picks a day and a sideways drag moves across them; a vertical swipe is left to the page, so a chart never traps a scroll.
                        let pick: (CGFloat) -> Void = { px in
                            guard let frame = proxy.plotFrame else { return }
                            let x = px - g[frame].origin.x
                            guard let d: Date = proxy.value(atX: x) else { return }
                            let cal = Calendar(identifier: .gregorian)
                            let i = Int((d.timeIntervalSince(origin) / 86400).rounded())
                            guard i >= 0, i < days, let day = cal.date(byAdding: .day, value: i, to: origin) else { return }
                            selected?.wrappedValue = NunaDayFormat.parser.string(from: day)
                        }
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .simultaneousGesture(SpatialTapGesture().onEnded { pick($0.location.x) })
                            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { v in
                                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                                pick(v.location.x)
                            })
                    }
                }
            }
        }
        .frame(height: height + 30)
        .accessibilityHidden(true)
    }

    /// The same labelling as the one-card trend chart: every day for a week, every seventh day (counted back from the
    /// latest) for a month, and the first of each month beyond that.
    private var tickDates: [Date] {
        let cal = Calendar(identifier: .gregorian)
        let all = (0..<max(days, 1)).compactMap { cal.date(byAdding: .day, value: $0, to: origin) }
        if days <= 8 { return all }
        if days <= 40 {
            return all.enumerated().filter { (days - 1 - $0.offset) % 7 == 0 }.map(\.element)
        }
        let firsts = all.filter { cal.component(.day, from: $0) == 1 }
        // Beyond eight months every second one, so the labels never touch.
        return firsts.count > 8 ? firsts.enumerated().filter { (firsts.count - 1 - $0.offset) % 2 == 0 }.map(\.element) : firsts
    }
}

/// Two or more lines on the same 0 to 100 scale (each by its own maximum), for "two lines moving together". A line that has a `title` and a `text` can be
/// read: touching the chart (or dragging along it) selects a day, and that day's figure for every such line is written above it, in the line's own terms.
struct NunaMultiLineChart: View {
    struct Line {
        let series: NunaDaySeries; let max: Double; let color: Color
        var pointColor: ((Double) -> Color)? = nil
        var dashed = false
        /// The name written beside the figure, and how a stored value of this line is written.
        var title: String? = nil
        var text: ((Double) -> String)? = nil
    }
    let start: String
    let days: Int
    let lines: [Line]
    var height: CGFloat = 130
    @State private var selected: String?

    private var readable: [Line] { lines.filter { $0.title != nil && $0.text != nil } }
    private static let readFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !readable.isEmpty { readout }
            NunaTrendChart(start: start, days: days,
                           series: lines.map { .init(points: $0.series, max: $0.max, color: $0.color, pointColor: $0.pointColor, dashed: $0.dashed) },
                           height: height + 24, selected: readable.isEmpty ? nil : $selected)
        }
        .onChange(of: start) { _, _ in selected = nil }
        .onChange(of: days) { _, _ in selected = nil }
    }

    /// The day touched and, on one row, each line's figure for it ("Rest 90%   Charge 45%"); a hint until something is touched.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let day = selected, let d = NunaDayFormat.parse(day) {
                Text(verbatim: Self.readFormat.string(from: d)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(spacing: 18) {
                    ForEach(Array(readable.enumerated()), id: \.offset) { _, line in
                        let value = line.series.first { $0.day == day }?.value
                        HStack(spacing: 6) {
                            Circle().fill(line.color).frame(width: 10, height: 10)
                            Text(verbatim: line.title ?? "").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: value.flatMap { line.text?($0) } ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).monospacedDigit()
                                .foregroundStyle(NunaPalette.textPrimary)
                        }
                        .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Touch the chart to read the figures").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
    }
}

/// A small line in the same style (smoothed 2.5 pt round line) with its newest point marked.
struct NunaSpark: View {
    let values: [Double]
    var color: Color = NunaPalette.ink
    var body: some View {
        if values.count >= 2, let lo = values.min(), let hi = values.max() {
            let pad = max((hi - lo) * 0.12, 0.0001)
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("i", i), y: .value("v", v))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)
                }
                if let last = values.last {
                    PointMark(x: .value("i", values.count - 1), y: .value("v", last)).symbolSize(48).foregroundStyle(NunaPalette.ink)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartPlotStyle { $0.padding(.horizontal, 4) }
            .accessibilityHidden(true)
        }
    }
}

/// One dot per day (x, y) with the straight line the correlation fits. Axis meaning is given by the caption.
struct NunaScatter: View {
    let points: [(x: Double, y: Double)]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    var slope: Double?
    var intercept: Double?
    var color: Color = NunaScoreStyle.chargeSeries
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 10
            func mx(_ v: Double) -> CGFloat { pad + CGFloat((v - xRange.lowerBound) / max(xRange.upperBound - xRange.lowerBound, 0.0001)) * (size.width - pad * 2) }
            func my(_ v: Double) -> CGFloat { size.height - pad - CGFloat((v - yRange.lowerBound) / max(yRange.upperBound - yRange.lowerBound, 0.0001)) * (size.height - pad * 2) }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(NunaPalette.field))
            var grid = Path()
            for i in 1...3 {
                let y = size.height * CGFloat(i) / 4, x = size.width * CGFloat(i) / 4
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(grid, with: .color(NunaPalette.ink.opacity(0.06)), lineWidth: 1)
            if let slope, let intercept {
                var p = Path()
                p.move(to: CGPoint(x: mx(xRange.lowerBound), y: my(slope * xRange.lowerBound + intercept)))
                p.addLine(to: CGPoint(x: mx(xRange.upperBound), y: my(slope * xRange.upperBound + intercept)))
                ctx.stroke(p, with: .color(NunaPalette.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
            for p in points {
                ctx.fill(Path(ellipseIn: CGRect(x: mx(p.x) - 3.5, y: my(p.y) - 3.5, width: 7, height: 7)), with: .color(color.opacity(0.85)))
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Legend entry: coloured bar or dot with a label.
struct NunaLegendItem: View {
    let color: Color
    let text: LocalizedStringKey
    var dot = false
    var dashed = false
    var body: some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color).frame(width: 6, height: 3) } }
            } else {
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(color).frame(width: dot ? 10 : 14, height: dot ? 10 : 8)
            }
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }
}

/// Small caption used above cards.
func nunaTrendsCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

/// The section header of the Journal, used across Me: the title, how many (when it is known), a hairline out to the edge and, optionally,
/// a control at the far end.
struct NunaRuledHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    let trailing: Trailing

    init(_ title: LocalizedStringKey, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.count = count; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            nunaTrendsCap(title).lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            if let count { Text(verbatim: "\(count)").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension NunaRuledHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, count: Int? = nil) { self.init(title, count: count) { EmptyView() } }
}

func nunaRuledHeader(_ title: LocalizedStringKey, count: Int? = nil) -> some View { NunaRuledHeader(title, count: count) }

/// Charge zone colour (green 67+, yellow 34 to 66, red below).
func nunaZoneColor(_ v: Double) -> Color { nunaChargeColor(v) }

/// The colours a score has on its ring in Today, for a bar that shows the same value: Charge by its zone, Effort from dark to light blue up to its level
/// (`value` on the stored 0 to 100 axis), Rest by how well the night went.
func nunaPeriodColors(_ kind: NunaTrendsMetricKind, _ value: Double?) -> [Color] {
    guard let value else { return [NunaPalette.ink.opacity(0.2)] }
    switch kind {
    case .charge: let c = nunaChargeColor(value); return [c.opacity(0.55), c]
    case .effort: return nunaEffortRingColors(value)
    case .rest: let c = nunaRestColor(value); return [c.opacity(0.55), c]
    }
}

/// A thick capsule bar on a faint track, filled with a gradient. `soft` dims it, for the earlier of two periods.
struct NunaPeriodBar: View {
    let fraction: Double
    let colors: [Color]
    var soft = false
    var height: CGFloat = 24
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.ink.opacity(0.09))
                Capsule().fill(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height * 0.6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                    .opacity(soft ? 0.6 : 1)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
#endif
