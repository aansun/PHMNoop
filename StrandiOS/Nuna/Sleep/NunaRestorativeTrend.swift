#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page the "Restorative sleep (hours)" card opens: the average of the window in hours and minutes, the week / month / six-month switch and
/// date stepper, a sentence, a key (deep and REM) and the nights as bars stacked by stage on a 0 to 6 hour axis. A week writes each total over its
/// bar; a month and six months mark the average with a dashed line and a white Avg. tag and write the last total; six months run week by week.
struct NunaRestorativeTrendView: View {
    /// How many days before today the page opens on: the night the Rest screen was showing.
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()
    @State private var range = 7
    @State private var page = 0

    private struct Day: Identifiable {
        let date: Date
        let rem: Double?    // hours
        let deep: Double?   // hours
        var id: Date { date }
        var total: Double? { rem.flatMap { r in deep.map { r + $0 } } }
    }

    private struct Piece: Identifiable {
        let date: Date
        let stage: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(stage)" }
    }

    private var cal: Calendar { Calendar.current }
    private var windowEnd: Date { cal.date(byAdding: .day, value: -(page * range + endingDaysAgo), to: cal.startOfDay(for: Date())) ?? Date() }
    private var windowStart: Date { cal.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }

    private var days: [Day] {
        var byKey: [String: (Double, Double)] = [:]
        for n in model.nights where n.stages.rem + n.stages.deep > 0 { byKey[n.dayKey] = (n.stages.rem / 60, n.stages.deep / 60) }
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: windowStart), let noon = cal.date(byAdding: .hour, value: 12, to: d) else { return nil }
            let v = byKey[Repository.localDayKey(d)]
            return Day(date: noon, rem: v?.0, deep: v?.1)
        }
    }

    private func plotted(_ all: [Day]) -> [Day] {
        guard range > 30 else { return all }
        var out: [Day] = []
        for chunk in stride(from: 0, to: all.count, by: 7) {
            let part = Array(all[chunk..<min(chunk + 7, all.count)])
            let r = part.compactMap(\.rem), d = part.compactMap(\.deep)
            guard !r.isEmpty, !d.isEmpty else { continue }
            out.append(Day(date: part[part.count / 2].date, rem: r.reduce(0, +) / Double(r.count), deep: d.reduce(0, +) / Double(d.count)))
        }
        return out
    }

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
        let totals = all.compactMap(\.total)
        let average: Double? = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(average)
            Text(verbatim: sentence(average)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            key
            chart(plotted(all), average)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
    }

    private var nameBox: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text("Restorative sleep (hours)").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    private func header(_ average: Double?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Average").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: average.map(hm) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if average != nil { Text("hr").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil) }
                }
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

    private func sentence(_ average: Double?) -> String {
        guard let average else { return String(localized: "Wear your strap to bed each night to track how your restorative sleep changes over time.") }
        let span = range == 7 ? String(localized: "this week was") : (range == 30 ? String(localized: "this month was") : String(localized: "over these six months has been"))
        return String(localized: "Your average restorative sleep \(span) \(hm(average)). Wear your strap to bed each night to track how this changes over time.")
    }

    private var key: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            ForEach([("SWS (Deep)", NunaRestChart.deep), ("REM", NunaRestChart.rem)], id: \.0) { item in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(item.1).frame(width: 12, height: 12)
                    Text(verbatim: item.0).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                }
            }
        }
        .padding(.horizontal, 2).padding(.top, 8)
    }

    // MARK: Chart

    private func chart(_ points: [Day], _ average: Double?) -> some View {
        let week = range == 7
        let top = max(6, ceil(((points.compactMap(\.total).max() ?? 6) + 0.01) / 2) * 2)
        let bars = points.filter { $0.total != nil }
        let marked = week ? bars : bars.suffix(1).map { $0 }
        let pieces: [Piece] = bars.flatMap { p -> [Piece] in
            [Piece(date: p.date, stage: "REM", hours: p.rem ?? 0), Piece(date: p.date, stage: "Deep", hours: p.deep ?? 0)]
        }
        return Chart {
            ForEach(pieces) { piece in
                BarMark(x: .value("Day", piece.date, unit: .day), y: .value("Hours", piece.hours), width: .fixed(week ? 18 : (range == 30 ? 8 : 6)))
                    .foregroundStyle(by: .value("Stage", piece.stage))
            }
            if !week, let average {
                RuleMark(y: .value("Average", average)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale(["REM": NunaRestChart.rem, "Deep": NunaRestChart.deep])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...top)
        .chartXScale(domain: windowStart...(cal.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd))
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: 0.0, through: top, by: 2.0).map { $0 }) { v in
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
                            if let t = p.total, let x = proxy.position(forX: p.date), let y = proxy.position(forY: t) {
                                Text(verbatim: hm(t)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                    .fixedSize().offset(x: !week && x > frame.width - 30 ? -16 : 0)
                                    .position(x: frame.minX + x, y: frame.minY + y - 14)
                            }
                        }
                        if !week, let average, let y = proxy.position(forY: average) {
                            Text("Avg.").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(Color.black)
                                .padding(.horizontal, 8).frame(height: 22).background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .position(x: frame.minX + 24, y: frame.minY + y)
                        }
                        ForEach(axisDates, id: \.self) { d in
                            if let x = proxy.position(forX: d) { axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 26) }
                        }
                    }
                }
            }
        }
        .frame(height: 360)
        .accessibilityLabel(Text("Restorative sleep in hours"))
    }

    private var noons: [Date] {
        (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: windowStart) else { return nil }
            return cal.date(byAdding: .hour, value: 12, to: d)
        }
    }

    private var monthMiddles: [Date] {
        var out: [Date] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: windowStart)) ?? windowStart
        while cursor <= windowEnd {
            if let mid = cal.date(byAdding: .day, value: 14, to: cursor), mid >= windowStart, mid <= windowEnd { out.append(mid) }
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? windowEnd.addingTimeInterval(86_400)
        }
        return out
    }

    private var axisDates: [Date] {
        switch range {
        case 7: return noons
        case 30: return noons.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        default: return monthMiddles
        }
    }

    private func axisLabel(_ d: Date) -> some View {
        let templates: [String] = range == 7 ? ["EEE", "d"] : (range == 30 ? ["MMM", "d"] : ["MMM"])
        return VStack(spacing: 2) {
            ForEach(templates, id: \.self) { t in
                let f = DateFormatter()
                Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(t); return f.string(from: d) }())
                    .font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }
}
#endif
