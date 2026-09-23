import Foundation

/// A completed Coach thread kept locally so the user can reopen or delete it later.
/// This is deliberately a small UserDefaults JSON store: Coach history is private app content and
/// must not become part of the health backup or a network sync surface.
struct CoachConversationHistoryItem: Identifiable, Codable, Equatable {
    struct Message: Codable, Equatable {
        let id: UUID
        let role: String
        let text: String

        init(_ message: ChatMessage) {
            id = message.id
            role = message.role.rawValue
            text = message.text
        }

        var chatMessage: ChatMessage {
            ChatMessage(id: id, role: ChatMessage.Role(rawValue: role) ?? .user, text: text)
        }
    }

    let id: UUID
    var title: String
    var messages: [Message]
    var provider: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), messages: [ChatMessage], provider: String, now: Date = Date()) {
        self.id = id
        self.title = Self.title(for: messages)
        self.messages = messages.map(Message.init)
        self.provider = provider
        self.createdAt = now
        self.updatedAt = now
    }

    var chatMessages: [ChatMessage] { messages.map(\.chatMessage) }

    /// A stable, useful title from the first user turn rather than a generic "New chat" label.
    static func title(for messages: [ChatMessage]) -> String {
        let source = messages.first(where: { $0.role == .user })?.text
            ?? messages.first?.text
            ?? "New conversation"
        let compact = source
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 56 else { return compact.isEmpty ? "New conversation" : compact }
        return String(compact.prefix(56)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

enum CoachConversationHistoryStore {
    static let defaultsKey = "coach.conversationHistory.v1"
    static let maximumItems = 30

    static func load() -> [CoachConversationHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([CoachConversationHistoryItem].self, from: data)
        else { return [] }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ items: [CoachConversationHistoryItem]) {
        let trimmed = Array(items.sorted { $0.updatedAt > $1.updatedAt }.prefix(maximumItems))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
