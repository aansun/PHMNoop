#if os(iOS)
import SwiftUI
import StrandDesign

/// An API key entry with an eye to reveal what was typed or pasted, and a line under it that shows only the first five and the
/// last four characters and the length, so a key that was cut short or pasted wrong is plain to see without showing all of it.
/// With the field empty it describes the key already kept in the Keychain.
struct NunaKeyField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var savedKey: String?
    var showsPaste = false
    @State private var revealed = false

    /// "sk-pr…a1b2 · 164 characters". Short keys are not spelled out.
    static func hint(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return "" }
        let n = k.count
        if n <= 12 { return String(localized: "\(n) characters") }
        return "\(k.prefix(5))…\(k.suffix(4)) · " + String(localized: "\(n) characters")
    }

    private var shown: String {
        if !text.isEmpty { return String(localized: "Typed") + ": " + Self.hint(text) }
        if let s = savedKey, !s.isEmpty { return String(localized: "Saved") + ": " + Self.hint(s) }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if revealed {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(NunaPalette.textMuted))
                    } else {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(NunaPalette.textMuted))
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                if showsPaste {
                    Button { if let s = UIPasteboard.general.string { text = s.trimmingCharacters(in: .whitespacesAndNewlines) } } label: {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(NunaPalette.textPrimary)
                    }.buttonStyle(.plain).accessibilityLabel(Text("Paste from clipboard"))
                }
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye").foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain).accessibilityLabel(Text(revealed ? "Hide the key" : "Show the key"))
            }
            if !shown.isEmpty {
                Text(verbatim: shown).font(.nuna(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }
}
#endif
