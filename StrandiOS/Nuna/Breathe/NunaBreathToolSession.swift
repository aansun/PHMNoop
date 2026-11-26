#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Resonance and Calm me on the same session screen as every other technique, run by the biofeedback controller the older screen used.
/// Calm me buzzes the strap just under the heart rate and eases it down; Resonance runs the short sweep that finds the slow pace where the
/// heart swings most, then offers to breathe at it. Both are kept in the history and as recovery activities, like any session.
struct NunaBreathToolSessionView: View {
    let tool: NunaBreathTool
    let onEnd: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var controller: BiofeedbackController?

    var body: some View {
        Group {
            if let c = controller { NunaToolSessionBody(tool: tool, controller: c, onEnd: onEnd) } else { NunaBackdrop() }
        }
        .task { if controller == nil { controller = BiofeedbackController(model: model, live: live) } }
    }
}

private struct NunaToolSessionBody: View {
    let tool: NunaBreathTool
    @ObservedObject var controller: BiofeedbackController
    let onEnd: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var startedAt = Date()
    @State private var hasRun = false
    @State private var logged = false
    @State private var phaseStart = Date()
    @State private var waveClock = NunaWaveClock()
    @State private var confirmEnd = false
    @State private var tab = 0
    @State private var notStarted: String?
    @State private var full = false
    @State private var discarding = false
    @State private var lastRow: WorkoutRow?
    @State private var saved: NunaWorkoutKey?
    /// Sound, as in every breathing session: a mark at the start and at the end, and for Resonance the in- and out-breath. Calm me is a beat on the strap,
    /// so it has the marks only.
    @AppStorage(NunaBreathAudioMode.key) private var audioModeRaw = ""
    @StateObject private var cue = NunaBreathCue()
    @State private var lastPhase: BreathPhase?
    @AppStorage(NunaBreathPrefs.countdownKey) private var useCountdown = true
    @State private var counting = false

    private var c: BiofeedbackController { controller }
    private var audioMode: NunaBreathAudioMode {
        NunaBreathAudioMode(rawValue: audioModeRaw) ?? (UserDefaults.standard.bool(forKey: NunaBreathPrefs.audioKey) ? .tone : .off)
    }
    private var finished: Bool { hasRun && !c.running }
    private var zone: Int { model.bpm.map { model.profile.hrZoneSet.zoneNumber(forBPM: Double($0)) } ?? 0 }
    private var zoneColor: Color { model.bpm == nil ? NunaPalette.effortModerate : NunaHeartBeat.zoneColors[min(max(zone, 1), 5) - 1] }
    private var kind: String { tool == .calmMe ? NunaBreathKind.calmMeId : NunaBreathKind.resonanceId }

    /// The pace in breaths a minute of whatever is running now.
    private var runningBpm: Double? {
        switch c.session {
        case .resonanceSweep(let bpm, _, _), .resonanceSession(let bpm): return bpm
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $saved) { key in NunaWorkoutSummaryView(key: key, initialRow: lastRow) }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                header
                progressLine
                NunaPageTabs([(value: 0, title: "Breathing"), (value: 1, title: "Heart rate")], selection: $tab)
                    .transaction { if reduceMotion { $0.disablesAnimations = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
            GeometryReader { viewport in
                // The two tabs sit side by side: slide with a finger, or tap the name above.
                TabView(selection: $tab) {
                    ScrollView {
                        VStack(spacing: NunaSpacing.section) {
                            if finished || notStarted != nil {
                                resultCard
                                if finished, let row = lastRow { NunaBPBreathCard(startTs: row.startTs, seconds: row.endTs - row.startTs) }
                            } else {
                                // The heart rate sits at the foot of the page, next to the figures under it.
                                VStack(spacing: 0) {
                                    visual(size: min(300, max(200, viewport.size.height - 150)))
                                    Spacer(minLength: NunaSpacing.section)
                                    heartReadout
                                }
                                .frame(minHeight: max(viewport.size.height - NunaSpacing.section * 2, 0))
                            }
                        }
                        .padding(.vertical, NunaSpacing.section).padding(.horizontal, NunaSpacing.screenH)
                    }
                    .scrollIndicators(.hidden).tag(0)
                    ScrollView {
                        NunaHeartBeat(bpm: model.bpm, color: zoneColor, zone: zone, size: min(250, max(170, (viewport.size.height - 80) / 1.2)))
                            .frame(maxWidth: .infinity, minHeight: max(viewport.size.height - NunaSpacing.section * 2, 0), alignment: .center)
                            .padding(.vertical, NunaSpacing.section).padding(.horizontal, NunaSpacing.screenH)
                    }
                    .scrollIndicators(.hidden).tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: tab)
            }
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
            if full && c.running {
                NunaBreathFullLayer(title: tool.title, headline: headline(big: true), wave: { wave(height: $0) }, bpm: model.bpm,
                                    figure: nil, timeText: clock(c.elapsedSeconds), timeLabel: "Time") {
                    withAnimation(.easeInOut(duration: 0.25)) { full = false }
                }
            }
        }
        .statusBarHidden(full && c.running)
        .overlay {
            if counting { NunaBreathCountdown(cue: cue, onDone: { counting = false; begin() }, onCancel: { counting = false; onEnd() }) }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear {
            cue.apply(audioMode)
            // A tool that cannot start says so at once, with no countdown before it.
            if useCountdown, live.bonded { counting = true } else { begin() }
        }
        .onDisappear { c.stop(); cue.deactivate() }
        .onChange(of: c.running) { _, now in
            if now {
                hasRun = true; logged = false; startedAt = Date(); movePhase()
                cue.apply(audioMode); lastPhase = nil
                // Resonance is told breath by breath, the first one the moment it starts; Calm me has only the mark of its start.
                if tool == .resonance { cue.cue(c.phase, previous: nil, label: nil); lastPhase = c.phase } else { cue.started() }
            } else if hasRun {
                let kept = !discarding && c.elapsedSeconds >= 20
                record()
                // The end is told the same way as in every session, and is let finish after this screen goes.
                if kept { cue.releaseAfterFinishing() } else { cue.deactivate() }
            }
        }
        .onChange(of: c.phase) { _, now in
            movePhase()
            if c.running, tool == .resonance { cue.cue(now, previous: lastPhase, label: nil); lastPhase = now }
        }
        .nunaEndFlow(isPresented: $confirmEnd, save: { c.stop() }, discard: { discarding = true; c.stop() })
    }

    // MARK: Flow

    private func begin() {
        switch tool {
        case .calmMe:
            c.startCalmMe()
            if !c.running { notStarted = c.calmOutcome ?? String(localized: "Couldn't start. Needs a connected strap and a resting heart rate.") }
        case .resonance:
            if live.bonded { c.startSweep(quick: true) } else { notStarted = String(localized: "Connect your strap to find your pace. It needs your heartbeats to read.") }
        }
    }

    /// The glow follows the cue the controller is on: it swells on the in-breath and settles on the out-breath, over the length of that part of the breath.
    private func movePhase() {
        guard c.running else { return }
        phaseStart = Date()
    }

    /// A session that lasted long enough goes into the history and the recovery activities, once.
    private func record() {
        guard !logged else { return }
        logged = true
        if discarding { onEnd(); return }
        let secs = c.elapsedSeconds
        guard secs >= 20 else { return }
        let start = Int(startedAt.timeIntervalSince1970)
        NunaBreathRecovery.logExternal(repo: repo, startTs: start, seconds: secs, kind: kind)
        lastRow = NunaBreathRecovery.row(startTs: start, seconds: secs, title: tool.title)
    }

    // MARK: Parts

    private var header: some View {
        let buzz = live.bonded ? String(localized: "strap buzz on") : String(localized: "silent session")
        return HStack(alignment: .center) {
            // A running session has no way out but End, so there is one window to be in; this keeps the title centred.
            Color.clear.frame(width: 84, height: 44)
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(verbatim: tool.title).font(.nuna(size: NunaTypeSize.sub, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Text(verbatim: String(localized: "Biofeedback") + " · " + buzz).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button { withAnimation(.easeInOut(duration: 0.25)) { full = true } } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("Full screen")).opacity(c.running ? 1 : 0).disabled(!c.running)
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

    /// Resonance: how far through the sweep. Calm me: how long it has run.
    private var progressLine: some View {
        let fraction: Double = tool == .resonance ? (c.running ? c.sweepProgress : (finished ? 1 : 0)) : 0
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool == .resonance ? "Finding your pace" : "Calm me").font(.nuna(size: NunaTypeSize.caption, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: tool == .resonance ? (c.sweepLabel ?? "–") : clock(c.elapsedSeconds))
                    .font(.nuna(size: NunaTypeSize.h3, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            if tool == .resonance {
                Capsule().fill(NunaPalette.glassStrong).frame(height: 6)
                    .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(NunaPalette.charge).frame(width: g.size.width * fraction) } }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    /// The dust: Resonance breathes with the cue; Calm me beats at the tempo it is buzzing.
    /// The breath as a line under its name. Resonance follows the pace it is breathing at, in step with the controller's phase; Calm me draws the
    /// slow wave of the pace it is easing the heart towards, so the line and the strap's buzz agree.
    private func visual(size: CGFloat) -> some View {
        VStack(spacing: 10) {
            headline(big: false)
            wave(height: max(110, size * 0.48))
        }
    }

    private func headline(big: Bool) -> some View {
        VStack(spacing: 4) {
            if tool == .calmMe, let t = c.calmTargetBpm {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(Int(t.rounded()))").font(.nuna(size: big ? 110 : 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    Text("bpm").font(.nuna(size: NunaTypeSize.caption, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Text(verbatim: centerWord).font(.nuna(size: big ? 22 : 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).minimumScaleFactor(0.7).lineLimit(2)
            } else {
                Text(verbatim: centerWord).font(.nuna(size: big ? 34 : 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.7).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: big ? 150 : 70)
    }

    private func wave(height: CGFloat) -> some View {
        let calm = tool == .calmMe
        let bpm = calm ? max(40, c.calmTargetBpm ?? Double(model.bpm ?? 70)) : runningBpm
        let track = bpm.map { NunaBreathTrack(bpm: $0, inhaleFraction: BreathPacer.defaultInhaleFraction) } ?? .free
        let index = c.phase == .inhale ? 0 : 1
        let start = phaseStart
        let clock = waveClock
        return NunaBreathWave(track: track, tint: tool.tintColor, height: height) { now in
            if track.length <= 0 { return now.timeIntervalSinceReferenceDate }
            if calm { return clock.position(at: now, length: track.length) }
            guard c.running else { return track.start(of: 0) }
            return track.start(of: index) + max(0, now.timeIntervalSince(start))
        }
    }

    private var centerWord: String {
        if tool == .calmMe { return String(localized: "Follow the buzz…") }
        switch c.phase {
        case .inhale: return String(localized: "Breathe in…")
        case .exhale: return String(localized: "Breathe out…")
        case .hold: return String(localized: "Hold…")
        case .textOnly: return String(localized: "Follow the cue…")
        }
    }

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

    /// What the session ended with, said plainly: the pace found, or how the heart rate moved.
    private var resultCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: tool.title).font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(verbatim: resultText).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultText: String {
        if let notStarted { return notStarted }
        switch tool {
        case .calmMe: return c.calmOutcome ?? String(localized: "Session ended.")
        case .resonance:
            guard let r = c.lastSweep else { return String(localized: "Session ended.") }
            let pace = String(format: "%.1f", r.lockedBpm)
            return r.didLock
                ? String(localized: "Your resonance pace is \(pace) breaths a minute. It is kept for your sessions.")
                : String(localized: "There were not enough clean heartbeats to lock a pace, so \(pace) breaths a minute is used for now. Wear the strap snugly, sit still and try again.")
        }
    }

    private var statistics: some View {
        let pace: String = {
            if tool == .calmMe { return c.calmTargetBpm.map { String(Int($0.rounded())) } ?? "–" }
            return runningBpm.map { String(format: "%.1f", $0) } ?? "–"
        }()
        let tiles: [(icon: String, label: LocalizedStringKey, value: String, unit: String)] = [
            ("timer", "Time", clock(c.elapsedSeconds), ""),
            (NunaIcons.respiratory, "Pace", pace, tool == .calmMe ? "bpm" : String(localized: "br/min")),
            (NunaIcons.heartRate, "Start", c.calmStartHR.map(String.init) ?? (model.bpm.map(String.init) ?? "–"), "bpm"),
        ]
        return HStack(alignment: .top, spacing: 12) {
            ForEach(tiles.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 96) }
                VStack(alignment: .leading, spacing: 8) {
                    NunaGlyph(tiles[i].icon, pointSize: NunaTypeSize.h2, weight: .semibold).foregroundStyle(NunaPalette.textSecondary)
                    Text(tiles[i].label).font(.nuna(size: NunaTypeSize.caption, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
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

    @ViewBuilder private var controls: some View {
        if finished || notStarted != nil {
            HStack(spacing: 12) {
                if tool == .resonance, let r = c.lastSweep, finished {
                    Button { startPaced(r.lockedBpm) } label: {
                        Text("Breathe at this pace").font(.nuna(size: NunaTypeSize.h3, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 60)
                            .background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                if let row = lastRow, finished {
                    Button { saved = NunaWorkoutKey(startTs: row.startTs, sport: row.sport, source: row.source) } label: {
                        Text("View activity").font(.nuna(size: NunaTypeSize.h3, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 20).frame(height: 60)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button(action: onEnd) {
                    Text("Done").font(.nuna(size: NunaTypeSize.h3, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 28).frame(maxWidth: tool == .resonance && c.lastSweep != nil && finished ? nil : .infinity).frame(height: 60)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
            }
        } else {
            Button { confirmEnd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill").font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    Text("End").font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 60)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    /// Five minutes at the pace the sweep found.
    private func startPaced(_ bpm: Double) {
        hasRun = false
        c.startResonanceSession(bpm: bpm, cycles: max(1, Int((5 * bpm).rounded())))
    }

    private func clock(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }
}

extension NunaBreathTool {
    /// The colour of the glow.
    var tintColor: Color { self == .resonance ? NunaPalette.charge : NunaPalette.recoveryBlue }
}
#endif
