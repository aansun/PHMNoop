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
    // Every surface and text token is adaptive: the first hex is the light value, the second the dark one. The dark
    // values are the Nuna originals; the light ones keep the same hierarchy on a white-grey canvas.

    // Surfaces
    public static let canvas        = Color(light: "#F2F4F6", dark: "#0A0D10")
    public static let card          = Color(light: "#FFFFFF", dark: "#14181D")
    public static let cardHighlight = Color(light: "#E9EEF2", dark: "#191F25")
    public static let glass         = Color(light: "#0A0D100D", dark: "#FFFFFF0D")
    public static let glassStrong   = Color(light: "#0A0D1014", dark: "#FFFFFF17")
    public static let hairline      = Color(light: "#0A0D1020", dark: "#FFFFFF1A")
    public static let hairlineSoft  = Color(light: "#0A0D1016", dark: "#FFFFFF14")

    /// The foreground ink of the theme (white on dark, near-black on light) and the matching shade for wells.
    /// Use `.opacity` on them wherever a translucent overlay of the text colour is wanted.
    public static let ink   = Color(light: "#0A0D10", dark: "#FFFFFF")
    public static let shade = Color(light: "#0A0D10", dark: "#000000")

    // Text
    public static let textPrimary   = Color(light: "#0A0D10", dark: "#FFFFFF")
    public static let textSecondary = Color(light: "#4C565E", dark: "#9AA4AC")
    public static let textMuted     = Color(light: "#7A848C", dark: "#6B7177")

    // Meaning colours (fills) and their readable text variants
    public static let charge        = Color(light: "#0CB300", dark: "#16EC06")   // ok, Charge, active toggles
    public static let effort        = Color(light: "#0084D1", dark: "#0093E7")
    public static let effortText    = Color(light: "#0070B5", dark: "#38AEF5")
    public static let rest          = Color(light: "#5F8AA6", dark: "#7BA1BB")
    public static let restText      = Color(light: "#43698A", dark: "#9DBBD0")
    public static let restLight     = Color(light: "#8FA9C4", dark: "#B8CCE0")   // REM
    public static let restDeep      = Color(light: "#3C5F7D", dark: "#4A7090")   // deep sleep
    public static let warning       = Color(light: "#C99A00", dark: "#FFDE00")
    public static let alert         = Color(light: "#E0001F", dark: "#FF0026")
    public static let alertText     = Color(light: "#D0102C", dark: "#FF5468")
    public static let zoneBase      = Color(light: "#C3C9D6", dark: "#3B4258")   // zone 1 / awake track

    // Primary action. White (the theme ink) by default; the wearer can pick a colour in Me > Appearance.
    public static var accent: Color { NunaThemePrefs.accent.fill }
    public static var onAccent: Color { NunaThemePrefs.accent.label }

    // Tinted chip backgrounds
    public static func tint(_ c: Color) -> Color { c.opacity(0.14) }
}

/// The wearer's theme choices, kept in UserDefaults so the palette can read them from anywhere.
public enum NunaThemePrefs {
    public static let accentKey = "nuna.accent"
    public static let typographyKey = "nuna.typography"

    public enum Accent: String, CaseIterable, Identifiable {
        case ink, green, blue, steel, yellow
        public var id: String { rawValue }
        public var fill: Color {
            switch self {
            case .ink:    return Color(light: "#0A0D10", dark: "#FFFFFF")
            case .green:  return Color(light: "#0CB300", dark: "#16EC06")
            case .blue:   return Color(light: "#0084D1", dark: "#0093E7")
            case .steel:  return Color(light: "#5F8AA6", dark: "#7BA1BB")
            case .yellow: return Color(light: "#C99A00", dark: "#FFDE00")
            }
        }
        /// The colour of text and icons drawn on top of `fill`.
        public var label: Color {
            self == .yellow ? Color(hex: "#000000") : Color(light: "#FFFFFF", dark: "#000000")
        }
        /// The swatch shown in the picker, the same in both themes so it reads as a colour name.
        public var swatch: Color {
            switch self {
            case .ink: return Color(hex: "#FFFFFF"); case .green: return Color(hex: "#16EC06"); case .blue: return Color(hex: "#0093E7")
            case .steel: return Color(hex: "#7BA1BB"); case .yellow: return Color(hex: "#FFDE00")
            }
        }
    }

    public enum Typography: String, CaseIterable, Identifiable {
        /// Rounded system face: heavy, compact numbers (the original Nuna look).
        case bold
        /// System face with expanded width: wider numerals.
        case geometric
        /// Plain system face.
        case system
        public var id: String { rawValue }
        public var design: Font.Design { self == .bold ? .rounded : .default }
    }

    public static var accent: Accent { Accent(rawValue: UserDefaults.standard.string(forKey: accentKey) ?? "") ?? .ink }
    public static var typography: Typography { Typography(rawValue: UserDefaults.standard.string(forKey: typographyKey) ?? "") ?? .bold }
}

/// Light, dark or follow the iPhone. Nuna is dark until the wearer chooses otherwise.
public enum NunaTheme {
    public static let storageKey = "nuna.theme"
    public enum Mode: String, CaseIterable, Identifiable {
        case auto, light, dark
        public var id: String { rawValue }
        public var scheme: ColorScheme? { self == .auto ? nil : (self == .light ? .light : .dark) }
    }
    public static var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .dark }
    public static var colorScheme: ColorScheme? { mode.scheme }
}

/// The font design the Nuna screens use for numerals and headings.
public enum NunaType {
    public static var design: Font.Design { NunaThemePrefs.typography.design }
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
    private let padding: EdgeInsets?
    private let content: Content
    /// `padding` overrides the default inner padding for the few cards the mockups inset differently.
    public init(small: Bool = false, highlight: Bool = false, padding: EdgeInsets? = nil,
                @ViewBuilder content: () -> Content) {
        self.small = small; self.highlight = highlight; self.padding = padding; self.content = content()
    }
    public var body: some View {
        content
            .padding(padding ?? EdgeInsets(top: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           leading: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           bottom: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           trailing: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight ? NunaPalette.cardHighlight : NunaPalette.card,
                        in: RoundedRectangle(cornerRadius: small ? NunaRadius.cardSmall : NunaRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: small ? NunaRadius.cardSmall : NunaRadius.card, style: .continuous)
                .strokeBorder(highlight ? Color.white.opacity(0.26) : NunaPalette.hairlineSoft, lineWidth: 1))
    }
}

/// Small status pill. Colour carries meaning; pass one of the NunaPalette meaning colours.
public struct NunaChip: View {
    private let text: Text
    private let systemImage: String?
    private let color: Color?
    public init(_ key: LocalizedStringKey, systemImage: String? = nil, color: Color? = nil) {
        self.text = Text(key); self.systemImage = systemImage; self.color = color
    }
    public init(verbatim: String, systemImage: String? = nil, color: Color? = nil) {
        self.text = Text(verbatim: verbatim); self.systemImage = systemImage; self.color = color
    }
    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
            text.font(.system(size: 12.5, weight: .bold))
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
