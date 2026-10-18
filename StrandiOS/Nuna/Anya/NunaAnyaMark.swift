#if os(iOS)
import SwiftUI
import StrandDesign

/// A light mark-up for the lines Anya writes: a part that is good news or bad news is wrapped in a marker, so the Anya sheet can draw
/// it in a colour while everything else (the Today card, the settings, the provider) shows the plain words. Used sparingly: a figure or
/// a short phrase, never a whole paragraph.
enum NunaMark {
    static func pos(_ s: String) -> String { "⟦+\(s)⟧" }
    static func neg(_ s: String) -> String { "⟦-\(s)⟧" }

    /// The words without the markers.
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "⟦+", with: "").replacingOccurrences(of: "⟦-", with: "").replacingOccurrences(of: "⟧", with: "")
    }

    /// The headline and what follows it as one run of sentences: the separators of a card line become commas, each line a sentence.
    static func compose(headline: String, detail: String?) -> String {
        func sentence(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " · ", with: ", ")
            guard let last = plain(t).last else { return "" }
            if !".!?:".contains(last) { t += "." }
            return t
        }
        let lines = [headline] + (detail?.split(separator: "\n").map(String.init) ?? [])
        return lines.map(sentence).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The text with the marked parts in a colour and a little heavier.
    static func attributed(_ s: String, size: CGFloat = 17) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(s)
        while let open = rest.range(of: "⟦") {
            out += AttributedString(String(rest[..<open.lowerBound]))
            let after = rest[open.upperBound...]
            guard let sign = after.first, let close = after.range(of: "⟧") else { out += AttributedString(String(rest[open.lowerBound...])); return out }
            var piece = AttributedString(String(after[after.index(after.startIndex, offsetBy: 1)..<close.lowerBound]))
            piece.foregroundColor = sign == "+" ? NunaPalette.charge : NunaPalette.warning
            piece.font = .nuna(size: size, weight: .heavy)
            out += piece
            rest = after[close.upperBound...]
        }
        out += AttributedString(String(rest))
        return out
    }
}
#endif
