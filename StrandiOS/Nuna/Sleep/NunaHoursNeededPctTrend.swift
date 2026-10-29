#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// A trend page for a score that is a percentage: the average of the window, the week / month / six-month switch and date stepper, a sentence, the
/// days as bars on a 0 to 100% axis (a week writes each figure, a month marks the average with a dashed line and a white Avg. tag), and the days per
/// level under it. Six months are drawn as the average of each sixth with the change against the one before. The sleep pages with such a figure
/// (hours against need, consistency) are this view with their own name, figures and levels.
struct NunaPctTrendView: View {
    let name: LocalizedStringKey
    let icon: String
    /// "Hours vs. Needed", "Sleep Consistency Score": the words the sentence says the figure with.
    let noun: String
    let bands: [NunaDaysBreakdown.Band]
    let breakdownTitle: LocalizedStringKey
    /// The figure of a day (its key), nil when the night has none.
    let value: (NunaSleepHistory, String) -> Double?
    /// Draws a week and a month as a line with a ring on each point (and a tight axis in steps of six), the way a figure that moves a little
    /// around a high level reads best; false draws bars from zero.
    var line = false
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var history = NunaSleepHistory()
    @State private var range = 7
    @State private var page = 0
    /// The day whose bar is touched on a week or a month: its figure replaces the average at the top and the other bars step back.
    @State private var picked: Date?
    /// Whether the touch that is under way began on the bar already picked, so lifting the finger there lets go of it.
    @State private var touchBeganOnPicked: Bool?

    private struct Day: Identifiable {
        let date: Date
        let value: Double?
        var id: Date { date }
    }

    private var win: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: endingDaysAgo) }

    private var days: [Day] {
        let w = win, cal = Calendar.current
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start) else { return nil }
            return Day(date: w.noon(d), value: value(history, Repository.localDayKey(d)))
        }
    }

    private var canGoBack: Bool {
        guard let oldest = history.oldest else { return false }
        return win.start > Calendar.current.startOfDay(for: oldest)
    }

    var body: some View {
        let all = days
        let values = all.compactMap(\.value)
        let average: Double? = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(average)
            Text(verbatim: sentence(average)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            chart(all, average).padding(.top, 8)
            NunaDaysBreakdown(title: breakdownTitle, bands: bands, values: values)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await history.load(repo: repo) }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private var nameBox: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text(name).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    private func header(_ average: Double?) -> some View {
        let pickedValue: Double? = picked.flatMap { d in days.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.value }
        let shown = pickedValue ?? average
        let tint = pickedValue == nil ? NunaPalette.textPrimary : NunaRestChart.steel
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedValue == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedValue == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map { "\(Int($0.rounded()))" } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil { Text("%").font(.nuna(size: 20, weight: .semibold, design: NunaType.design)).foregroundStyle(tint) }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(range: $range) { page = 0 }
                NunaDateStepper(label: win.label, canGoBack: canGoBack, canGoForward: page > 0,
                                back: { page += 1 }, forward: { page = max(0, page - 1) })
            }
        }
        .padding(.horizontal, 2)
    }

    /// "Sun, Jan 11" for the touched bar.
    private var pickedTitle: String {
        guard let picked else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: picked)
    }

    private func sentence(_ average: Double?) -> String {
        guard let average else { return String(localized: "Wear your strap to bed each night to track this over time.") }
        let span = range == 7 ? String(localized: "this week was") : (range == 30 ? String(localized: "this month was") : String(localized: "over these six months has been"))
        return String(localized: "Your \(noun) \(span) \(Int(average.rounded()))%. Wear your strap to bed each night to track how this changes over time.")
    }

    private func isPicked(_ date: Date) -> Bool { picked.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    /// The bar nearest a touch, or nil with no bars.
    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among bars: [Day]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return bars.filter { $0.value != nil }.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    // MARK: Chart

    /// The line look of a week or a month: a soft area under a thin line, and a ring (dark centre, steel edge) on the points that carry a figure;
    /// the one touched is filled.
    @ChartContentBuilder
    private func lineMarks(_ bars: [Day], bottom: Double, ringed: [Day]) -> some ChartContent {
        ForEach(bars) { p in
            AreaMark(x: .value("Day", p.date), yStart: .value("Base", bottom), yEnd: .value("Value", p.value ?? 0))
                .foregroundStyle(LinearGradient(colors: [NunaRestChart.steel.opacity(0.28), NunaRestChart.steel.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .foregroundStyle(NunaRestChart.steel).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
        ForEach(ringed) { p in
            PointMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(NunaRestChart.steel, lineWidth: 2.5)).frame(width: 11, height: 11) }
        }
        if let p = bars.first(where: { isPicked($0.date) }) {
            PointMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .symbol { Circle().fill(NunaRestChart.steel).overlay(Circle().stroke(Color.white, lineWidth: 2)).frame(width: 12, height: 12) }
        }
    }

    /// Where a figure sits against its point: above, and below a point lower than the ones either side of it so the line does not run through it.
    private func labelShift(_ p: Day, in bars: [Day]) -> CGFloat {
        guard line, range <= 30, let i = bars.firstIndex(where: { $0.id == p.id }), let v = p.value else { return -14 }
        let neighbours = [i - 1, i + 1].filter { bars.indices.contains($0) }.compactMap { bars[$0].value }
        return !neighbours.isEmpty && neighbours.allSatisfy({ $0 > v }) ? 20 : -18
    }

    private func chart(_ points: [Day], _ average: Double?) -> some View {
        let w = win
        let week = range == 7, sixMonths = range > 30
        let bars = points.filter { $0.value != nil }
        let lowest = bars.compactMap(\.value).min() ?? 100
        let step = line ? 6.0 : 25.0
        let top = line ? 100.0 : max(100, ceil((points.compactMap(\.value).max() ?? 100) / 25) * 25)
        let bottom = line ? 100 - 6 * max(4, ceil((100 - lowest) / 6)) : 0.0
        let ringed: [Day] = week ? bars : (picked != nil ? [] : bars.suffix(1).map { $0 })
        let marked = week ? bars : (sixMonths || picked != nil ? [] : bars.suffix(1).map { $0 })
        let segments = sixMonths ? NunaPeriodSegment.make(bars.compactMap { p in p.value.map { (p.date, $0) } }, from: w.start, to: w.end) : []
        return Chart {
            if line && !sixMonths {
                lineMarks(bars, bottom: bottom, ringed: ringed)
            } else {
                ForEach(bars) { p in
                    if sixMonths {
                        LineMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0)).foregroundStyle(Color.white.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    } else {
                        BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value ?? 0), width: .fixed(week ? 18 : 8))
                            .foregroundStyle(isPicked(p.date) || picked == nil ? NunaRestChart.steel : NunaRestChart.steel.opacity(0.28)).cornerRadius(3)
                    }
                }
            }
            if let picked, !sixMonths {
                RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if !week, !sixMonths, let average {
                RuleMark(y: .value("Average", average)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
        }
        .chartYScale(domain: bottom...top)
        .chartXScale(domain: w.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: bottom, through: top, by: step).map { $0 }) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: "\(Int(d))%").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) } }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ZStack {
                        ForEach(marked) { p in
                            if let v = p.value, let x = proxy.position(forX: p.date), let y = proxy.position(forY: v) {
                                Text(verbatim: "\(Int(v.rounded()))%").font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
                                    .fixedSize().offset(x: !week && x > frame.width - 30 ? -16 : 0)
                                    .position(x: frame.minX + x, y: frame.minY + y + labelShift(p, in: bars))
                            }
                        }
                        if sixMonths { NunaSegmentsLayer(segments: segments, proxy: proxy, frame: frame, text: { "\(Int($0.rounded()))%" }) }
                        if !week, !sixMonths, let average, let y = proxy.position(forY: average) {
                            Text("Avg.").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(Color.black)
                                .padding(.horizontal, 8).frame(height: 22).background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .position(x: frame.minX + 24, y: frame.minY + y)
                        }
                        ForEach(w.axisDates, id: \.self) { d in
                            if let x = proxy.position(forX: d) { w.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 26) }
                        }
                        }
                        .allowsHitTesting(false)
                        if !sixMonths {
                            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        if touchBeganOnPicked == nil { touchBeganOnPicked = picked.map { nearest(g.location.x, proxy, frame, among: points) == $0 } ?? false }
                                        if let d = nearest(g.location.x, proxy, frame, among: points) { picked = d }
                                    }
                                    .onEnded { g in
                                        if touchBeganOnPicked == true, abs(g.translation.width) < 6 { picked = nil }
                                        touchBeganOnPicked = nil
                                    })
                        }
                    }
                }
            }
        }
        .frame(height: 360)
        .accessibilityLabel(Text(name))
    }
}

/// "Hours vs. needed (%)": above 85% optimal, 70 to 85 sufficient, under 70 poor.
struct NunaHoursNeededPctTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Hours vs. needed (%)", icon: "moon", noun: "Hours vs. Needed",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: ">85%") { $0 > 85 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–85%") { $0 >= 70 && $0 <= 85 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Hours vs. needed (%) breakdown",
            value: { $0.hoursVsNeeded($1) }, endingDaysAgo: endingDaysAgo)
    }
}

/// "Sleep consistency": 80% and over optimal, 70 to 79 sufficient, under 70 poor.
struct NunaConsistencyTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Sleep consistency", icon: "calendar", noun: "Sleep Consistency Score",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: "80%+") { $0 >= 80 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–79%") { $0 >= 70 && $0 < 80 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Sleep consistency breakdown",
            value: { $0.consistency[$1] }, endingDaysAgo: endingDaysAgo)
    }
}

/// "Sleep efficiency": 90% and over optimal, 80 to 89 sufficient, under 80 poor, drawn as a line.
struct NunaEfficiencyTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Sleep efficiency", icon: "bed.double", noun: "average sleep efficiency",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: "90%+") { $0 >= 90 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "80–89%") { $0 >= 80 && $0 < 90 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<80%") { $0 < 80 },
            ],
            breakdownTitle: "Sleep efficiency breakdown",
            value: { $0.efficiency[$1] }, line: true, endingDaysAgo: endingDaysAgo)
    }
}
#endif
