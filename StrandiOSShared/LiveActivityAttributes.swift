#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for an active live-HR / workout session. Shared between the app (which
/// starts/updates the activity) and the widget extension (which renders it on the Lock Screen and in
/// the Dynamic Island).
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        /// Current heart-rate zone, resolved in the app from the user's HR-zone set.
        public var heartRateZone: Int?
        /// Workout distance and speed are pre-formatted in the app because unit preferences are not
        /// shared with the widget extension. Nil means the current activity has no GPS/sensor reading.
        public var distance: String?
        public var speed: String?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil,
                    heartRateZone: Int? = nil, distance: String? = nil, speed: String? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
            self.heartRateZone = heartRateZone
            self.distance = distance
            self.speed = speed
        }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif
