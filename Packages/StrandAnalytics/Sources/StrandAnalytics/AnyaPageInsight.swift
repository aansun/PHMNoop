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

// MARK: - Cleaning a reply

public enum AnyaReplyCleaner {
    /// Sentences a small model adds out of habit and that say nothing: a doubt tacked on to a cause it has just stated ("I am not sure what caused it, but ..."), or a
    /// line about "this surface". They are taken out; if that would leave nothing, the reply is returned as it was.
    public static func clean(_ reply: String) -> String {
        let doubt = try! NSRegularExpression(pattern: #"^\s*(i am not sure|i'm not sure|i am unsure|i can't tell|i cannot tell|i can’t tell)|\bthis surface\b"#, options: .caseInsensitive)
        var out: [String] = []
        for line in reply.components(separatedBy: "\n") {
            // Split a paragraph into sentences without losing the markdown around it.
            var kept: [String] = []
            var sentence = ""
            func flush() {
                let t = sentence.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, doubt.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) == nil { kept.append(t) }
                sentence = ""
            }
            // A full stop ends a sentence only when a space or the end of the line follows it, so "11.6" and "2.250" stay whole.
            let chars = Array(line)
            for (i, ch) in chars.enumerated() {
                sentence.append(ch)
                if ch == "." || ch == "?" || ch == "!", i + 1 == chars.count || chars[i + 1] == " " { flush() }
            }
            flush()
            out.append(kept.joined(separator: " "))
        }
        let joined = out.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = dropNarration(joined)
        return cleaned.isEmpty ? reply : cleaned
    }

    /// An opener that narrates the looking ("I see that", "Looking at your data,", "Saya lihat") instead of saying the thing. It is taken off the start of each
    /// line and sentence and the next word is capitalised, so "I can see that HRV fell" reads "HRV fell".
    private static let narration = try! NSRegularExpression(
        pattern: #"(^|(?<=[.!?]) )(?:i (?:can )?see(?: that)?|i(?:'ve| have)? noticed(?: that)?|i looked at your (?:data|numbers)(?: and)?|from what i can see|looking at your (?:data|numbers)|based on your (?:data|numbers)|it looks like|saya (?:bisa |dapat )?(?:lihat|melihat|perhatikan|memperhatikan)(?: bahwa)?|aku (?:lihat|melihat|perhatikan)(?: bahwa)?|terlihat bahwa|berdasarkan data ?(?:mu|kamu)?)[,:]?\s+"#,
        options: [.caseInsensitive, .anchorsMatchLines])

    static func dropNarration(_ text: String) -> String {
        var s = text
        // Repeat: a reply can open with one and carry the next after a full stop.
        for _ in 0..<4 {
            let ns = s as NSString
            guard let m = narration.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { break }
            let after = m.range.location + m.range.length
            guard after < ns.length else { break }
            let lead = ns.substring(with: NSRange(location: m.range.location, length: m.range.length))
            let keepPrefix = lead.hasPrefix(" ") ? " " : ""
            let first = ns.substring(with: NSRange(location: after, length: 1)).uppercased()
            s = ns.substring(to: m.range.location) + keepPrefix + first + ns.substring(from: after + 1)
        }
        return s
    }
}
