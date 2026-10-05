#if os(iOS)
import Foundation

/// A neutral symbol for a sport by what its name says. Shared by the app (sport lists, Anya's cards) and the Live Activities, so the
/// Dynamic Island shows the same icon as the screen the session was started from.
enum ActivitySport {
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("swim", "figure.pool.swim"), ("row", "figure.rower"), ("treadmill", "figure.run.treadmill"), ("run", "figure.run"),
            ("walk", "figure.walk"), ("hik", "figure.hiking"), ("cycl", "figure.outdoor.cycle"), ("bike", "figure.outdoor.cycle"),
            ("elliptical", "figure.elliptical"), ("yoga", "figure.yoga"), ("pilates", "figure.pilates"), ("strength", "dumbbell"),
            ("weight", "dumbbell"), ("gym", "dumbbell"), ("climb", "figure.climbing"), ("boxing", "figure.boxing"), ("dance", "figure.dance"),
            ("tennis", "figure.tennis"), ("padel", "figure.tennis"), ("badminton", "figure.badminton"), ("golf", "figure.golf"),
            ("soccer", "figure.soccer"), ("football", "figure.american.football"), ("basketball", "figure.basketball"), ("ski", "figure.skiing.downhill"),
            ("stair", "figure.stairs"), ("hiit", "bolt.heart"), ("stretch", "figure.flexibility"), ("martial", "figure.martial.arts"),
        ]
        return table.first { n.contains($0.0) }?.1 ?? "figure.mixed.cardio"
    }
}
#endif
