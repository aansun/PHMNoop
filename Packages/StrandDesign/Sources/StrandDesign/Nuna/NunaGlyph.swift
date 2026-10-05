import SwiftUI

/// Anya's mark: the letters "AN" in a heavy rounded face. It has no colour of its own, so it follows the foreground of the place it
/// sits in (white on the dark themes, near-black on light, the accent label on an accent fill) and needs no per-theme asset.
public struct NunaAnyaLetters: View {
    private let size: CGFloat
    /// `size` is the side of the box the mark sits in; the letters fill about 60% of it.
    public init(size: CGFloat) { self.size = size }
    public var body: some View {
        Text(verbatim: "AN")
            .font(.system(size: size * 0.6, weight: .heavy, design: .rounded))
            .tracking(-size * 0.02)
            .lineLimit(1).fixedSize()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An icon by name: an SF Symbol, or Anya's letters for `NunaGlyph.anya`. The icon tiles, icon buttons and tab bar use it so every
/// place that stands for Anya shows the same mark at the size of the icon beside it.
public struct NunaGlyph: View {
    public static let anya = "anya.mark"
    private let name: String
    private let pointSize: CGFloat
    private let weight: Font.Weight

    public init(_ name: String, pointSize: CGFloat, weight: Font.Weight = .bold) {
        self.name = name; self.pointSize = pointSize; self.weight = weight
    }

    public var body: some View {
        if name == Self.anya {
            NunaAnyaLetters(size: pointSize * 1.3)
        } else {
            Image(systemName: name).font(.nuna(size: pointSize, weight: weight))
        }
    }
}
