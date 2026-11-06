#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page the "Time in bed" card opens: the average time in bed of the window, the week / month / six-month switch and date stepper, a sentence
/// and the nights as floating bars from bedtime (top) to wake-up (bottom) on a clock axis. A week writes both times at the ends of each bar; a month
/// marks the average bedtime and wake time with dashed lines and white tags; six months are the average of each sixth over a faint daily line.
/// Touching a bar of a week or a month shows its day and time in bed at the top and steps the other bars back.
struct NunaTimeInBedTrendView: View {
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var history = NunaSleepHistory()
    @State private var range = 7
    @State private var page = 0
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?

    private struct Night: Identifiable {
        let date: Date
        let bed: Double?    // hours from the evening's midnight
        let wake: Double?
        var id: Date { date }
        var span: (bed: Double, wake: Double)? { bed.flatMap { b in wake.map { (b, $0) } } }
        var minutes: Double? { span.map { ($0.wake - $0.bed) * 60 } }
    }

    private var win: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: endingDaysAgo) }

    private var nights: [Night] {
        let w = win, cal = Calendar.current
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start) else { return nil }
            let key = Repository.localDayKey(d)
            return Night(date: w.noon(d), bed: history.bedHour[key], wake: history.wakeHour[key])
        }
    }

    private var canGoBack: Bool {
        guard let oldest = history.oldest else { return false }
        return win.start > Calendar.current.startOfDay(for: oldest)
    }

    private func isPicked(_ date: Date) -> Bool { picked.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    private var pickedTitle: String {
        guard let picked else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: picked)
    }

    private func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

    var body: some View {
        let all = nights
        let beds = all.compactMap { $0.bed }, wakes = all.compactMap { $0.wake }
        let averageBed = mean(beds), averageWake = mean(wakes)
        let average: Double? = mean(all.compactMap(\.minutes))
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(all, average)
            Text(verbatim: sentence(average, beds: beds)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            chart(all, averageBed: averageBed, averageWake: averageWake)
            NunaTrendInfo(kind: .timeInBed)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await history.load(repo: repo) }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private var nameBox: some View {
        NunaTrendNameBox(icon: "met:time-in-bed", title: "Time in bed")
    }

    private func header(_ all: [Night], _ average: Double?) -> some View {
        let pickedMinutes: Double? = picked.flatMap { d in all.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.minutes }
        let shown = pickedMinutes ?? average
        let tint = pickedMinutes == nil ? NunaPalette.textPrimary : NunaRestChart.steel
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedMinutes == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedMinutes == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map(NunaRestChart.hm) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil { Text("hr").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
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

    private func sentence(_ average: Double?, beds: [Double]) -> String {
        guard let average else { return String(localized: "Wear your strap to bed each night to track how your time in bed changes over time.") }
        let hm = NunaRestChart.hm(average)
        switch range {
        case 7:
            // A week reads as steady when the bedtimes sit within about 45 minutes of their mean.
            let m = mean(beds) ?? 0
            let spread = (mean(beds.map { abs($0 - m) }) ?? 0) * 60
            return spread <= 45
                ? String(localized: "Your Time in Bed was consistent during this period. Consistent sleep maintains a steady circadian rhythm, which enhances recovery.")
                : String(localized: "Your Time in Bed varied during this period. A steady bedtime keeps your circadian rhythm regular, which enhances recovery.")
        case 30:
            return String(localized: "Your average time in bed this month is \(hm). Wear your strap to bed each night to track how this changes over time.")
        default:
            return String(localized: "During this 6-month period, your average time in bed has been \(hm). Wear your strap to bed each night to track how this changes over time.")
        }
    }

    // MARK: Chart

    /// The chart plots the negative of the hour so that the earlier time sits at the top, like a night read down the page.
    private func clockLabel(_ plotted: Double) -> String { NunaRestChart.clock(-plotted) }

    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among bars: [Night]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return bars.filter { $0.span != nil }.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    private func chart(_ points: [Night], averageBed: Double?, averageWake: Double?) -> some View {
        let w = win
        let week = range == 7, sixMonths = range > 30
        let bars = points.filter { $0.span != nil }
        let low = min(19, floor(bars.compactMap { $0.bed }.min() ?? 19))
        let high = low + 3 * ceil((max(31, ceil(bars.compactMap { $0.wake }.max() ?? 31)) - low) / 3)
        let ticks = stride(from: low, through: high, by: 3).map { -$0 }
        let bedSegments = sixMonths ? NunaPeriodSegment.make(bars.compactMap { n in n.bed.map { (n.date, -$0) } }, from: w.start, to: w.end) : []
        let wakeSegments = sixMonths ? NunaPeriodSegment.make(bars.compactMap { n in n.wake.map { (n.date, -$0) } }, from: w.start, to: w.end) : []
        return Chart {
            if sixMonths {
                ForEach(bars) { n in
                    LineMark(x: .value("Day", n.date), y: .value("Bed", -(n.bed ?? 0)), series: .value("Series", "bed"))
                        .foregroundStyle(Color.white.opacity(0.18)).lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    LineMark(x: .value("Day", n.date), y: .value("Wake", -(n.wake ?? 0)), series: .value("Series", "wake"))
                        .foregroundStyle(Color.white.opacity(0.18)).lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            } else {
                ForEach(bars) { n in
                    if let s = n.span {
                        BarMark(x: .value("Day", n.date, unit: .day), yStart: .value("Bed", -s.bed), yEnd: .value("Wake", -s.wake), width: .fixed(week ? 18 : 8))
                            .foregroundStyle(NunaRestChart.steel).cornerRadius(week ? 3 : 2)
                            .opacity(picked == nil || isPicked(n.date) ? 1 : 0.3)
                    }
                }
                if !week, let averageBed, let averageWake {
                    RuleMark(y: .value("Average bed", -averageBed)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    RuleMark(y: .value("Average wake", -averageWake)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                }
                if let picked {
                    RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
        .chartYScale(domain: -high...(-low))
        .chartXScale(domain: w.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: clockLabel(d)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) } }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ZStack {
                            if week {
                                ForEach(bars) { n in
                                    if let s = n.span, let x = proxy.position(forX: n.date), let top = proxy.position(forY: -s.bed), let bottom = proxy.position(forY: -s.wake) {
                                        let dim = picked == nil || isPicked(n.date) ? 1.0 : 0.3
                                        Text(verbatim: NunaRestChart.clock(s.bed)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
                                            .opacity(dim).fixedSize().position(x: frame.minX + x, y: frame.minY + top - 14)
                                        Text(verbatim: NunaRestChart.clock(s.wake)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
                                            .opacity(dim).fixedSize().position(x: frame.minX + x, y: frame.minY + bottom + 14)
                                    }
                                }
                            }
                            if sixMonths {
                                NunaSegmentsLayer(segments: bedSegments, proxy: proxy, frame: frame, color: .white, showsDelta: false, text: clockLabel)
                                NunaSegmentsLayer(segments: wakeSegments, proxy: proxy, frame: frame, color: .white, showsDelta: false, text: clockLabel)
                            }
                            if !week, !sixMonths {
                                ForEach([averageBed, averageWake].compactMap { $0 }, id: \.self) { value in
                                    if let y = proxy.position(forY: -value) {
                                        Text(verbatim: NunaRestChart.clock(value)).font(.nuna(size: 12, weight: .heavy, design: NunaType.design)).foregroundStyle(Color.black)
                                            .padding(.horizontal, 8).frame(height: 24).background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            .position(x: frame.minX + 30, y: frame.minY + y)
                                    }
                                }
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
        .accessibilityLabel(Text("Time in bed"))
    }
}
#endif
