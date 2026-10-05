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
        /// Latest strap battery percentage. Optional so activities created by older builds still decode.
        public var batteryPct: Int?
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        /// Current heart-rate zone, resolved in the app from the user's HR-zone set.
        public var heartRateZone: Int?
        /// The active workout name, resolved from the same session shown by LiveWorkoutView.
        public var activityName: String?
        /// Start time for the running activity clock. The widget renders this locally so the timer
        /// keeps advancing while the app is suspended.
        public var activityStartedAt: Date?
        /// Running workout heart-rate statistics. Nil when the activity is live HR without a named workout.
        public var averageBPM: Int?
        public var peakBPM: Int?
        /// Workout distance and speed are pre-formatted in the app because unit preferences are not
        /// shared with the widget extension. Nil means the current activity has no GPS/sensor reading.
        public var distance: String?
        /// GPS pace, formatted with the user's distance preference. Nil for non-GPS activities.
        public var pace: String?
        /// Kept for decoding content created by older builds. New live-HR content uses `pace`.
        public var speed: String?
        /// Calories so far, estimated from the session's heart rate. Nil until there is enough data.
        public var calories: Int?
        /// One pre-translated line under the heart rate, e.g. "Target 30:00 · 162 kcal". Nil when there is nothing to say.
        public var subtitle: String?
        /// Progress to the session's time or distance target, 0 to 1. Nil for a session without one.
        public var progress: Double?
        /// The heart-rate zone the wearer asked to stay in. Nil without a zone target.
        public var targetZone: Int?
        /// Where the heart rate sits across the five-zone bar, 0 to 1.
        public var zonePosition: Double?
        /// Seconds spent in the current zone, for sports without a route.
        public var zoneSeconds: Int?
        /// Set while the session is paused: the moment the pause began, so the widget can run a pause timer.
        public var pausedAt: Date?
        /// The session's Effort as the app shows it (the user's scale, one decimal), e.g. "4.1". Nil outside a workout.
        public var effortLabel: String?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, batteryPct: Int? = nil,
                    effort: Int? = nil,
                    heartRateZone: Int? = nil, activityName: String? = nil,
                    activityStartedAt: Date? = nil,
                    averageBPM: Int? = nil, peakBPM: Int? = nil,
                    distance: String? = nil, pace: String? = nil, speed: String? = nil,
                    calories: Int? = nil, subtitle: String? = nil, progress: Double? = nil, targetZone: Int? = nil,
                    zonePosition: Double? = nil, zoneSeconds: Int? = nil, pausedAt: Date? = nil, effortLabel: String? = nil) {
            self.effortLabel = effortLabel
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.batteryPct = batteryPct
            self.effort = effort
            self.heartRateZone = heartRateZone
            self.activityName = activityName
            self.activityStartedAt = activityStartedAt
            self.averageBPM = averageBPM
            self.peakBPM = peakBPM
            self.distance = distance
            self.pace = pace
            self.speed = speed
            self.calories = calories
            self.subtitle = subtitle
            self.progress = progress
            self.targetZone = targetZone
            self.zonePosition = zonePosition
            self.zoneSeconds = zoneSeconds
            self.pausedAt = pausedAt
        }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif
