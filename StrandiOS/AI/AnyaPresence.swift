#if os(iOS)
import SwiftUI
import StrandDesign

struct AnyaDetailVisibilityKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                Text("Ask Anya")
                    .font(StrandFont.caption.weight(.bold))
                Text("·")
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(context)
                    .font(StrandFont.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(StrandPalette.surfaceRaised.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Anya about \(context)")
        .accessibilityHint("Open the daily coaching assistant")
    }
}
#endif
