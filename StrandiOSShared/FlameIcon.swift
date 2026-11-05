import SwiftUI

/// The flame of the day streak, drawn once for the app and the widgets: an outer flame with a tall, slim tip.
struct NunaFlameShape: Shape {
    /// 0 is the outer flame, 1 the lighter one inside it.
    var inner = false
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: x + a * w, y: y + b * h) }
        var p = Path()
        p.move(to: pt(0.5, 1))
        p.addCurve(to: pt(0.12, 0.62), control1: pt(0.2, 0.98), control2: pt(0.0, 0.8))
        p.addCurve(to: pt(0.30, 0.30), control1: pt(0.22, 0.50), control2: pt(0.34, 0.45))
        p.addCurve(to: pt(0.52, 0.0), control1: pt(0.28, 0.15), control2: pt(0.50, 0.12))
        p.addCurve(to: pt(0.72, 0.38), control1: pt(0.58, 0.12), control2: pt(0.62, 0.28))
        p.addCurve(to: pt(0.88, 0.66), control1: pt(0.80, 0.46), control2: pt(0.98, 0.52))
        p.addCurve(to: pt(0.5, 1), control1: pt(1.0, 0.9), control2: pt(0.8, 0.99))
        p.closeSubpath()
        return p
    }
}

/// The flame as a small icon: the same drawing as the big one, in a tall slim frame (half as wide as it is high), with the lighter flame inside.
struct NunaFlameIcon: View {
    var height: CGFloat
    var outer: [Color] = [Color(red: 1, green: 0.50, blue: 0.20), Color(red: 0.97, green: 0.36, blue: 0.10)]
    var inner: [Color] = [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.99, green: 0.78, blue: 0.55)]

    /// The first day of a run, in gold.
    static let gold: [Color] = [Color(red: 1, green: 0.84, blue: 0.48), Color(red: 1, green: 0.70, blue: 0.28)]
    /// A flame that is not lit.
    static let unlit: [Color] = [Color.white.opacity(0.46), Color.white.opacity(0.30)]

    var body: some View {
        ZStack {
            NunaFlameShape().fill(LinearGradient(colors: outer, startPoint: .top, endPoint: .bottom))
            NunaFlameShape(inner: true).fill(LinearGradient(colors: inner, startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: 0.40, y: 0.42, anchor: .bottom).offset(y: -height * 0.03)
        }
        .frame(width: height * 0.5, height: height)
        .accessibilityHidden(true)
    }
}
