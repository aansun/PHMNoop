import SwiftUI

/// The two vital-sign pictures that the WHOOP metric set does not carry, drawn in the same thin outline: blood oxygen (a drop with two bubbles)
/// and temperature (a thermometer). Named `vital:spo2` and `vital:temp` wherever an icon name is taken (see `NunaGlyph`).
public struct NunaVitalGlyph: View {
    public enum Kind { case spo2, temp }
    let kind: Kind
    let size: CGFloat
    public init(_ kind: Kind, size: CGFloat) { self.kind = kind; self.size = size }

    public init?(name: String, size: CGFloat) {
        switch name {
        case "vital:spo2": self.init(.spo2, size: size)
        case "vital:temp": self.init(.temp, size: size)
        default: return nil
        }
    }

    public var body: some View {
        NunaVitalShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: size * 0.068, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct NunaVitalShape: Shape {
    let kind: NunaVitalGlyph.Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2, oy = rect.minY + (rect.height - 24 * s) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        /// Points of an arc around (cx, cy); the angle grows clockwise on screen.
        func arc(_ p: inout Path, _ cx: Double, _ cy: Double, _ r: Double, from a: Double, to b: Double) {
            let steps = max(Int(abs(b - a) / 5), 2)
            for i in 0...steps {
                let t = (a + (b - a) * Double(i) / Double(steps)) * .pi / 180
                p.addLine(to: pt(cx + r * cos(t), cy + r * sin(t)))
            }
        }
        func circle(_ p: inout Path, _ cx: Double, _ cy: Double, _ r: Double) {
            p.move(to: pt(cx + r, cy))
            arc(&p, cx, cy, r, from: 0, to: 360)
        }
        var p = Path()
        switch kind {
        case .spo2:
            // A drop: the tangents from its tip to a circle, and the circle's lower half.
            p.move(to: pt(10, 3))
            p.addLine(to: pt(10 + 5.6 * cos(210 * .pi / 180), 14.2 + 5.6 * sin(210 * .pi / 180)))
            arc(&p, 10, 14.2, 5.6, from: 210, to: -30)
            p.closeSubpath()
            circle(&p, 17.2, 5.2, 1.7)
            circle(&p, 19.4, 9.4, 0.9)
        case .temp:
            p.move(to: pt(8.6, 16.05))
            p.addLine(to: pt(8.6, 6))
            arc(&p, 12, 6, 3.4, from: 180, to: 360)
            p.addLine(to: pt(15.4, 16.05))
            arc(&p, 12, 19, 4.5, from: -41, to: 221)
            p.closeSubpath()
            circle(&p, 12, 19, 1.8)
        }
        return p
    }
}
