#if os(iOS)
import Foundation

/// Optional AI wording layer for Smart Coach. The deterministic rule engine remains authoritative;
/// this provider only turns an already-approved intent into one short spoken sentence.
struct AudioAICoachingProvider {
    static let defaultBaseURL = "https://api.gutsai.id/v1"
    static let defaultModel = "deepseek-v4.1-flash"
    static let timeout: TimeInterval = 4

    static func bootstrapDefaults() {
        let defaults = UserDefaults.standard
        let baseURL = defaults.string(forKey: AIProvider.customBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if baseURL.isEmpty {
            defaults.set(defaultBaseURL, forKey: AIProvider.customBaseURLKey)
        }
    }

    var isConfigured: Bool {
        guard let key = AIKeyStore.read(), !key.isEmpty else { return false }
        let owner = AIKeyStore.ownerProvider
        return owner == nil || owner == AIProvider.custom.rawValue
    }

    func rewrite(intent: AudioCoachingIntent, context: AudioAICoachingContext) async -> String? {
        guard isConfigured, let key = AIKeyStore.read(), !key.isEmpty else { return nil }
        let model = configuredModel
        guard !model.isEmpty else { return nil }

        let message = """
        Structured workout context:
        activity=\(context.sport)
        duration_seconds=\(Int(context.duration.rounded()))
        heart_rate=\(context.heartRate.map(String.init) ?? "unavailable")
        heart_rate_zone=\(context.heartRateZone.map(String.init) ?? "unavailable")
        pace_delta_seconds_per_km=\(context.paceDelta.map { String(format: "%.0f", $0) } ?? "unavailable")
        heart_rate_delta_bpm=\(context.heartRateDelta.map(String.init) ?? "unavailable")
        cadence_delta_spm=\(context.cadenceDelta.map { String(format: "%.0f", $0) } ?? "unavailable")
        intent=\(intent.rawValue)

        Rewrite the approved intent as exactly one short spoken workout instruction. Use only the
        provided values. No markdown, no diagnosis, no safety claim, no invented data, and no more
        than 18 words.
        (AudioCoachingCopy.isIndonesian ? "Use natural, concise Indonesian. Keep Heart Rate, Zone, Pace, Cadence, Effort, and units unchanged." : "Use concise natural English.")
        """

        let client = CustomClient()
        let system = AudioCoachingCopy.isIndonesian
            ? "You are a concise offline-first workout audio coach. The rule engine already decided the intent. Reply in natural, concise Indonesian and preserve health terms."
            : "You are a concise offline-first workout audio coach. The rule engine already decided the intent."
        do {
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    try await client.send(
                        key: key,
                        model: model,
                        systemPrompt: system,
                        messages: [(.user, message)],
                        session: .shared)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(Self.timeout))
                    return nil
                }
                let result = try await group.next() ?? nil
                group.cancelAll()
                return sanitize(result)
            }
        } catch {
            return nil
        }
    }

    private var configuredModel: String {
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: "ai.provider")
        if provider == AIProvider.custom.rawValue,
           let stored = defaults.string(forKey: "ai.model"),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Self.defaultModel
    }

    private func sanitize(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.replacingOccurrences(of: "```", with: "")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count > 180 {
            value = String(value.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

struct AudioAICoachingContext: Sendable {
    let sport: String
    let duration: TimeInterval
    let heartRate: Int?
    let heartRateZone: Int?
    let heartRateDelta: Int?
    let paceDelta: Double?
    let cadenceDelta: Double?
}
#endif
