#if os(iOS)
import SwiftUI
import StrandDesign

/// A tile of an Explore grid: the photo fills the top of the card and fades into it, with a small square-cornered tag in its corner; the name in
/// capitals and a line under it sit on the fade, so photo and text read as one piece. Every card is the same height, so a row of them lines up.
/// Used by the Strength Trainer and by Breathe.
struct NunaPhotoCard: View {
    /// The name of an image in the asset catalog.
    let image: String
    let badge: Text
    let title: String
    let caption: Text
    /// How many lines the name may take (two or three); the text block is that tall on every card.
    var lines = 3
    private let photoHeight: CGFloat = 176
    private let textTop: CGFloat = 112

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(height: photoHeight)
                .overlay { Image(image).resizable().scaledToFill() }
                .clipped()
                // Faded by its own opacity, not painted over with the card colour, so no seam shows whatever the card sits on.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.30), .init(color: .black.opacity(0.35), location: 0.52), .init(color: .clear, location: 0.68)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: textTop)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: title).font(.nuna(size: 15.5, weight: .bold)).tracking(1.0).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading).lineLimit(lines).minimumScaleFactor(0.85)
                    caption.font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .frame(maxWidth: .infinity, minHeight: lines == 3 ? 88 : 70, maxHeight: lines == 3 ? 88 : 70, alignment: .topLeading)
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .overlay(alignment: .topTrailing) { tag.padding(10) }
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var tag: some View {
        badge.font(.nuna(size: 12.5, weight: .semibold)).tracking(0.9).textCase(.uppercase)
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 10).frame(height: 27)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
#endif
