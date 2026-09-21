// === PHM OVERLAY (PHMNOOP) ===
// On-device Apple Intelligence provider for the Coach, via Apple's Foundation Models framework.
//
// No API key, no network: the prompt is answered by the system on-device model and never leaves the
// device. Requires an Apple-Intelligence-capable device on iOS 26 / macOS 26+. On an older OS, an
// SDK without the framework, or an ineligible / not-yet-enabled device, every call fails with a
// clear, actionable message instead of a silent nothing.
//
// Implements only `send` + `fetchModels`; the protocol's default `stream` (send + one delta) and
// `streamWithImage` (delegates to stream) cover the rest — on-device replies are fast, so a single
// delta is fine and avoids depending on the streaming API's shape.

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

struct AppleIntelligenceClient: AIProviderClient {

    /// The single "model" id surfaced in the picker (there is one system model).
    static let modelId = "on-device"

    /// True when the on-device model can answer on THIS device right now. False when the OS is too old,
    /// the framework is absent from the build, the hardware is ineligible, Apple Intelligence is off, or
    /// the model assets are still downloading. Cheap + synchronous — safe to read from `isConfigured`.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    /// A human-readable reason on-device AI can't be used right now, or nil when it can.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return "Apple Intelligence isn't available (\(String(describing: reason))). Check "
                    + "Settings › Apple Intelligence & Siri, or this device may not support it."
            }
        } else {
            return "Apple Intelligence needs iOS 26 / macOS 26 or later."
        }
        #else
        return "This build was compiled without the Apple Intelligence framework."
        #endif
    }

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw AICoachError.server(0, AppleIntelligenceClient.unavailableReason
                    ?? "Apple Intelligence is unavailable on this device.")
            }
            let llm = LanguageModelSession(instructions: systemPrompt)
            let prompt = AppleIntelligenceClient.renderPrompt(messages)
            guard !prompt.isEmpty else { throw AICoachError.emptyQuestion }
            do {
                let response = try await llm.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw AICoachError.emptyReply("Apple Intelligence returned an empty reply.")
                }
                return text
            } catch let e as AICoachError {
                throw e
            } catch {
                // Guardrail violations, context-window overflow, etc. surface with their own message.
                throw AICoachError.server(0, "Apple Intelligence: \(error.localizedDescription)")
            }
        } else {
            throw AICoachError.server(0, "Apple Intelligence needs iOS 26 / macOS 26 or later.")
        }
        #else
        throw AICoachError.server(0, "This build was compiled without the Apple Intelligence framework.")
        #endif
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        [AppleIntelligenceClient.modelId]
    }

    /// Flatten the transcript into one prompt. The persona/system prompt is passed separately as the
    /// session's `instructions`, so here we only carry the conversation turns. A single-turn ask is
    /// sent verbatim; a multi-turn one is role-labelled and ends on an `Assistant:` cue to continue.
    private static func renderPrompt(_ messages: [(role: ChatMessage.Role, content: String)]) -> String {
        guard !messages.isEmpty else { return "" }
        if messages.count == 1 { return messages[0].content }
        var lines: [String] = []
        for m in messages {
            lines.append((m.role == .user ? "User: " : "Assistant: ") + m.content)
        }
        lines.append("Assistant:")
        return lines.joined(separator: "\n\n")
    }
}
