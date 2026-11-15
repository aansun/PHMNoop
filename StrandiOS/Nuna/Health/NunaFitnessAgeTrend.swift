#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign

/// The Trend view of the two Health pages, fitness age and pace of aging: the average of the window with the month / six-month switch and date stepper,
/// a sentence, and the weekly readings as a line. The fitness age is drawn against the calendar age in white; the pace is drawn blue against a white
/// line at 1.0x, on a fixed scale of -1.0x to 3.0x. The latest reading is ringed and carries its figure; touching a reading shows its week and figure at the top.
/// Under the chart: the way to the fitness age page and what the reading means.
struct NunaFitnessAgeTrendView: View {
    enum Kind { case fitnessAge, pace }
    let kind: Kind

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var readings: [(day: String, value: Double)] = []
    @State private var loaded = false
    @State private var range = 30
    @State private var page = 0
    @State private var picked: Date?

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var isPace: Bool { kind == .pace }
    private var tint: Color { isPace ? NunaPalette.recoveryBlue : NunaPalette.caution }
    private var unit: String { isPace ? "x" : "" }
    private var win: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: 0) }

    // MARK: Data

    /// Every stored weekly reading, oldest first, each at noon of its day.
    private var weekly: [Point] {
        readings.compactMap { r in Self.dayParser.date(from: r.day).map { Point(date: win.noon($0), value: r.value) } }.sorted { $0.date < $1.date }
    }

    /// The figure the page is about, one per weekly reading: the fitness age, or the pace worked out from the readings up to that week.
    private var all: [Point] {
        guard isPace else { return weekly }
        let rs = weekly.map { PaceOfAging.Reading(time: $0.date.timeIntervalSince1970, fitnessAge: $0.value) }
        var out: [Point] = []
        for i in 0..<rs.count {
            if let p = PaceOfAging.compute(Array(rs.prefix(i + 1))) { out.append(Point(date: weekly[i].date, value: p.pace)) }
        }
        return out
    }

    private var inWindow: [Point] {
        let w = win
        return all.filter { $0.date >= w.start && $0.date < w.domain.upperBound }
    }

    private func calendarAge(on day: Date) -> Double {
        Double(Calendar.current.dateComponents([.day], from: profile.dateOfBirth, to: day).day ?? 0) / 365.25
    }

    private var showsCalendar: Bool { !isPace && profile.age > 0 }

    private var canGoBack: Bool { all.first.map { $0.date < win.start } ?? false }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }

    private var pickedTitle: String {
        guard let picked else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: picked)
    }

    // MARK: Body

    var body: some View {
        let pts = inWindow
        let average: Double? = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            NunaTrendNameBox(icon: isPace ? NunaIcons.paceOfAging : NunaIcons.fitnessAge, title: isPace ? "Pace of aging" : "Fitness age")
            header(pts, average)
            Text(verbatim: sentence(pts, average)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            if showsCalendar { legend }
            chart(pts)
            NavigationLink(value: NunaTodayRoute.fitnessAge) { fitnessAgeCard }.buttonStyle(.plain)
            NunaTrendInfo(kind: isPace ? .paceOfAging : .fitnessAge)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) {
            readings = await repo.exploreSeries(key: "body_age", source: "my-whoop", days: 400)
            loaded = true
        }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private func header(_ pts: [Point], _ average: Double?) -> some View {
        let pickedValue: Double? = picked.flatMap { d in pts.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.value }
        let shown = pickedValue ?? average
        let colour = pickedValue == nil ? NunaPalette.textPrimary : tint
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedValue == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedValue == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map(fmt) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(colour)
                    if shown != nil, !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(colour).textCase(nil) }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(choices: NunaRangeSwitch.standard.filter { $0.value >= 30 }, range: $range) { page = 0 }
                NunaDateStepper(label: win.label, canGoBack: canGoBack, canGoForward: page > 0,
                                back: { page += 1 }, forward: { page = max(0, page - 1) })
            }
        }
        .padding(.horizontal, 2)
    }

    private func sentence(_ pts: [Point], _ average: Double?) -> String {
        guard let average else {
            return isPace ? String(localized: "No pace of aging in this period yet. It needs at least six weekly fitness age readings over five weeks.")
                          : String(localized: "No fitness age in this period yet. Wear your strap day and night to see trends.")
        }
        if isPace {
            if average > 1.05 { return String(localized: "Your pace of aging averaged \(fmt(average))x in this period: you aged faster than the calendar.") }
            if average < 0.95 { return String(localized: "Your pace of aging averaged \(fmt(average))x in this period: you aged more slowly than the calendar.") }
            return String(localized: "Your pace of aging averaged \(fmt(average))x in this period: you aged at about the same rate as the calendar.")
        }
        guard showsCalendar else { return String(localized: "Your fitness age averaged \(fmt(average)) in this period.") }
        let calendar = pts.map { calendarAge(on: $0.date) }.reduce(0, +) / Double(pts.count)
        let gap = average - calendar
        if abs(gap) < 0.5 { return String(localized: "Your fitness age averaged \(fmt(average)) in this period, about the same as your calendar age.") }
        return gap > 0 ? String(localized: "Your fitness age averaged \(fmt(average)) in this period, \(fmt(gap)) years older than your calendar age.")
                       : String(localized: "Your fitness age averaged \(fmt(average)) in this period, \(fmt(-gap)) years younger than your calendar age.")
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            legendItem(tint, "Fitness age")
            legendItem(NunaPalette.textPrimary, "Calendar age")
        }
        .padding(.horizontal, 2).padding(.top, 4)
    }

    private func legendItem(_ colour: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(colour).frame(width: 14, height: 14)
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private var fitnessAgeCard: some View {
        NunaCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("View your fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text("See your latest fitness age and pace of aging, and what drives them.").font(.nunaWords(size: 14)).tracking(0).textCase(nil)
                        .foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            }
        }
    }

    // MARK: Chart

    /// Five evenly spaced labels that cover the readings and, for the fitness age, the calendar age beside them; the pace has the fixed scale of its page.
    private func axis(_ pts: [Point]) -> (low: Double, high: Double, ticks: [Double]) {
        if isPace { return (-1, 3, [-1, 0, 1, 2, 3]) }
        var values = pts.map(\.value)
        if showsCalendar { values += pts.map { calendarAge(on: $0.date) } }
        if values.isEmpty { let base = Double(max(profile.age, 30)); values = [base, base + 8] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.12, 2)
        let step = max(1, ((hi - lo + 2 * pad) / 4).rounded(.up))
        let low = (lo - pad).rounded(.down)
        return (low, low + 4 * step, (0...4).map { low + Double($0) * step })
    }

    private func chart(_ pts: [Point]) -> some View {
        let w = win
        let (low, high, ticks) = axis(pts)
        let ringed: [Point] = range <= 30 ? pts : (pts.last.map { [$0] } ?? [])
        let last = pts.last
        let lastCalendar = last.map { calendarAge(on: $0.date) }
        // The calendar age's label goes on the side of its line away from the fitness age, so the two figures never meet.
        let calendarAbove = (lastCalendar ?? 0) >= (last?.value ?? 0)
        let shownPoint = pts.first(where: { isPicked($0.date) }) ?? last
        return Chart {
            if isPace {
                ForEach([w.start, w.end], id: \.self) { d in
                    LineMark(x: .value("Day", d), y: .value("Reference", 1.0), series: .value("Series", "reference"))
                        .foregroundStyle(NunaPalette.textPrimary).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            } else if showsCalendar, let first = pts.first, let last {
                ForEach([first, last]) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Reference", calendarAge(on: p.date)), series: .value("Series", "reference"))
                        .foregroundStyle(NunaPalette.textPrimary).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                PointMark(x: .value("Day", last.date), y: .value("Reference", calendarAge(on: last.date)))
                    .symbol { ring(NunaPalette.textPrimary) }
            }
            ForEach(pts) { p in
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value), series: .value("Series", "main"))
                    .interpolationMethod(.monotone).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(ringed) { p in
                PointMark(x: .value("Day", p.date), y: .value("Value", p.value)).symbol { ring(tint) }
            }
            if let shownPoint {
                PointMark(x: .value("Day", shownPoint.date), y: .value("Value", shownPoint.value))
                    .symbol { ring(tint, filled: isPicked(shownPoint.date)) }
            }
            if let picked {
                RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: w.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        // The line the pace is read against is the one label the page lights up.
                        let reference = isPace && d == 1
                        Text(verbatim: fmt(d) + unit).font(.nuna(size: 12, weight: .heavy)).textCase(nil)
                            .foregroundStyle(reference ? NunaPalette.textPrimary : NunaPalette.textMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: w.axisDates) { v in
                AxisValueLabel(anchor: .top) { if let d = v.as(Date.self) { w.axisLabel(d) } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        if let p = shownPoint, let x = proxy.position(forX: p.date), let y = proxy.position(forY: p.value) {
                            figure(fmt(p.value) + unit, tint, x: frame.minX + x, y: frame.minY + y + (!isPace && calendarAbove ? 22 : -22), in: frame)
                        }
                        if showsCalendar, let l = last, let x = proxy.position(forX: l.date), let y = proxy.position(forY: calendarAge(on: l.date)) {
                            figure(fmt(calendarAge(on: l.date)), NunaPalette.textPrimary, x: frame.minX + x, y: frame.minY + y + (calendarAbove ? -22 : 22), in: frame)
                        }
                    }
                    .allowsHitTesting(false)
                    Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            guard let touched: Date = proxy.value(atX: g.location.x - frame.minX) else { return }
                            picked = pts.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
                        })
                }
            }
        }
        .frame(height: 340)
        .accessibilityLabel(Text(isPace ? "Pace of aging" : "Fitness age"))
    }

    /// A figure beside its point, kept inside the plot so the newest one is never cut off at the right edge.
    private func figure(_ text: String, _ colour: Color, x: CGFloat, y: CGFloat, in frame: CGRect) -> some View {
        Text(verbatim: text).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).textCase(nil).foregroundStyle(colour).fixedSize()
            .position(x: min(max(x, frame.minX + 22), frame.maxX - 22), y: y)
    }

    private func isPicked(_ date: Date) -> Bool { picked.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    private func ring(_ colour: Color, filled: Bool = false) -> some View {
        Circle().fill(filled ? colour : NunaPalette.canvas).overlay(Circle().stroke(filled ? Color.white : colour, lineWidth: 2.5)).frame(width: 11, height: 11)
    }
}
#endif
