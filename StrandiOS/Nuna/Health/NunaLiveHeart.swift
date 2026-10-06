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

    /// The clock time of the first, middle and last banked reading, so the labels match what the line shows.
    private var dayLabels: [String] {
        guard banked.count >= 2 else { return [] }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("HH:mm")
        func t(_ i: Int) -> String { f.string(from: Date(timeIntervalSince1970: TimeInterval(banked[i].ts))) }
        return [t(0), t(banked.count / 2), t(banked.count - 1)]
    }

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
                            Text("Beats per minute").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary)
                            Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        Spacer()
                        NunaChip(isLive ? "Live" : (live.connected ? "Strap connected" : "Not connected"),
                                 color: isLive ? NunaPalette.charge : (live.connected ? nil : NunaPalette.warning))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "heart.fill").font(.nuna(size: 20)).foregroundStyle(NunaPalette.alert)
                        Text(verbatim: bigBpm.map(String.init) ?? "–")
                            .font(.nuna(size: 52, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(52)).foregroundStyle(NunaPalette.textPrimary)
                        Text("bpm").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Text(subtitle).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    if isLive || banked.count >= 2 {
                        NunaHRTrace(values: isLive ? samples : banked.map(\.bpm),
                                    segments: isLive ? nil : hrGapSegments(bucketTs: banked.map(\.ts), bucketSeconds: 300),
                                    xLabels: isLive ? [String(localized: "Earlier"), String(localized: "Now")] : dayLabels)
                            .frame(height: 110)
                        let vals = isLive ? samples : banked.map(\.bpm)
                        HStack {
                            stat("Min", vals.min()); Spacer(); stat("Avg", vals.reduce(0, +) / Double(vals.count)); Spacer(); stat("Max", vals.max())
                        }
                    } else {
                        Text(live.connected ? "Waiting for a live heartbeat…" : "Connect your strap to see live heart rate")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).textCase(nil)
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
            Text(label).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Text(verbatim: v.map { String(Int($0.rounded())) } ?? "–").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }
}

/// A heart-rate line in red with its axes: the beats-per-minute scale on the left, three guides, a baseline, and optional labels under it.
/// `segments` lifts the pen across hours nothing was recorded.
struct NunaHRTrace: View {
    let values: [Double]
    let segments: [String]?
    /// Labels spread evenly under the baseline (for example 00:00, 06:00, 12:00, Now). Empty draws none.
    var xLabels: [String] = []
    var color: Color = NunaPalette.alert

    private var scale: (lo: Double, hi: Double)? {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max((hi - lo) * 0.12, 2)
        return (lo - pad, hi + pad)
    }

    var body: some View {
        let sc = scale
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // The scale, top to bottom, at the three guides.
                VStack {
                    ForEach([0, 1, 2], id: \.self) { i in
                        if i > 0 { Spacer(minLength: 0) }
                        Text(verbatim: sc.map { String(Int(($0.hi - ($0.hi - $0.lo) * Double(i) / 2).rounded())) } ?? "")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                    }
                }
                .frame(width: 26, alignment: .trailing)
                Canvas { ctx, size in
                    guard values.count >= 2, let sc else { return }
                    let span = max(sc.hi - sc.lo, 1)
                    for i in 0...2 {
                        var g = Path(); let y = size.height * CGFloat(i) / 2
                        g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(NunaPalette.ink.opacity(i == 2 ? 0.22 : 0.08)), lineWidth: i == 2 ? 1.2 : 1)
                    }
                    func pt(_ i: Int) -> CGPoint {
                        CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: size.height * CGFloat(1 - (values[i] - sc.lo) / span))
                    }
                    let runs: [ClosedRange<Int>] = (segments.map { hrGapRuns(segments: $0) } ?? [0...(values.count - 1)])
                    for run in runs {
                        if run.count == 1 {
                            let c = pt(run.lowerBound)
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(color))
                            continue
                        }
                        var p = Path(); p.move(to: pt(run.lowerBound))
                        for i in (run.lowerBound + 1)...run.upperBound { p.addLine(to: pt(i)) }
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if !xLabels.isEmpty {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 34, height: 1)
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { i, t in
                        Text(verbatim: t).font(.system(size: 11, weight: .medium)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : (i == xLabels.count - 1 ? .trailing : .center))
                    }
                }
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
    /// What the chart spans when it is not zoomed: from the first to the last reading on show, so it opens full and the latest
    /// value sits at the right edge instead of trailing off into an empty rest of the day.
    private var chartRange: ClosedRange<Date> {
        guard let first = series.points.first?.date, let last = series.points.last?.date, last > first else { return dayBounds }
        return max(first, dayBounds.lowerBound)...min(last, dayBounds.upperBound)
    }
    private var visibleWindow: ClosedRange<Date> { zoomDomain ?? dayBounds }
    private var isLatest: Bool { dayStart >= Repository.logicalDayStart(Date()) }
    private let metrics: [Repository.TimelineMetric] = [.hr, .hrv, .spo2, .skinTemp, .respiration, .motion, .bandSleepState]

    var body: some View {
        NunaDetailScreen("Deep timeline") {
            metricMenu
            chartCard
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

    /// One colour per signal, so the chart and its chip read as the same thing.
    private func tint(_ m: Repository.TimelineMetric) -> Color {
        switch m {
        case .hr: return NunaPalette.alert
        case .hrv: return NunaPalette.charge
        case .spo2, .respiration, .bandSleepState: return NunaPalette.rest
        case .skinTemp: return NunaPalette.effort
        default: return NunaPalette.ink
        }
    }

    private var taskKey: String {
        "\(metric.rawValue)|\(Int(dayStart.timeIntervalSince1970))|\(Int(visibleWindow.lowerBound.timeIntervalSince1970))|\(Int(visibleWindow.upperBound.timeIntervalSince1970))|\(repo.refreshSeq)"
    }

    /// The signal picker: one dropdown instead of a row of tabs, tinted with the colour of the signal on show.
    private var metricMenu: some View {
        Menu {
            ForEach(metrics) { m in
                Button { metric = m } label: {
                    if metric == m { Label(m.title, systemImage: "checkmark") } else { Text(verbatim: m.title) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(tint(metric)).frame(width: 9, height: 9)
                Text(verbatim: metric.title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(tint(metric).opacity(0.7), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// The day switcher that sits in the top right of the chart card: previous day, the date, next day.
    private var dayNav: some View {
        HStack(spacing: 4) {
            Button { stepDay(-1) } label: { Image(systemName: "chevron.left").font(.nuna(size: 13, weight: .bold)).frame(width: 30, height: 30) }
            Text(verbatim: dayLabel).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(minWidth: 72)
            Button { stepDay(1) } label: { Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).frame(width: 30, height: 30) }.disabled(isLatest)
                .opacity(isLatest ? 0.35 : 1)
        }
        .foregroundStyle(NunaPalette.textPrimary)
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

    /// One card, like the other detail screens: the signal and the day switcher on top, the latest reading, the chart, and the minimum,
    /// average and maximum of what is on show as plain text underneath.
    private var chartCard: some View {
        let v = displayPoints.map(\.value)
        return NunaCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(verbatim: displayPoints.last.map { format($0.value) } ?? "–").font(.nuna(size: 40, weight: .bold, design: NunaType.design))
                                .foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: unit).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Text(verbatim: resolution).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    dayNav
                }
                Group {
                    if loading && series.points.isEmpty {
                        ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 280)
                    } else if series.points.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.slash").font(.nuna(size: 26, weight: .light)).foregroundStyle(NunaPalette.textMuted)
                            Text("Nothing recorded for this window").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        OverviewHRChart(points: displayPoints, sleep: sleepSpan, workouts: workoutSpans,
                                        gradient: Gradient(colors: [tint(metric).opacity(0.6), tint(metric)]),
                                        valueRange: range(displayPoints), xRange: chartRange, height: 280, touchScrub: true,
                                        zoomDomain: $zoomDomain, zoomBounds: panBounds,
                                        valueFormat: { format($0) },
                                        dateFormat: { Self.timeFmt.string(from: $0) })
                    }
                }
                if !v.isEmpty {
                    Rectangle().fill(NunaPalette.hairlineSoft).frame(height: 1)
                    HStack(spacing: 0) {
                        stat("Min", format(v.min() ?? 0))
                        stat("Avg", format(v.reduce(0, +) / Double(max(1, v.count))))
                        stat("Max", format(v.max() ?? 0))
                    }
                }
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: zoomDomain == nil ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            Text(zoomDomain == nil ? "Pinch to zoom · drag to pan · hold to read" : "Zoomed in. Drag to pan · hold to read")
            Spacer()
            if zoomDomain != nil { Button("Reset") { zoomDomain = nil }.foregroundStyle(NunaPalette.textPrimary) }
        }
        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
