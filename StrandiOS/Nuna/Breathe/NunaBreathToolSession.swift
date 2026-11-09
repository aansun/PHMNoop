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
    @State private var orb: CGFloat = 0.2
    @State private var confirmEnd = false
    @State private var tab = 0
    @State private var notStarted: String?
    @State private var discarding = false
    @State private var lastRow: WorkoutRow?
    @State private var saved: NunaWorkoutKey?

    private var c: BiofeedbackController { controller }
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
                ScrollView {
                    VStack(spacing: NunaSpacing.section) {
                        if tab == 1 {
                            NunaHeartBeat(bpm: model.bpm, color: zoneColor, zone: zone, size: min(250, max(170, (viewport.size.height - 80) / 1.2)))
                                .frame(maxWidth: .infinity, minHeight: max(viewport.size.height - NunaSpacing.section * 2, 0), alignment: .center)
                        } else if finished || notStarted != nil {
                            resultCard
                        } else {
                            visual(size: min(300, max(200, viewport.size.height - 150)))
                            heartReadout
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
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { begin() }
        .onDisappear { c.stop() }
        .onChange(of: c.running) { _, now in
            if now { hasRun = true; logged = false; startedAt = Date(); movePhase() } else if hasRun { record() }
        }
        .onChange(of: c.phase) { _, _ in movePhase() }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save") { c.stop() }
            Button("Discard", role: .destructive) { discarding = true; c.stop() }
            Button("Keep breathing", role: .cancel) {}
        }
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
        guard let bpm = runningBpm, c.running else { return }
        let cycle = 60 / bpm
        let inhale = cycle * BreathPacer.defaultInhaleFraction
        if c.phase == .inhale { withAnimation(.easeInOut(duration: inhale)) { orb = 1 } }
        else { withAnimation(.easeInOut(duration: cycle - inhale)) { orb = 0.2 } }
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
            Button { c.running ? (confirmEnd = true) : onEnd() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(verbatim: tool.title).font(.nuna(size: NunaTypeSize.sub, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Text(verbatim: String(localized: "Biofeedback") + " · " + buzz).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Color.clear.frame(width: 44, height: 44)
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

    /// The glow: Resonance breathes with the cue; Calm me beats at the tempo it is buzzing.
    @ViewBuilder private func visual(size: CGFloat) -> some View {
        ZStack {
            if tool == .calmMe {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
                    let bpm = max(40, c.calmTargetBpm ?? Double(model.bpm ?? 70))
                    let p = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * bpm / 60 * 2 * .pi)
                    NunaBreathPacer(progress: CGFloat(0.35 + 0.35 * p), animated: false, tint: tool.tintColor)
                }
            } else {
                NunaBreathPacer(progress: orb, animated: c.running, tint: tool.tintColor)
            }
            VStack(spacing: 6) {
                Text(verbatim: centerWord).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.center)
                if tool == .calmMe, let t = c.calmTargetBpm {
                    Text(verbatim: "\(Int(t.rounded())) bpm").font(.nuna(size: 16, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 44)
        }
        .frame(width: size, height: size).frame(maxWidth: .infinity)
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
            Image(systemName: "heart.fill").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(model.bpm == nil ? NunaPalette.textMuted : zoneColor)
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
            ("metronome", "Pace", pace, tool == .calmMe ? "bpm" : String(localized: "br/min")),
            ("heart", "Start", c.calmStartHR.map(String.init) ?? (model.bpm.map(String.init) ?? "–"), "bpm"),
        ]
        return HStack(alignment: .top, spacing: 12) {
            ForEach(tiles.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 96) }
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: tiles[i].icon).font(.nuna(size: NunaTypeSize.h2, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
