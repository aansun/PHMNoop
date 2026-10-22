import SwiftUI
import CoreText

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
    /// A token that follows the selected skin: the light and dark values of the Default skin, or the WHP slate in dark.
    static func skinned(light: String, dark: String, whp: String, flow: (light: String, dark: String)? = nil) -> Color {
        if NunaThemePrefs.skin == .flow, let flow { return Color(light: flow.light, dark: flow.dark) }
        return Color(light: light, dark: NunaThemePrefs.skin == .whp ? whp : dark)
    }

    // Every surface and text token is adaptive: the first hex is the light value, the second the dark one. The dark
    // values are the Nuna originals; the light ones keep the same hierarchy on a white-grey canvas.

    // Surfaces. Dark values follow the "Rekomendasi Palet Warna Health App Dark Mode" guide: pure black canvas, #121214 cards.
    public static var canvas: Color { skinned(light: "#E9ECEF", dark: "#000000", whp: "#0F1519", flow: ("#FBF6F2", "#1A1217")) }
    public static var card: Color { skinned(light: "#FFFFFF", dark: "#121214", whp: "#1B242B", flow: ("#FFFFFF", "#241A20")) }
    public static var cardHighlight: Color { skinned(light: "#E9EEF2", dark: "#1B1B1F", whp: "#25313A", flow: ("#F3E9E3", "#2E2228")) }
    /// The well of a text field or a segmented control: a dark inset on the dark themes, a soft light grey on the light one (a dark
    /// inset on a light card would make the text in it hard to read).
    public static var field: Color { skinned(light: "#F1F3F5", dark: "#00000047", whp: "#0000004D", flow: ("#F3E9E3", "#120C10")) }
    public static var glass: Color { skinned(light: "#0A0D100D", dark: "#FFFFFF0D", whp: "#FFFFFF0D", flow: ("#2A1B240D", "#F5EBEF0D")) }
    /// The surface of every card and tile: the ink at a low opacity over the canvas, so it follows the skin and the light or dark theme.
    public static var tile: Color { skinned(light: "#0A0D1014", dark: "#FFFFFF17", whp: "#FFFFFF17", flow: ("#2A1B2410", "#F5EBEF14")) }
    public static var glassStrong: Color { skinned(light: "#0A0D1014", dark: "#FFFFFF17", whp: "#FFFFFF17", flow: ("#2A1B2410", "#F5EBEF14")) }
    // Lines are opaque tones a step off the card colour, so a card edge reads as part of the card instead of a drawn outline.
    // The card itself stays clearly apart from the canvas (#121214 on #000000, white on #E9ECEF).
    public static var hairline: Color { skinned(light: "#D5DAE0", dark: "#2A2A30", whp: "#2F3B44", flow: ("#E6D6CE", "#3D2D36")) }
    public static var hairlineSoft: Color { skinned(light: "#E1E5EA", dark: "#202024", whp: "#27333B", flow: ("#E6D6CE99", "#3D2D3699")) }
    public static var cardBorderHighlight: Color { skinned(light: "#C3CAD2", dark: "#34343B", whp: "#3B4A55", flow: ("#9C8590", "#8A7380")) }
    /// The contrast layer and label colour placed above a system map. These deliberately stay constant so controls
    /// retain legibility regardless of the selected app theme or map tiles beneath them.
    public static let mapOverlay = Color(light: "#0A0D10B3", dark: "#000000B3")
    public static let mapOverlayText = Color(light: "#FFFFFF", dark: "#FFFFFF")

    /// The foreground ink of the theme (white on dark, near-black on light) and the matching shade for wells.
    /// Use `.opacity` on them wherever a translucent overlay of the text colour is wanted.
    public static var ink: Color { NunaThemePrefs.skin == .flow ? Color(light: "#2A1B24", dark: "#F5EBEF") : Color(light: "#0A0D10", dark: "#FFFFFF") }
    public static var shade: Color { NunaThemePrefs.skin == .flow ? Color(light: "#2A1B24", dark: "#120C10") : Color(light: "#0A0D10", dark: "#000000") }

    // Text. The guide's #71717A (grid lines and chart labels) is `textMuted`; running secondary text uses #A1A1AA, which keeps
    // its contrast on the #121214 cards where #71717A alone would not.
    public static var textPrimary: Color { NunaThemePrefs.skin == .flow ? Color(light: "#2A1B24", dark: "#F5EBEF") : Color(light: "#0A0D10", dark: "#FFFFFF") }
    public static var textSecondary: Color { skinned(light: "#4C565E", dark: "#A1A1AA", whp: "#9FABB4", flow: ("#6B5562", "#C4B0BA")) }
    public static var textMuted: Color { skinned(light: "#7A848C", dark: "#71717A", whp: "#6F7C86", flow: ("#9C8590", "#8A7380")) }

    // Meaning colours (fills) and their readable text variants. Each area has its own neon: Sleep / Rest cyan, Health / Charge
    // green, Trend / Effort yellow; alert is the guide's #FF3366. Light values stay readable on white.
    public static let charge        = Color(light: "#0CB300", dark: "#00FF66")   // ok, Charge, Health, active toggles
    public static let effort        = Color(light: "#8FA000", dark: "#DFFF00")   // Effort, Trend
    public static let effortText    = Color(light: "#6B7A00", dark: "#DFFF00")
    public static let rest          = Color(light: "#00A3BA", dark: "#00E5FF")   // Rest, Sleep
    public static let restText      = Color(light: "#007C90", dark: "#5CEFFF")
    public static let restLight     = Color(light: "#4FC3D6", dark: "#9BF4FF")   // REM
    public static let restDeep      = Color(light: "#00697A", dark: "#0093A8")   // deep sleep
    public static var warning: Color { NunaThemePrefs.skin == .flow ? Color(light: "#8A5A00", dark: "#F0C060") : Color(light: "#C98A00", dark: "#FFB020") }
    public static var alert: Color { NunaThemePrefs.skin == .flow ? Color(light: "#B42318", dark: "#FF8A7A") : Color(light: "#E0003C", dark: "#FF3366") }
    public static var alertText: Color { NunaThemePrefs.skin == .flow ? Color(light: "#B42318", dark: "#FF8A7A") : Color(light: "#D0103C", dark: "#FF6B8E") }

    // Charge zones (low, mid, high) and Effort levels (minimal, moderate, all out) from the score guide: red, yellow and green for how ready the
    // body is; dark to light blue for how hard the day was.
    public static let scoreLow      = Color(light: "#D0132D", dark: "#F0243A")
    public static let scoreMid      = Color(light: "#C99A00", dark: "#F5C400")
    public static let scoreHigh     = Color(light: "#2EA800", dark: "#46D200")
    public static let effortMinimal = Color(light: "#1D4C9C", dark: "#2A66C8")
    public static let effortModerate = Color(light: "#1480DA", dark: "#2BA0F5")
    public static let effortAllOut  = Color(light: "#19A8E0", dark: "#66DCFF")
    /// The full circle behind a score ring, so the ring always reads as a closed loop whatever the style or theme.
    public static var ringTrack: Color { skinned(light: "#0A0D1020", dark: "#FFFFFF1F", whp: "#FFFFFF1F", flow: ("#E6D6CE", "#3D2D36")) }
    public static var zoneBase: Color { skinned(light: "#C3C9D6", dark: "#3F3F46", whp: "#3A4650", flow: ("#E6D6CE", "#3D2D36")) }   // zone 1 / awake track

    // Primary action: white (the theme ink) on dark.
    public static var accent: Color { NunaThemePrefs.Accent.fill }
    public static var onAccent: Color { NunaThemePrefs.Accent.label }

    // Tinted chip backgrounds
    public static func tint(_ c: Color) -> Color { c.opacity(0.14) }
}

/// The look the app ships with. Colour, font and text size are fixed defaults (the palette and type scale of the design guides);
/// only light or dark, spacing density and the app icon are the wearer's choice.
public enum NunaThemePrefs {
    /// Primary action: the theme ink (white on dark). Not configurable.
    public enum Accent {
        public static var fill: Color { NunaThemePrefs.skin == .flow ? Color(light: "#8A2F5C", dark: "#EB9BBD") : Color(light: "#0A0D10", dark: "#FFFFFF") }
        public static var label: Color { NunaThemePrefs.skin == .flow ? Color(light: "#FFFFFF", dark: "#2A0F1C") : Color(light: "#FFFFFF", dark: "#000000") }
    }

    public static let densityKey = "nuna.density"
    public static let skinKey = "nuna.skin"

    /// Which palette the app wears. Default is the black-and-neon Nuna look (light, dark or automatic); WHP is a slate,
    /// blue-grey night look in the style of the WHOOP app and is dark only; Flow is a warm berry and cream look (Fraunces and Plus Jakarta Sans,
    /// soft pill shapes) with its own light and dark.
    public enum Skin: String, CaseIterable, Identifiable {
        case standard, whp, flow
        public var id: String { rawValue }
        public var displayName: String { switch self { case .standard: return "Default"; case .whp: return "WHP"; case .flow: return "Flow" } }
    }

    public static var skin: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: skinKey) ?? "") ?? .standard }

    public enum Density: String, CaseIterable, Identifiable {
        case roomy, standard, compact
        public var id: String { rawValue }
        public var factor: CGFloat { switch self { case .roomy: return 1.15; case .standard: return 1; case .compact: return 0.85 } }
    }

    public static var density: Density { Density(rawValue: UserDefaults.standard.string(forKey: densityKey) ?? "") ?? .standard }
    public static var accent: Accent.Type { Accent.self }
}

/// Light, dark or follow the iPhone. Nuna is dark until the wearer chooses otherwise.
public enum NunaTheme {
    public static let storageKey = "nuna.theme"
    public enum Mode: String, CaseIterable, Identifiable {
        case auto, light, dark
        public var id: String { rawValue }
        public var scheme: ColorScheme? { self == .auto ? nil : (self == .light ? .light : .dark) }
    }
    /// WHP is a night-only skin, so it overrides whatever light or automatic choice is stored.
    public static var mode: Mode { NunaThemePrefs.skin == .whp ? .dark : (Mode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .dark) }
    public static var colorScheme: ColorScheme? { mode.scheme }
}

public extension Font {
    /// The Nuna system font (SF Pro) at a design size.
    static func nuna(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        // WHP follows the WHOOP typography cheat sheet by role. Figures (the call sites that ask for `NunaType.design`) are D-DIN-PRO,
        // the DIN role of the sheet; words are Proxima Nova: main headers (24 to 31) bold, card headers (16 to 23) semibold, body (13 to 15)
        // regular, captions and menu labels medium. When a font file is not in the app the system font stands in with the same weights.
        if NunaThemePrefs.skin == .whp { return NunaWHPFont.font(size: size, weight: weight, design: design) }
        if NunaThemePrefs.skin == .flow { return NunaFlowFont.font(size: size, weight: weight, design: design) }
        return .system(size: size, weight: weight, design: design)
    }
}

/// The font design the Nuna screens use for numerals and headings: SF Pro, as the typography guide recommends.
public enum NunaType {
    /// The design every figure and heading asks for. In WHP and Flow it is a marker (`.rounded`) that `Font.nuna` turns into the skin's figure font (D-DIN-PRO, Fraunces).
    public static var design: Font.Design { NunaThemePrefs.skin != .standard ? .rounded : .default }
}

/// The WHP style's fonts: D-DIN-PRO for figures, Montserrat (the cheat sheet's free stand-in for Proxima Nova) for words, with the system
/// font as the fallback when a file is missing.
enum NunaWHPFont {
    private static func available(_ name: String) -> Bool {
        CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name
    }
    private static let din: [Font.Weight: String] = [.regular: "D-DIN-PRO-Regular", .medium: "D-DIN-PRO-Medium", .semibold: "D-DIN-PRO-SemiBold", .bold: "D-DIN-PRO-Bold"]
    private static let dinOK = din.values.allSatisfy(available)
    /// Montserrat ships as one variable file; its family name is "Montserrat" and the weight axis follows `.weight`.
    private static let montserratOK = CTFontCopyFamilyName(CTFontCreateWithName("Montserrat" as CFString, 12, nil)) as String == "Montserrat"

    static func font(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        // Headings ask for the figure design too but in the heaviest weight; below 32 pt those are words, set in Montserrat.
        let isHeading = (weight == .heavy || weight == .black) && size < 32
        if design == .rounded && !isHeading {
            // Figures: bold when large, semibold in lists, regular for small units.
            let w: Font.Weight = size >= 24 ? .bold : (size >= 15 ? .semibold : (weight == .regular ? .regular : .medium))
            return dinOK ? .custom(din[w] ?? "D-DIN-PRO-Bold", size: size) : .system(size: size, weight: w, design: .default).width(.condensed)
        }
        let w: Font.Weight
        var pt = size
        switch size {
        case 24...: w = .bold
        case 16..<24: w = weight == .regular ? .regular : .semibold; pt = (size * 0.92).rounded()
        case 13..<16: w = (weight == .heavy || weight == .black || weight == .bold) ? .semibold : .regular
        default: w = weight == .regular ? .regular : .medium
        }
        // Montserrat runs wider than Proxima Nova, so its words are set about 8% smaller to keep the same line lengths.
        return montserratOK ? montserrat(size: (pt * 0.92 * 2).rounded() / 2, weight: w) : .system(size: pt, weight: w, design: .default)
    }

    /// One size and weight of the variable Montserrat file, set on its weight axis (`wght`, 100 to 900).
    private static func montserrat(size: CGFloat, weight: Font.Weight) -> Font {
        let value: Double = weight == .bold ? 700 : (weight == .semibold ? 600 : (weight == .medium ? 500 : 400))
        let wght = 2003265652   // the four-character axis tag "wght"
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: "Montserrat",
            kCTFontVariationAttribute: [wght: value],
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

/// The Flow style's fonts: Fraunces (SIL OFL) for the large figures and titles, Plus Jakarta Sans (SIL OFL) for everything else. Both ship as
/// one variable file; the system font stands in with the same weights when a file is missing.
enum NunaFlowFont {
    private static func family(_ name: String) -> Bool {
        CTFontCopyFamilyName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name
    }
    private static let frauncesOK = family("Fraunces")
    private static let jakartaOK = family("Plus Jakarta Sans")

    // Variation axis tags (four-character codes as integers): weight, optical size, softness, wonk.
    private static let wght = 2003265652, opsz = 1869640570, soft = 1397704276, wonk = 1464815179

    static func font(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        let bold = weight == .bold || weight == .heavy || weight == .black
        // Fraunces is for the numeral (48), display (32) and title-lg (24) roles only: a figure or a heading from 24 pt up. Below that, figures are words.
        if size >= 24 && (design == .rounded || bold) {
            guard frauncesOK else { return .system(size: size, weight: .semibold, design: .serif) }
            let d = CTFontDescriptorCreateWithAttributes([
                kCTFontFamilyNameAttribute: "Fraunces",
                kCTFontVariationAttribute: [wght: 600, opsz: min(max(size, 9), 144), soft: 50, wonk: 0],
            ] as CFDictionary)
            return Font(CTFontCreateWithFontDescriptor(d, size, nil))
        }
        let value: Double
        switch weight {
        case .bold, .heavy, .black: value = 700
        case .semibold: value = 600
        case .medium: value = 500
        default: value = 400
        }
        guard jakartaOK else { return .system(size: size, weight: weight, design: .default) }
        let d = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Plus Jakarta Sans",
            kCTFontVariationAttribute: [wght: value],
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(d, size, nil))
    }
}

public enum NunaRadius {
    // Firm corners: cards and controls are rectangles with a modest radius, not pills. Flow is the opposite: soft, organic shapes, with pills for
    // buttons, chips and controls (its radius tokens: md 16, sm 12, lg 24, full).
    private static var flow: Bool { NunaThemePrefs.skin == .flow }
    private static let full: CGFloat = 9999
    public static var card: CGFloat { flow ? 16 : 14 }
    public static var cardSmall: CGFloat { 12 }
    public static var chip: CGFloat { flow ? full : 8 }        // height 30
    public static var pill: CGFloat { flow ? full : 10 }       // chips, buttons and bars that used to be capsules
    public static var button: CGFloat { flow ? full : 12 }     // height 48
    public static var iconButton: CGFloat { flow ? full : 12 } // 44 x 44
    public static var tabBar: CGFloat { flow ? 28 : 18 }       // height 72
    public static var sheet: CGFloat { flow ? 24 : 20 }
    public static var iconTile: CGFloat { flow ? full : 10 }   // 40 x 40
}

public enum NunaSpacing {
    // Section and card spacing follow the density choice (Roomy / Standard / Compact).
    public static let screenH: CGFloat = 16
    public static var section: CGFloat { (16 * NunaThemePrefs.density.factor).rounded() }
    public static var cardInner: CGFloat { (16 * NunaThemePrefs.density.factor).rounded() }
    public static var cardInnerSmall: CGFloat { (12 * NunaThemePrefs.density.factor).rounded() }
    public static let tabBarBottom: CGFloat = 24
}

public enum NunaTypeSize {
    // Text sizes (pt), from the "Panduan Tipografi dan Jarak UI" guide:
    //   main stat / score 44-48 bold  ·  page header 24-28 bold  ·  card title 16-18 semibold
    //   body and detail numbers 14    ·  chart labels and helper text 11-12
    // Large numbers use -1 to -2% tracking, small uppercase labels +1 to +2% (see `nunaTrackingNumber`, `nunaTrackingLabel`).
    public static let h1: CGFloat = 28
    public static let h2: CGFloat = 20
    public static let h3: CGFloat = 17
    public static let sub: CGFloat = 14
    public static let caption: CGFloat = 11.5
    // Numerals
    public static let numberXL: CGFloat = 56
    public static let numberL: CGFloat = 44
    public static let numberM: CGFloat = 30
    public static let numberS: CGFloat = 21
}

/// Letter spacing in points for a number of `size` (-1.5%) and for small labels.
public func nunaTrackingNumber(_ size: CGFloat) -> CGFloat { -size * 0.015 }
public let nunaTrackingLabel: CGFloat = 0.4

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
    /// Flow draws a card as a raised surface (white on cream, a lifted plum-tinted dark); the others keep the soft tile.
    private var cardFill: Color {
        if NunaThemePrefs.skin == .flow { return highlight ? NunaPalette.cardHighlight : NunaPalette.card }
        return highlight ? NunaPalette.cardHighlight : NunaPalette.tile
    }

    public var body: some View {
        content
            .padding(padding ?? EdgeInsets(top: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           leading: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           bottom: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner,
                                           trailing: small ? NunaSpacing.cardInnerSmall : NunaSpacing.cardInner))
            .frame(maxWidth: .infinity, alignment: .leading)
            // One flat tile: a soft lift off the canvas, no outline. Only the highlighted card (Anya, the selected one) keeps an edge.
            .background(FlowCardSurface(fill: cardFill, radius: small ? NunaRadius.cardSmall : NunaRadius.card, lifted: NunaThemePrefs.skin == .flow))
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: small ? NunaRadius.cardSmall : NunaRadius.card, style: .continuous)
                        .strokeBorder(NunaPalette.cardBorderHighlight, lineWidth: 1)
                }
            }
    }
}

/// A card's surface. In Flow it carries the elevation (a small plum-tinted shadow in light, a 1 px border in dark where a shadow would not show).
/// The shadow belongs to this plain rounded shape and not to the card's content: a shadow on the content makes the system draw all of it to an
/// offscreen layer again on every frame of a scroll, which is slow on a page of many cards.
private struct FlowCardSurface: View {
    let fill: Color
    let radius: CGFloat
    let lifted: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if lifted {
            shape.fill(fill)
                .shadow(color: scheme == .dark ? .clear : Color(hex: "#2A1B24").opacity(0.07), radius: 3, x: 0, y: 1)
                .overlay { if scheme == .dark { shape.strokeBorder(NunaPalette.hairline, lineWidth: 1) } }
        } else {
            shape.fill(fill)
        }
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
        // Important information is a chip: a tinted background and a thin outline in its own colour, so a status reads at a glance.
        let tint = color ?? NunaPalette.textSecondary
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .bold)) }
            text.font(.system(size: 12.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).frame(minHeight: 26)
        .background(NunaPalette.tint(tint), in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }
}

extension View {
    /// Wraps a status word in the chip look (tinted background, thin outline in its own colour) for a status that a card draws itself.
    public func nunaStatusChip(_ tint: Color, height: CGFloat = 26) -> some View {
        self.foregroundStyle(tint)
            .padding(.horizontal, 10).frame(minHeight: height)
            .background(NunaPalette.tint(tint), in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Score ring used for Charge / Effort / Rest and the Trends gauges.
public struct NunaRingGauge<Center: View>: View {
    private let fraction: Double
    private let color: Color
    private let gradient: [Color]?
    private let target: ClosedRange<Double>?
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let center: Center
    /// `gradient` paints the arc from its start to its end through these colours (Effort: dark blue to light blue); nil keeps `color`.
    /// `target` (0...1 of the ring) draws the day's aim as a grey stretch of the track with a white mark where it begins.
    public init(fraction: Double, color: Color, gradient: [Color]? = nil, target: ClosedRange<Double>? = nil, size: CGFloat = 98, lineWidth: CGFloat = 9,
                @ViewBuilder center: () -> Center) {
        self.fraction = min(max(fraction, 0), 1); self.color = color; self.gradient = gradient; self.target = target
        self.size = size; self.lineWidth = lineWidth; self.center = center()
    }
    public var body: some View {
        ZStack {
            Circle().stroke(NunaPalette.ringTrack, lineWidth: lineWidth)
            if let target {
                Circle().trim(from: min(max(target.lowerBound, 0), 1), to: min(max(target.upperBound, 0), 1))
                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Circle().trim(from: 0, to: fraction)
                .stroke(gradient.map { AnyShapeStyle(AngularGradient(colors: $0, center: .center, startAngle: .degrees(0), endAngle: .degrees(max(360 * fraction, 1)))) }
                        ?? AnyShapeStyle(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let target {
                // The least to aim for: a short white mark across the ring.
                let at = min(max(target.lowerBound, 0), 1)
                Circle().trim(from: max(at - 0.004, 0), to: min(at + 0.004, 1))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
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
                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.zoneBase).frame(maxWidth: .infinity)
                        .frame(width: geo.size.width * 0.18)
                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.charge).frame(width: geo.size.width * 0.18)
                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.warning).frame(width: geo.size.width * 0.18)
                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.alert).frame(maxWidth: .infinity)
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
