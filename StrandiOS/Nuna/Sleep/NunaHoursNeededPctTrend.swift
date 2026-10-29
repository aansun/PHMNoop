#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page the "Hours vs. needed (%)" card opens: the average of the window, the week / month / six-month switch and date stepper, a sentence,
/// the nights as bars on a 0 to 100% axis (a week writes each figure; a month and six months mark the average with a dashed line and a tag),
/// and the days per level under it: optimal, sufficient and poor.
struct NunaHoursNeededPctTrendView: View {
    /// How many days before today the page opens on: the night the Rest screen was showing.
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()
    @State private var range = 7
    @State private var page = 0

    private struct Day: Identifiable {
        let date: Date
        let value: Double?
        var id: Date { date }
    }

    private var cal: Calendar { Calendar.current }
    private var windowEnd: Date { cal.date(byAdding: .day, value: -(page * range + endingDaysAgo), to: cal.startOfDay(for: Date())) ?? Date() }
    private var windowStart: Date { cal.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }

    /// The percentage of every day of the window that has a night, at noon so a bar sits in the middle of its day.
    private var days: [Day] {
        var byKey: [String: Double] = [:]
        for n in model.nights { if let v = model.hoursVsNeeded(n) { byKey[n.dayKey] = v } }
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: windowStart), let noon = cal.date(byAdding: .hour, value: 12, to: d) else { return nil }
            return Day(date: noon, value: byKey[Repository.localDayKey(d)])
        }
    }

    /// Six months are drawn week by week, so the bars read as a trend and not as 180 slivers.
    private func plotted(_ all: [Day]) -> [Day] {
        guard range > 30 else { return all }
        var out: [Day] = []
        for chunk in stride(from: 0, to: all.count, by: 7) {
            let part = Array(all[chunk..<min(chunk + 7, all.count)])
            let v = part.compactMap(\.value)
            guard !v.isEmpty else { continue }
            out.append(Day(date: part[part.count / 2].date, value: v.reduce(0, +) / Double(v.count)))
        }
        return out
    }

    private func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

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
        let values = all.compactMap(\.value)
        let average: Double? = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(average)
            Text(verbatim: sentence(average)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            chart(plotted(all), average).padding(.top, 8)
            breakdown(values)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
    }

    private var nameBox: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text("Hours vs. needed (%)").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
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
                    Text(verbatim: average.map { "\(Int($0.rounded()))" } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if average != nil { Text("%").font(.nuna(size: 20, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
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
        guard let average else { return String(localized: "Wear your strap to bed each night to track your Hours vs. Needed over time.") }
        let span = range == 7 ? String(localized: "this week was") : (range == 30 ? String(localized: "this month is") : String(localized: "over these six months has been"))
        return String(localized: "Your average Hours vs. Needed \(span) \(pct(average)). Wear your strap to bed each night to track how this changes over time.")
    }

    // MARK: Chart

    private func chart(_ points: [Day], _ average: Double?) -> some View {
        let week = range == 7
        let top = max(100, ceil(((points.compactMap(\.value).max() ?? 100) + 0.01) / 25) * 25)
        let bars = points.filter { $0.value != nil }
        let marked = week ? bars : bars.suffix(1).map { $0 }
        return Chart {
            ForEach(bars) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Hours vs. needed", p.value ?? 0), width: .fixed(week ? 18 : (range == 30 ? 8 : 6)))
                    .foregroundStyle(NunaRestChart.steel).cornerRadius(3)
            }
            if !week, let average {
                RuleMark(y: .value("Average", average)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: windowStart...(cal.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd))
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: 0.0, through: top, by: 25.0).map { $0 }) { v in
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
                        ForEach(marked) { p in
                            if let v = p.value, let x = proxy.position(forX: p.date), let y = proxy.position(forY: v) {
                                Text(verbatim: pct(v)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
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
        .accessibilityLabel(Text("Hours vs. needed as a percentage"))
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

    // MARK: Breakdown

    /// Days of the window per level: optimal above 85%, sufficient from 70 to 85, poor under 70.
    private func breakdown(_ values: [Double]) -> some View {
        NunaDaysBreakdown(title: "Hours vs. needed (%) breakdown", bands: [
            .init(color: NunaRestChart.need, name: "Optimal", range: ">85%") { $0 > 85 },
            .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–85%") { $0 >= 70 && $0 <= 85 },
            .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
        ], values: values)
    }
}
#endif
