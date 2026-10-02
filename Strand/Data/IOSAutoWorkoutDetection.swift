import Foundation
import WhoopProtocol
import StrandAnalytics

/// A user-facing workout suggestion produced by the iOS-only detector.
///
/// The underlying `DetectedWorkout` remains the shared, sport-neutral window type. The iOS
/// confirmation path adds a sport only after the stored HR, motion and activity-class signals agree
/// enough to make a broad suggestion. Nothing is written until the user taps Save.
struct AutoWorkoutSuggestion: Equatable, Sendable {
    let workout: DetectedWorkout
    let sport: String
    let confidence: Double

    var startSec: Int { workout.startSec }
    var endSec: Int { workout.endSec }
    var avgBpm: Int { workout.avgBpm }
    var peakBpm: Int { workout.peakBpm }
    var durationMin: Int { workout.durationMin }
}

/// Conservative iOS auto-detection for locomotion workouts.
///
/// This is deliberately separate from the cross-platform `AutoWorkoutDetector`: that detector is the
/// frozen Android/iOS parity MVP and is intentionally strict and sport-neutral. iOS has enough decoded
/// WHOOP 5/MG activity-class data to make a better user-facing suggestion for walking, running and
/// cycling without changing the shared detector or Android behavior.
///
/// The classifier is advisory. Missing activity-class data never becomes negative evidence, and every
/// candidate still requires a sustained HR window or a sustained classified locomotion window.
enum IOSAutoWorkoutDetector {
    private struct Window: Equatable {
        let start: Int
        let end: Int
        let hint: CoarseWorkoutClass?
    }

    private static let walkMinSeconds = 10 * 60
    private static let runMinSeconds = 8 * 60
    private static let cycleMinSeconds = 12 * 60
    private static let maxClassGapSeconds = 90
    private static let mergeGapSeconds = 5 * 60

    /// Returns newest-first suggestions for walking, running and cycling.
    static func detect(hr: [HRSample], gravity: [GravitySample], steps: [StepSample],
                       restingBpm: Int?, savedSpans: [SavedWorkoutSpan]) -> [AutoWorkoutSuggestion] {
        let sortedHR = hr.sorted { $0.ts < $1.ts }
        guard sortedHR.count >= 2 else { return [] }

        let resting = restingBpm ?? derivedRestingBPM(sortedHR)
        var windows = locomotionWindows(steps, restingBpm: resting, hr: sortedHR)

        // A cycle has no foot-strike class. Use a sustained cardiovascular window and let the existing
        // broad classifier reject gait-like windows. This also catches a WHOOP 4.0 / older 5 capture
        // where @63 activity-class ticks are absent.
        let cardio = sustainedHRWindows(sortedHR, floor: resting + 15,
                                        minimumSeconds: cycleMinSeconds)
        for w in cardio {
            let classCounts = activityClassCounts(steps, start: w.start, end: w.end)
            let gaitFraction = classCounts.walk + classCounts.run
            guard gaitFraction < 0.35 else { continue }
            windows.append(Window(start: w.start, end: w.end, hint: .cycle))
        }

        // WHOOP 4.0 and older captures may have neither usable @63 classes nor a clean cardio window.
        // A motion-backed HR window is a safe fallback for a brisk walk/run, but it never invents a
        // sport from HR alone.
        if !gravity.isEmpty {
            let motion = WorkoutDetector.activitySeries(gravity)
            let motionBacked = sustainedHRWindows(sortedHR, floor: resting + 10,
                                                  minimumSeconds: walkMinSeconds)
            for w in motionBacked {
                let values = motion.filter { $0.ts >= w.start && $0.ts <= w.end }.map(\.intensity)
                let meanMotion = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                guard meanMotion >= 0.02 else { continue }
                let counts = activityClassCounts(steps, start: w.start, end: w.end)
                guard counts.walk + counts.run < 0.35 else { continue }
                windows.append(Window(start: w.start, end: w.end, hint: nil))
            }
        }

        let merged = mergeWindows(windows)
        var suggestions: [AutoWorkoutSuggestion] = []
        for window in merged {
            guard window.end - window.start >= walkMinSeconds else { continue }
            guard !savedSpans.contains(where: {
                overlaps(window.start, window.end, $0.startSec, $0.endSec)
            }) else { continue }

            guard let features = WorkoutTypeFeatureExtractor.extract(
                hr: sortedHR, gravity: gravity, steps: steps,
                start: window.start, end: window.end,
                restingHR: Double(resting), maxHR: nil, caloriesKcal: nil) else { continue }

            let prediction = WorkoutTypeClassifier.classify(features)
            let selected: CoarseWorkoutClass
            if let hint = window.hint, hint == .walk || hint == .run {
                // A decoded @63 gait class is stronger evidence than the fallback shape score. The
                // HR gate above still prevents a low-effort isolated step burst becoming a workout.
                selected = hint
            } else if prediction.predictedClass == .walk || prediction.predictedClass == .run
                        || prediction.predictedClass == .cycle {
                selected = prediction.predictedClass
            } else {
                continue
            }

            let minimum = selected == .run ? runMinSeconds :
                (selected == .cycle ? cycleMinSeconds : walkMinSeconds)
            guard window.end - window.start >= minimum else { continue }

            let hrWindow = sortedHR.filter { $0.ts >= window.start && $0.ts <= window.end }
            guard !hrWindow.isEmpty else { continue }
            let bpms = hrWindow.map(\.bpm)
            let average = Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded())
            let detected = DetectedWorkout(
                startSec: window.start, endSec: window.end,
                avgBpm: average, peakBpm: bpms.max() ?? average,
                durationMin: max(1, (window.end - window.start) / 60))
            suggestions.append(AutoWorkoutSuggestion(
                workout: detected, sport: sportName(selected),
                confidence: max(0, min(1, prediction.confidence))))
        }

        // One suggestion per overlapping activity window. Preserve the strongest/latest candidate so a
        // walk window and its HR-only fallback cannot produce duplicate cards.
        var byKey: [String: AutoWorkoutSuggestion] = [:]
        for suggestion in suggestions {
            let key = "\(suggestion.startSec):\(suggestion.endSec)"
            if let old = byKey[key], old.confidence >= suggestion.confidence { continue }
            byKey[key] = suggestion
        }
        return byKey.values.sorted { $0.startSec > $1.startSec }
    }

    private static func sportName(_ activity: CoarseWorkoutClass) -> String {
        switch activity {
        case .walk: return "Walking"
        case .run: return "Running"
        case .cycle: return "Cycling"
        default: return "Workout"
        }
    }

    private static func overlaps(_ start: Int, _ end: Int, _ otherStart: Int, _ otherEnd: Int) -> Bool {
        start < otherEnd && otherStart < end
    }

    private static func derivedRestingBPM(_ hr: [HRSample]) -> Int {
        let values = hr.map(\.bpm).sorted()
        guard !values.isEmpty else { return 60 }
        let index = min(values.count - 1, max(0, Int(ceil(Double(values.count) * 0.10)) - 1))
        return values[index]
    }

    private static func locomotionWindows(_ steps: [StepSample], restingBpm: Int,
                                          hr: [HRSample]) -> [Window] {
        let classified = steps.filter { $0.activityClass == 1 || $0.activityClass == 2 }
            .sorted { $0.ts < $1.ts }
        guard !classified.isEmpty else { return [] }

        var result: [Window] = []
        var start = classified[0].ts
        var end = start
        var currentClass = classified[0].activityClass!

        func close() {
            let duration = end - start
            let minimum = currentClass == 2 ? runMinSeconds : walkMinSeconds
            guard duration >= minimum else { return }
            let sample = hr.filter { $0.ts >= start && $0.ts <= end }
            guard !sample.isEmpty else { return }
            let mean = Double(sample.map(\.bpm).reduce(0, +)) / Double(sample.count)
            let elevated = sample.filter { $0.bpm >= restingBpm + (currentClass == 2 ? 18 : 10) }.count
            let elevatedFraction = Double(elevated) / Double(sample.count)
            guard mean >= Double(restingBpm + (currentClass == 2 ? 15 : 8)) || elevatedFraction >= 0.35 else {
                return
            }
            result.append(Window(start: start, end: end,
                                 hint: currentClass == 2 ? .run : .walk))
        }

        for tick in classified.dropFirst() {
            let activity = tick.activityClass!
            if tick.ts - end > maxClassGapSeconds || activity != currentClass {
                close()
                start = tick.ts
                currentClass = activity
            }
            end = tick.ts
        }
        close()
        return result
    }

    private static func sustainedHRWindows(_ hr: [HRSample], floor: Int,
                                           minimumSeconds: Int) -> [(start: Int, end: Int)] {
        var result: [(start: Int, end: Int)] = []
        var start: Int?
        var end = 0
        var dipStart: Int?

        func close() {
            if let start, end - start >= minimumSeconds {
                result.append((start: start, end: end))
            }
        }

        for sample in hr {
            if sample.bpm >= floor {
                if start == nil { start = sample.ts }
                end = sample.ts
                dipStart = nil
            } else if start != nil {
                if dipStart == nil { dipStart = sample.ts }
                if let dip = dipStart, sample.ts - dip > 90 {
                    close()
                    start = nil
                    dipStart = nil
                }
            }
        }
        close()
        return result
    }

    private static func activityClassCounts(_ steps: [StepSample], start: Int, end: Int)
        -> (still: Double, walk: Double, run: Double) {
        let classes = steps.filter { $0.ts >= start && $0.ts <= end }
            .compactMap(\.activityClass)
        guard !classes.isEmpty else { return (0, 0, 0) }
        let n = Double(classes.count)
        return (
            Double(classes.filter { $0 == 0 }.count) / n,
            Double(classes.filter { $0 == 1 }.count) / n,
            Double(classes.filter { $0 == 2 }.count) / n)
    }

    private static func mergeWindows(_ windows: [Window]) -> [Window] {
        guard !windows.isEmpty else { return [] }
        let sorted = windows.sorted { $0.start < $1.start }
        var result: [Window] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.start - current.end <= mergeGapSeconds {
                let hint = current.hint == next.hint ? current.hint : (current.hint ?? next.hint)
                current = Window(start: min(current.start, next.start), end: max(current.end, next.end), hint: hint)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}
