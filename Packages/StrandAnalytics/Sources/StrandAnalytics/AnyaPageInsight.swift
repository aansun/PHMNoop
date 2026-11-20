import Foundation

// AnyaPageInsight.swift — the shape of what Anya says about one page of data.
//
// PURE (Foundation only) and unit-tested. The provider is asked for four labelled paragraphs (HEADLINE, SEE, MEAN, DO); this reads them back
// so the pill can show the headline and the sheet can show every part under its own title. A small model does not always keep the shape, so
// `parse` returns nil for a reply that has no headline or nothing to explain, and the caller then shows the reply as plain prose, as before.

public struct AnyaPageInsight: Equatable, Sendable {
    /// One plain sentence: what the reading is and whether it is good, fair or needs attention.
    public var headline: String
    /// The figure against the person's own baseline.
    public var see: String
    /// What it most likely means.
    public var mean: String
    /// One next step: to improve it when it is poor, to keep it when it is good.
    public var advice: String

    public init(headline: String, see: String = "", mean: String = "", advice: String = "") {
        self.headline = headline; self.see = see; self.mean = mean; self.advice = advice
    }

    private static let labels = ["HEADLINE", "SEE", "MEAN", "DO"]

    /// Reads a reply that follows the shape. Tolerates markdown around a label (`**SEE:**`, `## SEE`), a label in lower case, and text before
    /// the first label (dropped). Nil when there is no headline, or when only the headline is there.
    public static func parse(_ reply: String) -> AnyaPageInsight? {
        var sections: [String: [String]] = [:]
        var current: String?
        for rawLine in reply.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let (label, rest) = leadingLabel(line) {
                current = label
                if !rest.isEmpty { sections[label, default: []].append(rest) }
            } else if let c = current, !line.isEmpty {
                sections[c, default: []].append(line)
            }
        }
        func text(_ k: String) -> String {
            clean((sections[k] ?? []).joined(separator: " "))
        }
        let headline = text("HEADLINE")
        guard !headline.isEmpty else { return nil }
        let insight = AnyaPageInsight(headline: headline, see: text("SEE"), mean: text("MEAN"), advice: text("DO"))
        return insight.mean.isEmpty && insight.advice.isEmpty && insight.see.isEmpty ? nil : insight
    }

    /// "SEE: text" → ("SEE", "text"), with any markdown around the label removed.
    private static func leadingLabel(_ line: String) -> (String, String)? {
        let stripped = line.drop { "#*_ >-".contains($0) }
        for label in labels {
            guard stripped.uppercased().hasPrefix(label) else { continue }
            var rest = stripped.dropFirst(label.count)
            // The label must be followed by a colon (possibly inside the bold markers), or the word is just the start of a sentence.
            let trimmed = rest.drop { "*_ ".contains($0) }
            guard trimmed.first == ":" else { continue }
            rest = trimmed.dropFirst()
            return (label, clean(String(rest)))
        }
        return nil
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*_")))
    }

    /// The sheet's text: the headline first, then each part that is there under its own title (titles passed in so the app can localise them).
    public func markdown(seeTitle: String, meanTitle: String, adviceTitle: String) -> String {
        var parts = [headline]
        if !see.isEmpty { parts.append("**\(seeTitle)**\n\(see)") }
        if !mean.isEmpty { parts.append("**\(meanTitle)**\n\(mean)") }
        if !advice.isEmpty { parts.append("**\(adviceTitle)**\n\(advice)") }
        return parts.joined(separator: "\n\n")
    }
}
