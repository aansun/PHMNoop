#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

// The trend page of blood pressure beside one other thing, laid out like the app's other trend pages: the topic's name box (which opens the list of
// topics), the window's average with the week / month / six-month switch and date stepper, a sentence, then the readings over the topic's own figure on
// one shared run of days, and the figures behind the sentence.

struct NunaBPTrendView: View {
    @State var topic: NunaBPTopic
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()
    @State private var range = 7
    @State private var page = 0
    @State private var picked: Date?
    @State private var listOpen = false
    /// The journal behaviour on the chart; nil follows the model's first.
    @State private var question: String?

    private var window: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: 0) }
    private var shownQuestion: String? { question ?? model.leadQuestion }

    var body: some View {
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            if !model.loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                header
                Text(verbatim: model.sentence(topic, question: shownQuestion)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                charts
                figures
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("How it is compared")
                    Text(verbatim: NunaBPLinksModel.method(topic)).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3)
                        .textCase(nil).fixedSize(horizontal: false, vertical: true)
                    Text("These are patterns in your own readings, not proof of cause: other things change on the same days, and a cuff reading varies by itself. Not a diagnosis.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)-\(effortScaleRaw)") {
            await model.load(repo: repo, readings: await NunaBP.load(repo), effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
        .onChange(of: topic) { _, _ in picked = nil }
    }

    // MARK: The list of topics

    private var nameBox: some View {
        VStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { listOpen.toggle() } } label: {
                NunaTrendBox(icon: topic.icon, title: LocalizedStringKey(topic.title), open: listOpen)
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Switch metric")).accessibilityValue(Text(verbatim: topic.title))
            if listOpen {
                VStack(spacing: 0) {
                    ForEach(NunaBPTopic.allCases) { t in
                        Button { topic = t; withAnimation(.easeOut(duration: 0.2)) { listOpen = false } } label: {
                            HStack(spacing: 14) {
                                NunaIcon(name: t.icon, size: 18).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                                Text(verbatim: t.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 52)
                            .background(t == topic ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(t == topic ? .isSelected : [])
                    }
                }
                .padding(10)
                .background(Color.black, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            }
        }
    }

    // MARK: The window's figures

    private struct Day: Identifiable {
        let date: Date
        let pressure: PressureLinks.Pressure?
        let value: Double?
        var id: Date { date }
    }

    private var values: [String: Double] {
        switch topic {
        case .journal: return (shownQuestion.flatMap { model.answers[$0] } ?? [:]).mapValues { $0 ? 1 : 0 }
        case .breathing: return [:]
        default: return model.series[topic] ?? [:]
        }
    }

    private var days: [Day] {
        let values = values
        return window.noons.map { d in
            let key = Repository.localDayKey(d)
            return Day(date: d, pressure: model.daily[key], value: values[key])
        }
    }

    /// The breathing sessions measured on both sides that fall in the window, each at its day's noon.
    private var windowPairs: [(date: Date, pair: PressureLinks.BreathPair)] {
        let w = window
        return model.pairs.compactMap { p in
            let at = w.noon(Date(timeIntervalSince1970: TimeInterval(p.session.start)))
            return w.domain.contains(at) ? (at, p) : nil
        }
    }

    private var header: some View {
        let all = days
        let w = window
        let day = picked.flatMap { p in all.first { Calendar.current.isDate($0.date, inSameDayAs: p) } }
        let big: String
        let small: String?
        if topic == .breathing {
            let shown = windowPairs.filter { day == nil || Calendar.current.isDate($0.date, inSameDayAs: day!.date) }.map(\.pair)
            big = PressureLinks.meanChange(shown).map(NunaBPLinksModel.changeText) ?? "–"
            small = shown.isEmpty ? nil : (shown.count == 1 ? String(localized: "1 session") : String(localized: "\(shown.count) sessions"))
        } else {
            let list = day.map { [$0] } ?? all
            let p = list.compactMap(\.pressure)
            big = p.isEmpty ? "–" : NunaBP.text(p.map(\.systolic).reduce(0, +) / Double(p.count), p.map(\.diastolic).reduce(0, +) / Double(p.count))
            small = beside(list)
        }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: day.map { Self.dayTitle($0.date) } ?? (topic == .breathing ? String(localized: "Average change") : String(localized: "Average")))
                    .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(day == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                Text(verbatim: big).font(.nuna(size: 34, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: "mmHg").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                if let small {
                    Text(verbatim: small).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(range: $range) { page = 0 }
                NunaDateStepper(label: w.label, canGoBack: model.daily.keys.min().map { Repository.localDayKey(w.start) > $0 } ?? false, canGoForward: page > 0,
                                back: { page += 1 }, forward: { page = max(0, page - 1) })
            }
        }
        .padding(.horizontal, 2)
    }

    /// The topic's own figure for the days given: the mean, or for the journal how many of the answers were yes.
    private func beside(_ list: [Day]) -> String? {
        let v = list.compactMap(\.value)
        guard !v.isEmpty else { return nil }
        if topic == .journal {
            if list.count == 1 { return String(localized: "Answered: \(model.figureText(.journal, v[0]))") }
            return String(localized: "Yes on \(v.filter { $0 > 0 }.count) of \(v.count) days")
        }
        let mean = model.figureText(topic, v.reduce(0, +) / Double(v.count))
        switch topic {
        case .sleep: return String(localized: "Sleep \(mean)")
        case .activity: return String(localized: "Strain \(mean)")
        default: return mean + " kg"
        }
    }

    private static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: date)
    }

    // MARK: Charts

    private var charts: some View {
        let all = days
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                if topic == .breathing {
                    legend("Before", filled: false); legend("After", filled: true)
                } else {
                    lineLegend("Systolic", dashed: false); lineLegend("Diastolic", dashed: true)
                }
            }
            pressureChart(all)
            if topic != .breathing {
                nunaTrendsCap(LocalizedStringKey(figureCaption))
                if all.contains(where: { $0.value != nil }) {
                    figureChart(all)
                } else {
                    Text("Nothing recorded in this period yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .textCase(nil).frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }

    private var figureCaption: String {
        switch topic {
        case .sleep: return String(localized: "Sleep the night before")
        case .activity: return String(localized: "Activity the day before")
        case .weight: return String(localized: "Body weight (kg)")
        case .journal: return shownQuestion.map { String(localized: "Journal: \(NunaBehaviorModel.title($0))") } ?? String(localized: "Journal")
        case .breathing: return ""
        }
    }

    private func legend(_ title: LocalizedStringKey, filled: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: 2).background(Circle().fill(filled ? NunaPalette.textPrimary : .clear)).frame(width: 10, height: 10)
            nunaTrendsCap(title)
        }
    }

    private func lineLegend(_ title: LocalizedStringKey, dashed: Bool) -> some View {
        HStack(spacing: 7) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 18, y: 1)) }
                .stroke(NunaPalette.textSecondary, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
                .frame(width: 18, height: 2)
            nunaTrendsCap(title)
        }
    }

    /// The readings of the window: a day's means joined into two lines, or, for breathing, each session's before and after joined upright.
    private func pressureChart(_ all: [Day]) -> some View {
        let w = window
        let measured = all.filter { $0.pressure != nil }
        let pairs = windowPairs
        let breathing = topic == .breathing
        let highs = breathing ? pairs.flatMap { [$0.pair.before.systolic, $0.pair.after.systolic] } : measured.compactMap { $0.pressure?.systolic }
        let lows = breathing ? pairs.flatMap { [$0.pair.before.diastolic, $0.pair.after.diastolic] } : measured.compactMap { $0.pressure?.diastolic }
        let low = (((lows.min() ?? 70) - 14) / 10).rounded(.down) * 10
        let high = (((highs.max() ?? 130) + 14) / 10).rounded(.up) * 10
        // A week writes every day's figures, a month only the newest, six months none.
        let labelled: Set<Date> = range == 7 ? Set(measured.map(\.date)) : (range == 30 ? Set(measured.suffix(1).map(\.date)) : [])
        let dot: CGFloat = range > 30 ? 5 : 9
        // Each written figure with its place: over an upper reading, under a lower one.
        let figures = breathing ? [] : measured.filter { labelled.contains($0.date) }.flatMap { d in
            d.pressure.map { [Written(date: d.date, value: $0.systolic, lift: -15), Written(date: d.date, value: $0.diastolic, lift: 15)] } ?? []
        }
        return Chart {
            if breathing {
                ForEach(pairs, id: \.pair.session.start) { item in
                    ForEach(0..<2, id: \.self) { i in
                        let before = i == 0 ? item.pair.before.systolic : item.pair.before.diastolic
                        let after = i == 0 ? item.pair.after.systolic : item.pair.after.diastolic
                        RuleMark(x: .value("Day", item.date), yStart: .value("Before", before), yEnd: .value("After", after))
                            .foregroundStyle(NunaPalette.ink.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Day", item.date), y: .value("Before", before))
                            .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: 2)).frame(width: 10, height: 10) }
                        PointMark(x: .value("Day", item.date), y: .value("After", after))
                            .symbol { Circle().fill(NunaPalette.textPrimary).frame(width: 10, height: 10) }
                    }
                }
            } else {
                ForEach(measured) { d in
                    LineMark(x: .value("Day", d.date), y: .value("Systolic", d.pressure?.systolic ?? 0), series: .value("Line", "s"))
                        .foregroundStyle(NunaPalette.ink.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    LineMark(x: .value("Day", d.date), y: .value("Diastolic", d.pressure?.diastolic ?? 0), series: .value("Line", "d"))
                        .foregroundStyle(NunaPalette.ink.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [4, 3]))
                }
                ForEach(measured) { d in
                    if let p = d.pressure {
                        let tone = NunaBPCategory.of(p.systolic, p.diastolic).color
                        PointMark(x: .value("Day", d.date), y: .value("Systolic", p.systolic))
                            .symbol { Circle().fill(tone).frame(width: dot, height: dot) }
                        PointMark(x: .value("Day", d.date), y: .value("Diastolic", p.diastolic))
                            .symbol { Circle().fill(tone).frame(width: dot, height: dot) }
                    }
                }
            }
            if let picked {
                RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: w.domain, range: .plotDimension(startPadding: 4, endPadding: 12))
        .chartYAxis { axis(Array(stride(from: low, through: high, by: max(10, ((high - low) / 40).rounded(.up) * 10)))) { "\(Int($0))" } }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, breathing ? 46 : 0) }
        .chartOverlay { proxy in overlay(proxy, dates: breathing ? pairs.map(\.date) : measured.map(\.date), axisLabels: breathing, written: figures) }
        .frame(height: breathing ? 280 : 220)
        .overlay { if (breathing ? pairs.isEmpty : measured.isEmpty) { Text("No reading in this period.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } }
        .accessibilityLabel(Text("Blood pressure"))
    }

    /// The topic's own figure on the same days: bars for sleep and activity, a line for weight, filled and open rings for a yes and a no.
    private func figureChart(_ all: [Day]) -> some View {
        let w = window
        let present = all.filter { $0.value != nil }
        let v = present.compactMap(\.value)
        let low: Double, high: Double, ticks: [Double]
        switch topic {
        case .weight:
            low = (v.min() ?? 0).rounded(.down) - 1; high = (v.max() ?? 1).rounded(.up) + 1; ticks = [low, (low + high) / 2, high]
        case .journal:
            low = -0.5; high = 1.5; ticks = [0, 1]
        case .sleep:
            low = 0; high = max(((v.max() ?? 480) / 120).rounded(.up) * 120, 240); ticks = [0, high / 2, high]
        default:
            // Strain is kept from 0 to 100, so the whole scale gives round figures on either of the person's scales.
            low = 0; high = 100; ticks = [0, 50, 100]
        }
        return Chart {
            ForEach(present) { d in
                let value = d.value ?? 0
                switch topic {
                case .weight:
                    LineMark(x: .value("Day", d.date), y: .value("Value", value)).foregroundStyle(topic.color).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    PointMark(x: .value("Day", d.date), y: .value("Value", value))
                        .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().strokeBorder(topic.color, lineWidth: 2)).frame(width: range > 30 ? 5 : 9, height: range > 30 ? 5 : 9) }
                case .journal:
                    PointMark(x: .value("Day", d.date), y: .value("Value", value))
                        .symbol {
                            Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: range > 30 ? 1 : 2).background(Circle().fill(value > 0 ? NunaPalette.textPrimary : .clear))
                                .frame(width: range > 30 ? 5 : 11, height: range > 30 ? 5 : 11)
                        }
                default:
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Value", value), width: .ratio(range == 7 ? 0.34 : 0.7))
                        .foregroundStyle(topic.color).cornerRadius(range > 30 ? 0 : 3)
                }
            }
            if let picked {
                RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: w.domain, range: .plotDimension(startPadding: 4, endPadding: 12))
        .chartYAxis { axis(ticks) { model.figureText(topic, $0) } }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 46) }
        .chartOverlay { proxy in overlay(proxy, dates: present.map(\.date), axisLabels: true) }
        .frame(height: topic == .journal ? 130 : 180)
        .accessibilityLabel(Text(verbatim: figureCaption))
    }

    private struct Written {
        let date: Date
        let value: Double
        let lift: CGFloat
    }

    /// Figures at the left in a column of one width, so the two charts' days stand over each other.
    private func axis(_ ticks: [Double], text: @escaping (Double) -> String) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { v in
            AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
            AxisValueLabel {
                if let d = v.as(Double.self) {
                    Text(verbatim: text(d)).font(.nuna(size: 11.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    /// The day names under a chart, and a finger on it picking the nearest day that has something; a second tap on that day lets go.
    private func overlay(_ proxy: ChartProxy, dates: [Date], axisLabels: Bool, written: [Written] = []) -> some View {
        GeometryReader { geo in
            if let frame = proxy.plotFrame.map({ geo[$0] }) {
                ZStack {
                    ForEach(Array(written.enumerated()), id: \.offset) { _, w in
                        if let x = proxy.position(forX: w.date), let y = proxy.position(forY: w.value) {
                            Text(verbatim: "\(Int(w.value.rounded()))").font(.nuna(size: 12, weight: .heavy, design: NunaType.design))
                                .foregroundStyle(NunaPalette.textPrimary).fixedSize()
                                .position(x: frame.minX + min(x, frame.width - 11), y: frame.minY + y + w.lift)
                        }
                    }
                    .allowsHitTesting(false)
                    if axisLabels {
                        ForEach(window.axisDates, id: \.self) { d in
                            if let x = proxy.position(forX: d) { window.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 26) }
                        }
                        .allowsHitTesting(false)
                    }
                    Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture(coordinateSpace: .local) { point in
                            guard let touched: Date = proxy.value(atX: point.x),
                                  let near = dates.min(by: { abs($0.timeIntervalSince(touched)) < abs($1.timeIntervalSince(touched)) }) else { return }
                            picked = picked == near ? nil : near
                        }
                }
            }
        }
    }

    // MARK: The figures behind the sentence

    @ViewBuilder private var figures: some View {
        switch topic {
        case .sleep, .activity, .weight:
            if let level = model.levels.first(where: { $0.topic == topic }), let c = level.comparison {
                NunaCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            nunaTrendsCap("All your readings")
                            Spacer(minLength: 8)
                            if c.verdict != .needMore, c.early { NunaChip("Early") }
                        }
                        HStack(alignment: .top, spacing: 18) {
                            NunaBPSideView(label: level.first, side: c.first, size: 30, progress: c.verdict == .needMore)
                            NunaBPSideView(label: level.second, side: c.second, size: 30, progress: c.verdict == .needMore)
                        }
                    }
                }
            }
        case .journal: journal
        case .breathing: sessions
        }
    }

    /// Every answered behaviour that has enough days; a tap puts it on the chart.
    @ViewBuilder private var journal: some View {
        ForEach(model.behaviours) { b in
            let c = b.comparison
            let on = b.question == shownQuestion
            Button { question = b.question; picked = nil } label: {
                NunaCard(small: true, highlight: on) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(verbatim: NunaBehaviorModel.title(b.question)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .textCase(nil).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if c.verdict == .same { NunaChip("No clear difference") }
                            else if let d = c.difference { NunaChip(verbatim: NunaBPLinksModel.changeText(d) + " mmHg", color: NunaPalette.textPrimary).textCase(nil) }
                        }
                        HStack(alignment: .top, spacing: 18) {
                            NunaBPSideView(label: String(localized: "After Yes"), side: c.first, size: 24)
                            NunaBPSideView(label: String(localized: "After No"), side: c.second, size: 24)
                        }
                    }
                }
            }
            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        }
        if !model.behaviours.isEmpty, model.waiting > 0 {
            Text(verbatim: String(localized: "Behaviours still short of days: \(model.waiting)."))
                .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var sessions: some View {
        if !model.pairs.isEmpty {
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    ForEach(model.pairs.prefix(10), id: \.session.start) { pair in
                        if pair.session.start != model.pairs.first?.session.start { NunaDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: NunaBP.when(Date(timeIntervalSince1970: TimeInterval(pair.session.start))))
                                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Text(verbatim: NunaBP.text(pair.before.systolic, pair.before.diastolic) + "  →  " + NunaBP.text(pair.after.systolic, pair.after.diastolic))
                                .font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
#endif
