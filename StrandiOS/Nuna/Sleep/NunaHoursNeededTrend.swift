#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page the "Hours vs. needed (hours)" card opens: the average need and the average sleep of the window, a week, a month or six months, and
/// the two lines over it, the need in green and the sleep in blue. A week writes every figure; a month and six months show the average of each as a
/// dashed line with a tag, and the last figure.
struct NunaHoursNeededTrendView: View {
    /// How many days before today the page opens on: the night the Rest screen was showing.
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()
    @State private var range = 7
    @State private var page = 0

    private struct Day: Identifiable {
        let date: Date
        let slept: Double?   // hours
        let need: Double?    // hours
        var id: Date { date }
    }

    private var cal: Calendar { Calendar.current }
    private var windowEnd: Date { cal.date(byAdding: .day, value: -(page * range + endingDaysAgo), to: cal.startOfDay(for: Date())) ?? Date() }
    private var windowStart: Date { cal.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }

    /// Hours slept and hours needed for every day of the window that has a night.
    private var days: [Day] {
        var byKey: [String: (Double, Double)] = [:]
        for n in model.nights { byKey[n.dayKey] = ((n.daily?.totalSleepMin ?? n.asleepMin) / 60, model.need(n) / 60) }
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: windowStart), let noon = cal.date(byAdding: .hour, value: 12, to: d) else { return nil }
            let v = byKey[Repository.localDayKey(d)]
            return Day(date: noon, slept: v?.0, need: v?.1)
        }
    }

    /// Six months are drawn week by week, so the lines read as a trend and not as 180 points.
    private func plotted(_ all: [Day]) -> [Day] {
        guard range > 30 else { return all }
        var out: [Day] = []
        for chunk in stride(from: 0, to: all.count, by: 7) {
            let part = Array(all[chunk..<min(chunk + 7, all.count)])
            let s = part.compactMap(\.slept), n = part.compactMap(\.need)
            guard !s.isEmpty || !n.isEmpty, let mid = part[part.count / 2] as Day? else { continue }
            out.append(Day(date: mid.date, slept: s.isEmpty ? nil : s.reduce(0, +) / Double(s.count), need: n.isEmpty ? nil : n.reduce(0, +) / Double(n.count)))
        }
        return out
    }

    private func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    private func hm(_ hours: Double) -> String { NunaRestChart.hm(hours * 60) }

    private var dateLabel: String {
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("MMM d")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("MMM d, yy")
        return "\(a.string(from: windowStart)) – \(b.string(from: windowEnd))"
    }

    private var canGoBack: Bool {
        guard let oldest = model.nights.map(\.wakeDate).min() else { return false }
        return windowStart > cal.startOfDay(for: oldest)
    }

    var body: some View {
        let all = days
        let avgNeed = mean(all.compactMap(\.need)), avgSlept = mean(all.compactMap(\.slept))
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(avgNeed, avgSlept)
            if let sentence = sentence(avgNeed, avgSlept) {
                Text(verbatim: sentence).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            }
            chart(plotted(all), avgNeed, avgSlept).padding(.top, 8)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
    }

    /// The name of the reading, in a box, as the reference shows it.
    private var nameBox: some View {
        NunaTrendNameBox(icon: "moon", title: "Hours vs. needed (hours)")
    }

    private func header(_ need: Double?, _ slept: Double?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 18) {
                figure(need, "Avg. need", NunaRestChart.need)
                figure(slept, "Avg. hours", NunaRestChart.steel)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(range: $range) { page = 0 }
                NunaDateStepper(label: dateLabel, canGoBack: canGoBack, canGoForward: page > 0,
                                back: { page += 1 }, forward: { page = max(0, page - 1) })
            }
        }
        .padding(.horizontal, 2)
    }

    private func figure(_ hours: Double?, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: hours.map(hm) ?? "–").font(.nuna(size: 32, weight: .semibold, design: NunaType.design)).foregroundStyle(color)
                if hours != nil { Text("hr").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(color).textCase(nil) }
            }
            Text(label).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func sentence(_ need: Double?, _ slept: Double?) -> String? {
        guard let need, let slept else { return String(localized: "Wear your strap to bed each night to track how your hours of sleep and sleep need change over time.") }
        let gap = need - slept
        let span = range == 7 ? String(localized: "this week") : (range == 30 ? String(localized: "this month") : String(localized: "these six months"))
        if gap > 0.25 {
            return String(localized: "Over \(span) you slept \(hm(slept)) a night on average against a need of \(hm(need)), \(hm(gap)) short. Keep an eye on sleep need to plan for more sleep when your body asks for it.")
        }
        return String(localized: "Over \(span) you slept \(hm(slept)) a night on average, in line with a need of \(hm(need)).")
    }

    // MARK: Chart

    private func chart(_ points: [Day], _ avgNeed: Double?, _ avgSlept: Double?) -> some View {
        let top = max(12, ceil(((points.flatMap { [$0.slept, $0.need] }.compactMap { $0 }.max() ?? 12) + 0.01) / 3) * 3)
        let week = range == 7
        // Every figure on a week; only the last on a month and six months.
        let marked = week ? points : points.suffix(1).map { $0 }
        let needPoints = points.filter { $0.need != nil }, sleptPoints = points.filter { $0.slept != nil }
        return Chart {
            ForEach(needPoints) { p in
                LineMark(x: .value("Day", p.date), y: .value("Need", p.need ?? 0), series: .value("Series", "need")).foregroundStyle(NunaRestChart.need)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(sleptPoints) { p in
                LineMark(x: .value("Day", p.date), y: .value("Sleep", p.slept ?? 0), series: .value("Series", "sleep")).foregroundStyle(NunaRestChart.steel)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if !week {
                if let avgNeed { RuleMark(y: .value("Avg need", avgNeed)).foregroundStyle(NunaRestChart.need).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4])) }
                if let avgSlept { RuleMark(y: .value("Avg sleep", avgSlept)).foregroundStyle(NunaRestChart.steel).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4])) }
            }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: windowStart...(cal.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd))
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: 0.0, through: top, by: 3.0).map { $0 }) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: "\(Int(d))").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) } }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ForEach(marked) { p in
                            if let n = p.need, let x = proxy.position(forX: p.date), let y = proxy.position(forY: n) {
                                mark(hm(n), NunaRestChart.need, above: true, shift: x > frame.width - 30 ? -18 : 0).position(x: frame.minX + x, y: frame.minY + y)
                            }
                            if let sl = p.slept, let x = proxy.position(forX: p.date), let y = proxy.position(forY: sl) {
                                mark(hm(sl), NunaRestChart.steel, above: false, shift: x > frame.width - 30 ? -18 : 0).position(x: frame.minX + x, y: frame.minY + y)
                            }
                        }
                        ForEach(axisDates, id: \.self) { d in
                            if let x = proxy.position(forX: d) { axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 26) }
                        }
                        if !week {
                            // The two tags sit at the line they name, pushed apart when the averages are close.
                            let ys = tagPositions(proxy.position(forY: avgNeed ?? 0), proxy.position(forY: avgSlept ?? 0))
                            if avgNeed != nil { tag(NunaRestChart.need).position(x: frame.minX + 24, y: frame.minY + ys.0) }
                            if avgSlept != nil { tag(NunaRestChart.steel).position(x: frame.minX + 24, y: frame.minY + ys.1) }
                        }
                    }
                }
            }
        }
        .frame(height: 360)
        .accessibilityLabel(Text("Hours of sleep and sleep needed"))
    }

    /// A ring on its point with the figure above it or below it, drawn from the point's own position so the two always line up.
    private func mark(_ text: String, _ color: Color, above: Bool, shift: CGFloat = 0) -> some View {
        ZStack {
            ring(color)
            Text(verbatim: text).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(color)
                .fixedSize().offset(x: shift, y: above ? -18 : 18)
        }
    }

    /// Heights for the two tags, kept at least `gap` apart: the need's above the sleep's, as the lines are.
    private func tagPositions(_ a: CGFloat?, _ b: CGFloat?, gap: CGFloat = 24) -> (CGFloat, CGFloat) {
        let need = a ?? 0, slept = b ?? 0
        guard abs(slept - need) < gap else { return (need, slept) }
        let mid = (need + slept) / 2
        return (mid - gap / 2, mid + gap / 2)
    }

    /// Noon of each day shown, so a point sits in the middle of its day.
    private var noons: [Date] {
        (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: windowStart) else { return nil }
            return cal.date(byAdding: .hour, value: 12, to: d)
        }
    }

    /// Where the time axis is labelled: every day of a week, every seventh day of a month, the middle of each month over six months.
    private var axisDates: [Date] {
        switch range {
        case 7: return noons
        case 30: return noons.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        default: return monthMiddles
        }
    }

    /// The label drawn under a point, from the same position the point uses, so a label is always under its day.
    private func axisLabel(_ d: Date) -> some View {
        switch range {
        case 7: return dayLabel(d, ["EEE", "d"])
        case 30: return dayLabel(d, ["MMM", "d"])
        default: return dayLabel(d, ["MMM"])
        }
    }

    /// The middle of each calendar month in the window, for six months' labels.
    private var monthMiddles: [Date] {
        var out: [Date] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: windowStart)) ?? windowStart
        while cursor <= windowEnd {
            if let mid = cal.date(byAdding: .day, value: 14, to: cursor), mid >= windowStart, mid <= windowEnd { out.append(mid) }
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? windowEnd.addingTimeInterval(86_400)
        }
        return out
    }

    private func dayLabel(_ date: Date, _ templates: [String]) -> some View {
        VStack(spacing: 2) {
            ForEach(templates, id: \.self) { t in
                let f = DateFormatter()
                Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(t); return f.string(from: date) }())
                    .font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private func ring(_ color: Color) -> some View {
        Circle().fill(NunaPalette.canvas).overlay(Circle().strokeBorder(color, lineWidth: 2.5)).frame(width: 12, height: 12)
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(verbatim: text).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(color)
    }

    private func tag(_ color: Color) -> some View {
        Text("Avg.").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.canvas)
            .padding(.horizontal, 8).frame(height: 22).background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
#endif
