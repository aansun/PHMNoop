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

/// Where a memory came from. Optional in the model so JSON saved before this field decodes fine
/// (a missing value reads as manual).
enum CoachMemorySource: String, Codable {
    case manual
    case conversation
}

struct CoachMemory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var category: CoachMemoryCategory
    var isActive: Bool = true
    var createdAt: Date = Date()
    var source: CoachMemorySource? = .manual

    var fromConversation: Bool { source == .conversation }
}

// MARK: - Auto-capture from conversation

/// Pure, on-device extractor: turns a user's Coach message into at most ONE candidate memory when it
/// clearly states a durable preference / goal / event / remember-directive. Conservative by design —
/// most chat is not memory-worthy, and everything captured is user-deletable. No network, no LLM.
enum CoachMemoryExtractor {
    static func extract(from message: String) -> (title: String, detail: String, category: CoachMemoryCategory)? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6, text.count <= 280 else { return nil }
        let lower = text.lowercased()

        // 1) Explicit "remember this" directive (highest signal) — strip the cue for a cleaner title.
        let rememberCues = ["ingat kalau", "ingat bahwa", "ingatlah", "tolong ingat", "catat kalau",
                            "catat bahwa", "simpan bahwa", "remember that", "please remember", "note that"]
        for cue in rememberCues where lower.contains(cue) {
            let captured = after(cue, in: text) ?? text
            return (summaryTitle(captured), captured, .note)
        }

        // 2) Coaching preferences.
        let prefCues = ["lebih suka", "lebih memilih", "aku suka", "saya suka", "prefer", "panggil aku",
                        "panggil saya", "gunakan bahasa", "pakai bahasa", "tolong selalu", "selalu gunakan",
                        "jangan pernah", "tolong jangan"]
        if prefCues.contains(where: { lower.contains($0) }) {
            return (summaryTitle(text), text, .preference)
        }

        // 3) Goals.
        let goalCues = ["target", "aku mau", "saya mau", "aku ingin", "saya ingin", "pengen", "pengin",
                        "goal", "mau capai", "ingin capai", "aim for", "minimum pace", "mau lari",
                        "turun berat", "naik berat"]
        if goalCues.contains(where: { lower.contains($0) }) {
            return (summaryTitle(text), text, .goal)
        }

        // 4) Events (a date/time cue).
        let eventCues = ["besok", "lusa", "minggu depan", "tanggal", "pukul", " jam ", "senin", "selasa",
                         "rabu", "kamis", "jumat", "sabtu", "januari", "februari", "maret", "april", "mei",
                         "juni", "juli", "agustus", "september", "oktober", "november", "desember"]
        if eventCues.contains(where: { lower.contains($0) }) {
            return (summaryTitle(text), text, .event)
        }
        return nil
    }

    /// First ~8 words (≤ 60 chars) of `text`, trailing punctuation trimmed, first letter capitalised.
    private static func summaryTitle(_ text: String) -> String {
        let words = text.split(separator: " ").prefix(8).joined(separator: " ")
        var t = String(words.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?"))
        if let first = t.first { t.replaceSubrange(t.startIndex...t.startIndex, with: String(first).uppercased()) }
        return t.isEmpty ? text : t
    }

    /// The remainder of `text` after the first occurrence of `cue` (case-insensitive), or nil.
    private static func after(_ cue: String, in text: String) -> String? {
        guard let r = text.range(of: cue, options: .caseInsensitive) else { return nil }
        let rest = text[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :,-—"))
        return rest.isEmpty ? nil : rest
    }
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
        return "\n\nBefore anything else, apply these saved memories the user set. Honour them in every reply:\n"
            + lines.joined(separator: "\n")
    }

    /// Auto-capture a memory from a user's Coach message (called on every send, any provider). Saves at
    /// most one candidate, skips duplicates (same detail or title, case-insensitive). Off-actor so the
    /// send flow can call it without hopping. Everything captured is user-deletable in My Memory.
    nonisolated static func autoCapture(from message: String) {
        guard let cand = CoachMemoryExtractor.extract(from: message) else { return }
        var all = loadAll()
        let normDetail = cand.detail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normTitle = cand.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let dup = all.contains { m in
            m.detail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normDetail
                || m.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normTitle
        }
        guard !dup else { return }
        all.insert(CoachMemory(title: cand.title, detail: cand.detail,
                               category: cand.category, source: .conversation),
                   at: 0)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
