#if os(iOS)
import Foundation

/// ChatGPT/Codex client authenticated by `ChatGPTAuthService`.
///
/// This endpoint is intentionally isolated from the public OpenAI API-key client. The user signs
/// in once with the device flow; only the short-lived access token and account id are used here.
struct ChatGPTClient: AIProviderClient {
    // The ChatGPT subscription endpoint follows the Responses v1 contract used by the Codex client.
    // Keep this isolated here because it is not the public OpenAI API-key endpoint.
    private static let codexBetaHeader = "responses=v1"
    private static let codexClientVersion = "0.146.0"
    private static let modelsEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/models")!

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
                    "type": "message",
                    "role": message.role.rawValue,
                    "content": [["type": "input_text", "text": message.content]]
                ] as [String: Any]
            },
            "store": false,
            "stream": true
        ]

        var request = URLRequest(url: AIProvider.chatGPT.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // The ChatGPT subscription endpoint is the Codex Responses backend rather than the public
        // OpenAI API. These headers opt into its HTTP/SSE contract and give each request a fresh
        // routing identity. Without them the backend currently responds with HTTP 400.
        request.setValue(Self.codexBetaHeader, forHTTPHeaderField: "OpenAI-Beta")
        let sessionID = UUID().uuidString
        let threadID = UUID().uuidString
        request.setValue(sessionID, forHTTPHeaderField: "session_id")
        request.setValue(sessionID, forHTTPHeaderField: "session-id")
        request.setValue(threadID, forHTTPHeaderField: "thread-id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-client-request-id")
        request.setValue(Self.codexClientVersion, forHTTPHeaderField: "version")
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
        let auth = try await ChatGPTAuthService.shared.validAuthorization()
        var components = URLComponents(url: Self.modelsEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "client_version", value: Self.codexClientVersion)]
        guard let url = components?.url else { throw AICoachError.decode }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.codexBetaHeader, forHTTPHeaderField: "OpenAI-Beta")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "session-id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-client-request-id")
        request.setValue(Self.codexClientVersion, forHTTPHeaderField: "version")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AICoachError.network("no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            if AICoachError.isKeyRejection(http.statusCode) { throw AICoachError.badKey }
            if http.statusCode == 429 {
                throw AICoachError.rateLimited(providerErrorMessage(from: data))
            }
            throw AICoachError.server(http.statusCode, providerErrorMessage(from: data))
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = root["models"] as? [[String: Any]] else {
            throw AICoachError.decode
        }

        // The backend catalog contains hidden and API-incompatible entries. Only expose models that
        // are visible in the picker and accepted by the Responses endpoint.
        let ids = rawModels.compactMap { item -> String? in
            guard let slug = item["slug"] as? String, !slug.isEmpty else { return nil }
            let visibility = item["visibility"] as? String ?? "list"
            let supportedInAPI = item["supported_in_api"] as? Bool ?? true
            return visibility == "list" && supportedInAPI ? slug : nil
        }
        return ids.isEmpty ? AIProvider.chatGPT.modelOptions : ids
    }
}
#endif
