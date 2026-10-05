#if os(iOS)
import Foundation

/// What Anya remembers inside one module. Memory is local to the module it was learned in: the Breathing module's notes
/// (past sessions, what was asked there) are never read by another module, and each module can forget its own. It lives in
/// this phone's defaults; it reaches a provider only inside a question the wearer asks there, and only with data access on.
enum NunaAnyaMemory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var ts: Int
        var text: String
    }

    static let maxEntries = 40
    private static func key(_ module: NunaAnyaModule) -> String { "nuna.anya.memory.\(module.rawValue)" }

    static func entries(_ module: NunaAnyaModule) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(module)),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    static func remember(_ module: NunaAnyaModule, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = entries(module)
        list.append(Entry(ts: Int(Date().timeIntervalSince1970), text: String(t.prefix(400))))
        if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key(module)) }
    }

    static func clear(_ module: NunaAnyaModule) { UserDefaults.standard.removeObject(forKey: key(module)) }

    /// The latest notes as plain lines for a provider prompt, or nil when there is nothing to recall.
    static func summary(_ module: NunaAnyaModule, limit: Int = 8) -> String? {
        let list = entries(module).suffix(limit)
        guard !list.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return "Anya's notes from this module:\n" + list.map { "- \(f.string(from: Date(timeIntervalSince1970: TimeInterval($0.ts)))) \($0.text)" }.joined(separator: "\n")
    }
}
#endif
