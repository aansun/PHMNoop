import Foundation
import StrandAnalytics

struct AnthropicClient: AIProviderClient {

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        try await send(key: key, model: model, systemPrompt: systemPrompt, messages: messages, session: session, effort: "low", inlineImage: nil)
    }

    /// One whole reply at the effort asked, with an optional photo on the last turn.
    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        effort: String,
        inlineImage: String?
    ) async throws -> String {
        var turns = wire(messages)
        if let inlineImage, !inlineImage.isEmpty, let last = messages.last, last.role == .user {
            turns[turns.count - 1] = ["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": AIImageType.mime(base64: inlineImage), "data": inlineImage]],
                ["type": "text", "text": last.content],
            ]]
        }
        // Anthropic: system prompt is a top-level field, not a message role.
        var req = try request(key: key, body: AnthropicWire.body(model: model, system: systemPrompt, messages: turns, stream: false, effort: effort))
        if effort != "low" { req.timeoutInterval = 180 }
        let json = try await performRequest(req, session: session)
        if json["stop_reason"] as? String == "refusal" { throw AICoachError.emptyReply(Self.declined) }
        // A reply can open with a thinking block, so the text is every text block, not the first block.
        let text = AnthropicWire.text(ofContent: json["content"] as? [[String: Any]] ?? []).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw emptyReplyError(json)   // #1074: surface the provider's real error if the 200 body has one
        }
        return text
    }

    static var declined: String { String(localized: "The model declined to answer that. Try asking it another way.") }

    private func wire(_ messages: [(role: ChatMessage.Role, content: String)]) -> [[String: Any]] {
        messages.map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    private func request(key: String, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: AIProvider.anthropic.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 120
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// One streamed message, with its text handed on as it arrives; the whole message is returned for a caller that has more to do with it.
    private func streamMessage(_ req: URLRequest, session: URLSession, onDelta: (String) -> Void) async throws -> AnthropicStreamMessage {
        var message = AnthropicStreamMessage()
        try await performStreamingRequest(req, session: session) { payload in
            if let delta = message.ingest(payload) { onDelta(delta) }
        }
        if let error = message.errorMessage { throw AICoachError.network(error) }
        if message.stopReason == "refusal" { throw AICoachError.emptyReply(Self.declined) }
        return message
    }

    /// K1: Stream via `stream: true`. Anthropic SSE uses typed events; `AnthropicStreamMessage` rebuilds the message from them.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        let req = try request(key: key, body: AnthropicWire.body(model: model, system: systemPrompt, messages: wire(messages), stream: true))
        _ = try await streamMessage(req, session: session, onDelta: onDelta)
    }

    /// Stream with an optional inline image (base64 PNG): the last user turn becomes a text block plus an image block.
    func streamWithImage(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        inlineImage: String?,
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        var body = wire(messages)
        if let inlineImage, !inlineImage.isEmpty, let last = messages.last, last.role == .user {
            body[body.count - 1] = ["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": AIImageType.mime(base64: inlineImage), "data": inlineImage]],
                ["type": "text", "text": last.content],
            ]]
        }
        let req = try request(key: key, body: AnthropicWire.body(model: model, system: systemPrompt, messages: body, stream: true))
        _ = try await streamMessage(req, session: session, onDelta: onDelta)
    }

    /// How many times in one answer Anya may go and look something up before she has to answer with what she has.
    static let lookUpRounds = 6

    /// A streamed answer that may look things up on the way: each time the model asks for a tool, it is run on the phone and the result sent
    /// back, until the model answers. The blocks of each round go back exactly as they came.
    func converse(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        inlineImage: String?,
        session: URLSession,
        tools: [[String: Any]],
        lookUp: @MainActor (_ name: String, _ input: [String: Any]) async -> (text: String, failed: Bool),
        onDelta: (String) -> Void
    ) async throws {
        var turns = wire(messages)
        if let inlineImage, !inlineImage.isEmpty, let last = messages.last, last.role == .user {
            turns[turns.count - 1] = ["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": AIImageType.mime(base64: inlineImage), "data": inlineImage]],
                ["type": "text", "text": last.content],
            ]]
        }
        var said = false
        for round in 0...Self.lookUpRounds {
            var body = AnthropicWire.body(model: model, system: systemPrompt, messages: turns, tools: tools, stream: true)
            if round == Self.lookUpRounds { body["tool_choice"] = ["type": "none"] }
            let needsBreak = said
            var started = false
            let message = try await streamMessage(try request(key: key, body: body), session: session) { delta in
                // Words said before a lookup and words said after it are separate paragraphs.
                if !started && needsBreak { onDelta("\n\n") }
                started = true
                said = true
                onDelta(delta)
            }
            let calls = message.toolUses
            guard message.stopReason == "tool_use", !calls.isEmpty else { return }
            turns.append(["role": "assistant", "content": message.content])
            var results: [[String: Any]] = []
            for call in calls {
                let input = (try? JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))) as? [String: Any] ?? [:]
                let result = await lookUp(call.name, input)
                var block: [String: Any] = ["type": "tool_result", "tool_use_id": call.id, "content": result.text]
                if result.failed { block["is_error"] = true }
                results.append(block)
            }
            turns.append(["role": "user", "content": results])
        }
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        var req = URLRequest(url: AIProvider.anthropic.modelsEndpoint)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        return parseModels(try await performRequest(req, session: session))
    }

    /// Pure: unwrap the `/models` body into ids (Anthropic keeps all non-empty). No network — unit-tested.
    func parseModels(_ json: [String: Any]) -> [String] {
        guard let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return id
        }
    }
}
