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
    /// When the detector could not name the sport with confidence, the three it finds most likely (best first), so the person can
    /// pick the closest one. Empty when the sport is named.
    var alternatives: [String] = []

    /// The same window saved under another sport (one of `alternatives`, chosen by the person).
    func withSport(_ name: String) -> AutoWorkoutSuggestion {
        AutoWorkoutSuggestion(workout: workout, sport: name, confidence: confidence)
    }

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
    /// What a suggestion is called when the evidence does not support a specific sport.
    static let genericSport = "Workout"
    /// A walking or running label from the shape classifier (not from a gait tick) needs at least this confidence.
    private static let minLabelConfidence = 0.5
    /// Cycling needs more: at least this confidence, and decoded ticks that are mostly "still".
    private static let minCycleConfidence = 0.55
    private static let minStillFractionForCycling = 0.6
    /// Strength is named only when the heart rate is clearly saw-toothed (sets then rest) and the classifier is confident.
    private static let minStrengthConfidence = 0.5
    private static let minStrengthHrCV = 0.10
    /// Past this peak (%HRR) a saw-toothed session is intervals (HIIT), not sets of lifts.
    private static let maxStrengthPeakHRR = 85.0
    /// A sport the person has saved at least this many times (90 days) is one they do; cycling is named only for them.
    private static let minHistoryToName = 2
    private static let cyclingNames: Set<String> = ["Cycling", "Indoor cycle"]
    private static let strengthNames: Set<String> = ["Strength", "Weightlifting", "Bodybuilding", "Strength Training"]
    /// A window with no gait to show for it (cycling, strength, unnamed) must be effort, not stress: the mean heart rate sits at
    /// least this far up the reserve (Karvonen %HRR). A seated presentation, a drive or a hard meeting stays below it.
    static let minEffortHRRPct = 35.0
    /// The HRmax used when the caller has none (the profile's value is passed from the repository).
    static let fallbackMaxBpm = 190
    private static let maxClassGapSeconds = 90
    private static let mergeGapSeconds = 5 * 60

    /// Returns newest-first suggestions for walking, running and cycling.
    static func detect(hr: [HRSample], gravity: [GravitySample], steps: [StepSample],
                       restingBpm: Int?, maxBpm: Int? = nil, userSports: [String: Int] = [:],
                       savedSpans: [SavedWorkoutSpan]) -> [AutoWorkoutSuggestion] {
        let sortedHR = hr.sorted { $0.ts < $1.ts }
        guard sortedHR.count >= 2 else { return [] }

        let resting = restingBpm ?? derivedRestingBPM(sortedHR)
        // HRmax from the profile. The extractor used to derive it from the window's own samples, which makes the reserve tiny for
        // a calm window and reads a drive or a meeting as a high %HRR.
        let maxHR = Double(max(maxBpm ?? fallbackMaxBpm, resting + 40))
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
            guard window.end - window.start >= runMinSeconds else { continue }
            guard !savedSpans.contains(where: {
                overlaps(window.start, window.end, $0.startSec, $0.endSec)
            }) else { continue }

            guard let features = WorkoutTypeFeatureExtractor.extract(
                hr: sortedHR, gravity: gravity, steps: steps,
                start: window.start, end: window.end,
                restingHR: Double(resting), maxHR: maxHR, caloriesKcal: nil) else { continue }

            let prediction = WorkoutTypeClassifier.classify(features)
            // A specific label is given only on positive evidence; otherwise the suggestion stays generic ("Workout") and the
            // person names it. Guessing is worse than not naming: a steady, low-motion, elevated heart rate is true of an
            // elliptical, a row, a class or a stretch of housework, and it used to be read as cycling.
            let selected: CoarseWorkoutClass?
            if let hint = window.hint, hint == .walk || hint == .run {
                // A decoded @63 gait class is stronger evidence than the fallback shape score. The
                // HR gate above still prevents a low-effort isolated step burst becoming a workout.
                selected = hint
            } else {
                switch prediction.predictedClass {
                case .walk, .run:
                    selected = prediction.confidence >= minLabelConfidence ? prediction.predictedClass : nil
                case .cycle:
                    // Not seeing steps is not seeing a bike. Steady effort with no foot strikes is true of an elliptical, a row or a
                    // class as much as of a bike, and the strap has no speed or position to tell them apart. So cycling is named
                    // only when the ticks do see no gait, the classifier is confident AND this person actually cycles: they have
                    // saved cycling before. Otherwise the suggestion stays generic and offers their own sports first.
                    let seesNoGait = features.tickCoverage >= WorkoutTypeClassifier.minTickCoverage
                        && features.stillFraction >= minStillFractionForCycling
                    let cycleCount = historyCount(userSports, group: cyclingNames)
                    let otherGaitless = userSports.filter { !cyclingNames.contains($0.key) && !["Walking", "Running", "Hiking", genericSport, "Other"].contains($0.key) }
                        .values.max() ?? 0
                    // Cycling must be what this person does most of the time when there is no gait, not just something they did.
                    let cycles = cycleCount >= minHistoryToName && cycleCount >= otherGaitless
                    selected = (seesNoGait && cycles && prediction.confidence >= minCycleConfidence) ? .cycle : nil
                case .strength:
                    // Sets then rest: a saw-toothed heart rate with no gait through it, and not so high that it is intervals.
                    let seesNoGait = features.tickCoverage >= WorkoutTypeClassifier.minTickCoverage
                        && features.stillFraction >= minStillFractionForCycling
                    let peakHRR = peakHRRPct(features, resting: resting, maxHR: maxHR)
                    selected = (seesNoGait && features.hrCV >= minStrengthHrCV && peakHRR <= maxStrengthPeakHRR
                                && prediction.confidence >= minStrengthConfidence) ? .strength : nil
                default:
                    selected = nil
                }
                // No label, and not a sustained cardio window either: nothing to suggest.
                if selected == nil, window.hint != .cycle { continue }
                // Without a gait to show for it, the window must also be effort and not stress or a drive.
                if selected == nil || selected == .cycle || selected == .strength {
                    guard let hrr = features.meanHRRPct, hrr >= minEffortHRRPct else { continue }
                }
            }

            let minimum = selected == .run ? runMinSeconds :
                (selected == nil || selected == .cycle || selected == .strength ? cycleMinSeconds : walkMinSeconds)
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
                workout: detected, sport: selected.map { sportName($0, userSports: userSports) } ?? genericSport,
                confidence: max(0, min(1, prediction.confidence)),
                alternatives: selected == nil ? topAlternatives(prediction, features: features, userSports: userSports) : []))
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

    /// The three most likely sports when none could be named with confidence (the same rule WHOOP states for an activity it cannot
    /// classify). The classifier is coarse, so each class stands for the catalogue sport people most often mean by it. Three things
    /// shape the order: ticks that saw no gait rule out walking and running; cycling is offered when the ticks could have seen a
    /// gait or when the person has saved cycling before; and the sports the person logs themselves (elliptical, rowing, yoga…)
    /// rank among the classes, because a manual log is the best label the strap will ever get.
    private static func topAlternatives(_ prediction: WorkoutClassPrediction, features: WorkoutClassFeatures,
                                        userSports: [String: Int]) -> [String] {
        let seesGait = features.tickCoverage >= WorkoutTypeClassifier.minTickCoverage
        let noGait = seesGait && features.stillFraction >= minStillFractionForCycling
        let cycleCount = historyCount(userSports, group: cyclingNames)
        let strengthCount = historyCount(userSports, group: strengthNames)
        var scored: [(name: String, score: Double)] = []

        func add(_ cls: CoarseWorkoutClass, _ name: String, history: Int) {
            guard let base = prediction.scores[cls] else { return }
            scored.append((name, base + 1.0 * min(1, Double(history) / 5)))
        }
        if !noGait {
            add(.walk, "Walking", history: userSports["Walking", default: 0])
            add(.run, "Running", history: userSports["Running", default: 0])
        }
        if seesGait || cycleCount > 0 { add(.cycle, favourite(userSports, group: cyclingNames, fallback: "Cycling"), history: cycleCount) }
        add(.strength, favourite(userSports, group: strengthNames, fallback: "Strength"), history: strengthCount)
        if userSports["Skiing", default: 0] > 0 { add(.ski, "Skiing", history: userSports["Skiing", default: 0]) }

        // What the person logs that has no class of its own.
        let known = Set(["Walking", "Running", "Skiing"]).union(cyclingNames).union(strengthNames)
        for (name, n) in userSports where n >= minHistoryToName && !known.contains(name) && name != genericSport && name != "Other" {
            scored.append((name, 0.6 + 1.0 * min(1, Double(n) / 5)))
        }

        var out: [String] = []
        for item in scored.sorted(by: { $0.score > $1.score || ($0.score == $1.score && $0.name < $1.name) }) {
            if !out.contains(item.name) { out.append(item.name) }
            if out.count == 3 { break }
        }
        // Three to pick from, always. Effort with no gait is, in practice, one of a handful of indoor or gym sports.
        for filler in ["HIIT", "Elliptical", "Row machine", "Indoor cycle"] where out.count < 3 && !out.contains(filler) {
            out.append(filler)
        }
        return out
    }

    /// How many saved sessions of a group of sport names the person has.
    private static func historyCount(_ sports: [String: Int], group: Set<String>) -> Int {
        sports.reduce(0) { $0 + (group.contains($1.key) ? $1.value : 0) }
    }

    /// The group's member the person saves most, or `fallback` when they have none.
    private static func favourite(_ sports: [String: Int], group: Set<String>, fallback: String) -> String {
        group.filter { sports[$0, default: 0] > 0 }
            .sorted { (sports[$0, default: 0], $1) > (sports[$1, default: 0], $0) }
            .first ?? fallback
    }

    private static func peakHRRPct(_ f: WorkoutClassFeatures, resting: Int, maxHR: Double) -> Double {
        let reserve = maxHR - Double(resting)
        guard reserve > 0 else { return 100 }
        return min(100, max(0, (Double(f.peakHR) - Double(resting)) / reserve * 100))
    }

    private static func sportName(_ activity: CoarseWorkoutClass, userSports: [String: Int]) -> String {
        switch activity {
        case .walk: return "Walking"
        case .run: return "Running"
        case .cycle: return favourite(userSports, group: cyclingNames, fallback: "Cycling")
        case .strength: return favourite(userSports, group: strengthNames, fallback: "Strength")
        default: return genericSport
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

    /// Stretches of decoded walking or running ticks, joined across short gaps and across the switch between the two, so an
    /// interval session (two minutes running, two walking) is one window and not a string of pieces that are each too short.
    /// The window is a run when at least a third of its gait ticks read run.
    private static func locomotionWindows(_ steps: [StepSample], restingBpm: Int,
                                          hr: [HRSample]) -> [Window] {
        let classified = steps.filter { $0.activityClass == 1 || $0.activityClass == 2 }
            .sorted { $0.ts < $1.ts }
        guard !classified.isEmpty else { return [] }

        var result: [Window] = []
        var start = classified[0].ts
        var end = start
        var runTicks = classified[0].activityClass == 2 ? 1 : 0
        var walkTicks = 1 - runTicks

        func close() {
            let isRun = Double(runTicks) / Double(max(1, runTicks + walkTicks)) >= 0.35
            let duration = end - start
            let minimum = isRun ? runMinSeconds : walkMinSeconds
            guard duration >= minimum else { return }
            let sample = hr.filter { $0.ts >= start && $0.ts <= end }
            guard !sample.isEmpty else { return }
            let mean = Double(sample.map(\.bpm).reduce(0, +)) / Double(sample.count)
            let elevated = sample.filter { $0.bpm >= restingBpm + (isRun ? 18 : 10) }.count
            let elevatedFraction = Double(elevated) / Double(sample.count)
            guard mean >= Double(restingBpm + (isRun ? 15 : 8)) || elevatedFraction >= 0.35 else {
                return
            }
            result.append(Window(start: start, end: end, hint: isRun ? .run : .walk))
        }

        for tick in classified.dropFirst() {
            if tick.ts - end > maxClassGapSeconds {
                close()
                start = tick.ts
                runTicks = 0; walkTicks = 0
            }
            if tick.activityClass == 2 { runTicks += 1 } else { walkTicks += 1 }
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
