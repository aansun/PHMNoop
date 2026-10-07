#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// A folder of programs in the Gym hub.
struct NunaProgramGroup: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var collapsed = false
}

/// Which program sits in which group. Kept on this iPhone beside the programs, not inside the database: a program stays exactly what it
/// was, and a group that is lost or a program that is deleted only ever leaves a program ungrouped, never missing. A program with no entry
/// here is simply "ungrouped".
@MainActor
final class NunaProgramGroupsModel: ObservableObject {
    static let shared = NunaProgramGroupsModel()
    static let maxNameLength = 40
    private static let key = "nuna.gym.programGroups"

    private struct Stored: Codable { var groups: [NunaProgramGroup]; var membership: [String: String] }

    @Published private(set) var groups: [NunaProgramGroup] = []
    /// Program id to group id.
    @Published private(set) var membership: [String: String] = [:]

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        groups = s.groups; membership = s.membership
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(groups: groups, membership: membership)) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: Reading

    func group(of programId: String) -> NunaProgramGroup? { membership[programId].flatMap { id in groups.first { $0.id == id } } }
    func programs(in group: NunaProgramGroup, from all: [LiftProgramRow]) -> [LiftProgramRow] { all.filter { membership[$0.id] == group.id } }
    func ungrouped(_ all: [LiftProgramRow]) -> [LiftProgramRow] { all.filter { group(of: $0.id) == nil } }

    // MARK: Changing

    private static func clean(_ name: String) -> String { String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength)) }

    /// A new group, or the one that already has that name (case aside). Nil for an empty name.
    @discardableResult
    func add(name: String) -> NunaProgramGroup? {
        let n = Self.clean(name)
        guard !n.isEmpty else { return nil }
        if let same = groups.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { return same }
        let g = NunaProgramGroup(name: n)
        groups.append(g); save()
        return g
    }

    func rename(_ group: NunaProgramGroup, to name: String) {
        let n = Self.clean(name)
        guard !n.isEmpty, let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        guard !groups.contains(where: { $0.id != group.id && $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        groups[i].name = n; save()
    }

    /// The group goes; its programs stay and become ungrouped.
    func delete(_ group: NunaProgramGroup) {
        groups.removeAll { $0.id == group.id }
        membership = membership.filter { $0.value != group.id }
        save()
    }

    func move(_ programId: String, to group: NunaProgramGroup?) {
        if let group { membership[programId] = group.id } else { membership.removeValue(forKey: programId) }
        save()
    }

    func toggleCollapsed(_ group: NunaProgramGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[i].collapsed.toggle(); save()
    }

    /// Forget programs that no longer exist, so a deleted program does not leave a ghost behind.
    func prune(existing ids: Set<String>) {
        let groupIds = Set(groups.map(\.id))
        let kept = membership.filter { ids.contains($0.key) && groupIds.contains($0.value) }
        if kept.count != membership.count { membership = kept; save() }
    }

    // MARK: Suggestions

    /// Programs named "Plan · Day A", "Plan · Day B" share "Plan"; the ungrouped ones that share a name before " · " (two or more) are offered
    /// as a group. Programs saved from a session or imported from a sheet are named this way.
    struct Suggestion: Identifiable { let name: String; let programIds: [String]; var id: String { name } }

    func suggestions(for all: [LiftProgramRow]) -> [Suggestion] {
        var byPrefix: [String: [LiftProgramRow]] = [:]
        for p in ungrouped(all) {
            guard let r = p.name.range(of: " · ") else { continue }
            let prefix = String(p.name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty { byPrefix[prefix, default: []].append(p) }
        }
        return byPrefix.filter { $0.value.count >= 2 }.map { Suggestion(name: $0.key, programIds: $0.value.map(\.id)) }.sorted { $0.name < $1.name }
    }

    func apply(_ s: Suggestion) {
        guard let g = add(name: s.name) else { return }
        for id in s.programIds { membership[id] = g.id }
        save()
    }
}
#endif
