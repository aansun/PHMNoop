#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// The page the "Restorative sleep (hours)" card opens: the average of the window in hours and minutes, the week / month / six-month switch and
/// date stepper, a sentence, a key (deep and REM) and the nights as bars stacked by stage on a 0 to 6 hour axis. A week writes each total over its
/// bar; a month marks the average with a dashed line and a white Avg. tag; six months are the average of each sixth over a faint daily line with the
/// change against the one before. Touching a bar of a week or a month shows its day and total at the top and steps the other bars back.
struct NunaRestorativeTrendView: View {
    var endingDaysAgo = 0

    @EnvironmentObject private var repo: Repository
    @StateObject private var history = NunaSleepHistory()
    @State private var range = 7
    @State private var page = 0
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?

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

    private var win: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: endingDaysAgo) }

    private var days: [Day] {
        let w = win, cal = Calendar.current
        return (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start) else { return nil }
            let key = Repository.localDayKey(d)
            return Day(date: w.noon(d), rem: history.remMin[key].map { $0 / 60 }, deep: history.deepMin[key].map { $0 / 60 })
        }
    }

    private func hm(_ hours: Double) -> String { NunaRestChart.hm(hours * 60) }

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

    var body: some View {
        let all = days
        let totals = all.compactMap(\.total)
        let average: Double? = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header(all, average)
            Text(verbatim: sentence(average)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            key
            chart(all, average)
            NunaTrendInfo(kind: .restorative)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await history.load(repo: repo) }
        .onChange(of: range) { _, _ in picked = nil }
        .onChange(of: page) { _, _ in picked = nil }
    }

    private var nameBox: some View {
        NunaTrendNameBox(icon: "met:restorative-sleep-hours", title: "Restorative sleep (hours)")
    }

    private func header(_ all: [Day], _ average: Double?) -> some View {
        let pickedTotal: Double? = picked.flatMap { d in all.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.total }
        let shown = pickedTotal ?? average
        let tint = pickedTotal == nil ? NunaPalette.textPrimary : NunaRestChart.rem
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pickedTotal == nil ? String(localized: "Average") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedTotal == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map(hm) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil { Text("hr").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                }
                if pickedTotal == nil {
                    NunaChangeChip(average: average, prior: NunaTrendChange.prior(start: win.start, range: range) { d in
                        let key = Repository.localDayKey(d)
                        guard let rem = history.remMin[key], let deep = history.deepMin[key] else { return nil }
                        return (rem + deep) / 60
                    }, range: range, upIsGood: true)
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

    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among bars: [Day]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return bars.filter { $0.total != nil }.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    private func chart(_ points: [Day], _ average: Double?) -> some View {
        let w = win
        let week = range == 7, sixMonths = range > 30
        let top = max(6, ceil((points.compactMap(\.total).max() ?? 6) / 2) * 2)
        let bars = points.filter { $0.total != nil }
        let marked = week ? bars : (sixMonths || picked != nil ? [] : bars.suffix(1).map { $0 })
        let segments = sixMonths ? NunaPeriodSegment.make(bars.compactMap { p in p.total.map { (p.date, $0) } }, from: w.start, to: w.end) : []
        let pieces: [Piece] = bars.flatMap { p -> [Piece] in
            [Piece(date: p.date, stage: "REM", hours: p.rem ?? 0), Piece(date: p.date, stage: "Deep", hours: p.deep ?? 0)]
        }
        return Chart {
            if sixMonths {
                ForEach(bars) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Hours", p.total ?? 0)).foregroundStyle(Color.white.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            } else {
                ForEach(pieces) { piece in
                    BarMark(x: .value("Day", piece.date, unit: .day), y: .value("Hours", piece.hours), width: .fixed(week ? 18 : 8))
                        .foregroundStyle(by: .value("Stage", piece.stage))
                        .opacity(picked == nil || isPicked(piece.date) ? 1 : 0.3)
                }
                if !week, let average {
                    RuleMark(y: .value("Average", average)).foregroundStyle(Color.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                }
                if let picked {
                    RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
        .chartForegroundStyleScale(["REM": NunaRestChart.rem, "Deep": NunaRestChart.deep])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...top)
        .chartXScale(domain: w.domain)
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
                        ZStack {
                            ForEach(marked) { p in
                                if let t = p.total, let x = proxy.position(forX: p.date), let y = proxy.position(forY: t) {
                                    Text(verbatim: hm(t)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                        .fixedSize().offset(x: !week && x > frame.width - 30 ? -16 : 0)
                                        .position(x: frame.minX + x, y: frame.minY + y - 14)
                                }
                            }
                            if sixMonths { NunaSegmentsLayer(segments: segments, proxy: proxy, frame: frame, text: { hm($0) }) }
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
        .accessibilityLabel(Text("Restorative sleep in hours"))
    }
}
#endif
