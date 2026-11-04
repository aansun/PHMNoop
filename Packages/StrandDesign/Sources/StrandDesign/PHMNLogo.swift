import SwiftUI

// MARK: - PHMN logo
//
// The PHMN identity drawn natively from the butterfly of the app icon, in the same family of marks as the reference: a thin Circle, a solid
// Puck with the butterfly cut out of it, and a monoline wordmark. The geometry is generated (PHMNLogoGeometry.swift) from the icon's vector
// source, so the vector files in PHMN-logo/ and these views always draw the same butterfly.
//
// Anya, the assistant, wears the same butterfly in a ring that runs from violet to sky blue.

/// The butterfly in a single colour: the wings (each with a thin gap between its two facets), the body, the stem and the antenna.
public struct PHMNButterflyShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * k, oy = rect.midY - 50 * k
        var path = Path()
        for piece in PHMNButterflyGeometry.mono { Self.add(piece, to: &path, k: k, ox: ox, oy: oy) }
        return path
    }

    static func add(_ cmds: [PHMNButterflyGeometry.Cmd], to path: inout Path, k: CGFloat, ox: CGFloat, oy: CGFloat) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }
        for c in cmds {
            switch c {
            case .m(let x, let y): path.move(to: pt(x, y))
            case .l(let x, let y): path.addLine(to: pt(x, y))
            case .c(let x1, let y1, let x2, let y2, let x, let y): path.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
            case .z: path.closeSubpath()
            }
        }
    }
}

/// The butterfly in the colours of the app icon: teal facets, a white and grey body, a gold antenna.
public struct PHMNButterfly: View {
    public var size: CGFloat
    public init(size: CGFloat = 28) { self.size = size }

    private static func color(_ role: String) -> Color {
        switch role {
        case "wingUpLight": return Color(red: 127 / 255, green: 224 / 255, blue: 210 / 255)
        case "wingUpDark": return Color(red: 53 / 255, green: 167 / 255, blue: 159 / 255)
        case "wingLoLight": return Color(red: 79 / 255, green: 191 / 255, blue: 188 / 255)
        case "wingLoDark": return Color(red: 35 / 255, green: 128 / 255, blue: 127 / 255)
        case "bodyL": return Color(red: 244 / 255, green: 247 / 255, blue: 249 / 255)
        case "bodyR": return Color(red: 174 / 255, green: 187 / 255, blue: 198 / 255)
        case "stem": return Color(red: 133 / 255, green: 147 / 255, blue: 161 / 255)
        default: return Color(red: 226 / 255, green: 185 / 255, blue: 95 / 255)
        }
    }

    public var body: some View {
        Canvas { ctx, canvas in
            let k = min(canvas.width, canvas.height) / 100
            let ox = (canvas.width - 100 * k) / 2, oy = (canvas.height - 100 * k) / 2
            for piece in PHMNButterflyGeometry.color {
                var p = Path()
                PHMNButterflyShape.add(piece.cmds, to: &p, k: k, ox: ox, oy: oy)
                ctx.fill(p, with: .color(Self.color(piece.role)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The Circle and the Puck of the logo family: the butterfly in a thin ring, or cut out of a solid disc.
public struct PHMNMark: View {
    public enum Style { case circle, puck }
    public var style: Style
    public var size: CGFloat
    public var color: Color

    public init(_ style: Style = .circle, size: CGFloat = 30, color: Color = .white) {
        self.style = style; self.size = size; self.color = color
    }

    /// The butterfly is this share of the frame's width.
    static let share: CGFloat = 0.6

    public var body: some View {
        ZStack {
            switch style {
            case .circle:
                Circle().strokeBorder(color, lineWidth: size * 0.05)
                PHMNButterflyShape().fill(color).frame(width: size * Self.share, height: size * Self.share)
            case .puck:
                // The disc and the butterfly in one path filled even-odd: the butterfly is a hole.
                PHMNPuckShape().fill(color, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PHMNPuckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect)
        let side = min(rect.width, rect.height)
        p.addPath(PHMNButterflyShape().path(in: CGRect(x: rect.midX - side * PHMNMark.share / 2, y: rect.midY - side * PHMNMark.share / 2, width: side * PHMNMark.share, height: side * PHMNMark.share)))
        return p
    }
}

/// Anya's mark: the PHMN butterfly in white inside a ring that runs from violet at the upper left to sky blue at the lower right.
public struct PHMNAnyaMark: View {
    public var size: CGFloat
    /// A faint glow of the ring's colour just inside it, for the floating button and the pill.
    public var glow: Bool

    public init(size: CGFloat = 34, glow: Bool = true) { self.size = size; self.glow = glow }

    public static let violet = Color(red: 132 / 255, green: 124 / 255, blue: 233 / 255)
    public static let sky = Color(red: 134 / 255, green: 196 / 255, blue: 255 / 255)
    public static var gradient: LinearGradient { LinearGradient(colors: [violet, sky], startPoint: .topLeading, endPoint: .bottomTrailing) }

    public var body: some View {
        ZStack {
            if glow {
                Circle().fill(RadialGradient(colors: [.clear, Self.violet.opacity(0.30)], center: .center, startRadius: size * 0.30, endRadius: size * 0.5))
            }
            Circle().strokeBorder(Self.gradient, lineWidth: max(1.3, size * 0.05))
            PHMNButterflyShape().fill(Color.white).frame(width: size * PHMNMark.share, height: size * PHMNMark.share)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "PHMN" in the monoline letters of the logo. `height` is the capital height; the width follows.
public struct PHMNWordmark: View {
    public var height: CGFloat
    public var color: Color

    public init(height: CGFloat = 12, color: Color = .white) { self.height = height; self.color = color }

    public var body: some View {
        let k = height / PHMNButterflyGeometry.wordmarkCap
        PHMNWordmarkShape().fill(color)
            .frame(width: PHMNButterflyGeometry.wordmarkWidth * k, height: height)
            .accessibilityLabel(Text(verbatim: "PHMN"))
    }
}

struct PHMNWordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.height / PHMNButterflyGeometry.wordmarkCap
        var path = Path()
        for poly in PHMNButterflyGeometry.wordmark {
            guard let first = poly.first else { continue }
            path.move(to: CGPoint(x: rect.minX + first.x * k, y: rect.minY + first.y * k))
            for p in poly.dropFirst() { path.addLine(to: CGPoint(x: rect.minX + p.x * k, y: rect.minY + p.y * k)) }
            path.closeSubpath()
        }
        return path
    }
}

/// The app icon as a tile: the colour butterfly in the thin ring on the icon's navy, in a rounded square (for places that show the app as a picture).
public struct PHMNAppTile: View {
    public var size: CGFloat
    public init(size: CGFloat = 84) { self.size = size }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Color(red: 12 / 255, green: 17 / 255, blue: 27 / 255))
            Circle().strokeBorder(Color(red: 143 / 255, green: 163 / 255, blue: 192 / 255), lineWidth: max(1, size * 0.016)).frame(width: size * 0.86, height: size * 0.86)
            PHMNButterfly(size: size * 0.58)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
