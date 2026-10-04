#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Live heart rate card (same data as "Beats per minute" on the Default Today screen)

/// The live heart-rate card. While the strap streams it shows the rolling beat-by-beat trace; otherwise
/// today's banked 5-minute averages since midnight, with gaps left as gaps. Tapping opens the deep timeline.
struct NunaLiveHRCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @State private var banked: [(ts: Int, bpm: Double)] = []
    @State private var samples: [Double] = []
    private let maxSamples = 90

    private var isLive: Bool { live.connected && samples.count >= 2 }

    private var bigBpm: Int? {
        if let hr = live.heartRate, hr > 0, live.connected { return hr }
        return banked.last.map { Int($0.bpm.rounded()) }
    }

    private var subtitle: LocalizedStringKey {
        if isLive { return "Live · beat by beat" }
        if banked.count >= 2 { return "5-minute average · since midnight" }
        return live.connected ? "Waiting for the strap" : "Strap not connected"
    }

    var body: some View {
        NavigationLink(value: NunaTodayRoute.liveHeart) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Text("Beats per minute").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary)
                            Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        Spacer()
                        NunaChip(isLive ? "Live" : (live.connected ? "Strap connected" : "Not connected"),
                                 color: isLive ? NunaPalette.charge : (live.connected ? nil : NunaPalette.warning))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "heart.fill").font(.nuna(size: 20)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: bigBpm.map(String.init) ?? "–")
                            .font(.nuna(size: 52, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("bpm").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Text(subtitle).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    if isLive || banked.count >= 2 {
                        NunaHRTrace(values: isLive ? samples : banked.map(\.bpm),
                                    segments: isLive ? nil : hrGapSegments(bucketTs: banked.map(\.ts), bucketSeconds: 300))
                            .frame(height: 92)
                        let vals = isLive ? samples : banked.map(\.bpm)
                        HStack {
                            stat("Min", vals.min()); Spacer(); stat("Avg", vals.reduce(0, +) / Double(vals.count)); Spacer(); stat("Max", vals.max())
                        }
                    } else {
                        Text(live.connected ? "Waiting for a live heartbeat…" : "Connect your strap to see live heart rate")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: repo.refreshSeq) {
            let from = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
            banked = await repo.hrBuckets(from: from, to: Int(Date().timeIntervalSince1970), bucketSeconds: 300).map { ($0.ts, $0.bpm) }
        }
        .onAppear { if samples.isEmpty, let hr = live.heartRate, hr > 0 { samples = [Double(hr)] } }
        .onChange(of: live.heartRate) { _, hr in
            guard let hr, hr > 0 else { return }
            samples.append(Double(hr))
            if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v.map { String(Int($0.rounded())) } ?? "–").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }
}

/// A heart-rate line with three faint guides. `segments` lifts the pen across hours nothing was recorded.
struct NunaHRTrace: View {
    let values: [Double]
    let segments: [String]?

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return }
            let pad = max((hi - lo) * 0.12, 2)
            let lo2 = lo - pad, span = max(hi - lo + 2 * pad, 1)
            for i in 0...2 {
                var g = Path(); let y = size.height * CGFloat(i) / 2
                g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(g, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
            }
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height * CGFloat(1 - (values[i] - lo2) / span))
            }
            let runs: [ClosedRange<Int>] = (segments.map { hrGapRuns(segments: $0) } ?? [0...(values.count - 1)])
            for run in runs {
                if run.count == 1 {
                    let c = pt(run.lowerBound)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(NunaPalette.ink))
                    continue
                }
                var p = Path(); p.move(to: pt(run.lowerBound))
                for i in (run.lowerBound + 1)...run.upperBound { p.addLine(to: pt(i)) }
                ctx.stroke(p, with: .color(NunaPalette.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Deep timeline (Nuna look for the existing per-second timeline)

struct NunaDeepTimelineView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    @State private var dayStart = Repository.logicalDayStart(Date())
    @State private var didLand = false
    @State private var metric: Repository.TimelineMetric = .hr
    @State private var series: Repository.TimelineSeries = .empty
    @State private var sleepSpan: OverviewHRChart.SleepSpan?
    @State private var workoutSpans: [OverviewHRChart.WorkoutSpan] = []
    @State private var zoomDomain: ClosedRange<Date>?
    @State private var loading = true

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }
    private var dayBounds: ClosedRange<Date> { dayStart...dayStart.addingTimeInterval(86_400) }
    private var panBounds: ClosedRange<Date> { dayStart.addingTimeInterval(-2 * 86_400)...dayBounds.upperBound }
    private var visibleWindow: ClosedRange<Date> { zoomDomain ?? dayBounds }
    private var isLatest: Bool { dayStart >= Repository.logicalDayStart(Date()) }
    private let metrics: [Repository.TimelineMetric] = [.hr, .hrv, .spo2, .skinTemp, .respiration, .motion, .bandSleepState]

    var body: some View {
        NunaDetailScreen("Deep timeline") {
            Text("Every second of your day, zoomable.").font(.nuna(size: 14, weight: .semibold))
                .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            metricChips
            dayNav
            chartCard
            if !series.points.isEmpty { statTiles }
            hint
        }
        .task(id: taskKey) { await reload() }
        .task(id: "\(Int(dayStart.timeIntervalSince1970))|\(repo.refreshSeq)") { await reloadAnnotations() }
        .task {
            guard !didLand else { return }
            didLand = true
            if let latest = await repo.latestDataDayStart(), latest < dayStart { dayStart = latest }
        }
    }

    private var taskKey: String {
        "\(metric.rawValue)|\(Int(dayStart.timeIntervalSince1970))|\(Int(visibleWindow.lowerBound.timeIntervalSince1970))|\(Int(visibleWindow.upperBound.timeIntervalSince1970))|\(repo.refreshSeq)"
    }

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(metrics) { m in
                    Button { metric = m } label: {
                        Text(verbatim: m.title).font(.nuna(size: 13.5, weight: .bold))
                            .foregroundStyle(metric == m ? NunaPalette.onAccent : NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background(metric == m ? NunaPalette.accent : NunaPalette.glassStrong, in: Capsule())
                            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: metric == m ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var dayNav: some View {
        HStack {
            step("chevron.left", true) { stepDay(-1) }
            Spacer()
            Text(verbatim: dayLabel).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            step("chevron.right", !isLatest) { stepDay(1) }
        }
    }

    private func step(_ s: String, _ enabled: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.nuna(size: 15, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
        }.disabled(!enabled)
    }

    private func stepDay(_ d: Int) {
        let next = dayStart.addingTimeInterval(Double(d) * 86_400)
        if d > 0 && next > Repository.logicalDayStart(Date()) { return }
        dayStart = next; zoomDomain = nil
    }

    private var dayLabel: String {
        let today = Repository.logicalDayStart(Date())
        if Calendar.current.isDate(dayStart, inSameDayAs: today) { return String(localized: "Today") }
        if Calendar.current.isDate(dayStart, inSameDayAs: today.addingTimeInterval(-86_400)) { return String(localized: "Yesterday") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: dayStart)
    }

    private var displayPoints: [TrendPoint] {
        guard metric == .skinTemp, temperatureUnit == .fahrenheit else { return series.points }
        return series.points.map { TrendPoint(date: $0.date, value: UnitFormatter.celsiusToFahrenheit($0.value)) }
    }

    private var chartCard: some View {
        NunaCard(padding: EdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(verbatim: metric.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(verbatim: resolution).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                if let last = displayPoints.last {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: format(last.value)).font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: unit).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                Group {
                    if loading && series.points.isEmpty {
                        ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 260)
                    } else if series.points.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.slash").font(.nuna(size: 26, weight: .light)).foregroundStyle(NunaPalette.textMuted)
                            Text("Nothing recorded for this window").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        OverviewHRChart(points: displayPoints, sleep: sleepSpan, workouts: workoutSpans,
                                        gradient: Gradient(colors: [NunaPalette.ink.opacity(0.55), Color.white]),
                                        valueRange: range(displayPoints), xRange: dayBounds, height: 260, touchScrub: true,
                                        zoomDomain: $zoomDomain, zoomBounds: panBounds,
                                        valueFormat: { format($0) },
                                        dateFormat: { Self.timeFmt.string(from: $0) })
                    }
                }
            }
        }
    }

    private var statTiles: some View {
        let v = displayPoints.map(\.value)
        return HStack(spacing: 12) {
            NunaStatTile(label: "Min", value: format(v.min() ?? 0), unit: unit)
            NunaStatTile(label: "Avg", value: format(v.reduce(0, +) / Double(max(1, v.count))), unit: unit)
            NunaStatTile(label: "Max", value: format(v.max() ?? 0), unit: unit)
        }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: zoomDomain == nil ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            Text(zoomDomain == nil ? "Pinch to zoom · drag to pan · hold to read" : "Zoomed in. Drag to pan · hold to read")
            Spacer()
            if zoomDomain != nil { Button("Reset") { zoomDomain = nil }.foregroundStyle(NunaPalette.textPrimary) }
        }
        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
    }

    private var resolution: String {
        guard !series.points.isEmpty else { return "—" }
        if series.isRaw { return String(localized: "Raw · per second") }
        let m = series.bucketSeconds / 60
        return m >= 1 ? String(localized: "\(m)-minute average") : String(localized: "\(series.bucketSeconds)-second average")
    }

    private var unit: String {
        switch metric {
        case .hr: return "bpm"
        case .skinTemp: return UnitFormatter.temperatureUnit(temperatureUnit)
        case .hrv: return "ms"
        case .motion: return "g"
        case .ouraMovement: return "s"
        default: return ""
        }
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case .hr, .respiration, .hrv, .ouraMovement: return String(Int(v.rounded()))
        case .skinTemp: return String(format: "%.1f", v)
        case .spo2, .motion: return String(format: "%.2f", v)
        case .bandSleepState: return FullDayChartView.bandStateLabel(v)
        }
    }

    private func range(_ pts: [TrendPoint]) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return metric == .hr ? 40...120 : 0...1 }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    private func reload() async {
        loading = true
        let w = visibleWindow
        let r = await repo.timelineSeries(metric: metric, from: Int(w.lowerBound.timeIntervalSince1970),
                                          to: Int(w.upperBound.timeIntervalSince1970), targetPoints: 600)
        guard !Task.isCancelled else { return }
        series = r; loading = false
    }

    private func reloadAnnotations() async {
        let daysBack = max(0, Int(Date().timeIntervalSince(dayStart) / 86_400)) + 2
        let sleeps: [OverviewHRChart.SleepSpan] = await repo.allSleepSessions(days: daysBack).map { s in
            let secs = s.endTs - s.effectiveStartTs
            return .init(start: Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs)), end: Date(timeIntervalSince1970: TimeInterval(s.endTs)),
                         label: "\(max(0, secs) / 3600):" + String(format: "%02d", (max(0, secs) % 3600) / 60))
        }
        let works: [OverviewHRChart.WorkoutSpan] = await repo.workoutRows(days: daysBack).map { w in
            .init(start: Date(timeIntervalSince1970: TimeInterval(w.startTs)), end: Date(timeIntervalSince1970: TimeInterval(w.endTs)), symbol: sportSymbol(w.sport))
        }
        guard !Task.isCancelled else { return }
        sleepSpan = OverviewHRChart.mainSleep(sleeps, overlapping: dayBounds)
        workoutSpans = OverviewHRChart.workouts(works, overlapping: dayBounds)
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
#endif
