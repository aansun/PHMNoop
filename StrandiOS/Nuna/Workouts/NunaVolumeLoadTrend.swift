#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The trend page of the total volume load: the weight lifted in logged strength sessions (weight times reps of the working sets), a bar a day over a month or six
/// months with its average at the top, a way into the workouts and the heaviest set of each exercise as personal records. The same figures as the Progress tab of
/// Strength Trainer, on the page every other trend has.
struct NunaVolumeLoadTrendView: View {
    @EnvironmentObject private var repo: Repository
    @State private var range = 30
    @State private var page = 0
    /// The day whose bar is touched: its figure replaces the average at the top and the other bars step back.
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?
    /// Volume load (kg) of each day that had a session, by the start of the day.
    @State private var dayVolumes: [Date: Double] = [:]
    /// The heaviest set of each exercise with the day it was lifted, newest first.
    @State private var records: [(exercise: String, kg: Double, ts: Int)] = []
    @State private var loaded = false

    private var window: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: 0) }

    var body: some View {
        NunaDetailScreen("Trend view", centersTitle: true) {
            NunaTrendNameBox(icon: "met:total-volume-load", title: "Total volume load")
            chartBlock
            viewWorkouts
            recordsBlock
        }
        .environment(\.nunaDetailSwitch, nil)
        .nunaWorkoutDestinations()
        .task(id: repo.refreshSeq) { await load() }
    }

    // MARK: Header and chart

    private var chartBlock: some View {
        let w = window, cal = Calendar.current
        let days: [(date: Date, kg: Double)] = (0..<range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start), let kg = dayVolumes[cal.startOfDay(for: d)], kg > 0 else { return nil }
            return (w.noon(d), kg)
        }
        let average: Double? = days.isEmpty ? nil : days.map(\.kg).reduce(0, +) / Double(days.count)
        let most = days.map(\.kg).max() ?? 0
        // Steps of a round size, so the axis never has more than five labels.
        let step = [1000.0, 2000, 2500, 5000, 10000, 20000].first { ceil(max(most, 3000) / $0) <= 4 } ?? 20000
        let top = step * max(3, ceil(most / step))
        let ticks = stride(from: 0.0, through: top, by: step).map { $0 }
        let oldest = dayVolumes.keys.min()
        let pickedKg: Double? = picked.flatMap { p in days.first { cal.isDate($0.date, inSameDayAs: p) }?.kg }
        let shown = pickedKg ?? average
        let pickedTitle: String = {
            guard let p = picked else { return "" }
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
            return f.string(from: p)
        }()
        func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect) -> Date? {
            guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
            return days.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
        }
        func lit(_ d: Date) -> Bool { picked == nil || cal.isDate(d, inSameDayAs: picked!) }
        let blue = Color(hex: "#3E90E0")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pickedKg == nil ? String(localized: "Avg. volume load") : pickedTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: shown.map { nunaThousands($0) } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design))
                            .foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : blue)
                        if shown != nil { Text("kg").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : blue).textCase(nil) }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) {
                    NunaRangeSwitch(choices: [(30, "M"), (180, "6M")], range: $range) { page = 0; picked = nil }
                    NunaDateStepper(label: w.label, canGoBack: oldest.map { w.start > cal.startOfDay(for: $0) } ?? false, canGoForward: page > 0,
                                    back: { page += 1; picked = nil }, forward: { page = max(0, page - 1); picked = nil })
                }
            }
            .padding(.horizontal, 2)
            Chart {
                ForEach(days, id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("kg", d.kg), width: .fixed(range == 30 ? 8 : 3))
                        .foregroundStyle(blue).cornerRadius(1.5).opacity(lit(d.date) ? 1 : 0.3)
                }
                if let p = picked, days.contains(where: { cal.isDate($0.date, inSameDayAs: p) }) {
                    RuleMark(x: .value("Picked", w.noon(p))).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartYScale(domain: 0...top)
            .chartXScale(domain: w.domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(NunaPalette.textMuted.opacity(0.25))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: nunaThousands(d)).font(.nuna(size: 11, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted).textCase(nil) } }
                }
            }
            .chartXAxis(.hidden)
            .chartPlotStyle { $0.padding(.bottom, 46) }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame.map({ geo[$0] }) {
                        ZStack {
                            ForEach(w.axisDates, id: \.self) { d in
                                if let x = proxy.position(forX: d) { w.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 25).allowsHitTesting(false) }
                            }
                            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        let hit = nearest(g.location.x, proxy, frame)
                                        if touchBeganOnPicked == nil { touchBeganOnPicked = picked != nil && hit.map { cal.isDate($0, inSameDayAs: picked!) } == true }
                                        if let hit { picked = hit }
                                    }
                                    .onEnded { g in
                                        if touchBeganOnPicked == true, abs(g.translation.width) < 6 { picked = nil }
                                        touchBeganOnPicked = nil
                                    })
                        }
                    }
                }
            }
            .frame(height: 280)
            .accessibilityLabel(Text("Total volume load"))
            if loaded && days.isEmpty {
                Text("No strength sessions in this period").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.horizontal, 2)
            }
        }
    }

    // MARK: Workouts and records

    private var viewWorkouts: some View {
        NavigationLink(value: NunaWorkoutRoute.gym) {
            HStack(spacing: 16) {
                NunaGlyph("act:strength-trainer", pointSize: 20).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
                Text("View workouts").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 16).frame(height: 64).frame(maxWidth: .infinity)
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var recordsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .accessibilityAddTraits(.isHeader).padding(.top, 14).padding(.horizontal, 4)
            if records.isEmpty {
                Text("Your heaviest set of each exercise shows here once you log a session.").font(.nuna(size: 13.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.horizontal, 4)
            }
            ForEach(Array(records.prefix(5).enumerated()), id: \.offset) { _, r in
                let match = NunaExerciseLibrary.match(r.exercise)
                let row = NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14)) {
                    HStack(spacing: 12) {
                        NunaExerciseThumb(match, width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(verbatim: match?.name ?? r.exercise).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).textCase(nil)
                        Spacer(minLength: 8)
                        Text(verbatim: LiftFormat.trim(r.kg)).font(.nuna(size: 26, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 64, alignment: .trailing)
                        Text("kg").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).frame(width: 20, alignment: .leading)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).opacity(match == nil ? 0 : 1)
                    }
                }
                if let match {
                    NavigationLink { NunaExerciseDetailView(exerciseId: match.id, opensOnHistory: true) } label: { row }.buttonStyle(.plain)
                } else { row }
            }
        }
    }

    // MARK: Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let all = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: now - 400 * 86_400, toTs: now + 86_400)) ?? [])
            .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }
        var perDay: [Date: Double] = [:]
        var best: [String: (kg: Double, ts: Int)] = [:]
        for s in all {
            let sets = (try? await store.liftSets(sessionId: s.id)) ?? []
            if let v = LiftMetrics.volumeLoadKg(sets) {
                perDay[Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.startTs))), default: 0] += v
            }
            for set in sets where !set.isWarmup {
                guard let w = set.weightKg, w > 0, let r = set.reps, r > 0 else { continue }
                if w > (best[set.exercise]?.kg ?? 0) { best[set.exercise] = (w, s.startTs) }
            }
        }
        dayVolumes = perDay
        records = best.map { (exercise: $0.key, kg: $0.value.kg, ts: $0.value.ts) }.sorted { $0.ts != $1.ts ? $0.ts > $1.ts : $0.exercise < $1.exercise }
        loaded = true
    }
}
#endif
