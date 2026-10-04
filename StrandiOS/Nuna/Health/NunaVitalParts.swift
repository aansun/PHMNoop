#if os(iOS)
import SwiftUI
import StrandDesign

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
                Capsule().fill(NunaPalette.ink.opacity(0.09)).frame(height: 8).offset(y: 30)
                Capsule().fill(NunaPalette.charge.opacity(0.6)).frame(width: abs(x(age) - x(fitness)), height: 8)
                    .offset(x: min(x(age), x(fitness)), y: 30)
                Text(verbatim: String(format: "%.0f", fitness))
                    .font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.onAccent)
                    .padding(.horizontal, 8).frame(height: 22).background(NunaPalette.charge, in: Capsule())
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
            .background(NunaPalette.tint(color), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
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
                        .frame(width: 34, height: 34).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase)
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
                else if let note { Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).frame(height: 24, alignment: .leading) }
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
                Text(verbatim: String(format: "%.0f", cm)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
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
                .frame(width: 64, height: 64).background(NunaPalette.glassStrong, in: Circle())
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
                    Capsule().fill(live[i].color)
                        .frame(width: max(0, (geo.size.width - gaps) * CGFloat(live[i].weight / total)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
#endif
