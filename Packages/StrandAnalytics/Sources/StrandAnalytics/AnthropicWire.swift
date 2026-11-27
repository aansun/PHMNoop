import Foundation

/// The parts of Anthropic's Messages API the app has to get right, kept free of networking so they can be tested.
///
/// Current Claude models think before they answer unless told otherwise, so a reply can open with a `thinking` block: content is read by
/// type, never by position. While a tool is being used those blocks have to go back exactly as they came, which is why the stream is
/// rebuilt into whole blocks here and not only into text.
public enum AnthropicWire {
    /// Whether a model takes `output_config.effort`. Older ones answer such a request with an error.
    public static func takesEffort(_ model: String) -> Bool {
        let m = model.lowercased()
        let older = ["claude-3", "haiku-4", "sonnet-4-5", "opus-4-0", "opus-4-1", "sonnet-4-0", "sonnet-4-2025", "opus-4-2025"]
        return m.hasPrefix("claude-") && !older.contains { m.contains($0) }
    }

    /// The most a reply may take, thinking included: the cap counts both, so it is well above what a chat answer needs.
    public static let maxTokens = 8000

    /// The effort and room for something built to rules (a program, a food estimate, an explanation of figures): a small model keeps to the rules
    /// better when it thinks longer, and the thinking counts against the cap.
    public static let buildEffort = "high"
    public static let buildMaxTokens = 16000

    /// A request body. `messages` are in wire form already. Effort is low unless asked otherwise: a chat should answer quickly, and a small
    /// model at low effort still thinks when a question calls for it.
    public static func body(model: String, system: String, messages: [[String: Any]], tools: [[String: Any]] = [], stream: Bool, effort: String = "low") -> [String: Any] {
        var body: [String: Any] = ["model": model, "max_tokens": effort == "low" ? maxTokens : buildMaxTokens, "system": system, "messages": messages]
        if takesEffort(model) { body["output_config"] = ["effort": effort] }
        if !tools.isEmpty {
            body["tools"] = tools
            // A tool loop sends the same prefix again on every step; caching it is what keeps that cheap.
            body["cache_control"] = ["type": "ephemeral"]
        }
        if stream { body["stream"] = true }
        return body
    }

    /// The text of a reply that was not streamed: every `text` block, in order.
    public static func text(ofContent content: [[String: Any]]) -> String {
        content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    }
}

/// Rebuilds one streamed assistant message from its events.
public struct AnthropicStreamMessage {
    public struct ToolUse: Equatable {
        public let id: String
        public let name: String
        /// The arguments as JSON text, "{}" when the tool takes none.
        public let inputJSON: String
    }

    private var blocks: [[String: Any]] = []
    private var partialJSON: [Int: String] = [:]
    public private(set) var stopReason: String?
    /// Set when the stream carried an error event.
    public private(set) var errorMessage: String?

    public init() {}

    /// Takes one event's JSON; returns the visible text it added, if any.
    @discardableResult
    public mutating func ingest(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String else { return nil }
        let index = event["index"] as? Int ?? max(blocks.count - 1, 0)
        switch type {
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any] else { return nil }
            while blocks.count < index { blocks.append(["type": "text", "text": ""]) }
            if blocks.count == index { blocks.append(block) } else { blocks[index] = block }
            let opening = block["type"] as? String == "text" ? block["text"] as? String : nil
            return opening?.isEmpty == false ? opening : nil
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], let kind = delta["type"] as? String, blocks.indices.contains(index) else { return nil }
            func append(_ key: String) -> String {
                let add = delta[key] as? String ?? ""
                blocks[index][key] = (blocks[index][key] as? String ?? "") + add
                return add
            }
            switch kind {
            case "text_delta":
                let add = append("text")
                return add.isEmpty ? nil : add
            case "thinking_delta": _ = append("thinking")
            case "signature_delta": _ = append("signature")
            case "input_json_delta": partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
            default: break
            }
        case "message_delta":
            if let delta = event["delta"] as? [String: Any], let stop = delta["stop_reason"] as? String { stopReason = stop }
        case "error":
            errorMessage = (event["error"] as? [String: Any])?["message"] as? String ?? "stream error"
        default:
            break
        }
        return nil
    }

    /// The tool calls the message asks for. A call whose arguments did not arrive whole is left out.
    public var toolUses: [ToolUse] {
        blocks.enumerated().compactMap { i, block in
            guard block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            let raw = partialJSON[i] ?? ""
            if raw.isEmpty { return ToolUse(id: id, name: name, inputJSON: "{}") }
            guard let data = raw.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
            return ToolUse(id: id, name: name, inputJSON: raw)
        }
    }

    /// The message's content as it goes back to the API: every block as it came, tool arguments restored.
    public var content: [[String: Any]] {
        blocks.enumerated().map { i, block in
            var block = block
            if block["type"] as? String == "tool_use" {
                let data = (partialJSON[i] ?? "").data(using: .utf8) ?? Data()
                block["input"] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }
            return block
        }
    }
}
