import Foundation

/// iOS display-layer correction for a computed sleep block whose stored hypnogram includes
/// a leading in-bed / awake period. This is deliberately outside `Packages/StrandAnalytics`:
/// it changes only the iOS readout window and never changes detection, persistence, scoring, or
/// the Android/macOS paths.
enum IOSSleepOnsetResolver {
    struct Segment: Equatable {
        let start: Int
        let end: Int
        let stage: String
    }

    /// Five consecutive minutes of a non-wake hypnogram are required before the iOS screen moves
    /// the displayed "Asleep" marker. This matches the existing staged-onset evidence without
    /// inventing an onset when the stored timeline is absent or all wake.
    static let minimumSustainedSleepSeconds = 5 * 60

    /// Finds the first sustained non-wake run inside a stored computed session.
    ///
    /// The fallback is the detector's original start. A missing timeline, an imported minute-dict,
    /// a gap in the timeline, or an all-wake session therefore remains unchanged.
    static func onset(segments: [Segment], detectedStart: Int, detectedEnd: Int,
                      minimumSeconds: Int = minimumSustainedSleepSeconds) -> Int {
        guard detectedEnd > detectedStart, minimumSeconds > 0 else { return detectedStart }

        var runSeconds = 0
        var runStart: Int?
        var previousEnd = detectedStart

        for segment in segments.sorted(by: { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }) {
            let start = max(detectedStart, segment.start)
            let end = min(detectedEnd, segment.end)
            guard end > start else { continue }

            // A hole is missing evidence, not sleep. Do not let two separated fragments satisfy the
            // persistence rule merely because their timestamps happen to be close in the array.
            if start > previousEnd {
                runSeconds = 0
                runStart = nil
            }

            if isWake(segment.stage) {
                runSeconds = 0
                runStart = nil
            } else {
                if runSeconds == 0 { runStart = start }
                runSeconds += end - start
                if runSeconds >= minimumSeconds, let runStart {
                    return runStart
                }
            }
            previousEnd = max(previousEnd, end)
        }
        return detectedStart
    }

    /// Decode only the computed segment-array format. Imported minute dictionaries intentionally
    /// return nil because they do not contain a real onset timeline.
    static func segments(from stagesJSON: String?) -> [Segment]? {
        guard let stagesJSON, let data = stagesJSON.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !rows.isEmpty else { return nil }

        let decoded = rows.compactMap { row -> Segment? in
            guard let start = (row["start"] as? NSNumber)?.intValue,
                  let end = (row["end"] as? NSNumber)?.intValue,
                  let stage = row["stage"] as? String,
                  end > start else { return nil }
            return Segment(start: start, end: end, stage: stage)
        }
        return decoded.isEmpty ? nil : decoded
    }

    /// Resolve an iOS-only displayed onset from a persisted computed hypnogram.
    static func onset(from stagesJSON: String?, detectedStart: Int, detectedEnd: Int) -> Int {
        guard let segments = segments(from: stagesJSON) else { return detectedStart }
        return onset(segments: segments, detectedStart: detectedStart, detectedEnd: detectedEnd)
    }

    private static func isWake(_ stage: String) -> Bool {
        stage == "wake" || stage == "awake"
    }
}
