import Foundation

/// End a detected night where the strap stopped recording, not where the session happened to end.
///
/// A session can run past the last sleep because the detector closes it when the next data arrives. When the strap was off the
/// wrist or had not synced, everything in between is a stretch with no recording, and staging it as wake puts the person in bed
/// long after they got up (a night that ended at 05:52 stored as ending 06:24, 32 minutes of "awake" that nothing measured).
///
/// The signal is the movement series itself: movement the strap measures is never exactly zero, so a run of exact zeros on the
/// session's own 30 s grid is a stretch with no recording. A night is trimmed only when such a run, of at least `minGapEpochs`
/// epochs, starts within `reachS` of the last sleep. It is then cut at the last sleep, keeping at most `graceS` of wake.
/// Awake time the strap did record (any movement) and gaps in the middle of a night are left alone.
///
/// Pure and deterministic, so it is unit-tested directly. The Kotlin twin has not been changed.
public enum SleepTailTrim {
    public static let epochS = 30
    /// 10 minutes of exact zeros.
    public static let minGapEpochs = 20
    /// The gap has to start this soon after the last sleep.
    public static let reachS = 600
    /// Wake kept after the last sleep.
    public static let graceS = 300

    /// `motion[i]` is the movement of `[start + 30 i, start + 30 (i + 1))`, as `SleepStager.sessionEpochMotion` returns it.
    public static func trimmed(_ s: SleepSession, motion: [Double]) -> SleepSession {
        guard !motion.isEmpty,
              let lastSleep = s.stages.filter({ !SleepStageVocabulary.isWake($0.stage) }).map(\.end).max(),
              s.end > lastSleep + graceS else { return s }
        var run = 0
        var runStart = 0
        var i = max(0, (lastSleep - s.start) / epochS - 1)
        while i < motion.count {
            if motion[i] == 0 {
                if run == 0 { runStart = s.start + i * epochS }
                run += 1
                if run >= minGapEpochs {
                    guard runStart <= lastSleep + reachS else { return s }
                    return cut(s, at: min(max(runStart, lastSleep), lastSleep + graceS))
                }
            } else {
                run = 0
            }
            i += 1
        }
        return s
    }

    private static func cut(_ s: SleepSession, at end: Int) -> SleepSession {
        guard end > s.start, end < s.end else { return s }
        let stages: [StageSegment] = s.stages.compactMap { seg in
            guard seg.start < end else { return nil }
            return StageSegment(start: seg.start, end: min(seg.end, end), stage: seg.stage)
        }
        return SleepSession(start: s.start, end: end,
                            efficiency: SleepStager.efficiency(start: s.start, end: end, stages: stages),
                            stages: stages, restingHR: s.restingHR, avgHRV: s.avgHRV, hrOnly: s.hrOnly)
    }
}
