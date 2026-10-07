#if os(iOS)
import Foundation

/// The workouts pinned to "Start a workout", at most eight, in the order they were pinned. Until the person changes it the
/// quick set is the one the screen always had. Kept on this device only.
enum NunaPinnedSports {
    static let key = "nuna.workouts.pinnedSports"
    static let maxCount = 8
    static let defaults = ["Running", "Walking", "Cycling", "Pool swim", "HIIT", "Yoga"]
    /// Left out of the "Start a workout" lists: lifting is started from the Gym tab, which has its own programs and session screen.
    static let hidden: Set<String> = ["Strength"]

    /// "default" until the first change, then the comma-joined names (empty once everything is unpinned).
    static let unset = "default"

    static func decode(_ raw: String) -> [String] {
        if raw == unset { return defaults }
        let known = Set(WorkoutCatalog.all.map(\.name))
        var seen = Set<String>()
        return raw.split(separator: ",").map { String($0) }.filter { known.contains($0) && !hidden.contains($0) && seen.insert($0).inserted }.prefix(maxCount).map { $0 }
    }

    static func encode(_ names: [String]) -> String { names.joined(separator: ",") }

    /// The list after pinning or unpinning `name`; nil when pinning would pass the limit.
    static func toggled(_ name: String, in current: [String]) -> [String]? {
        if current.contains(name) { return current.filter { $0 != name } }
        guard current.count < maxCount else { return nil }
        return current + [name]
    }
}
#endif
