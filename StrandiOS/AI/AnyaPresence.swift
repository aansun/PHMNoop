#if os(iOS)
import SwiftUI
import StrandDesign

struct AnyaDetailVisibilityKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Anya's shared visual mark. Keep the asset in one component so every Coach entry point has
/// the same warm, friendly face instead of a collection of unrelated symbols.
struct AnyaMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("AnyaIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AnyaIconTile: View {
    var size: CGFloat = 40

    var body: some View {
        AnyaMark(size: size * 0.76)
            .frame(width: size, height: size)
            // Rest's cyan well ties North Star's cool blue orb to the app's meaning palette;
            // the amber point inside the mark echoes the warning token without becoming a status color.
            .background(NunaPalette.rest.opacity(0.14), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous).strokeBorder(NunaPalette.rest.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The persistent, low-friction entry point for Anya on iOS.
///
/// This is intentionally an access surface, not a second chat implementation. It opens the
/// existing launcher so consent, provider setup, streaming and history remain owned by the
/// canonical Coach flow.
struct AnyaPresenceButton: View {
    let context: String
    let action: () -> Void
    @State private var isExpanded = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AnyaMark(size: 22)
                if isExpanded {
                    Text("Ask Anya")
                        .font(StrandFont.caption.weight(.bold))
                    Text("·")
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(context)
                        .font(StrandFont.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, isExpanded ? 14 : 12)
            .frame(width: isExpanded ? nil : 42, height: 42)
            .background(StrandPalette.surfaceRaised.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        })
        .accessibilityLabel("Ask Anya about \(context)")
        .accessibilityHint(isExpanded ? "Double tap to collapse. Tap to open Anya." : "Double tap to expand. Tap to open Anya.")
    }
}
#endif
