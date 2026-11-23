#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What the wearer asked to breathe: where it came from (a template or a catalogue protocol) and how long.
struct NunaBreathRequest: Identifiable, Equatable {
    let id = UUID()
    var goal: BreathGoal
    var templateId: String?
    var protocolId: String
    var seconds: Int
}

/// The breathing itself: an optional countdown, then the protocol's stages paced by a ring, the strap's buzz and (if chosen) a soft
/// tone, with heart rate and HRV beside it. It ends when the time is up or the wearer ends it, and hands the record to the caller.
struct NunaBreathSessionView: View {
    let request: NunaBreathRequest
    let onEnd: (NunaBreathRecord?) -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NunaBreathPrefs.hapticsKey) private var haptics = true
    @AppStorage(NunaBreathAudioMode.key) private var audioModeRaw = ""
    @AppStorage(NunaBreathPrefs.countdownKey) private var useCountdown = true
    @StateObject private var cue = NunaBreathCue()

    @State private var countdown: Int?
    @State private var running = false
    @State private var paused = false
    @State private var phase: BreathPhase = .inhale
    @State private var phaseLabel: String?
    @State private var stageIndex = 0
    @State private var phaseDeadline = Date.distantFuture
    @State private var pausedLeft: TimeInterval = 0
    @State private var phaseLeft = 0
    /// When the step now running began (moved back when a paused step resumes), and how far into it the wearer was when pausing.
    @State private var phaseStart = Date()
    @State private var pausedOffset: TimeInterval = 0
    @State private var seconds = 0
    @State private var breaths = 0
    @State private var startedAt = Date()
    @State private var rrBuffer: [Int] = []
    @State private var rmssd: Double?
    @State private var rmssdSum = 0.0
    @State private var rmssdCount = 0
    @State private var rmssdPeak = 0.0
    @State private var hrSeries: [Double] = []
    @State private var rmssdSeries: [Double] = []
    @State private var confirmEnd = false
    /// The time is up but the breath in progress is not: the session goes on to the end of the out-breath and stops there, never in the middle of a hold or an in-breath.
    @State private var closing = false
    @State private var closingSince = Date()
    /// Set when time ran out during the pause after an out-breath: the breath is already out, so that pause is the last step.
    @State private var closeAtPhaseEnd = false
    /// Time is read from the wall clock, never counted from ticks, and the timer lives in this view's state. Held as a plain constant it was made
    /// again whenever the parent redrew (the strap's heart rate does that every second), which cancelled the one-second timer before it fired
    /// and left the clock crawling on a phone with the strap connected.
    @State private var clockTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    @State private var countdownFrom = Date()
    @State private var pausedTotal: TimeInterval = 0
    @State private var pausedAt: Date?
    private let step = 10

    private var audioMode: NunaBreathAudioMode {
        NunaBreathAudioMode(rawValue: audioModeRaw) ?? (UserDefaults.standard.bool(forKey: NunaBreathPrefs.audioKey) ? .tone : .off)
    }

    private var proto: BreathProtocol? { BreathProtocolCatalog.protocolById(request.protocolId) }
    private var stages: [BreathStage] { proto?.stages.filter { $0.durationMs > 0 } ?? [] }
    private var guided: Bool { proto?.mode == .guided }
    private var track: NunaBreathTrack { guided || stages.isEmpty ? .free : NunaBreathTrack(stages: stages) }
    private var title: String { request.templateId.flatMap { NunaBreathLibrary.template(id: $0)?.title } ?? proto.map { String(localized: String.LocalizationValue($0.title)) } ?? "" }

    @State private var tab = 0
    @State private var full = false

    private var zone: Int { model.bpm.map { model.profile.hrZoneSet.zoneNumber(forBPM: Double($0)) } ?? 0 }
    private var zoneColor: Color { model.bpm == nil ? NunaPalette.effortModerate : NunaHeartBeat.zoneColors[min(max(zone, 1), 5) - 1] }

    /// Laid out like the live screen of a Strain activity: a header with the name and what is on, two tabs, the big picture
    /// (here the glow of the breath), the heart rate, three figures, and Pause (with End once paused) on a bar of its own.
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                header
                NunaPageTabs([(value: 0, title: "Breathing"), (value: 1, title: "Heart rate")], selection: $tab)
                    .transaction { if reduceMotion { $0.disablesAnimations = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: NunaSpacing.section) {
                        if tab == 1 {
                            NunaHeartBeat(bpm: model.bpm, color: zoneColor, zone: zone, size: min(250, max(170, (viewport.size.height - 80) / 1.2)))
                                .frame(maxWidth: .infinity, minHeight: max(viewport.size.height - NunaSpacing.section * 2, 0), alignment: .center)
                        } else {
                            // The heart rate sits at the foot of the page, next to the figures under it.
                            VStack(spacing: 0) {
                                pacer(size: min(300, max(200, viewport.size.height - 150)))
                                Spacer(minLength: NunaSpacing.section)
                                heartReadout
                            }
                            .frame(minHeight: max(viewport.size.height - NunaSpacing.section * 2, 0))
                        }
                    }
                    .padding(.vertical, NunaSpacing.section).padding(.horizontal, NunaSpacing.screenH)
                }
                .scrollIndicators(.hidden)
            }
            .transaction(value: tab) { $0.animation = nil }
            statistics.padding(.horizontal, NunaSpacing.screenH)
        }
        .background(NunaBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
                .background(NunaPalette.canvas)
                .overlay(alignment: .top) { NunaDivider() }
        }
        .overlay {
            if full {
                NunaBreathFullLayer(content: pacer(size: 360, big: true), bpm: model.bpm, timeText: clock(max(0, request.seconds - seconds))) {
                    withAnimation(.easeInOut(duration: 0.25)) { full = false }
                }
            }
        }
        .statusBarHidden(full)
        .preferredColorScheme(NunaTheme.colorScheme)
        .onReceive(clockTimer) { now in onClock(now) }
        .onRRPackets(live) { ingest($0) }
        .onAppear { begin() }
        .onDisappear { cue.deactivate(); ScreenIdle.keepAwake(false) }
        .nunaEndFlow(isPresented: $confirmEnd, save: { finish() }, discard: { cancel() })
    }

    // MARK: Parts

    private var header: some View {
        let buzz = live.bonded && haptics ? String(localized: "strap buzz on") : String(localized: "silent session")
        return HStack(alignment: .center) {
            // A running session has no way out but End (reached through Pause), so there is one window to be in; this keeps the title centred.
            Color.clear.frame(width: 84, height: 44)
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(verbatim: title).font(.nuna(size: NunaTypeSize.sub, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: request.goal.shortTitle + " · " + buzz).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button { withAnimation(.easeInOut(duration: 0.25)) { full = true } } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("Full screen"))
            NunaMenu {
                ForEach(NunaBreathAudioMode.allCases) { m in
                    NunaMenuItem(m.title, selected: audioMode == m) { audioModeRaw = m.rawValue; cue.apply(m) }
                }
            } label: {
                Image(systemName: audioMode == .off ? "speaker.slash" : (audioMode == .voice ? "person.wave.2" : "speaker.wave.2")).font(.nuna(size: 15, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(Text("Audio cues"))
        }
    }

    /// The breath as a line under the step's count and name. The count is the big figure, as on the breathing pacers it follows.
    private func pacer(size: CGFloat, big: Bool = false) -> some View {
        let t = track, idx = stageIndex, follows = running && !guided
        return VStack(spacing: big ? 20 : 10) {
            VStack(spacing: 4) {
                if let c = countdown {
                    Text(verbatim: "\(c)").font(.nuna(size: big ? 110 : 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    Text("Get ready").font(.nuna(size: big ? 22 : 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text(verbatim: follows && phaseLeft > 0 ? "\(phaseLeft)" : " ").font(.nuna(size: big ? 110 : 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    Text(verbatim: phaseWord).font(.nuna(size: big ? 22 : 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.7).lineLimit(2)
                    if closing && !paused {
                        Text("Finishing this breath…").font(.nuna(size: big ? 16 : 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            NunaBreathWave(track: t, tint: request.goal.tint, height: big ? 320 : max(110, size * 0.48)) { now in
                guard t.length > 0 else { return now.timeIntervalSinceReferenceDate }
                guard follows else { return t.start(of: 0) }
                return t.start(of: idx) + max(0, paused ? pausedOffset : now.timeIntervalSince(phaseStart))
            }
        }
    }

    /// The heart rate under the line, at the left: its name and the reading.
    private var heartReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heart rate").font(.nuna(size: NunaTypeSize.caption, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: model.bpm.map(String.init) ?? "–").font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                Text("bpm").font(.nuna(size: NunaTypeSize.caption, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three plain figures with a hairline between them, as the statistics row of an activity.
    private var statistics: some View {
        let tiles: [(icon: String, label: LocalizedStringKey, value: String, unit: String)] = [
            ("timer", "Time left", clock(max(0, request.seconds - seconds)), ""),
            (NunaIcons.respiratory, "Breaths", "\(breaths)", ""),
            (NunaIcons.hrv, "HRV (RMSSD)", rmssd.map { String(format: "%.0f", $0) } ?? "–", "ms"),
        ]
        return HStack(alignment: .top, spacing: 12) {
            ForEach(tiles.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 96) }
                VStack(alignment: .leading, spacing: 8) {
                    NunaGlyph(tiles[i].icon, pointSize: NunaTypeSize.h2, weight: .semibold).foregroundStyle(NunaPalette.textSecondary)
                    Text(tiles[i].label).font(.nuna(size: NunaTypeSize.caption, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: tiles[i].value).font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                        Text(verbatim: tiles[i].unit.isEmpty ? " " : tiles[i].unit).font(.nuna(size: NunaTypeSize.caption, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { togglePause() } label: {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "play.fill" : "pause.fill").font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    Text(paused ? "Resume" : "Pause").font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 60)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain).disabled(countdown != nil).opacity(countdown != nil ? 0.4 : 1)
            // End is offered only while the session is paused, as in a workout: a running one cannot be ended by a stray tap.
            if paused {
                // Ending a session that would be kept asks first (save, discard or keep going), as the close button does; one under 20 s is not kept.
                Button { seconds >= 20 ? (confirmEnd = true) : cancel() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill").font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                        Text("End").font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 24).frame(height: 60)
                    .background(NunaPalette.alertText, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: paused)
    }

    private var phaseWord: String {
        if paused { return String(localized: "Paused") }
        if !running { return String(localized: "Get ready") }
        if let l = phaseLabel, !l.isEmpty { return String(localized: String.LocalizationValue(l)) }
        switch phase {
        case .inhale: return String(localized: "Breathe in…")
        case .hold: return String(localized: "Hold…")
        case .exhale: return String(localized: "Breathe out…")
        case .textOnly: return guided ? title : String(localized: "Follow the cue…")
        }
    }

    // MARK: Flow

    private func begin() {
        model.startRealtimeHR()
        cue.apply(audioMode)
        ScreenIdle.keepAwake(true)
        startedAt = Date()
        if useCountdown { countdown = 3; countdownFrom = Date() } else { go() }
    }

    private func go() {
        countdown = nil
        running = true
        seconds = 0; breaths = 0; stageIndex = 0
        pausedTotal = 0; pausedAt = nil
        rmssdSum = 0; rmssdCount = 0; rmssdPeak = 0; hrSeries = []; rmssdSeries = []
        startedAt = Date()
        closing = false; closeAtPhaseEnd = false
        cue.started()
        if guided {
            phase = .textOnly; phaseDeadline = .distantFuture
        } else {
            arm(from: Date(), buzz: true, firstAfterStart: true)
        }
    }

    /// One clock for everything: the countdown, the session seconds and the phases are all read off `now`.
    private func onClock(_ now: Date) {
        if countdown != nil {
            let left = 3 - Int(now.timeIntervalSince(countdownFrom))
            if left <= 0 { go() } else if left != countdown { countdown = left }
            return
        }
        guard running, !paused else { return }
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt) - pausedTotal))
        // Every second that went by is counted, also after the app was away for a while, so the series keep their spacing.
        while seconds < elapsed {
            seconds += 1
            if seconds % step == 0 {
                hrSeries.append(live.worn ? Double(model.bpm ?? 0) : 0)
                rmssdSeries.append(rmssd ?? 0)
            }
        }
        if seconds >= request.seconds, !closing, !beginClosing(now) { return }
        // A hold that will not end (or a protocol whose steps never reach an out-breath) cannot keep the session open for ever.
        if closing, now.timeIntervalSince(closingSince) > 180 { finish(); return }
        advance(now)
    }

    /// The time is up. A session paced by steps carries on until the breath in progress is out; one with no steps, or none that breathe out, ends now.
    /// Returns false when it ended here.
    private func beginClosing(_ now: Date) -> Bool {
        guard !guided, !stages.isEmpty, stages.contains(where: { $0.type == .exhale }) else { finish(); return false }
        closing = true; closingSince = now
        let here = stages[stageIndex % stages.count].type
        let before = stages[(stageIndex + stages.count - 1) % stages.count].type
        closeAtPhaseEnd = here == .hold && before == .exhale
        return true
    }

    private func advance(_ now: Date) {
        guard !guided else { return }
        let left = Int(ceil(phaseDeadline.timeIntervalSince(now)))
        if left != phaseLeft { phaseLeft = max(0, left) }
        guard now >= phaseDeadline, !stages.isEmpty else { return }
        let endedExhale = stages[stageIndex % stages.count].type == .exhale
        if endedExhale { breaths += 1 }
        if closing, endedExhale || closeAtPhaseEnd { finish(); return }
        stageIndex += 1
        // A phase that ended long ago (the screen was off) is not announced late, and the pace resumes from now.
        arm(from: now, buzz: now.timeIntervalSince(phaseDeadline) < 1.5)
    }

    private func arm(from now: Date, buzz: Bool, remaining: TimeInterval? = nil, firstAfterStart: Bool = false) {
        guard !stages.isEmpty else { return }
        let stage = stages[stageIndex % stages.count]
        phase = stage.type; phaseLabel = stage.label
        let duration = remaining ?? Double(stage.durationMs) / 1000
        phaseDeadline = now.addingTimeInterval(duration)
        phaseLeft = Int(ceil(duration))
        // The line is read off this: a step resumed after a pause carries on from where it stopped.
        phaseStart = now.addingTimeInterval(-max(0, Double(stage.durationMs) / 1000 - duration))
        if buzz {
            let loops = BreathProtocolPlayer.loops(for: stage.type)
            if loops > 0, haptics { model.buzz(loops: UInt8(clamping: loops), gate: HapticPrefs.breathing) }
            // A hold is told by its own cue, and by whether the lungs are full or empty: the step before says which.
            let before = stages[(stageIndex + stages.count - 1) % stages.count].type
            cue.cue(stage.type, previous: before, label: stage.label, queued: firstAfterStart)
        }
    }

    private func togglePause() {
        guard running else { return }
        if paused {
            paused = false
            if let began = pausedAt { pausedTotal += Date().timeIntervalSince(began) }
            pausedAt = nil
            cue.resumed()
            if !guided { arm(from: Date(), buzz: false, remaining: max(pausedLeft, 0.3)) }
        } else {
            pausedLeft = max(0, phaseDeadline.timeIntervalSinceNow)
            pausedOffset = max(0, Date().timeIntervalSince(phaseStart))
            paused = true
            pausedAt = Date()
            phaseDeadline = .distantFuture
            model.stopHaptics(); cue.silence(); cue.paused()
        }
    }

    private func ingest(_ rr: [Int]) {
        guard !rr.isEmpty else { return }
        rrBuffer.append(contentsOf: rr)
        if rrBuffer.count > 30 { rrBuffer.removeFirst(rrBuffer.count - 30) }
        guard rrBuffer.count >= 2 else { return }
        var sumSq = 0.0
        for i in 1..<rrBuffer.count { let d = Double(rrBuffer[i] - rrBuffer[i - 1]); sumSq += d * d }
        let r = (sumSq / Double(rrBuffer.count - 1)).squareRoot()
        rmssd = r
        NunaBreathLive.shared.rmssd = r
        if running, !paused { rmssdSum += r; rmssdCount += 1; rmssdPeak = max(rmssdPeak, r) }
    }

    private func cancel() {
        model.stopHaptics(); cue.deactivate(); ScreenIdle.keepAwake(false)
        onEnd(nil)
    }

    private func finish() {
        guard running || countdown != nil else { onEnd(nil); return }
        let wasRunning = running
        running = false; paused = false
        model.stopHaptics(); ScreenIdle.keepAwake(false)
        if wasRunning, seconds >= request.seconds { cue.releaseAfterFinishing() } else { cue.deactivate() }
        guard wasRunning, seconds >= 20 else { onEnd(nil); return }
        func mean(_ a: ArraySlice<Double>) -> Double? { let v = a.filter { $0 > 0 }; return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let record = NunaBreathRecord(
            startTs: Int(startedAt.timeIntervalSince1970), seconds: seconds, goal: request.goal.rawValue,
            templateId: request.templateId, protocolId: request.protocolId, breaths: breaths,
            hrStart: mean(hrSeries.prefix(3)), hrEnd: mean(hrSeries.suffix(3)), hrAvg: mean(hrSeries[...]),
            rmssdStart: mean(rmssdSeries.prefix(3)), rmssdAvg: rmssdCount > 0 ? rmssdSum / Double(rmssdCount) : nil,
            rmssdPeak: rmssdCount > 0 ? rmssdPeak : nil, hrSeries: hrSeries, rmssdSeries: rmssdSeries,
            haptics: haptics && live.bonded, step: step)
        NunaBreathLog.append(record)
        NunaBreathRecovery.log(repo: repo, startTs: record.startTs, seconds: record.seconds, title: title)
        NunaAnyaMemory.remember(.breathing, Self.memoryLine(record, title: title))
        onEnd(record)
    }

    static func memoryLine(_ r: NunaBreathRecord, title: String) -> String {
        var bits = ["\(title), \(r.seconds / 60) min, goal \(r.goal)"]
        if let a = r.hrStart, let b = r.hrEnd { bits.append("heart rate \(Int(a.rounded())) to \(Int(b.rounded())) bpm") }
        if let p = r.rmssdChangePct { bits.append(String(format: "HRV %+.0f%%", p)) } else { bits.append("no HRV recorded") }
        return "Breathing session: " + bits.joined(separator: ", ")
    }

    private func clock(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }
}
#endif
