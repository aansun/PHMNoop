import Foundation
import SwiftUI
import StrandDesign

/// The compact Coach launcher opened from the optional Today card (#1862).
///
/// Coach is otherwise reachable only through More/Insights, which makes it easy to miss and means
/// leaving Today to try it. This is the shortcut — and deliberately ONLY a shortcut.
///
/// The notice owns a deliberately small, local conversation. It can answer a follow-up in context without
/// writing that exchange into the persistent full Coach transcript.
///
/// NO PROVIDER REQUEST IS MADE BY OPENING THIS. Everything shown is local: `isConfigured` reads the
/// stored key. The first network call still happens only after the existing provider and data-consent
/// gates pass.
struct CoachLauncherSheet: View {
    @EnvironmentObject var coach: AICoachEngine
    @EnvironmentObject var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    /// The module that opened Anya. This is presentation context only; the analysis engine still owns
    /// the metrics and evidence used by the brief.
    let context: String
    @State private var contextualBrief: String?
    @State private var readingContext = false
    @State private var localTurns: [ChatMessage] = []
    @State private var draft = ""
    @State private var sending = false

    private var configuredDescription: String {
        #if os(iOS)
        return "I’ll connect the signals, explain what they mean for this moment, and keep the next step simple."
        #else
        return "Ask about your charge, effort, rest and workouts, grounded in your own numbers."
        #endif
    }

    private var unconfiguredDescription: String {
        #if os(iOS)
        return "Anya uses your own provider connection. Nothing is sent until you enable it and ask a question; your key stays securely in the Keychain."
        #else
        return "Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the Keychain and never leaves \(Platform.deviceNounPhrase) except as the request you make."
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if coach.isConfigured {
                        configured
                    } else {
                        unconfigured
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            #if os(iOS)
            .navigationTitle(Text("Anya"))
            #else
            .navigationTitle(Text("Coach"))
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        #if os(iOS)
        .task(id: context) {
            guard coach.isConfigured else { return }
            readingContext = true
            contextualBrief = await coach.generateContextualBrief(pageContext: context)
            readingContext = false
        }
        #endif
    }

    // MARK: Configured — suggestions + a compact composer

    @ViewBuilder
    private var configured: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StrandPalette.accent)
                Text("Anya noticed")
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 0)
                Text(context.uppercased())
                    .font(StrandFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(StrandPalette.textTertiary)
            }

            if let brief = contextualBrief {
                formattedBrief(cleanedBrief(brief))
                    .fixedSize(horizontal: false, vertical: true)
            } else if readingContext {
                ProgressView()
                    .controlSize(.small)
                    .tint(StrandPalette.accent)
            } else {
                Text(configuredDescription)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !localTurns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(localTurns) { turn in
                        if turn.role == .user {
                            Text(turn.text)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            formattedBrief(cleanedBrief(turn.text))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(FrostedCardSurface(cornerRadius: NoopMetrics.cardRadius))

        HStack(alignment: .bottom, spacing: 8) {
            TextField("Tanya Anya…", text: $draft, axis: .vertical)
                .font(StrandFont.footnote)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))

            Button { sendMessage() } label: {
                Image(systemName: sending ? "hourglass" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .frame(width: 36, height: 36)
                    .background(StrandPalette.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Not configured — explain the opt-in and route to the existing setup

    @ViewBuilder
    private var unconfigured: some View {
        // The SAME explanation the Coach screen shows, so the bring-your-own-key model is described
        // once. The button routes to that screen, which stays the only place a key is entered.
        Text(unconfiguredDescription)
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textTertiary)

        Button {
            dismiss()
            router.openCoach()
        } label: {
            Text("Connect a provider")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(FrostedCardSurface(cornerRadius: NoopMetrics.cardRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Local conversation

    private func sendMessage() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !sending else { return }
        draft = ""
        let history = localTurns
        localTurns.append(ChatMessage(role: .user, text: question))
        sending = true
        Task {
            let reply = await coach.answerContextualMessage(
                pageContext: context,
                notice: contextualBrief.map { cleanedBrief($0) },
                history: history,
                question: question
            )
            if let reply {
                localTurns.append(ChatMessage(role: .assistant, text: reply))
            } else if let last = localTurns.last, last.role == .user, last.text == question {
                localTurns.removeLast()
                draft = question
            }
            sending = false
        }
    }

    private func cleanedBrief(_ rawText: String) -> String {
        let text = rawText
            .replacingOccurrences(of: "Today's brief\n\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = text
            .split(whereSeparator: \.isNewline)
            .map { line in
                let value = line.trimmingCharacters(in: .whitespaces)
                guard let dot = value.firstIndex(of: "."),
                      value[..<dot].allSatisfy(\.isNumber),
                      value.index(after: dot) < value.endIndex else { return String(line) }
                return "- " + String(value[value.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")

        // Older persisted briefs can arrive as one paragraph without list breaks. Keep those sessions
        // readable too, while leaving provider-generated Markdown bullets untouched.
        guard !cleaned.contains("\n-") else { return cleaned }
        return ["Arah latihan:", "Pemulihan:", "Cues nanti:", "Latihan:", "Perhatikan nanti:"].reduce(cleaned) { result, label in
            result.replacingOccurrences(of: label, with: "\n\n- \(label)")
        }
    }

    private func formattedBrief(_ text: String) -> Text {
        guard let attributed = try? AttributedString(markdown: text) else {
            return Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        return Text(attributed)
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textSecondary)
    }

}
