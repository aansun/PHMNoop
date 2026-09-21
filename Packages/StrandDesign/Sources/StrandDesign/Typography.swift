import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Typography preset (§ PHM: WHOOP typography system)
//
// A selectable typography personality applied app-wide through `StrandFont`. Because every view reads
// its font from `StrandFont.*`, switching the preset re-skins the whole app with no per-view change.
//
// - `.standard` — NOOP's SF Rounded house style (the original).
// - `.whoop`    — WHOOP-inspired (see WHOOP_Typography_Development_Guide.md): geometric SF Pro text,
//   heavier body weights, tracked ALL-CAPS labels, and distinct tabular numerals. Uses SYSTEM fonts
//   (SF Pro / SF Pro's tabular digits), NOT WHOOP's commercial Proxima Nova / DINPro — the guide flags
//   those as licensed and the repo bars shipping WHOOP font binaries. The open-source Inter / Inter
//   Tight fallbacks the guide recommends can be bundled later; this preset captures the CHARACTER with
//   zero bundled binaries and no licensing risk.
public enum TypographyPreset: String, CaseIterable, Sendable, Identifiable {
    case standard
    case whoop

    public var id: String { rawValue }
    public static let storageKey = "typography.preset"

    public var displayName: String {
        switch self {
        case .standard: return "Default"
        case .whoop:    return "WHOOP"
        }
    }

    /// The active preset, read from UserDefaults (defaults to `.standard`). nonisolated so `StrandFont`
    /// can read it from anywhere; UserDefaults keeps the value in memory so this is cheap per access.
    public static var active: TypographyPreset {
        TypographyPreset(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .standard
    }
}

// MARK: - Strand Typography (§9.2)
//
// SF Rounded (`.standard`) follows the reference's friendly Apple-native geometry; the `.whoop` preset
// swaps to SF Pro with heavier text weights for a sharper, metrics-forward feel. Tabular digits keep
// live metrics stable in both, while named text styles retain Dynamic Type scaling. SF Mono stays for logs.

public enum StrandFont {

    // MARK: Preset-driven family

    /// Text/number design for the active preset: rounded for `.standard`, default (SF Pro) for `.whoop`.
    private static var design: Font.Design {
        TypographyPreset.active == .whoop ? .default : .rounded
    }

    /// Body/caption weight — the `.whoop` preset leans on Medium (its "heavy use of Semibold/Bold"
    /// character) where `.standard` uses Regular.
    private static var textWeight: Font.Weight {
        TypographyPreset.active == .whoop ? .medium : .regular
    }

    private static func sysFont(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    // MARK: Scale (§9.2)

    /// Display 64–80 / Bold — the gauge score number. Tight tracking (≈ -0.04em), tabular digits so a
    /// changing value never reflows.
    public static func display(_ size: CGFloat = 72) -> Font {
        sysFont(size, weight: .bold).monospacedDigit()
    }

    /// The tight tracking for big display numbers (≈ -0.04em). Apply alongside `display(_:)` at the use
    /// site, e.g. `.tracking(StrandFont.displayTracking(72))`.
    public static func displayTracking(_ size: CGFloat = 72) -> CGFloat {
        -size * 0.04
    }

    /// A numeric style at an arbitrary size/weight — the house numeral. Tabular so live values align.
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        sysFont(size, weight: weight).monospacedDigit()
    }

    /// Title1 28 / Bold. Scales with Dynamic Type.
    public static var title1: Font { .system(.title, design: design, weight: .bold) }

    /// Title2 22 / Semibold. Scales with Dynamic Type.
    public static var title2: Font { .system(.title2, design: design, weight: .semibold) }

    /// Headline 17 / Semibold. Scales with Dynamic Type.
    public static var headline: Font { .system(.headline, design: design, weight: .semibold) }

    /// Body 15. Regular (`.standard`) / Medium (`.whoop`). Scales with Dynamic Type.
    public static var body: Font { .system(.body, design: design, weight: textWeight) }

    /// Subhead 13. Scales with Dynamic Type.
    public static var subhead: Font { .system(.subheadline, design: design, weight: textWeight) }

    /// Caption 12. Scales with Dynamic Type.
    public static var caption: Font { .system(.caption, design: design, weight: textWeight) }

    /// Footnote 11. Scales with Dynamic Type.
    public static var footnote: Font { .system(.footnote, design: design, weight: textWeight) }

    /// Overline 11 / Semibold, tracked ALL-CAPS label (apply `.tracking(overlineTracking)`;
    /// `overlineText(_:)` does it for you). Scales with Dynamic Type.
    public static var overline: Font { .system(.caption2, design: design, weight: .semibold) }

    /// `overline` at a custom point size — same face, weight and Dynamic-Type scaling (relativeTo
    /// `.caption2`), just smaller. Passing 11 returns exactly `.overline`.
    public static func overlineScaled(_ size: CGFloat) -> Font {
        let uiDesign: SystemFontDesign = (TypographyPreset.active == .whoop) ? .default : .rounded
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let descriptor = base.fontDescriptor.withDesign(uiDesign) ?? base.fontDescriptor
        let styled = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: .caption2).scaledFont(for: styled))
        #elseif canImport(AppKit)
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(uiDesign),
              let styled = NSFont(descriptor: descriptor, size: size) else {
            return Font(base)
        }
        return Font(styled)
        #else
        return sysFont(size, weight: .semibold)
        #endif
    }

    /// Mono 13 (SF Mono) — raw / log views. Tabular by nature. Not preset-driven.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)

    // MARK: Numeric variants (tabular digits)

    /// A numeric style at an arbitrary size/weight, for live values — tabular digits. The tile/value numeral.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        sysFont(size, weight: weight).monospacedDigit()
    }

    /// Body number — for inline live values that should align. Scales with Dynamic Type alongside its
    /// sibling `body`/`caption` labels so a value and its label stay matched.
    public static var bodyNumber: Font { .system(.body, design: design, weight: .medium).monospacedDigit() }

    /// Caption number — for small live values (sparklines, chips). Scales with Dynamic Type.
    public static var captionNumber: Font { .system(.caption, design: design, weight: .medium).monospacedDigit() }

    /// Mono at an arbitrary size.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The recommended tracking for overline text (wide ALL-CAPS labels). The `.whoop` preset widens it
    /// toward the guide's +0.06em label tracking; `.standard` keeps the original.
    public static var overlineTracking: CGFloat {
        TypographyPreset.active == .whoop ? 0.6 : 0.45
    }
}

#if canImport(UIKit)
private typealias SystemFontDesign = UIFontDescriptor.SystemDesign
#elseif canImport(AppKit)
private typealias SystemFontDesign = NSFontDescriptor.SystemDesign
#else
private enum SystemFontDesign { case rounded, `default` }
#endif

// MARK: - Text helpers

public extension Text {
    /// Style as an overline label: ALL-CAPS, bold, tracked, secondary text.
    func strandOverline() -> some View {
        self.font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
    }
}

public extension View {
    /// Convenience: an overline-styled label string.
    static func strandOverline(_ string: String) -> some View {
        Text(string).strandOverline()
    }
}

#if DEBUG
#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("88").font(StrandFont.display(72)).tracking(StrandFont.displayTracking(72)).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 1 / Bold 28").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 2 / Semibold 22").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text("Headline / Semibold 17").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            Text("Body / 15 — the thread of you, read in full.")
                .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Text("Subhead 13").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text("Caption 12").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Footnote 11").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text("Overline").strandOverline()
            Text("0xAA 41 00 1c crc32=f3a1  mono 13").font(StrandFont.mono).foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("62").font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                Text("ms").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 620)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
