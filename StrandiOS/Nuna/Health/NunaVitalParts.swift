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
            ctx.stroke(arc(1), with: .color(.white.opacity(0.09)), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            guard let value else { return }
            let f = max(0, min(1, value / maxValue))
            if f > 0 { ctx.stroke(arc(f), with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round)) }
            let a = Angle.degrees(180 + 180 * f).radians
            let m = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 7, y: m.y - 7, width: 14, height: 14)), with: .color(.white))
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
                Capsule().fill(Color.white.opacity(0.09)).frame(height: 8).offset(y: 30)
                Capsule().fill(NunaPalette.charge.opacity(0.6)).frame(width: abs(x(age) - x(fitness)), height: 8)
                    .offset(x: min(x(age), x(fitness)), y: 30)
                Text(verbatim: String(format: "%.0f", fitness))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.onAccent)
                    .padding(.horizontal, 8).frame(height: 22).background(NunaPalette.charge, in: Capsule())
                    .position(x: fx, y: 11)
                Circle().strokeBorder(.white, lineWidth: 3).background(Circle().fill(NunaPalette.card))
                    .frame(width: 16, height: 16).position(x: x(age), y: 34)
                Text(verbatim: String(localized: "Your age \(Int(age))"))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    .position(x: ax, y: 58)
            }
        }
        .frame(height: 68)
        .accessibilityHidden(true)
    }
}
#endif
