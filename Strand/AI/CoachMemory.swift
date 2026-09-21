// === PHM OVERLAY (PHMNOOP) ===
// Coach "Memory": user-curated facts, goals, events and coaching preferences the Coach should
// remember. Stored ON-DEVICE (UserDefaults JSON), fully user-managed — add, toggle Active, delete.
// Active memories are folded into the Coach system prompt (see AICoachEngine.systemPrompt) so they
// actually steer replies. Reached from Coach settings › Memory.

import Foundation

enum CoachMemoryCategory: String, Codable, CaseIterable, Identifiable {
    case goal
    case event
    case preference
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .goal:       return "Goals"
        case .event:      return "Events"
        case .preference: return "Coaching Preference"
        case .note:       return "Note"
        }
    }

    var symbol: String {
        switch self {
        case .goal:       return "target"
        case .event:      return "calendar"
        case .preference: return "slider.horizontal.3"
        case .note:       return "note.text"
        }
    }
}

struct CoachMemory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var category: CoachMemoryCategory
    var isActive: Bool = true
    var createdAt: Date = Date()
}

/// On-device store for Coach memories. Single JSON blob in UserDefaults — no schema migration, and
/// `activePromptBlock()` can read it statically from the prompt builder without an instance.
@MainActor
final class CoachMemoryStore: ObservableObject {
    static let defaultsKey = "coach.memories.v1"

    @Published private(set) var memories: [CoachMemory] = []

    init() { memories = Self.loadAll() }

    /// All stored memories, newest first. `nonisolated` so the prompt builder can read it off-actor.
    nonisolated static func loadAll() -> [CoachMemory] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([CoachMemory].self, from: data) else { return [] }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        objectWillChange.send()
    }

    func add(title: String, detail: String, category: CoachMemoryCategory) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        memories.insert(CoachMemory(title: t,
                                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                                    category: category),
                        at: 0)
        persist()
    }

    func delete(_ memory: CoachMemory) {
        memories.removeAll { $0.id == memory.id }
        persist()
    }

    func setActive(_ memory: CoachMemory, _ active: Bool) {
        guard let i = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[i].isActive = active
        persist()
    }

    func update(_ memory: CoachMemory) {
        guard let i = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[i] = memory
        persist()
    }

    /// The current value of `memory` in the store (so a detail view reflects toggles/edits live).
    func current(_ id: UUID) -> CoachMemory? { memories.first { $0.id == id } }

    /// Prompt block of ACTIVE memories, appended to the Coach system prompt so they steer replies.
    /// Empty when there are none, so the prompt is unchanged for users who never add any.
    nonisolated static func activePromptBlock() -> String {
        let active = loadAll().filter { $0.isActive }
        guard !active.isEmpty else { return "" }
        let lines = active.map { m -> String in
            let d = m.detail.isEmpty ? "" : " — \(m.detail)"
            return "- [\(m.category.displayName)] \(m.title)\(d)"
        }
        return "\n\nThe user has saved these coaching memories. Honour them in every reply:\n"
            + lines.joined(separator: "\n")
    }
}
