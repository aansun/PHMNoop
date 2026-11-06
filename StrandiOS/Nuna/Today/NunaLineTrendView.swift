#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page a vital's weekly card opens (heart rate variability, resting heart rate, respiratory rate): the average of the window with its unit,
/// the week / month / six-month switch and date stepper, a sentence, and the nights as a line on a five-step axis with the typical range shaded
/// behind it. A week writes each figure by its ring; a month rings the newest; six months are the average of each sixth over a faint daily line
/// with the change against the one before. Touching a point of a week or a month shows its day and figure at the top.
struct NunaLineTrendView: View {
    let name: LocalizedStringKey
    let icon: String
    /// "average HRV", "average resting heart rate": the words the sentence says the figure with.
    let noun: String
    let key: String
    let unit: String
    var decimals = 0
    /// Whether a rise is good (HRV), bad (resting heart rate) or neither (respiratory rate): the colour of the change in the six-month view.
    var upIsGood: Bool?
    /// Where the readings are kept: the strap's own series, unless the page is about a reading that comes from elsewhere (weight).
    var source = "my-whoop"
    /// A second source merged on top (a weight typed in by hand wins over the imported one for that day).
    var also: String?
    /// What the sentence ends with, when it is not about wearing the strap to bed.
    var closing: String?
    /// Compares the window with the one before it (a chip and a sentence), for readings with no good or bad direction of their own.
    var comparesWithPrior = false
    /// Leaves today out: a figure that is still adding up through the day would pull the average down.
    var excludesToday = false
    /// Shown under the chart (an explanation card).
    var footer: AnyView?
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var series = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?

    private let color = NunaPalette.effortModerate

    private struct Day: Identifiable {
        let date: Date
        let value: Double?
        var id: Date { date }
    }

    /// The pages for the three vitals the Charge page lists; nil for any other key.
    static func forMetric(_ key: String, endingDaysAgo: Int) -> NunaLineTrendView? {
        switch key {
        case "hrv":
            return NunaLineTrendView(name: "Heart rate variability", icon: "met:heart-rate-variability", noun: "average HRV", key: key, unit: "ms", upIsGood: true, footer: AnyView(NunaTrendInfo(kind: .hrv)), endingDaysAgo: endingDaysAgo)
        case "rhr":
            return NunaLineTrendView(name: "Resting heart rate", icon: "met:resting-heart-rate", noun: "average resting heart rate", key: key, unit: "bpm", upIsGood: false, footer: AnyView(NunaTrendInfo(kind: .rhr)), endingDaysAgo: endingDaysAgo)
        case "resp_rate":
            return NunaLineTrendView(name: "Respiratory rate", icon: "met:respiratory-rate", noun: "average respiratory rate", key: key, unit: "rpm", decimals: 1, footer: AnyView(NunaTrendInfo(kind: .respiratory)), endingDaysAgo: endingDaysAgo)
        case "spo2":
            return NunaLineTrendView(name: "Blood oxygen", icon: "vital:spo2", noun: "average blood oxygen", key: key, unit: "%", upIsGood: true, endingDaysAgo: endingDaysAgo)
        case "skin_temp":
            return NunaLineTrendView(name: "Skin temperature", icon: "vital:temp", noun: "average skin temperature (against your usual)", key: key, unit: "°C", decimals: 1,
                                     endingDaysAgo: endingDaysAgo)
        case "avg_hr":
            // The strap's own daily figure when a WHOOP export brought one; Apple Health (Apple Watch) fills the days it has.
            return NunaLineTrendView(name: "Average heart rate", icon: "met:average-heart-rate", noun: "average heart rate", key: key, unit: "bpm", also: "apple-health",
                                     comparesWithPrior: true, excludesToday: true, footer: AnyView(NunaAverageHRInfo()), endingDaysAgo: endingDaysAgo)
        case "vo2max_est":
            return NunaLineTrendView(name: "VO₂ max", icon: "met:vo2-max", noun: "average estimated VO₂ max", key: key, unit: "ml/kg/min", decimals: 1, upIsGood: true,
                                     closing: String(localized: "It is worked out once a week from your resting heart rate and your profile."), footer: AnyView(NunaVO2MaxFooter()), endingDaysAgo: endingDaysAgo)
        case "vitality":
            return NunaLineTrendView(name: "Vitality", icon: "sparkles", noun: "average Vitality", key: key, unit: "", upIsGood: true,
                                     closing: String(localized: "It is worked out once a week from your sleep, activity and recovery."), endingDaysAgo: endingDaysAgo)
        case "weight":
            return NunaLineTrendView(name: "Weight", icon: "met:weight", noun: "average weight", key: key, unit: "kg", decimals: 1, source: "apple-health", also: nunaManualSource,
                                     closing: String(localized: "Log it from Quick actions or connect Apple Health to track how it changes over time."), footer: AnyView(NunaTrendInfo(kind: .weight)), endingDaysAgo: endingDaysAgo)
        default:
            return nil
        }
    }

    private var win: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: endingDaysAgo) }

    private var days: [Day] {
        let w = win, cal = Calendar.current
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start) else { return nil }
            if excludesToday && cal.isDateInToday(d) { return Day(date: w.noon(d), value: nil) }
            return Day(date: w.noon(d), value: series.byDay[Repository.localDayKey(d)])
        }
    }

    /// The average of the window just before this one, when it has readings.
    private var priorAverage: Double? {
        guard comparesWithPrior else { return nil }
        let w = win, cal = Calendar.current
        let vals = (1...range).compactMap { i in cal.date(byAdding: .day, value: -i, to: w.start).flatMap { series.byDay[Repository.localDayKey($0)] } }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    /// The change against the window before, in percent; nil under half a percent either way is still returned (the caller words "near").
    private func change(_ average: Double?) -> Double? {
        guard let average, let prior = priorAverage, prior > 0 else { return nil }
        return (average - prior) / prior * 100
    }

    private var priorLabel: String {
        range == 7 ? String(localized: "vs. prior week") : (range == 30 ? String(localized: "vs. prior month") : String(localized: "vs. prior six months"))
    }

    private var canGoBack: Bool {
        series.byDay.keys.min().map { Repository.localDayKey(win.start) > $0 } ?? false
    }

    private func fmt(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    private func isPicked(_ date: Date) -> Bool { picked.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    private var pickedTitle: String {
        guard let picked else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: picked)
    }

    var body: some View {
        let all = days
        let values = all.compactMap(\.value)
        let average: Double? = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(all, average)
            Text(verbatim: sentence(average)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            if range <= 30 { legend }
            chart(all, average)
            if excludesToday { Text("Average does not include today").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(.horizontal, 2) }
            if let footer { footer }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await series.load(repo: repo, key: key, source: source, days: 400, also: also) }
        .onReceive(NotificationCenter.default.publisher(for: .nunaManualVO2Changed)) { _ in
            guard key == NunaVO2Manual.key else { return }
            Task { await series.load(repo: repo, key: key, source: source, days: 400, also: also) }
        }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private var nameBox: some View {
        NunaTrendNameBox(icon: icon, title: name)
    }

    private func header(_ all: [Day], _ average: Double?) -> some View {
        let pickedValue: Double? = picked.flatMap { d in all.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.value }
        let shown = pickedValue ?? average
        let tint = pickedValue == nil ? NunaPalette.textPrimary : color
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedValue == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedValue == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map(fmt) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil { Text(verbatim: unit).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                }
                if pickedValue == nil, let c = change(average) {
                    HStack(spacing: 4) {
                        Image(systemName: c >= 0 ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .heavy))
                        Text(verbatim: String(format: "%.0f%%", locale: AppLanguage.activeLocale, abs(c)) + " " + priorLabel).font(.nuna(size: 12, weight: .bold)).textCase(nil)
                    }
                    .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 9).padding(.vertical, 4)
                    .background(NunaPalette.glassStrong, in: Capsule())
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

    private func sentence(_ average: Double?) -> String {
        guard let average else {
            if comparesWithPrior { return String(localized: "Nothing recorded in this period yet.") }
            return closing == nil ? String(localized: "Wear your strap to bed each night to track this over time.") : String(localized: "Nothing recorded in this period yet.")
        }
        if comparesWithPrior {
            let period = range == 7 ? String(localized: "7-day period") : (range == 30 ? String(localized: "30-day period") : String(localized: "six-month period"))
            guard let c = change(average) else { return String(localized: "Your \(noun) during this \(period) was \(fmt(average)).") }
            if abs(c) < 2 { return String(localized: "Your \(noun) during this \(period) was near its prior average.") }
            return c > 0 ? String(localized: "Your \(noun) during this \(period) was higher than its prior average.")
                         : String(localized: "Your \(noun) during this \(period) was lower than its prior average.")
        }
        let span = range == 7 ? String(localized: "this week was") : (range == 30 ? String(localized: "this month was") : String(localized: "over these six months has been"))
        guard let closing else {
            return String(localized: "Your \(noun) \(span) \(fmt(average)). Wear your strap to bed each night to track how this changes over time.")
        }
        return String(localized: "Your \(noun) \(span) \(fmt(average)).") + " " + closing
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white.opacity(0.14)).frame(width: 12, height: 12)
            Text("Typical range").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
        }
        .padding(.horizontal, 2).padding(.top, 4)
    }

    // MARK: Chart

    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among bars: [Day]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return bars.filter { $0.value != nil }.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    /// Where a figure sits against its point so the line does not run through it: above a peak, below a dip, and to the side away from the line on a
    /// slope (up and left while it climbs, up and right while it falls).
    private func labelOffset(_ p: Day, in bars: [Day]) -> CGSize {
        guard let i = bars.firstIndex(where: { $0.id == p.id }), let v = p.value else { return CGSize(width: 0, height: -18) }
        let before = i > 0 ? bars[i - 1].value : nil, after = i + 1 < bars.count ? bars[i + 1].value : nil
        switch (before, after) {
        case let (b?, a?):
            if b < v && a < v { return CGSize(width: 0, height: -18) }
            if b > v && a > v { return CGSize(width: 0, height: 20) }
            return b < v ? CGSize(width: -14, height: -16) : CGSize(width: 14, height: -16)
        case let (n?, nil), let (nil, n?):
            return n > v ? CGSize(width: 0, height: 20) : CGSize(width: 0, height: -18)
        default:
            return CGSize(width: 0, height: -18)
        }
    }

    /// Five evenly spaced labels that cover the readings and the typical range.
    private func axis(_ readings: [Double], band: ClosedRange<Double>?) -> (low: Double, high: Double, ticks: [Double]) {
        let all = readings + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.12, decimals > 0 ? 0.3 : 2)
        var step = (hi - lo + 2 * pad) / 4
        step = decimals > 0 ? max(0.2, (step * 10).rounded(.up) / 10) : max(1, step.rounded(.up))
        let low = decimals > 0 ? ((lo - pad) * 10).rounded(.down) / 10 : (lo - pad).rounded(.down)
        return (low, low + 4 * step, (0...4).map { low + Double($0) * step })
    }

    @ChartContentBuilder
    private func lineMarks(_ bars: [Day], low: Double, ringed: [Day]) -> some ChartContent {
        ForEach(bars) { p in
            AreaMark(x: .value("Day", p.date), yStart: .value("Base", low), yEnd: .value("Value", p.value ?? 0))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
        ForEach(ringed) { p in
            PointMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(color, lineWidth: 2.5)).frame(width: 11, height: 11) }
        }
        if let p = bars.first(where: { isPicked($0.date) }) {
            PointMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0))
                .symbol { Circle().fill(color).overlay(Circle().stroke(Color.white, lineWidth: 2)).frame(width: 12, height: 12) }
        }
    }

    private func chart(_ points: [Day], _ average: Double?) -> some View {
        let w = win
        let week = range == 7, sixMonths = range > 30
        let bars = points.filter { $0.value != nil }
        let band = sixMonths ? nil : series.typicalRange
        let (low, high, ticks) = axis(bars.compactMap(\.value), band: band)
        let ringed: [Day] = week ? bars : (picked != nil ? [] : bars.suffix(1).map { $0 })
        let marked = week ? bars : (sixMonths || picked != nil ? [] : bars.suffix(1).map { $0 })
        let segments = sixMonths ? NunaPeriodSegment.make(bars.compactMap { p in p.value.map { (p.date, $0) } }, from: w.start, to: w.end) : []
        return Chart {
            if let band {
                RectangleMark(xStart: .value("Start", w.start), xEnd: .value("End", w.domain.upperBound), yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(Color.white.opacity(0.08))
            }
            if sixMonths {
                ForEach(bars) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Value", p.value ?? 0)).foregroundStyle(Color.white.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            } else {
                lineMarks(bars, low: low, ringed: ringed)
                if let picked {
                    RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: w.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: fmt(d)).font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textMuted) } }
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
                                    Text(verbatim: fmt(v)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(color)
                                        .fixedSize().offset(x: !week && x > frame.width - 30 ? -16 : 0)
                                        .position(x: frame.minX + x + labelOffset(p, in: bars).width, y: frame.minY + y + labelOffset(p, in: bars).height)
                                }
                            }
                            if sixMonths {
                                NunaSegmentsLayer(segments: segments, proxy: proxy, frame: frame, color: upIsGood == nil ? .white : nil,
                                                  upIsGood: upIsGood ?? true, text: fmt)
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
        .frame(height: 340)
        .accessibilityLabel(Text(name))
    }
}
#endif
