import Foundation

/// The decision behind the early wake: given what the night holds so far, should the strap buzz now, before the wake time that is already armed on it?
///
/// The armed wake time stays the guarantee: this only ever brings the buzz forward, inside the hour before that time, and says nothing when the data
/// is too old to judge. The night is read from the same one-day analysis the scores come from, on whatever the strap has handed over so far, so both
/// "sleep so far" and "Recovery so far" are estimates that later data can move.
public enum SmartWake {
    public enum Mode: String, Sendable {
        /// Wake at the set time only.
        case exact
        /// Wake once the sleep so far reaches the chosen share of the sleep need.
        case goal
        /// Wake once Recovery, worked out on the night so far, is green.
        case green
    }

    /// How long before the wake time the early wake may fire.
    public static let windowSeconds: TimeInterval = 3600
    /// Data older than this says nothing about now.
    public static let freshSeconds: TimeInterval = 20 * 60
    /// In the last minutes the strap's own alarm is about to fire, so nothing is brought forward.
    public static let stopBeforeSeconds: TimeInterval = 120
    /// Green Recovery, in whole percent.
    public static let greenRecovery = 67.0
    /// A green reading from a short stretch of sleep is not trusted: at least this much sleep first.
    public static let greenMinimumAsleepMin = 240.0

    /// What the night holds so far.
    public struct Night: Equatable, Sendable {
        public let asleepMin: Double
        public let recovery: Double?
        /// The time of the newest heart-rate sample the figures were worked out from.
        public let dataEnd: Date
        public init(asleepMin: Double, recovery: Double?, dataEnd: Date) {
            self.asleepMin = asleepMin; self.recovery = recovery; self.dataEnd = dataEnd
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Not the moment to judge: exact mode, or outside the window.
        case idle
        /// Inside the window with nothing recent enough to judge.
        case needData
        /// Judged, and the target is not reached yet.
        case keepSleeping
        /// The target is reached: buzz now.
        case wake
    }

    /// Whether `now` is inside the window before `latest`.
    public static func inWindow(now: Date, latest: Date) -> Bool {
        let left = latest.timeIntervalSince(now)
        return left <= windowSeconds && left > stopBeforeSeconds
    }

    public static func decide(now: Date, latest: Date, mode: Mode, needMin: Double, goalPercent: Int, night: Night?) -> Decision {
        guard mode != .exact, inWindow(now: now, latest: latest) else { return .idle }
        guard let night, now.timeIntervalSince(night.dataEnd) <= freshSeconds else { return .needData }
        switch mode {
        case .exact:
            return .idle
        case .goal:
            let target = needMin * Double(goalPercent) / 100
            return target > 0 && night.asleepMin >= target ? .wake : .keepSleeping
        case .green:
            guard night.asleepMin >= greenMinimumAsleepMin, let r = night.recovery else { return .keepSleeping }
            return r.rounded() >= greenRecovery ? .wake : .keepSleeping
        }
    }
}
