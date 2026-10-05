#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for a running Lift Log session — the minimised session bar, on the Lock
/// Screen and in the Dynamic Island.
///
/// Deliberately a SEPARATE activity type from `NOOPActivityAttributes` (live HR). They answer
/// different questions and have different lifetimes: the HR activity lives as long as the strap is
/// streaming, this one as long as a gym session is open. While a session is running this one is the
/// useful surface — it carries the heart rate too — so the app suppresses the HR activity rather
/// than stacking two banners on the Lock Screen.
///
/// TIME IS CARRIED AS DATES, NOT AS A FORMATTED STRING. The widget renders them with
/// `Text(timerInterval:)`, which ticks on its own without the app pushing anything. Pushing a new
/// content state every second to animate a clock would burn the Live Activity update budget and
/// still look worse.
public struct LiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Amber rest vs green working — the same colour language as the sheet and the bar.
        public var isResting: Bool
        /// The exercise being worked, or rested from.
        public var exercise: String
        /// "Set 2" / "Resting after set 2" — resolved app-side so the wording matches the bar.
        public var status: String
        /// "8 x 30 kg", already unit-converted, because the unit preference lives in the app.
        /// Nil when neither reps nor weight is known.
        public var detail: String?
        public var bpm: Int?
        /// "3 of 19 sets done", localized APP-SIDE. The widget extension ships no string catalog, so
        /// every word it renders has to arrive already translated — the same reason `status` and
        /// `detail` are strings rather than numbers.
        public var progress: String
        /// Live HR zone resolved in the app from the user's HR-zone set.
        public var heartRateZone: Int?
        /// Pre-formatted workout metrics; nil means no live GPS/sensor reading exists yet.
        public var distance: String?
        public var speed: String?
        /// When the current stage began — the widget counts UP from here while working.
        public var stageStartedAt: Date
        /// When the running rest is due to end; the widget counts DOWN to it. Nil while working.
        public var restEndsAt: Date?
        /// When the whole session began, for the session clock (the two dates above are per stage).
        public var sessionStartedAt: Date?
        /// Working sets finished, and planned, as numbers for the "Set 7 / 13" figure.
        public var setsDone: Int?
        public var setsPlanned: Int?
        /// Lifted volume so far (weight x reps over the finished working sets), already unit-converted and formatted.
        public var volume: String?
        /// Effort built so far by the session's heart rate, on NOOP's 0-100 axis.
        public var effort: Int?
        /// Where the heart rate sits across the five-zone bar, 0 to 1.
        public var zonePosition: Double?
        /// Effort as the app shows it (the user's scale, one decimal). Takes the place of `effort` when present.
        public var effortLabel: String?

        public init(isResting: Bool, exercise: String, status: String, detail: String?,
                    bpm: Int?, progress: String,
                    stageStartedAt: Date, restEndsAt: Date?, heartRateZone: Int? = nil,
                    distance: String? = nil, speed: String? = nil,
                    sessionStartedAt: Date? = nil, setsDone: Int? = nil, setsPlanned: Int? = nil,
                    volume: String? = nil, effort: Int? = nil, zonePosition: Double? = nil, effortLabel: String? = nil) {
            self.effortLabel = effortLabel
            self.sessionStartedAt = sessionStartedAt
            self.setsDone = setsDone
            self.setsPlanned = setsPlanned
            self.volume = volume
            self.effort = effort
            self.zonePosition = zonePosition
            self.isResting = isResting
            self.exercise = exercise
            self.status = status
            self.detail = detail
            self.bpm = bpm
            self.progress = progress
            self.stageStartedAt = stageStartedAt
            self.restEndsAt = restEndsAt
            self.heartRateZone = heartRateZone
            self.distance = distance
            self.speed = speed
        }
    }

    /// The program's name, fixed for the life of the session.
    public var programName: String

    public init(programName: String) {
        self.programName = programName
    }
}
#endif
