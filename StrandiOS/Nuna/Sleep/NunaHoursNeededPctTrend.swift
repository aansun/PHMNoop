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
    /// The noun in the language of the page, for the sentences that carry it.
    private var nounText: String { String(localized: String.LocalizationValue(noun)) }
    let bands: [NunaDaysBreakdown.Band]
    let breakdownTitle: LocalizedStringKey
    /// The figure of a day (its key), nil when the night has none.
    let value: (NunaSleepHistory, String) -> Double?
    /// Draws a week and a month as a line with a ring on each point (and a tight axis in steps of six), the way a figure that moves a little
    /// around a high level reads best; false draws bars from zero.
    var line = false
    /// The figure is minutes shown as hours and minutes (sleep debt) instead of a percentage; bars on a 0 to 3 hour axis (and up in whole hours).
    var duration = false
    /// A score with colour zones (Charge): light bars, the newest or the touched one in the colour of its zone, and an axis with the zone
    /// edges at 0, 33, 66 and 100 in their colours. A month writes no figure over its last bar.
    var zones: ((Double) -> Color)?
    /// Own wording for a figure (Effort on the scale the wearer chose); nil writes the percentage or the duration.
    var format: ((Double) -> String)?
    /// No unit beside the average at the top (Effort has none).
    var hidesUnit = false
    /// The labelled steps of the axis, from zero (Effort: 0, 5, 10, 15, 21); nil lets the page choose.
    var axisTicks: [Double]?
    /// The colour of the bars, their figures and the touched figure.
    var tint = NunaRestChart.steel
    /// The average leaves today out, a day still in progress, and a line under the chart says so.
    var excludesToday = false
    /// The unit beside the average at the top, for a figure with its own ("Cals"); empty uses "%" or "hr".
    var unitText = ""
    /// The axis written out for the page (Calories: 0 to 3,000 in thousands); the sentence is its own too.
    var customSentence: ((Double, Int) -> String)?
    /// Hides the breakdown under the chart (a figure with no levels).
    var showsBreakdown = true
    /// A month writes the figure of its newest day over its bar; false leaves the bars bare (Effort, Calories).
    var labelsNewestInMonth = true
    /// Whether a rise of the average is the better way (sleep, Charge, steps), a fall is (sleep debt), or neither is (Effort, calories): the colour of
    /// the change under the average.
    var upIsGood: Bool? = true
    var endingDaysAgo = 0
    /// What sits under the chart and the levels (Steps: the target and what steps are).
    var footer: AnyView?

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
        let counted = excludesToday ? all.filter { !Calendar.current.isDateInToday($0.date) }.compactMap(\.value) : values
        let average: Double? = counted.isEmpty ? nil : counted.reduce(0, +) / Double(counted.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(average)
            Text(verbatim: sentence(average)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            chart(all, average).padding(.top, 4)
            if excludesToday, all.contains(where: { Calendar.current.isDateInToday($0.date) }) { todayNote }
            if showsBreakdown { NunaDaysBreakdown(title: breakdownTitle, bands: bands, values: values) }
            if let footer { footer }
        }
        .appears(when: history.loaded)
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await history.load(repo: repo) }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private var nameBox: some View {
        NunaTrendNameBox(icon: icon, title: name)
    }

    private func header(_ average: Double?) -> some View {
        let pickedValue: Double? = picked.flatMap { d in days.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.value }
        let shown = pickedValue ?? average
        let tint = pickedValue == nil ? NunaPalette.textPrimary : (pickedValue.flatMap { zones?($0) } ?? tint)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedValue == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedValue == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map { format?($0) ?? (duration ? NunaRestChart.hm($0) : "\(Int($0.rounded()))") } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil, !hidesUnit {
                        if !unitText.isEmpty { Text(verbatim: unitText).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                        else if duration { Text("hr").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                        else { Text("%").font(.nuna(size: 20, weight: .semibold, design: NunaType.design)).foregroundStyle(tint) }
                    }
                }
                if pickedValue == nil {
                    NunaChangeChip(average: average, prior: NunaTrendChange.prior(start: win.start, range: range) { value(history, Repository.localDayKey($0)) },
                                   range: range, upIsGood: upIsGood)
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

    /// A figure the way the page writes it: "88%" or "1:16".
    private func fmt(_ v: Double) -> String {
        if let format { return format(v) }
        // The Charge card rounds the way printf does (56.5 reads 56); a scored page follows it so a day never differs between the two.
        return duration ? NunaRestChart.hm(v) : (zones != nil ? String(format: "%.0f%%", v) : "\(Int(v.rounded()))%")
    }

    private func sentence(_ average: Double?) -> String {
        guard let average else { return String(localized: "Wear your strap to bed each night to track this over time.") }
        if let customSentence { return customSentence(average, range) }
        let span = range == 7 ? String(localized: "this week was") : (range == 30 ? String(localized: "this month was") : String(localized: "over these six months has been"))
        return String(localized: "Your \(nounText) \(span) \(fmt(average)). Wear your strap to bed each night to track how this changes over time.")
    }

    private func isPicked(_ date: Date) -> Bool { picked.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    /// The bar nearest a touch, or nil with no bars.
    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among bars: [Day]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return bars.filter { $0.value != nil }.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    /// A bar: the zone's colour for the newest or touched one of a scored page, light grey for the others, steel blue on a page without zones.
    private func barColor(_ p: Day, latest: Date?) -> Color {
        let lit = picked != nil ? isPicked(p.date) : p.date == latest
        guard let zones, let v = p.value else { return isPicked(p.date) || picked == nil ? tint : tint.opacity(0.28) }
        return lit ? zones(v) : Color(hex: "#DCDCDC").opacity(picked == nil ? 1 : 0.4)
    }

    private func labelColor(_ p: Day, latest: Date?) -> Color {
        guard let zones, let v = p.value else { return tint }
        return (picked != nil ? isPicked(p.date) : p.date == latest) ? zones(v) : NunaPalette.textPrimary
    }

    private var todayNote: some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d")
        return HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.nuna(size: 14, weight: .semibold))
            Text(verbatim: String(localized: "Average does not include today (\(f.string(from: Date())))")).font(.nuna(size: 12.5, weight: .semibold)).textCase(nil)
        }
        .foregroundStyle(NunaPalette.textSecondary).padding(.horizontal, 2).frame(maxWidth: .infinity, alignment: .leading)
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
        // A fixed axis grows by its own step when a day goes past the top of it.
        var scale = axisTicks ?? []
        if scale.count > 1, let peak = points.compactMap(\.value).max() {
            let gap = scale[1] - scale[0]
            while let last = scale.last, peak > last { scale.append(last + gap) }
        }
        let step = duration ? 60.0 : (line ? 6.0 : 25.0)
        let top = scale.last ?? (zones != nil ? 100.0 : duration ? max(180, ceil((points.compactMap(\.value).max() ?? 180) / 60) * 60)
            : (line ? 100.0 : max(100, ceil((points.compactMap(\.value).max() ?? 100) / 25) * 25)))
        let bottom = line ? 100 - 6 * max(4, ceil((100 - lowest) / 6)) : 0.0
        let latest = bars.last?.date
        let tickValues: [Double] = axisTicks != nil ? scale : (zones != nil ? [0, 33, 66, 100] : stride(from: bottom, through: top, by: step).map { $0 })
        let ringed: [Day] = week ? bars : (picked != nil ? [] : bars.suffix(1).map { $0 })
        let marked = week ? bars : (sixMonths || picked != nil || zones != nil || !labelsNewestInMonth ? [] : bars.suffix(1).map { $0 })
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
                            .foregroundStyle(barColor(p, latest: latest)).cornerRadius(3)
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
            AxisMarks(position: .leading, values: tickValues) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) {
                    Text(verbatim: duration ? NunaRestChart.hm(d) : (axisTicks != nil ? (format?(d) ?? "\(Int(d))") : "\(Int(d))%")).font(.nuna(size: 12, weight: .heavy))
                        .foregroundStyle(zones.map { $0(d == 0 ? 1 : d) } ?? NunaPalette.textMuted)
                } }
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
                                Text(verbatim: fmt(v)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(labelColor(p, latest: latest))
                                    .fixedSize().offset(x: !week && x > frame.width - 30 ? -16 : 0)
                                    .position(x: frame.minX + x, y: frame.minY + y + labelShift(p, in: bars))
                            }
                        }
                        if sixMonths { NunaSegmentsLayer(segments: segments, proxy: proxy, frame: frame, upIsGood: !duration, text: fmt) }
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
        .frame(height: 280)
        .accessibilityLabel(Text(name))
    }
}

/// "Hours vs. needed (%)": above 85% optimal, 70 to 85 sufficient, under 70 poor.
struct NunaHoursNeededPctTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Hours vs. needed (%)", icon: "met:hours-vs-needed", noun: "Hours vs. Needed",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: ">85%") { $0 > 85 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–85%") { $0 >= 70 && $0 <= 85 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Hours vs. needed (%) breakdown",
            value: { $0.hoursVsNeeded($1) }, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .hoursNeeded)))
    }
}

/// "Sleep consistency": 80% and over optimal, 70 to 79 sufficient, under 70 poor.
struct NunaConsistencyTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Sleep consistency", icon: "met:sleep-consistency", noun: "Sleep Consistency Score",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: "80%+") { $0 >= 80 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–79%") { $0 >= 70 && $0 < 80 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Sleep consistency breakdown",
            value: { $0.consistency[$1] }, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .consistency)))
    }
}

/// "Sleep efficiency": 85% and over optimal, 70 to 85 sufficient, under 70 poor, drawn as a line.
struct NunaEfficiencyTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Sleep efficiency", icon: "met:sleep-efficiency", noun: "average sleep efficiency",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: "85%+") { $0 >= 85 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–85%") { $0 >= 70 && $0 < 85 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Sleep efficiency breakdown",
            value: { $0.efficiency[$1] }, line: true, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .efficiency)))
    }
}

/// "Sleep debt": more than 45 minutes is high, 30 to 45 moderate, under 30 low; a rise is the wrong way.
struct NunaSleepDebtTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Sleep debt", icon: "met:sleep-debt", noun: "average sleep debt",
            bands: [
                .init(color: Color(hex: "#7BA4C4"), name: "High", range: ">0:45") { $0 > 45 },
                .init(color: Color(hex: "#587C99"), name: "Moderate", range: "0:30–0:45") { $0 >= 30 && $0 <= 45 },
                .init(color: Color(hex: "#3F5C75"), name: "Low", range: "<0:30") { $0 < 30 },
            ],
            breakdownTitle: "Sleep debt breakdown",
            value: { $0.debtMin[$1] }, duration: true, upIsGood: false, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .debt)))
    }
}

/// "Charge": the 0 to 100 score with its three zones, the way the Recovery trend view draws it.
struct NunaChargeScoreTrendView: View {
    var endingDaysAgo = 0
    var body: some View {
        NunaPctTrendView(
            name: "Recovery", icon: "met:recovery", noun: "average Recovery",
            bands: NunaDaysBreakdown.chargeBands,
            breakdownTitle: "Recovery breakdown",
            value: { $0.charge[$1] }, zones: { nunaChargeColor($0) }, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .charge)))
    }
}

/// "Effort": Day Strain on the scale the wearer chose (0 to 21 by default), bars in blue and the days per level under it.
struct NunaEffortScoreTrendView: View {
    var endingDaysAgo = 0
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View { page }

    private var page: NunaPctTrendView {
        // Levels are defined on the 21 scale (light under 10, moderate to 14, strenuous to 18, all out above); the 100 scale carries the same edges.
        let k = scale == .whoop ? 1.0 : 100.0 / 21.0
        func edge(_ v: Double) -> String { String(format: "%.1f", v * k) }
        let blue = NunaPalette.effortModerate
        return NunaPctTrendView(
            name: "Day Strain", icon: "met:day-strain", noun: "average Day Strain",
            bands: [
                .init(color: NunaPalette.effortAllOut, name: "All out", range: ">\(edge(18))") { $0 > 18 * k },
                .init(color: NunaPalette.effortModerate, name: "Strenuous", range: "\(edge(14.1))–\(edge(18))") { $0 > 14 * k && $0 <= 18 * k },
                .init(color: NunaPalette.effortMinimal, name: "Moderate", range: "\(edge(10.1))–\(edge(14))") { $0 >= 10 * k && $0 <= 14 * k },
                .init(color: NunaPalette.effortMinimal.opacity(0.6), name: "Light", range: "<\(edge(10))") { $0 < 10 * k },
            ],
            breakdownTitle: "Day Strain breakdown",
            value: { h, day in h.effort[day].map { UnitFormatter.effortValue($0, scale: scale) } },
            format: { String(format: "%.1f", $0) }, hidesUnit: true,
            axisTicks: scale == .whoop ? [0, 5, 10, 15, 21] : [0, 25, 50, 75, 100],
            tint: blue, excludesToday: true, labelsNewestInMonth: false, upIsGood: nil, endingDaysAgo: endingDaysAgo,
            footer: AnyView(NunaDayStrainFooter()))
    }
}

/// "Calories": calories burned each day, bars in blue on a 0 to 3,000 axis (up in thousands when a day goes over), the average without today.
struct NunaCaloriesTrendView: View {
    var endingDaysAgo = 0

    var body: some View { page }

    private static func thousands(_ v: Double) -> String { nunaThousands(v) }

    private var page: NunaPctTrendView {
        NunaPctTrendView(
            name: "Calories", icon: "met:calories", noun: "calories", bands: [], breakdownTitle: "",
            value: { $0.calories[$1] },
            format: { Self.thousands($0) }, hidesUnit: false,
            axisTicks: [0, 1000, 2000, 3000],
            tint: NunaPalette.effortModerate, excludesToday: true, unitText: "Cals",
            customSentence: { average, range in
                let n = Self.thousands(average)
                switch range {
                case 7: return String(localized: "Your average calories burned this week was \(n). Wear your strap consistently to see how this changes over time.")
                case 30: return String(localized: "You have burned an average of \(n) calories this month. Wear your strap consistently to see how this changes over time.")
                default: return String(localized: "During this 6-month period, you have burned an average of \(n) calories. Wear your strap consistently to see how this changes over time.")
                }
            },
            showsBreakdown: false, labelsNewestInMonth: false, upIsGood: nil, endingDaysAgo: endingDaysAgo, footer: AnyView(NunaTrendInfo(kind: .calories)))
    }
}

/// A whole number with the grouping of the app's language ("1,785" or "1.785").
func nunaThousands(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = AppLanguage.activeLocale; f.numberStyle = .decimal; f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
}

/// "Steps": steps each day, bars in blue on a 0 to 15,000 axis (up in fives of thousands when a day goes over), the average without today.
struct NunaStepsTrendView: View {
    var endingDaysAgo = 0

    var body: some View { page }

    private var page: NunaPctTrendView {
        NunaPctTrendView(
            name: "Steps", icon: "met:steps", noun: "steps", bands: [], breakdownTitle: "",
            value: { $0.steps[$1] },
            format: { nunaThousands($0) }, hidesUnit: true,
            axisTicks: [0, 5000, 10000, 15000],
            tint: NunaPalette.effortModerate, excludesToday: true,
            customSentence: { average, range in
                let n = nunaThousands(average)
                let span = range == 7 ? String(localized: "the last 7 days") : (range == 30 ? String(localized: "the last 30 days") : String(localized: "the last 6 months"))
                return String(localized: "Your average steps for \(span) is \(n). Wear your strap all day to unlock personalized insights.")
            },
            showsBreakdown: false, labelsNewestInMonth: false, endingDaysAgo: endingDaysAgo,
            footer: AnyView(NunaStepsFooter()))
    }
}
#endif
