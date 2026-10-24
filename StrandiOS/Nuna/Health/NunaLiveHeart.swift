#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Live heart rate card (same data as "Beats per minute" on the Default Today screen)

/// The live heart-rate card, drawn like a bedside monitor: a dark screen with faint graph paper, the reading in green at the right and the beat-by-beat trace
/// beside it, with a dot that pulses at the pace of the heart. While the strap streams the trace is live. When it does not, the card keeps the last trace
/// it has (the newest readings stored on the phone) and says when that signal was, until a new one arrives. Tapping opens the deep timeline.
struct NunaLiveHRCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var profile: ProfileStore
    /// Today's banked 5-minute averages: the last resort when no recent beat-by-beat readings are stored.
    @State private var banked: [(ts: Int, bpm: Double)] = []
    /// The newest stored readings, oldest first, kept on show while nothing live arrives.
    @State private var recent: [(ts: Int, bpm: Double)] = []
    @State private var samples: [Double] = []
    private let maxSamples = 90

    private var isLive: Bool { live.connected && (live.heartRate ?? 0) > 0 && samples.count >= 2 }

    /// What the trace draws: the live samples, else the last stored readings, else today's averages.
    private var trace: [Double] {
        if isLive { return samples }
        if recent.count >= 2 { return recent.map(\.bpm) }
        return banked.suffix(36).map(\.bpm)
    }

    /// When the trace on show last got a reading, for the line "Last signal 14:32".
    private var lastSignal: Date? {
        if let t = recent.last?.ts ?? banked.last?.ts { return Date(timeIntervalSince1970: TimeInterval(t)) }
        return nil
    }

    private var bigBpm: Int? {
        if let hr = live.heartRate, hr > 0, live.connected { return hr }
        return trace.last.map { Int($0.rounded()) }
    }

    private var statusText: String {
        if isLive { return String(localized: "Live") }
        if let t = lastSignal {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(t) ? "HH:mm" : "d MMM HH:mm")
            return String(localized: "Last signal \(f.string(from: t))")
        }
        return live.connected ? String(localized: "Strap connected") : String(localized: "Not connected")
    }

    private var zoneText: String? {
        guard let hr = bigBpm else { return nil }
        return String(localized: "Zone \(profile.hrZoneSet.zoneNumber(forBPM: Double(hr)))")
    }

    var body: some View {
        NavigationLink(value: NunaTodayRoute.deepTimeline) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Text("Beats per minute").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.mapOverlayText.opacity(0.7))
                        Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.mapOverlayText.opacity(0.45))
                    }
                    Spacer()
                    Text(verbatim: statusText).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(isLive ? NunaPalette.charge : (lastSignal != nil || live.connected ? NunaPalette.mapOverlayText.opacity(0.6) : NunaPalette.warning))
                }
                HStack(alignment: .center, spacing: 10) {
                    NunaMonitorTrace(values: trace, live: isLive, bpm: bigBpm, hint: live.connected ? "Waiting for a live heartbeat…" : "Connect your strap to see live heart rate")
                        .frame(height: 104)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: bigBpm.map(String.init) ?? "–")
                            .font(.nuna(size: 46, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(46)).monospacedDigit()
                            .foregroundStyle(NunaPalette.charge).opacity(isLive || bigBpm == nil ? 1 : 0.75)
                        Text("bpm").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.mapOverlayText.opacity(0.6))
                        if let zoneText { Text(verbatim: zoneText).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.mapOverlayText.opacity(0.7)).textCase(nil).padding(.top, 4) }
                    }
                    .frame(width: 84, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(NunaPalette.shade, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.charge.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Beats per minute"))
        .accessibilityValue(Text(verbatim: bigBpm.map { "\($0) bpm" } ?? "–"))
        .task(id: repo.refreshSeq) {
            let now = Int(Date().timeIntervalSince1970)
            banked = await repo.hrBuckets(from: Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970), to: now, bucketSeconds: 300).map { ($0.ts, $0.bpm) }
            // The newest beat-by-beat readings: look back 3 minutes, then 30, then 3 hours, and keep the last 90 of the first window that has any.
            for window in [180, 1_800, 10_800] {
                let rows = await repo.hrSamples(from: now - window, to: now, limit: 12_000).filter { $0.bpm > 0 }
                if rows.count >= 2 { recent = rows.suffix(maxSamples).map { ($0.ts, Double($0.bpm)) }; return }
            }
            #if DEBUG
            if CommandLine.arguments.contains("--demo-hr") { return }
            #endif
            recent = []
        }
        .onAppear {
            if samples.isEmpty, let hr = live.heartRate, hr > 0 { samples = [Double(hr)] }
            #if DEBUG
            // `--demo-hr`: a made-up last trace from half an hour ago, to see the card as it looks between two signals.
            if CommandLine.arguments.contains("--demo-hr"), recent.isEmpty {
                let end = Int(Date().timeIntervalSince1970) - 1_800
                recent = (0..<90).map { i in
                    let beat = sin(Double(i) / 3.1) * 7 + sin(Double(i) / 1.3) * 3
                    return (end - (89 - i) * 2, 76 + beat)
                }
            }
            #endif
        }
        .onChange(of: live.heartRate) { _, hr in
            guard let hr, hr > 0 else { return }
            samples.append(Double(hr))
            if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        }
    }
}

/// The monitor screen: graph paper, the trace with a soft glow, and, while live, a dot at the newest reading that pulses at the pace of the heart.
struct NunaMonitorTrace: View {
    let values: [Double]
    let live: Bool
    let bpm: Int?
    let hint: LocalizedStringKey

    private let green = NunaPalette.charge

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return [] }
        // At least 24 bpm of range, so a steady heart reads as a gently moving line and not as noise stretched to the screen.
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2 * 1.25, 12)
        let top = mid + half, span = half * 2
        let pad: CGFloat = 8
        let slots = CGFloat(max(values.count - 1, 29))
        return values.enumerated().map { i, v in
            CGPoint(x: pad + (size.width - pad * 2) * CGFloat(i) / slots, y: pad + (size.height - pad * 2) * CGFloat((top - v) / span))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Canvas { ctx, size in
                    // Graph paper: a fine line every 12 pt, a stronger one every fifth.
                    let step: CGFloat = 12
                    var x: CGFloat = 0, n = 0
                    while x <= size.width {
                        var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(green.opacity(n % 5 == 0 ? 0.14 : 0.06)), lineWidth: 0.7); x += step; n += 1
                    }
                    var y: CGFloat = 0; n = 0
                    while y <= size.height {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(green.opacity(n % 5 == 0 ? 0.14 : 0.06)), lineWidth: 0.7); y += step; n += 1
                    }
                    guard pts.count >= 2 else {
                        var base = Path(); base.move(to: CGPoint(x: 0, y: size.height / 2)); base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        ctx.stroke(base, with: .color(green.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        return
                    }
                    var path = Path(); path.move(to: pts[0])
                    for q in pts.dropFirst() { path.addLine(to: q) }
                    let alpha = live ? 1.0 : 0.55
                    ctx.stroke(path, with: .color(green.opacity(0.22 * alpha)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(green.opacity(alpha)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                if pts.count < 2 {
                    Text(hint).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.mapOverlayText.opacity(0.7)).textCase(nil)
                        .multilineTextAlignment(.leading).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).offset(y: 30)
                } else if let last = pts.last {
                    Circle().fill(NunaPalette.mapOverlayText).frame(width: 8, height: 8).opacity(live ? 1 : 0.6).position(last)
                    if live {
                        // One ring a beat: the period is 60 / bpm seconds.
                        Circle().strokeBorder(green, lineWidth: 2).frame(width: 10, height: 10).position(last)
                            .phaseAnimator([false, true]) { c, grown in c.scaleEffect(grown ? 2.6 : 1).opacity(grown ? 0 : 0.9) }
                                animation: { _ in .easeOut(duration: 60 / Double(max(bpm ?? 60, 30))) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityHidden(true)
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
    /// Drops the bpm scale on the left and marks the latest reading with a dot, for the card beside the big number.
    var compact = false

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
                if !compact { VStack {
                    ForEach([0, 1, 2], id: \.self) { i in
                        if i > 0 { Spacer(minLength: 0) }
                        Text(verbatim: sc.map { String(Int(($0.hi - ($0.hi - $0.lo) * Double(i) / 2).rounded())) } ?? "")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                    }
                }
                .frame(width: 26, alignment: .trailing) }
                Canvas { ctx, size in
                    guard values.count >= 2, let sc else { return }
                    let span = max(sc.hi - sc.lo, 1)
                    for i in 0...2 {
                        var g = Path(); let y = size.height * CGFloat(i) / 2
                        g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(NunaPalette.ink.opacity(i == 2 ? 0.22 : 0.08)), lineWidth: i == 2 ? 1.2 : 1)
                    }
                    func pt(_ i: Int) -> CGPoint {
                        CGPoint(x: (compact ? 6 : 0) + (size.width - (compact ? 12 : 0)) * CGFloat(i) / CGFloat(values.count - 1),
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
                    if compact, let last = runs.last?.upperBound {
                        let c = pt(last)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(NunaPalette.textPrimary))
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(color), lineWidth: 2)
                    }
                }
            }
            if !xLabels.isEmpty {
                HStack(spacing: 0) {
                    if !compact { Color.clear.frame(width: 34, height: 1) }
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

/// The heart rate page. The day's timeline is the page: the reading on top (live today), the chart with its day switcher and signal
/// menu, the time in each zone for the day, and the two switches that send the heart rate elsewhere (the Dynamic Island and the strap's
/// own broadcast).
struct NunaDeepTimelineView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.liveActivityKey) private var islandOn = true
    @AppStorage(PuffinExperiment.broadcastHrKey) private var broadcastOn = false
    @State private var daySamples: [HRSample] = []
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
        NunaDetailScreen("Heart rate") {
            metricMenu
            chartCard
            hint
            zonesCard
            settingsCard
        }
        .task(id: taskKey) { await reload() }
        .task(id: "\(Int(dayStart.timeIntervalSince1970))|\(repo.refreshSeq)") { await loadDaySamples() }
        .task(id: "\(Int(dayStart.timeIntervalSince1970))|\(repo.refreshSeq)") { await reloadAnnotations() }
        .task {
            guard !didLand else { return }
            didLand = true
            if let latest = await repo.latestDataDayStart(), latest < dayStart { dayStart = latest }
        }
    }

    // MARK: Zones

    private var zoneSet: HRZoneSet { profile.hrZoneSet }

    // MARK: Zones for the day

    /// Time in each of the five zones for the day on show, with the resting and the highest heart rate of that day.
    @ViewBuilder private var zonesCard: some View {
        let tiz = HRZones.timeInZone(daySamples, zoneSet: zoneSet)
        if tiz.total > 0 {
            let resting = repo.days.first { $0.day == Repository.localDayKey(dayStart) }?.restingHr
            let peak = daySamples.map(\.bpm).max()
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    // The same card as the zone breakdown of the Effort pages: title, one bar, a row per zone (swatch, "Zone n", time as h:mm).
                    Text("Heart-rate zones breakdown")
                        .font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    NunaProportionBar(parts: (0..<5).map { (tiz.seconds[$0], nunaHRZoneColors[$0]) }, height: 12)
                    ForEach(0..<5, id: \.self) { i in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(nunaHRZoneColors[i]).frame(width: 10, height: 10)
                            Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer(minLength: 8)
                            Text(verbatim: Self.hm(tiz.seconds[i] / 60)).font(.nuna(size: 15, weight: .bold, design: NunaType.design))
                                .monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        stat("Resting", resting.map(String.init) ?? "–")
                        stat("Highest", peak.map(String.init) ?? "–")
                        stat("Zones set by", zoneSource)
                    }
                }
            }
        }
    }

    private static func hm(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Where the zone boundaries come from, in a word.
    private var zoneSource: String {
        profile.hrZoneSet.source == "custom" ? String(localized: "You") : String(localized: "Age")
    }

    // MARK: Where the heart rate goes

    /// The Dynamic Island switch always; the strap broadcast only for a 5.0 / MG (or while it is on, so it can be turned off).
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaToggleRow("HR Dynamic Island", subtitle: "Heart rate on the Lock Screen and in the Dynamic Island",
                                  systemImage: "platter.filled.top.iphone", isOn: $islandOn).padding(.vertical, 8)
                    if model.whoop5Detected || broadcastOn {
                        NunaDivider()
                        NunaToggleRow("Broadcast HR", subtitle: "Your strap shares its heart rate with a Garmin, Zwift or gym equipment",
                                      systemImage: "dot.radiowaves.left.and.right", isOn: $broadcastOn).padding(.vertical, 8)
                            .onChange(of: broadcastOn) { _, on in model.ble.setBroadcastHr(on) }
                    }
                }
            }
            if broadcastOn {
                Text("Broadcast is on: the strap advertises its heart rate all the time, which uses its battery faster. Turn it off when you are not using it with another device.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadDaySamples() async {
        let from = Int(dayStart.timeIntervalSince1970)
        let to = min(from + 86_400, Int(Date().timeIntervalSince1970))
        guard to > from else { daySamples = []; return }
        let samples = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard !Task.isCancelled else { return }
        daySamples = samples
    }

    private func icon(_ m: Repository.TimelineMetric) -> String {
        switch m {
        case .hr: return "heart"
        case .hrv: return "waveform.path.ecg"
        case .spo2: return "drop"
        case .skinTemp: return "thermometer.medium"
        case .respiration: return "lungs"
        case .motion, .ouraMovement: return "figure.walk.motion"
        case .bandSleepState: return "moon.zzz"
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
            // The signal's icon in the neutral icon colour; the colour of the signal lives in the chart only.
            HStack(spacing: 12) {
                Image(systemName: icon(metric)).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                Text(verbatim: metric.title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
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
