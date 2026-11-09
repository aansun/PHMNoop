#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The shape of one breath cycle as a level between empty (0) and full (1): up while breathing in, down while breathing out, flat during a hold.
/// It is built from the technique's own stages, so box breathing is a trapezoid, 4-7-8 a short climb, a flat top and a long slide, and
/// coherent breathing a plain wave. `shape` says how the corners are drawn: angled for holds and quick pulses, rounded for slow flowing breaths.
struct NunaBreathTrack: Equatable {
    enum Shape: Equatable { case smooth, angular }
    struct Seg: Equatable { let type: BreathPhase; let seconds: Double }

    let segs: [Seg]
    let shape: Shape
    private let from: [Double]
    private let to: [Double]
    let length: Double

    init(segs: [Seg], shape: Shape) {
        self.segs = segs
        self.shape = shape
        length = segs.reduce(0) { $0 + $1.seconds }
        // Two passes round the cycle: a hold keeps the level the step before left, and the first step needs to know where the last one ended.
        var prev = segs.contains(where: { $0.type == .inhale || $0.type == .exhale }) ? 0.0 : 0.5
        var f: [Double] = [], t: [Double] = []
        for _ in 0..<2 {
            f = []; t = []
            for s in segs {
                f.append(prev)
                switch s.type {
                case .inhale: prev = 1
                case .exhale: prev = 0
                case .hold, .textOnly: break
                }
                t.append(prev)
            }
        }
        from = f; to = t
    }

    /// A technique's stages. Holds and quick pulses are drawn with corners, slow breaths with curves.
    init(stages: [BreathStage]) {
        let segs = stages.filter { $0.durationMs > 0 }.map { Seg(type: $0.type, seconds: Double($0.durationMs) / 1000) }
        let moving = segs.filter { $0.type == .inhale || $0.type == .exhale }
        let mean = moving.isEmpty ? 5 : moving.reduce(0) { $0 + $1.seconds } / Double(moving.count)
        let holds = segs.contains { $0.type == .hold }
        self.init(segs: segs, shape: holds || mean < 2.2 ? .angular : .smooth)
    }

    /// A paced breath at some breaths a minute: in for `inhaleFraction` of the cycle, then out, drawn as a wave.
    init(bpm: Double, inhaleFraction: Double) {
        let cycle = 60 / max(bpm, 1)
        self.init(segs: [Seg(type: .inhale, seconds: cycle * inhaleFraction), Seg(type: .exhale, seconds: cycle * (1 - inhaleFraction))], shape: .smooth)
    }

    /// No steps to follow: a slow, gentle swell.
    static let free = NunaBreathTrack(segs: [], shape: .smooth)

    /// Seconds into the cycle at which the step with this index (counted without end) begins.
    func start(of index: Int) -> Double {
        guard !segs.isEmpty else { return 0 }
        let n = index % segs.count
        return segs[0..<n].reduce(0) { $0 + $1.seconds }
    }

    func level(at position: Double) -> Double {
        guard !segs.isEmpty, length > 0 else { return 0.5 + 0.2 * sin(position * 2 * .pi / 9) }
        var p = position.truncatingRemainder(dividingBy: length)
        if p < 0 { p += length }
        var acc = 0.0
        for (i, s) in segs.enumerated() {
            if p < acc + s.seconds || i == segs.count - 1 {
                let f = s.seconds > 0 ? min(max((p - acc) / s.seconds, 0), 1) : 1
                let e = shape == .smooth ? 0.5 - 0.5 * cos(f * .pi) : f
                return from[i] + (to[i] - from[i]) * e
            }
            acc += s.seconds
        }
        return 0.5
    }
}

/// Keeps a free-running wave continuous when its pace changes (Calm me eases the pace down): it counts cycles, not seconds.
final class NunaWaveClock {
    private var cycles = 0.0
    private var last: Date?
    func position(at now: Date, length: Double) -> Double {
        if let l = last, length > 0 { cycles += max(0, now.timeIntervalSince(l)) / length }
        last = now
        return (cycles - cycles.rounded(.down)) * length
    }
}

/// The breath as a line, after the pacer graphs of breathing apps: the line scrolls past a glowing dot, which rises while you breathe in, stays
/// level through a hold and falls while you breathe out. What is behind the dot is bright and fades away, what is ahead is the pace to follow.
struct NunaBreathWave: View {
    let track: NunaBreathTrack
    let tint: Color
    var height: CGFloat = 200
    /// Seconds into the track's cycle at a moment; the caller knows where the session is.
    let position: (Date) -> Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30)) { ctx in
            Canvas { g, size in
                let pos = position(ctx.date)
                // About a cycle and a half in view, a little under a third of it behind the dot.
                let window = track.length > 0 ? min(max(track.length * 1.6, 9), 26) : 12
                let past = window * 0.3
                let pps = size.width / window
                let xNow = past * pps
                let pad: CGFloat = 26
                func y(_ level: Double) -> CGFloat { pad + CGFloat(1 - level) * (size.height - pad * 2) }

                // The top and the bottom of the breath: full lungs and empty.
                for level in [0.0, 1.0] {
                    var rule = Path(); rule.move(to: CGPoint(x: 0, y: y(level))); rule.addLine(to: CGPoint(x: size.width, y: y(level)))
                    g.stroke(rule, with: .color(NunaPalette.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                }

                let steps = max(Int(size.width / 2), 2)
                var behind = Path(), ahead = Path()
                for i in 0...steps {
                    let r = -past + window * Double(i) / Double(steps)
                    let pt = CGPoint(x: xNow + CGFloat(r) * pps, y: y(track.level(at: pos + r)))
                    if r <= 0 {
                        if behind.isEmpty { behind.move(to: pt) } else { behind.addLine(to: pt) }
                    } else {
                        if ahead.isEmpty { ahead.move(to: CGPoint(x: xNow, y: y(track.level(at: pos)))) }
                        ahead.addLine(to: pt)
                    }
                }
                let style = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                let fade = GraphicsContext.Shading.linearGradient(Gradient(colors: [tint.opacity(0), tint]), startPoint: .zero, endPoint: CGPoint(x: xNow, y: 0))
                g.stroke(ahead, with: .color(tint.opacity(0.42)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                g.drawLayer { l in
                    l.addFilter(.blur(radius: 7))
                    l.stroke(behind, with: .linearGradient(Gradient(colors: [tint.opacity(0), tint.opacity(0.8)]), startPoint: .zero, endPoint: CGPoint(x: xNow, y: 0)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                }
                g.stroke(behind, with: fade, style: style)

                // The dot: where you are in the breath.
                let dot = CGPoint(x: xNow, y: y(track.level(at: pos)))
                func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)) }
                g.fill(disc(30), with: .radialGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0)]), center: dot, startRadius: 0, endRadius: 30))
                g.fill(disc(7), with: .color(tint))
                g.fill(disc(3.5), with: .color(.white))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The full-screen view of a session: nothing but the breath with its words, the heart rate and the time left. A small mark at the corner brings
/// the rest back.
struct NunaBreathFullLayer<Content: View>: View {
    let content: Content
    let bpm: Int?
    let timeText: String
    var timeLabel: LocalizedStringKey = "Time left"
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            NunaBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onCollapse) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(Text("Exit full screen"))
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
                Spacer(minLength: 0)
                content.padding(.horizontal, NunaSpacing.screenH)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(bpm == nil ? NunaPalette.textMuted : NunaPalette.alertText)
                    Text(verbatim: bpm.map(String.init) ?? "–").font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    Text("bpm").font(.nuna(size: NunaTypeSize.caption, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Text(verbatim: timeText).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit().padding(.top, 6)
                Text(timeLabel).font(.nuna(size: NunaTypeSize.caption, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    .padding(.bottom, 56)
            }
        }
        .transition(.opacity)
    }
}
#endif
