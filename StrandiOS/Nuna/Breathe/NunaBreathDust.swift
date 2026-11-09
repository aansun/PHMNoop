#if os(iOS)
import SwiftUI
import StrandDesign

/// The breath as a sphere of glowing dust, after the "Charging" study on Dribbble: a thin shell of thousands of tiny lights that drift round like a
/// galaxy or like water, brightest at the rim, with a dark hollow in the middle for the words. The shell swells while you breathe in and settles while
/// you breathe out (`progress`, 0 to 1, animated by the caller). It is `Animatable`, so SwiftUI hands it every in-between value of an animation.
struct NunaDustOrb: View, Animatable {
    var progress: CGFloat
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private struct Dust { let theta: Double; let phi: Double; let size: Double; let seed: Double }

    /// A fixed scatter over a sphere (a golden-angle spiral, so it is even), each grain with its own size, speed and twinkle.
    private static let dust: [Dust] = {
        var out: [Dust] = []
        let n = 2800
        var s: UInt64 = 0x9E37_79B9_7F4A_7C15
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF) }
        for i in 0..<n {
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let phi = acos(y)
            let theta = Double(i) * 2.399963229728653
            out.append(Dust(theta: theta, phi: phi, size: 0.7 + rnd() * rnd() * 2.6, seed: rnd()))
        }
        return out
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2
                let rMax = outer * 0.76
                let p = Double(min(max(progress, 0), 1))
                let radius = rMax * (0.66 + 0.34 * p)
                let hollow = rMax * 0.40
                func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

                // The glow behind the shell, wider while it is full.
                g.fill(circle(outer), with: .radialGradient(
                    Gradient(stops: [.init(color: tint.opacity(0), location: radius * 0.80 / outer), .init(color: tint.opacity(0.30 + 0.12 * p), location: radius * 1.02 / outer), .init(color: tint.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: outer))
                // A soft bright rim.
                g.drawLayer { l in
                    l.addFilter(.blur(radius: 9))
                    l.stroke(circle(radius), with: .color(tint.opacity(0.42)), lineWidth: 9)
                }

                // The dust: it turns about the vertical axis, each grain at its own speed, and twinkles.
                let spin = t * 0.2
                for d in Self.dust {
                    let th = d.theta + spin * (0.55 + 0.9 * d.seed)
                    let x = sin(d.phi) * cos(th), y = cos(d.phi), z = sin(d.phi) * sin(th)
                    let r = radius * (1 + 0.03 * sin(t * 1.1 + d.seed * 23))
                    let px = c.x + CGFloat(x) * r, py = c.y + CGFloat(y) * r * 0.98
                    let depth = (z + 1) / 2
                    let twinkle = 0.55 + 0.45 * sin(t * (1.2 + d.seed * 2.2) + d.seed * 41)
                    let alpha = (0.14 + 0.86 * depth) * twinkle
                    let s = CGFloat(d.size * (0.65 + 0.7 * depth)) * (size.width > 500 ? 1.6 : 1)
                    let color: Color = d.seed > 0.88 ? .white : tint
                    g.fill(Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)), with: .color(color.opacity(alpha)))
                }

                // The hollow in the middle, so the words sit on dark and the shell reads as a ring.
                g.fill(circle(hollow * 1.2), with: .radialGradient(
                    Gradient(stops: [.init(color: NunaPalette.canvas.opacity(0.96), location: 0), .init(color: NunaPalette.canvas.opacity(0.96), location: 0.72), .init(color: NunaPalette.canvas.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: hollow * 1.2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The full-screen view of a session: nothing but the dust with its words, the heart rate and the time left. A small mark at the corner brings the rest back.
struct NunaBreathFullLayer<Orb: View>: View {
    let orb: Orb
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
                orb.frame(maxWidth: 380).aspectRatio(1, contentMode: .fit).padding(.horizontal, 12)
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
