#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// A 180-degree arc gauge (0...maxValue) with a dot marking the value.
struct NunaHalfGauge: View {
    let value: Double?
    let maxValue: Double
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let lw: CGFloat = 12
            let r = min(size.width / 2 - lw / 2, size.height - lw)
            let c = CGPoint(x: size.width / 2, y: size.height - lw / 2)
            func arc(_ f: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * f), clockwise: false)
                return p
            }
            ctx.stroke(arc(1), with: .color(NunaPalette.ink.opacity(0.09)), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            guard let value else { return }
            let f = max(0, min(1, value / maxValue))
            if f > 0 { ctx.stroke(arc(f), with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round)) }
            let a = Angle.degrees(180 + 180 * f).radians
            let m = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 7, y: m.y - 7, width: 14, height: 14)), with: .color(NunaPalette.ink))
        }
        .accessibilityHidden(true)
    }
}

/// Fitness age against real age: a track with the fitness marker above and the real-age ring below.
struct NunaAgeSlider: View {
    let fitness: Double
    let age: Double

    var body: some View {
        let lo = min(fitness, age) - 8, hi = max(fitness, age) + 8
        let span = max(hi - lo, 1)
        return GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / span) * w }
            let fx = min(max(x(fitness), 18), w - 18), ax = min(max(x(age), 30), w - 30)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink.opacity(0.09)).frame(height: 8).offset(y: 30)
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.charge.opacity(0.6)).frame(width: abs(x(age) - x(fitness)), height: 8)
                    .offset(x: min(x(age), x(fitness)), y: 30)
                Text(verbatim: String(format: "%.0f", fitness))
                    .font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.onAccent)
                    .padding(.horizontal, 8).frame(height: 22).background(NunaPalette.charge, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    .position(x: fx, y: 11)
                Circle().strokeBorder(NunaPalette.ink, lineWidth: 3).background(Circle().fill(NunaPalette.card))
                    .frame(width: 16, height: 16).position(x: x(age), y: 34)
                Text(verbatim: String(localized: "Your age \(Int(age))"))
                    .font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    .position(x: ax, y: 58)
            }
        }
        .frame(height: 68)
        .accessibilityHidden(true)
    }
}

/// Small status chip for the vital tiles ("Normal", "Small deviation"). Colour carries the meaning.
struct NunaMiniChip: View {
    let text: LocalizedStringKey
    var color: Color = NunaPalette.charge
    /// A small dot before the text: the mark of a reading that has no verdict yet.
    var dot = false
    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text).font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(color).textCase(dot ? nil : .uppercase).lineLimit(1)
        }
        .padding(.horizontal, 9).frame(height: 24)
        .background(NunaPalette.tint(color), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// A vital sign on the Health monitor page, as on the WHOOP page: the picture and the name, the reading large with its unit, and under it a
/// pill that says where the reading sits against the wearer's own range ("within 60 - 62", "elevated > 80"), with a check when that is fine.
struct NunaVitalTile: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    /// The pill's words and colour; a check mark leads when `symbol` is given, a dot when it is nil (no verdict yet).
    var chip: String?
    var chipColor: Color = NunaPalette.charge
    var symbol: String?

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    NunaIcon(name: icon, size: 17, weight: .medium).foregroundStyle(NunaPalette.textSecondary).frame(width: 26, height: 26)
                    Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary).lineLimit(2).multilineTextAlignment(.leading).padding(.top, 6)
                }
                .frame(minHeight: 26, alignment: .top)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: value).font(.nuna(size: 36, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(36))
                        .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !unit.isEmpty && value != "–" {
                        Text(verbatim: unit).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    }
                }
                .frame(height: 40).padding(.top, 10)
                Group {
                    if let chip {
                        HStack(spacing: 6) {
                            if let symbol { Image(systemName: symbol).font(.nuna(size: 10, weight: .heavy)) } else { Circle().fill(chipColor).frame(width: 6, height: 6) }
                            Text(verbatim: chip).font(.nuna(size: 13, weight: .semibold)).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(chipColor).padding(.horizontal, 8).frame(height: 24)
                        .background(chipColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Manual waist entry. Writes the profile value that the VO₂max estimate reads.
struct NunaWaistSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var cm: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Waist").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: String(format: "%.0f", cm)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).foregroundStyle(NunaPalette.textPrimary)
                Text("cm").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            HStack(spacing: 16) {
                stepButton("minus") { cm = max(60, cm - 1) }
                stepButton("plus") { cm = min(160, cm + 1) }
            }
            Button {
                profile.waistCm = cm; dismiss()
            } label: {
                Text("Save").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NunaBackdrop())
        .presentationDetents([.height(380)])
        .onAppear { cm = profile.waistCm > 0 ? profile.waistCm : 80 }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 64, height: 64)
        }.buttonStyle(.plain)
    }
}

/// A row of rounded segments sized by share (weights need not add up to 1). Zero-weight parts are left out.
struct NunaProportionBar: View {
    let parts: [(weight: Double, color: Color)]
    var height: CGFloat = 14
    /// Corner radius of a segment; nil is a full pill.
    var corner: CGFloat?
    var gap: CGFloat = 3
    var body: some View {
        GeometryReader { geo in
            let total0 = max(parts.reduce(0) { $0 + max($1.weight, 0) }, 0.0001)
            let live = parts.filter { $0.weight / total0 >= 0.004 }
            let total = max(live.reduce(0) { $0 + $1.weight }, 0.0001)
            let gaps = CGFloat(max(live.count - 1, 0)) * gap
            HStack(spacing: gap) {
                ForEach(live.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: corner ?? NunaRadius.pill, style: .continuous).fill(live[i].color)
                        .frame(width: max(0, (geo.size.width - gaps) * CGFloat(live[i].weight / total)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
#endif

#if os(iOS)
private enum NunaOrbField {
    /// Deterministic particle field so it does not flicker between redraws.
    static let particles: [(a: Double, r: Double, s: Double, o: Double)] = {
        var g = SplitMix(seed: 7)
        return (0..<90).map { _ in (g.next() * 2 * .pi, 0.18 + 0.8 * g.next().squareRoot(), 1 + 3.2 * g.next() * g.next(), 0.35 + 0.65 * g.next()) }
    }()

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }


}

/// The fitness-age orb: an organic blob with a soft glow and a field of small particles, the number in its middle. The colour
/// says which way the comparison goes (green younger, amber older, neutral about the same). The shape drifts slowly and stands
/// still when Reduce Motion is on. Pure decoration around one stored number.
struct NunaFitnessOrb<Center: View>: View {
    let tint: Color
    var size: CGFloat = 270
    @ViewBuilder var center: () -> Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var motion = NoopMotionState.shared

    /// Closed smooth blob: a circle whose radius is nudged by a few low harmonics.
    private static func blob(in rect: CGRect, phase: Double, grow: Double = 1) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 * 0.74 * grow
        let steps = 120
        var p = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let wob = 0.055 * sin(2 * t + phase) + 0.04 * sin(3 * t - phase * 1.3) + 0.025 * sin(5 * t + phase * 0.7)
            let r = base * (1 + wob)
            let pt = CGPoint(x: c.x + CGFloat(cos(t) * r), y: c.y + CGFloat(sin(t) * r))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: motion.poseStill(reduceMotion))) { tl in
            let phase = motion.poseStill(reduceMotion) ? 0.6 : tl.date.timeIntervalSinceReferenceDate * 0.35
            ZStack {
                Canvas { ctx, sz in
                    let rect = CGRect(origin: .zero, size: sz)
                    // Outer glow
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 18))
                        l.fill(Self.blob(in: rect, phase: phase, grow: 1.02), with: .color(tint.opacity(0.38)))
                    }
                    let shape = Self.blob(in: rect, phase: phase)
                    // The core carries the figure in the text colour, so it is dark on a dark theme and light on a light one: a black core under
                    // dark text on the light theme hid the number and its caption.
                    let core = scheme == .dark ? Color.black : NunaPalette.card
                    ctx.fill(shape, with: .radialGradient(Gradient(stops: [
                        .init(color: core.opacity(0.92), location: 0.0),
                        .init(color: core.opacity(0.85), location: 0.45),
                        .init(color: tint.opacity(0.55), location: 0.9),
                        .init(color: tint.opacity(0.85), location: 1.0)]),
                        center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: min(sz.width, sz.height) / 2 * 0.9))
                    ctx.stroke(shape, with: .color(tint.opacity(0.9)), lineWidth: 1.6)
                    // Particles, drifting a little
                    let rad = min(sz.width, sz.height) / 2 * 0.68
                    for p in NunaOrbField.particles {
                        let a = p.a + phase * 0.12 * (p.r > 0.6 ? 1 : -1)
                        let r = rad * p.r
                        let pt = CGPoint(x: rect.midX + CGFloat(cos(a) * r), y: rect.midY + CGFloat(sin(a) * r))
                        // brighter near the rim
                        let alpha = p.o * (0.35 + 0.65 * p.r)
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - p.s / 2, y: pt.y - p.s / 2, width: p.s, height: p.s)), with: .color(tint.opacity(alpha)))
                    }
                }
                center()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}
#endif

#if os(iOS)
/// The pace dial: a ruler from -1.0x to 3.0x with the reading marked, Slow on the left and Fast on the right, 1.0x labelled
/// in the middle of the useful range. With no reading it shows the empty ruler.
struct NunaPaceDial: View {
    let value: Double?
    private let lo = PaceOfAging.range.lowerBound, hi = PaceOfAging.range.upperBound

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Slow").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Spacer()
                Text("Fast").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / (hi - lo)) * w }
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let ticks = 80
                        for i in 0...ticks {
                            let v = lo + (hi - lo) * Double(i) / Double(ticks)
                            let major = i % 20 == 0
                            let h: CGFloat = major ? 34 : (i % 5 == 0 ? 26 : 20)
                            let px = x(v)
                            var p = Path(); p.move(to: CGPoint(x: px, y: size.height / 2 - h / 2)); p.addLine(to: CGPoint(x: px, y: size.height / 2 + h / 2))
                            ctx.stroke(p, with: .color(NunaPalette.ink.opacity(major ? 0.55 : 0.28)), lineWidth: major ? 2 : 1.2)
                        }
                    }
                    if let value {
                        let px = min(max(x(value), 2), w - 2)
                        RoundedRectangle(cornerRadius: 2).fill(NunaPalette.textPrimary).frame(width: 4, height: 46).position(x: px, y: 22)
                    }
                }
            }
            .frame(height: 44)
            HStack {
                Text(verbatim: "-1.0x"); Spacer(); Text(verbatim: "1.0x"); Spacer(); Text(verbatim: "3.0x")
            }
            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: value.map { String(format: "%.1fx", $0) } ?? "–"))
    }
}
#endif

#if os(iOS)
/// The stress gauge: an open arc from 0.0 to 3.0 that runs blue, green, yellow and red, the current value as a white block on
/// the arc with a short streak pointing inward, the number large in the middle, the level word under it and the time of the
/// reading. The part of the arc past the value is dimmed.
struct NunaStressGauge: View {
    let value: Double?
    let level: LocalizedStringKey?
    let levelColor: Color
    let time: String?
    var onInfo: (() -> Void)?
    /// The height of the dial; the number inside follows it.
    var height: CGFloat = 250

    /// The short form (the Stress monitor page): a wider, flatter arc with the labels close under its ends, so the dial takes less height.
    private var compact: Bool { height < 220 }
    private var start: Double { compact ? 159 : 140 }
    private var span: Double { compact ? 222 : 260 }
    private var numberSize: CGFloat { compact ? 60 : 64 }
    /// Blue, green, yellow and amber along the arc. An angular gradient runs round the whole circle from 3 o'clock, so the colours are
    /// placed by the angle the arc covers (it starts low on the left and ends low on the right, past 12 o'clock).
    private var stops: Gradient {
        let ramp: [Gradient.Stop] = [.init(color: NunaStressBand.low, location: 0), .init(color: NunaStressBand.medium, location: 0.38),
                                     .init(color: NunaPalette.effort, location: 0.7), .init(color: NunaStressBand.high, location: 1)]
        var out: [Gradient.Stop] = []
        for d in stride(from: 0.0, through: 360.0, by: 2.0) {
            var rel = (d - start).truncatingRemainder(dividingBy: 360)
            if rel < 0 { rel += 360 }
            // Inside the gap under the dial the colour jumps from the end of the ramp to its start, half way across it, so neither end of
            // the arc takes the other's colour at its rounded cap.
            let f = rel <= span ? rel / span : (rel - span < (360 - span) / 2 ? 1 : 0)
            out.append(.init(color: StrandPalette.sample(stops: ramp, at: f), location: d / 360))
        }
        return Gradient(stops: out)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    GeometryReader { geo in
                        let lw: CGFloat = 7
                        let side = min(geo.size.width, geo.size.height)
                        let r = compact ? min(118, geo.size.width / 2 - lw - 8) : side / 2 - lw
                        let c = CGPoint(x: geo.size.width / 2, y: compact ? r + lw + 2 : geo.size.height / 2 + 6)
                        let f = max(0, min(1, (value ?? 0) / 3))
                        let a = Angle.degrees(start + span * f).radians
                        let m = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                        ZStack {
                            arc(c, r, 1).stroke(AngularGradient(gradient: stops, center: .center),
                                                style: StrokeStyle(lineWidth: lw, lineCap: .round)).opacity(0.3)
                            if value != nil {
                                arc(c, r, f).stroke(AngularGradient(gradient: stops, center: .center),
                                                    style: StrokeStyle(lineWidth: lw, lineCap: .round))
                                streak(from: m, toward: c, along: a, length: 44)
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaPalette.textPrimary)
                                    .frame(width: 6, height: 24).rotationEffect(.radians(a + .pi / 2)).position(m)
                            }
                            VStack(spacing: 6) {
                                Text(verbatim: value.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                                    .font(.nuna(size: numberSize, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(numberSize)).foregroundStyle(NunaPalette.textPrimary)
                                if let level { Text(level).font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(levelColor) }
                                if let time { Text(verbatim: time).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                            }
                            .position(x: c.x, y: compact ? c.y : c.y - 6)
                            ForEach([("0.0", start), ("3.0", start + span)], id: \.0) { label, deg in
                                let rad = Angle.degrees(deg).radians
                                Text(verbatim: label).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                    .position(x: c.x + r * CGFloat(cos(rad)), y: c.y + r * CGFloat(sin(rad)) + (compact ? 20 : 30))
                            }
                        }
                    }
                }
                .frame(height: height)
            }
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: 30, height: 30).overlay(Circle().strokeBorder(NunaPalette.textSecondary, lineWidth: 2))
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("About this score"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func arc(_ c: CGPoint, _ r: CGFloat, _ f: Double) -> Path {
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(start), endAngle: .degrees(start + span * f), clockwise: false)
        return p
    }

    /// A short motion streak behind the marker, drawn toward the centre of the gauge.
    private func streak(from m: CGPoint, toward c: CGPoint, along a: Double, length: CGFloat) -> some View {
        let end = CGPoint(x: m.x - length * CGFloat(cos(a)), y: m.y - length * CGFloat(sin(a)))
        return Path { p in p.move(to: m); p.addLine(to: end) }
            .stroke(LinearGradient(colors: [NunaPalette.textPrimary.opacity(0.85), NunaPalette.textPrimary.opacity(0)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: UnitPoint(x: 0.5, y: 0.5)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .mask(LinearGradient(colors: [.white, .clear], startPoint: UnitPoint(x: m.x / max(c.x * 2, 1), y: m.y / max(c.y * 2, 1)),
                                 endPoint: UnitPoint(x: end.x / max(c.x * 2, 1), y: end.y / max(c.y * 2, 1))))
    }
}
#endif
