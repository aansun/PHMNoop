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

/// The pacer: a ring the breath fills and drains, a soft disc inside it and the phase in the middle.
struct NunaBreathPacer: View {
    let progress: CGFloat
    let animated: Bool
    var tint: Color = NunaPalette.rest
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let p = min(max(progress, 0), 1)
            let inner = d * (0.40 + 0.60 * p)
            ZStack {
                Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1).frame(width: d, height: d)
                Circle().strokeBorder(tint.opacity(0.22), lineWidth: 1).frame(width: d * 0.7, height: d * 0.7)
                Circle().fill(tint.opacity(0.16)).frame(width: inner, height: inner)
                Circle().strokeBorder(tint, lineWidth: 3).frame(width: inner, height: inner)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The breathing itself: an optional countdown, then the protocol's stages paced by a ring, the strap's buzz and (if chosen) a soft
/// tone, with heart rate and HRV beside it. It ends when the time is up or the wearer ends it, and hands the record to the caller.
struct NunaBreathSessionView: View {
    let request: NunaBreathRequest
    let onEnd: (NunaBreathRecord?) -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @AppStorage(NunaBreathPrefs.hapticsKey) private var haptics = true
    @AppStorage(NunaBreathPrefs.audioKey) private var audioCues = false
    @AppStorage(NunaBreathPrefs.countdownKey) private var useCountdown = true
    @StateObject private var tone = BreathTonePlayer()

    @State private var countdown: Int?
    @State private var running = false
    @State private var paused = false
    @State private var orb: CGFloat = 0
    @State private var phase: BreathPhase = .inhale
    @State private var phaseLabel: String?
    @State private var stageIndex = 0
    @State private var phaseDeadline = Date.distantFuture
    @State private var pausedLeft: TimeInterval = 0
    @State private var phaseLeft = 0
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

    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let step = 10

    private var proto: BreathProtocol? { BreathProtocolCatalog.protocolById(request.protocolId) }
    private var stages: [BreathStage] { proto?.stages.filter { $0.durationMs > 0 } ?? [] }
    private var guided: Bool { proto?.mode == .guided }
    private var still: Bool { motion.poseStill(reduceMotion) }
    private var title: String { request.templateId.flatMap { BreathTemplates.template(id: $0)?.title } ?? proto.map { String(localized: String.LocalizationValue($0.title)) } ?? "" }

    var body: some View {
        VStack(spacing: 16) {
            topBar
            Spacer(minLength: 0)
            ZStack {
                NunaBreathPacer(progress: orb, animated: running, tint: request.goal.tint)
                if let c = countdown {
                    Text(verbatim: "\(c)").font(.nuna(size: 96, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                } else {
                    VStack(spacing: 6) {
                        Text(verbatim: phaseWord).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .multilineTextAlignment(.center)
                        if running, !guided, phaseLeft > 0 {
                            Text(verbatim: "\(phaseLeft)").font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: 320).aspectRatio(1, contentMode: .fit).padding(.horizontal, 20)
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(verbatim: clock(max(0, request.seconds - seconds))).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                Text(verbatim: String(localized: "\(breaths) breaths")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            liveRow
            controls
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 20)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .onReceive(phaseTimer) { now in advance(now) }
        .onReceive(secondTimer) { _ in tick() }
        .onRRPackets(live) { ingest($0) }
        .onAppear { begin() }
        .onDisappear { tone.deactivate(); ScreenIdle.keepAwake(false) }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and see report") { finish() }
            Button("Keep breathing", role: .cancel) {}
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { seconds >= 20 ? (confirmEnd = true) : cancel() } label: {
                Image(systemName: "xmark").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.nuna(size: 18, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Text(request.goal.title).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer()
            Button { audioCues.toggle(); audioCues ? tone.activate() : tone.deactivate() } label: {
                Image(systemName: audioCues ? "speaker.wave.2" : "speaker.slash").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).accessibilityLabel(Text("Audio cues"))
        }
    }

    private var liveRow: some View {
        HStack(spacing: 10) {
            liveTile("Heart rate", model.bpm.map(String.init) ?? "–", "bpm", NunaPalette.alertText)
            liveTile("HRV (RMSSD)", rmssd.map { String(format: "%.0f", $0) } ?? "–", "ms", NunaPalette.restLight)
            liveTile("Haptics", live.bonded && haptics ? String(localized: "On") : String(localized: "Off"), "", live.bonded && haptics ? NunaPalette.charge : NunaPalette.textMuted)
        }
    }

    private func liveTile(_ label: LocalizedStringKey, _ value: String, _ unit: String, _ color: Color) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(color).monospacedDigit()
                    if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { togglePause() } label: {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "play.fill" : "pause.fill").font(.nuna(size: 15, weight: .bold))
                    Text(paused ? "Resume" : "Pause").font(.nuna(size: 17, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain).disabled(countdown != nil).opacity(countdown != nil ? 0.4 : 1)
            Button { seconds >= 20 ? finish() : cancel() } label: {
                Text("End").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .padding(.horizontal, 28).frame(height: 54)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
        }
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
        if audioCues { tone.activate() }
        ScreenIdle.keepAwake(true)
        startedAt = Date()
        if useCountdown { countdown = 3 } else { go() }
    }

    private func go() {
        countdown = nil
        running = true
        seconds = 0; breaths = 0; stageIndex = 0
        rmssdSum = 0; rmssdCount = 0; rmssdPeak = 0; hrSeries = []; rmssdSeries = []
        startedAt = Date()
        if guided {
            phase = .textOnly; phaseDeadline = .distantFuture
            orb = 0.5
        } else {
            arm(from: Date(), buzz: true)
        }
    }

    private func tick() {
        if let c = countdown { if c > 1 { countdown = c - 1 } else { go() }; return }
        guard running, !paused else { return }
        seconds += 1
        if seconds % step == 0 {
            hrSeries.append(live.worn ? Double(model.bpm ?? 0) : 0)
            rmssdSeries.append(rmssd ?? 0)
        }
        if seconds >= request.seconds { finish() }
    }

    private func advance(_ now: Date) {
        guard running, !paused, !guided, now.timeIntervalSince(startedAt) > 0 else { return }
        let left = Int(ceil(phaseDeadline.timeIntervalSince(now)))
        if left != phaseLeft { phaseLeft = max(0, left) }
        guard now >= phaseDeadline, !stages.isEmpty else { return }
        if stages[stageIndex % stages.count].type == .exhale { breaths += 1 }
        stageIndex += 1
        arm(from: now, buzz: true)
    }

    private func arm(from now: Date, buzz: Bool, remaining: TimeInterval? = nil) {
        guard !stages.isEmpty else { return }
        let stage = stages[stageIndex % stages.count]
        phase = stage.type; phaseLabel = stage.label
        let duration = remaining ?? Double(stage.durationMs) / 1000
        phaseDeadline = now.addingTimeInterval(duration)
        phaseLeft = Int(ceil(duration))
        if still { orb = 0.5 } else {
            withAnimation(.easeInOut(duration: max(duration, 0.05))) {
                switch stage.type {
                case .inhale: orb = 1
                case .exhale: orb = 0
                case .hold, .textOnly: break
                }
            }
        }
        if buzz {
            let loops = BreathProtocolPlayer.loops(for: stage.type)
            if loops > 0, haptics { model.buzz(loops: UInt8(clamping: loops), gate: HapticPrefs.breathing) }
            if audioCues {
                switch stage.type { case .inhale: tone.play(.inhale); case .exhale: tone.play(.exhale); default: break }
            }
        }
    }

    private func togglePause() {
        guard running else { return }
        if paused {
            paused = false
            if !guided { arm(from: Date(), buzz: false, remaining: max(pausedLeft, 0.3)) }
        } else {
            pausedLeft = max(0, phaseDeadline.timeIntervalSinceNow)
            paused = true
            phaseDeadline = .distantFuture
            model.stopHaptics()
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
        model.stopHaptics(); tone.deactivate(); ScreenIdle.keepAwake(false)
        onEnd(nil)
    }

    private func finish() {
        guard running || countdown != nil else { onEnd(nil); return }
        let wasRunning = running
        running = false; paused = false
        model.stopHaptics(); tone.deactivate(); ScreenIdle.keepAwake(false)
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
