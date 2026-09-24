#if os(iOS)
import Foundation

/// ChatGPT/Codex client authenticated by `ChatGPTAuthService`.
///
/// This endpoint is intentionally isolated from the public OpenAI API-key client. The user signs
/// in once with the device flow; only the short-lived access token and account id are used here.
struct ChatGPTClient: AIProviderClient {
    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        var reply = ""
        try await stream(key: key, model: model, systemPrompt: systemPrompt,
                         messages: messages, session: session) { delta in
            reply += delta
        }
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw emptyReplyError([:]) }
        return trimmed
    }

    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        let auth = try await ChatGPTAuthService.shared.validAuthorization()
        let body: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
            "input": messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": [["type": "input_text", "text": message.content]]
                ] as [String: Any]
            },
            "max_output_tokens": 4096,
            "store": false,
            "stream": true
        ]

        var request = URLRequest(url: AIProvider.chatGPT.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // The backend uses this header to identify the first-party Codex client family. It is not a
        // credential and does not contain user data.
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        try await performStreamingRequest(request, session: session) { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "response.output_text.delta",
                  let delta = json["delta"] as? String,
                  !delta.isEmpty else { return }
            onDelta(delta)
        }
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        // ChatGPT device-auth does not expose the public `/models` catalogue used by API keys. Keep
        // the picker deterministic and offline; the user can still select the supported model ids.
        AIProvider.chatGPT.modelOptions
    }
}
#endif
