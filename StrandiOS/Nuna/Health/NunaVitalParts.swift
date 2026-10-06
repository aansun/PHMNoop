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
    var body: some View {
        Text(text).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 9).frame(height: 24)
            .background(NunaPalette.tint(color), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// Vital tile from the Health Vital mockup: icon tile and label, the value, then a status chip or note.
struct NunaVitalTile: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var chip: LocalizedStringKey?
    var chipColor: Color = NunaPalette.charge
    var note: String?

    var body: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 34, height: 34).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !unit.isEmpty && value != "–" {
                        Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let chip { NunaMiniChip(text: chip, color: chipColor) }
                else if let note { Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).frame(height: 24, alignment: .leading) }
                else { Color.clear.frame(height: 24) }
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
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDetents([.height(380)])
        .onAppear { cm = profile.waistCm > 0 ? profile.waistCm : 80 }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 64, height: 64).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// A row of rounded segments sized by share (weights need not add up to 1). Zero-weight parts are left out.
struct NunaProportionBar: View {
    let parts: [(weight: Double, color: Color)]
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { geo in
            let total0 = max(parts.reduce(0) { $0 + max($1.weight, 0) }, 0.0001)
            let live = parts.filter { $0.weight / total0 >= 0.004 }
            let total = max(live.reduce(0) { $0 + $1.weight }, 0.0001)
            let gaps = CGFloat(max(live.count - 1, 0)) * 3
            HStack(spacing: 3) {
                ForEach(live.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(live[i].color)
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
                    // Dark core with a bright rim
                    ctx.fill(shape, with: .radialGradient(Gradient(stops: [
                        .init(color: Color.black.opacity(0.92), location: 0.0),
                        .init(color: Color.black.opacity(0.85), location: 0.45),
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

    private let start = 160.0, span = 220.0
    private var stops: Gradient {
        Gradient(colors: [NunaPalette.effort, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert])
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    GeometryReader { geo in
                        let lw: CGFloat = 16
                        let side = min(geo.size.width, geo.size.height)
                        let r = side / 2 - lw
                        let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let f = max(0, min(1, (value ?? 0) / 3))
                        let a = Angle.degrees(start + span * f).radians
                        let m = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                        ZStack {
                            arc(c, r, 1).stroke(AngularGradient(gradient: stops, center: .center, startAngle: .degrees(start), endAngle: .degrees(start + span)),
                                                style: StrokeStyle(lineWidth: lw, lineCap: .round)).opacity(0.42)
                            if value != nil {
                                arc(c, r, f).stroke(AngularGradient(gradient: stops, center: .center, startAngle: .degrees(start), endAngle: .degrees(start + span)),
                                                    style: StrokeStyle(lineWidth: lw, lineCap: .round))
                                streak(from: m, toward: c, along: a, length: 50)
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaPalette.textPrimary)
                                    .frame(width: 14, height: 22).rotationEffect(.radians(a + .pi / 2)).position(m)
                            }
                            VStack(spacing: 8) {
                                Text(verbatim: value.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                                    .font(.nuna(size: 92, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(92)).foregroundStyle(NunaPalette.textPrimary)
                                if let level { Text(level).font(.nuna(size: 20, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(levelColor) }
                                if let time { Text(verbatim: time).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                            }
                            .position(x: c.x, y: c.y - 6)
                            ForEach([("0.0", start), ("3.0", start + span)], id: \.0) { label, deg in
                                let rad = Angle.degrees(deg).radians
                                Text(verbatim: label).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted)
                                    .position(x: c.x + r * CGFloat(cos(rad)), y: c.y + r * CGFloat(sin(rad)) + 36)
                            }
                        }
                    }
                }
                .frame(height: 280)
            }
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.textSecondary, lineWidth: 1.6))
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
