import SwiftUI

// MARK: - Nuna design tokens
//
// Source of truth: docs/nuna/TOKENS.md and the Design Canvas mockups in docs/nuna/mockups (ui.css).
// Nuna is the "Experience" introduced by PHMNOOP. Default keeps the original NOOP look.
//
// Rules the mockups follow, and the code must keep:
//  - A restricted palette. Colour carries MEANING only:
//      green  = ok / Charge        blue = Effort          steel = Rest
//      yellow = needs attention    red  = alert / heart   white = primary action
//  - Surfaces are near-black; cards are one step lighter. No gradients on cards.
//  - Numbers use the numeric face; labels use the text face. Both come from `StrandFont`
//    (WHOOP typography preset), not from web fonts used in the mockups.

public enum NunaPalette {
    // Surfaces
    public static let canvas       = Color(hex: "#0A0D10")
    public static let card         = Color(hex: "#14181D")
    public static let cardHighlight = Color(hex: "#191F25")
    public static let glass        = Color.white.opacity(0.05)
    public static let glassStrong  = Color.white.opacity(0.09)
    public static let hairline     = Color.white.opacity(0.10)
    public static let hairlineSoft = Color.white.opacity(0.08)

    // Text
    public static let textPrimary   = Color(hex: "#FFFFFF")
    public static let textSecondary = Color(hex: "#9AA4AC")
    public static let textMuted     = Color(hex: "#6B7177")
    public static let onAccent      = Color(hex: "#000000")

    // Meaning colours (fills) and their readable text variants
    public static let charge        = Color(hex: "#16EC06")   // ok, Charge, active toggles
    public static let effort        = Color(hex: "#0093E7")
    public static let effortText    = Color(hex: "#38AEF5")
    public static let rest          = Color(hex: "#7BA1BB")
    public static let restText      = Color(hex: "#9DBBD0")
    public static let restLight     = Color(hex: "#B8CCE0")   // REM
    public static let restDeep      = Color(hex: "#4A7090")   // deep sleep
    public static let warning       = Color(hex: "#FFDE00")
    public static let alert         = Color(hex: "#FF0026")
    public static let alertText     = Color(hex: "#FF5468")
    public static let zoneBase      = Color(hex: "#3B4258")   // zone 1 / awake track

    // Tinted chip backgrounds
    public static func tint(_ c: Color) -> Color { c.opacity(0.14) }
}

public enum NunaRadius {
    public static let card: CGFloat = 28
    public static let cardSmall: CGFloat = 24
    public static let chip: CGFloat = 15       // height 30
    public static let button: CGFloat = 24     // height 48
    public static let iconButton: CGFloat = 22 // 44 x 44
    public static let tabBar: CGFloat = 36     // height 72
    public static let sheet: CGFloat = 34
    public static let iconTile: CGFloat = 14   // 40 x 40
}

public enum NunaSpacing {
    public static let screenH: CGFloat = 20
    public static let section: CGFloat = 16
    public static let cardInner: CGFloat = 18
    public static let cardInnerSmall: CGFloat = 14
    public static let tabBarBottom: CGFloat = 24
}

public enum NunaTypeSize {
    // Text sizes (pt). Weights: h1/h2 800, h3 700, body/sub 600, caption 800 uppercase.
    public static let h1: CGFloat = 34
    public static let h2: CGFloat = 22
    public static let h3: CGFloat = 17
    public static let sub: CGFloat = 14
    public static let caption: CGFloat = 11.5   // uppercase, tracking 0.1em
    // Numerals
    public static let numberXL: CGFloat = 68
    public static let numberL: CGFloat = 44
    public static let numberM: CGFloat = 30
    public static let numberS: CGFloat = 21
}

/// Which look the whole app uses. Stored in `@AppStorage(ExperienceMode.storageKey)`.
public enum ExperienceMode: String, CaseIterable, Identifiable {
    /// The original NOOP look.
    case standard
    /// The Nuna look documented in docs/nuna.
    case nuna

    public static let storageKey = "experience.mode"
    public var id: String { rawValue }
    public var displayName: String { self == .standard ? "Default" : "Nuna" }
}

// MARK: - Components

/// Card surface used everywhere in Nuna. `small` = list-row cards, `highlight` = Anya / selected.
public struct NunaCard<Content: View>: View {
    private let small: Bool
    private let highlight: Bool
    private let content: Content
    public init(small: Bool = false, highlight: Bool = false, @ViewBuilder content: () -> Content) {
        self.small = small; self.highlight = highlight; self.content = content()
    }
    public var body: some View {
        content
            .padding(small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight ? NunaPalette.cardHighlight : NunaPalette.card,
                        in: RoundedRectangle(cornerRadius: small ? NunaRadius.cardSmall : NunaRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: small ? NunaRadius.cardSmall : NunaRadius.card, style: .continuous)
                .strokeBorder(highlight ? Color.white.opacity(0.26) : NunaPalette.hairlineSoft, lineWidth: 1))
    }
}

/// Small status pill. Colour carries meaning; pass one of the NunaPalette meaning colours.
public struct NunaChip: View {
    private let text: String
    private let systemImage: String?
    private let color: Color?
    public init(_ text: String, systemImage: String? = nil, color: Color? = nil) {
        self.text = text; self.systemImage = systemImage; self.color = color
    }
    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            Text(text).font(.system(size: 12.5, weight: .bold))
        }
        .foregroundStyle(color ?? NunaPalette.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(color.map { NunaPalette.tint($0) } ?? NunaPalette.glassStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(color?.opacity(0.35) ?? NunaPalette.hairline, lineWidth: 1))
    }
}

/// Score ring used for Charge / Effort / Rest and the Trends gauges.
public struct NunaRingGauge<Center: View>: View {
    private let fraction: Double
    private let color: Color
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let center: Center
    public init(fraction: Double, color: Color, size: CGFloat = 98, lineWidth: CGFloat = 9,
                @ViewBuilder center: () -> Center) {
        self.fraction = min(max(fraction, 0), 1); self.color = color
        self.size = size; self.lineWidth = lineWidth; self.center = center()
    }
    public var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.09), lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size - lineWidth, height: size - lineWidth)
        .padding(lineWidth / 2)
    }
}

/// Heart-rate zone bar with a marker. `position` is 0...1 along the bar.
public struct NunaZoneBar: View {
    private let position: Double
    public init(position: Double) { self.position = min(max(position, 0), 1) }
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    Capsule().fill(NunaPalette.zoneBase).frame(maxWidth: .infinity)
                        .frame(width: geo.size.width * 0.18)
                    Capsule().fill(NunaPalette.charge).frame(width: geo.size.width * 0.18)
                    Capsule().fill(NunaPalette.warning).frame(width: geo.size.width * 0.18)
                    Capsule().fill(NunaPalette.alert).frame(maxWidth: .infinity)
                }
                .frame(height: 10)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .offset(x: geo.size.width * position - 5, y: 12)
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}
