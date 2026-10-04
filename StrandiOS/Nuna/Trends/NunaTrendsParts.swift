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
                        ForEach(s.points, id: \.day) { p in
                            if let d = date(p.day) {
                                LineMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s)), series: .value("Series", s.id.uuidString))
                                    .interpolationMethod(.catmullRom)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(s.color)
                            }
                        }
                        if s.points.count <= 60 {
                            ForEach(s.points, id: \.day) { p in
                                if let d = date(p.day) {
                                    PointMark(x: .value("Day", d), y: .value("Value", scaled(p.value, s))).symbolSize(18).foregroundStyle(s.color)
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
            .chartYScale(domain: 0...100)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.4))
                    if let d = value.as(Date.self) {
                        AxisValueLabel(collisionResolution: .greedy) { Text(verbatim: nunaAxisDate(d)) }
                            .foregroundStyle(NunaPalette.textMuted).font(.nuna(size: 11.5, weight: .semibold))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.4))
                    AxisValueLabel().foregroundStyle(NunaPalette.textMuted).font(.nuna(size: 11.5, weight: .semibold))
                }
            }
            .chartOverlay { proxy in
                if selected != nil {
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                guard let frame = proxy.plotFrame else { return }
                                let x = v.location.x - g[frame].origin.x
                                guard let d: Date = proxy.value(atX: x) else { return }
                                let cal = Calendar(identifier: .gregorian)
                                let i = Int((d.timeIntervalSince(origin) / 86400).rounded())
                                guard i >= 0, i < days, let day = cal.date(byAdding: .day, value: i, to: origin) else { return }
                                selected?.wrappedValue = NunaDayFormat.parser.string(from: day)
                            })
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Bars (one per day, e.g. Effort) with a line over them (e.g. Charge) on one shared day axis.
struct NunaComboChart: View {
    let start: String
    let days: Int
    let bars: NunaDaySeries
    let barMax: Double
    let line: NunaDaySeries
    let lineMax: Double
    var barColor: Color = NunaPalette.effort
    var lineColor: Color = NunaPalette.charge
    @Binding var selected: String?
    var height: CGFloat = 150
    var interactive = true

    var body: some View {
        NunaTrendChart(start: start, days: days,
                       series: [.init(points: bars, max: barMax, color: barColor, bars: true), .init(points: line, max: lineMax, color: lineColor)],
                       height: height + 24,
                       selected: interactive ? $selected : nil)
    }
}

/// Two or more lines on the same 0 to 100 scale (each by its own maximum), for "two lines moving together".
struct NunaMultiLineChart: View {
    struct Line { let series: NunaDaySeries; let max: Double; let color: Color }
    let start: String
    let days: Int
    let lines: [Line]
    var height: CGFloat = 130

    var body: some View {
        NunaTrendChart(start: start, days: days, series: lines.map { .init(points: $0.series, max: $0.max, color: $0.color) }, height: height + 24)
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
    var color: Color = NunaPalette.charge
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 10
            func mx(_ v: Double) -> CGFloat { pad + CGFloat((v - xRange.lowerBound) / max(xRange.upperBound - xRange.lowerBound, 0.0001)) * (size.width - pad * 2) }
            func my(_ v: Double) -> CGFloat { size.height - pad - CGFloat((v - yRange.lowerBound) / max(yRange.upperBound - yRange.lowerBound, 0.0001)) * (size.height - pad * 2) }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14), with: .color(NunaPalette.shade.opacity(0.28)))
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
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: dot ? 10 : 14, height: dot ? 10 : 8)
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

/// Small caption used above cards.
func nunaTrendsCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

/// Charge zone colour (green 67+, yellow 34 to 66, red below).
func nunaZoneColor(_ v: Double) -> Color { nunaChargeColor(v) }
#endif
