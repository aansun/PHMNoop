import Foundation

// AnyaNoteStore.swift — Anya's notes, one private store per module.
//
// PURE (Foundation only) and unit-tested. A note is a line of text, optionally with the figures it was written from and a tag
// (for example the day) so that a module's daily snapshot replaces itself instead of piling up. Each module reads and writes only
// its own store: there is no call that reads across modules, so what Anya learned in Breathing cannot reach Sleep.

public struct AnyaNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var ts: Int
    public var text: String
    public var tag: String?
    public var values: [String: Double]?
    public init(id: UUID = UUID(), ts: Int, text: String, tag: String? = nil, values: [String: Double]? = nil) {
        self.id = id; self.ts = ts; self.text = text; self.tag = tag; self.values = values
    }
}

public struct AnyaNoteStore {
    public static let maxNotes = 40
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "nuna.anya.memory.") {
        self.defaults = defaults; self.prefix = prefix
    }

    private func key(_ module: String) -> String { prefix + module }

    public func notes(_ module: String) -> [AnyaNote] {
        guard let data = defaults.data(forKey: key(module)),
              let list = try? JSONDecoder().decode([AnyaNote].self, from: data) else { return [] }
        return list
    }

    /// Adds a note. With a `tag`, an existing note of this module with the same tag is replaced (the newest figures win).
    public func remember(_ module: String, _ text: String, tag: String? = nil, values: [String: Double]? = nil, now: Date = Date()) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = notes(module)
        let note = AnyaNote(ts: Int(now.timeIntervalSince1970), text: String(t.prefix(400)), tag: tag, values: values)
        if let tag, let i = list.firstIndex(where: { $0.tag == tag }) { list[i] = note } else { list.append(note) }
        if list.count > Self.maxNotes { list.removeFirst(list.count - Self.maxNotes) }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key(module)) }
    }

    public func clear(_ module: String) { defaults.removeObject(forKey: key(module)) }

    /// The newest note of this module that carries figures and a tag different from `excluding` (the one being written now).
    public func previousSnapshot(_ module: String, excluding tag: String?) -> AnyaNote? {
        notes(module).last { $0.values != nil && $0.tag != nil && $0.tag != tag }
    }

    public func summary(_ module: String, limit: Int = 8) -> String? {
        let list = notes(module).suffix(limit)
        guard !list.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return "Anya's notes from this module:\n" + list.map { "- \(f.string(from: Date(timeIntervalSince1970: TimeInterval($0.ts)))) \($0.text)" }.joined(separator: "\n")
    }
}

public enum AnyaNoteMath {
    public struct Change: Equatable, Sendable {
        public let key: String
        public let was: Double
        public let now: Double
        public var relative: Double { was == 0 ? (now == 0 ? 0 : 1) : (now - was) / abs(was) }
    }

    /// The figures that moved between two snapshots by at least `minRelative` (and `minAbsolute`), biggest move first, at most
    /// `limit` of them. Only keys present in both are compared.
    public static func changes(previous: [String: Double], current: [String: Double],
                               minRelative: Double = 0.05, minAbsolute: Double = 1, limit: Int = 3) -> [Change] {
        current.compactMap { k, now -> Change? in
            guard let was = previous[k] else { return nil }
            let c = Change(key: k, was: was, now: now)
            return abs(now - was) >= minAbsolute && abs(c.relative) >= minRelative ? c : nil
        }
        .sorted { abs($0.relative) > abs($1.relative) || (abs($0.relative) == abs($1.relative) && $0.key < $1.key) }
        .prefix(limit).map { $0 }
    }

    /// Whole days between two timestamps (never negative).
    public static func daysBetween(_ a: Int, _ b: Int) -> Int { max(0, (b - a) / 86_400) }
}
