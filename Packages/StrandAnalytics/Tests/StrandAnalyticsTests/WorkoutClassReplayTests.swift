import XCTest
import WhoopStore
@testable import StrandAnalytics

/// Tests for the label side of auto-detect learning prep: the sport-name map, label provenance and the replay report.
/// The replay is exercised with several distinct injected shapes per class (the CLAUDE.md derived-signal rule), a classifier that is wrong on
/// purpose so the report is shown to SEE a miss, and a swapped-in classifier to prove the same code can measure a future model.
final class WorkoutClassReplayTests: XCTestCase {

    // MARK: - Sport name → class

    func testSportNamesMapToTheirClass() {
        let cases: [(String, CoarseWorkoutClass)] = [
            ("Running", .run), ("Treadmill run", .run), ("jogging", .run),
            ("Walking", .walk), ("Treadmill walk", .walk), ("Hiking", .walk), ("Nordic walking", .walk), ("Rucking", .walk),
            ("Cycling", .cycle), ("Indoor cycle", .cycle), ("Mountain biking", .cycle), ("Spinning", .cycle),
            ("Strength", .strength), ("Weightlifting", .strength), ("Powerlifting", .strength), ("Bodybuilding", .strength),
            ("Skiing", .ski), ("Snowboarding", .ski),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: name), expected, name)
        }
    }

    func testOtherRealSportsAreOtherNotNil() {
        for name in ["Yoga", "Boxing", "Tennis", "Basketball", "Skateboarding", "Ice skating", "Calisthenics", "Bikram yoga", "Stair climber", "Jump rope"] {
            XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: name), .other, "\(name) is a real sport outside the five")
        }
    }

    func testMatchingIsByWholeWordNotPrefix() {
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Bikram yoga"), .other, "bikram is not a bike")
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Basketball"), .other, "basketball is not skiing")
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Spikeball"), .other, "spikeball is not spinning")
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Running-back drills"), .run, "a whole word 'running' still counts, hyphen or not")
    }

    func testCrossCountryAndNordicSkiingAreNotDownhill() {
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Cross-country skiing"), .other)
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Nordic skiing"), .other)
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Ski touring"), .other)
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "Downhill skiing"), .ski)
    }

    func testGenericNamesAreNotLabels() {
        for name in ["", "  ", "Workout", "workout", "Other", "detected", "Activity", "Session"] {
            XCTAssertNil(WorkoutSportMap.coarseClass(forSport: name), "'\(name)' says nothing about the sport")
            XCTAssertTrue(WorkoutSportMap.isGeneric(name))
        }
        XCTAssertFalse(WorkoutSportMap.isGeneric("Running"))
    }

    func testAmbiguousNameIsNotLabelledEitherWay() {
        XCTAssertNil(WorkoutSportMap.coarseClass(forSport: "Run and bike"))
        XCTAssertNil(WorkoutSportMap.coarseClass(forSport: "Walk + strength"))
    }

    func testCaseAndPunctuationDoNotMatter() {
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "  RUNNING "), .run)
        XCTAssertEqual(WorkoutSportMap.coarseClass(forSport: "indoor-cycle"), .cycle)
    }

    // MARK: - Label provenance

    private func suggestion(start: Int, outcome: WorkoutSuggestionOutcome, predicted: String = "Running", saved: String? = nil) -> WorkoutSuggestionRow {
        WorkoutSuggestionRow(id: "d:\(start):\(start + 1800)", deviceId: "d", startSec: start, endSec: start + 1800, createdAt: start + 1900,
                             predictedSport: predicted, predictedClass: "run", confidence: 0.7, scoresJSON: nil, featuresJSON: nil,
                             outcome: outcome.rawValue, outcomeAt: start + 2000, savedSport: saved)
    }

    func testManualRowWithNoSuggestionIsTypedByThePerson() {
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000)
        XCTAssertEqual(o, .typedByPerson)
        XCTAssertTrue(o.isLabel(includeBeforeLog: false))
    }

    func testManualRowSavedFromASuggestionIsTheDetectorsOwnGuess() {
        let s = suggestion(start: 10_000, outcome: .saved, saved: "Running")
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(o, .savedFromSuggestion)
        XCTAssertFalse(o.isLabel(includeBeforeLog: true), "a saved suggestion is not ground truth, not even when pre-log rows are accepted")
    }

    func testChangingTheSportAfterSavingIsACorrection() {
        let s = suggestion(start: 10_000, outcome: .saved, saved: "Running")
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Hiking", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(o, .editedAfterSuggestion)
        XCTAssertTrue(o.isLabel(includeBeforeLog: false))
    }

    func testPickingAnotherSportFromTheAlternativesAtSaveTimeIsThePersonsWord() {
        // The card offered "Workout" and three alternatives; the person saved it as "Hiking". The row says Hiking, the log says Workout was offered.
        let s = suggestion(start: 10_000, outcome: .saved, predicted: "Workout", saved: "Hiking")
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Hiking", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(o, .editedAfterSuggestion)
        XCTAssertTrue(o.isLabel(includeBeforeLog: false))
    }

    func testRenamingAfterSavingAsOfferedIsACorrectionToo() {
        let s = suggestion(start: 10_000, outcome: .saved, predicted: "Running", saved: "Running")
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Trail running", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(o, .editedAfterSuggestion)
    }

    func testSportComparisonIgnoresCaseAndSpaces() {
        let s = suggestion(start: 10_000, outcome: .saved, predicted: "Indoor cycle", saved: "Indoor cycle")
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: " indoor CYCLE ", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(o, .savedFromSuggestion)
    }

    func testStartMayDifferByTheToleranceButNotMore() {
        let s = suggestion(start: 10_000, outcome: .saved, saved: "Running")
        let near = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000 + WorkoutLabelProvenance.startToleranceSec,
                                                 suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(near, .savedFromSuggestion)
        let far = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000 + WorkoutLabelProvenance.startToleranceSec + 1,
                                                suggestions: [s], logStartedAt: 5_000)
        XCTAssertEqual(far, .typedByPerson, "a different workout that merely starts near a suggestion is not that suggestion")
    }

    func testOnlySavedSuggestionsMatch() {
        for outcome in [WorkoutSuggestionOutcome.pending, .dismissed] {
            let s = suggestion(start: 10_000, outcome: outcome)
            let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [s], logStartedAt: 5_000)
            XCTAssertEqual(o, .typedByPerson, "a \(outcome.rawValue) suggestion produced no row, so a typed one beside it is the person's")
        }
    }

    func testManualRowBeforeTheLogCannotBeAttributed() {
        let before = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 4_000, suggestions: [], logStartedAt: 5_000)
        XCTAssertEqual(before, .manualBeforeLog)
        XCTAssertFalse(before.isLabel(includeBeforeLog: false))
        XCTAssertTrue(before.isLabel(includeBeforeLog: true))
        let noLogYet = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 9_000, suggestions: [], logStartedAt: nil)
        XCTAssertEqual(noLogYet, .manualBeforeLog, "with no log at all nothing can be told apart")
    }

    func testOtherSourcesAreClassifiedBySource() {
        func o(_ s: WorkoutLabelSource) -> WorkoutLabelOrigin {
            WorkoutLabelProvenance.origin(source: s, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000)
        }
        XCTAssertEqual(o(.apple), .imported)
        XCTAssertEqual(o(.lifting), .imported)
        XCTAssertEqual(o(.activityFile), .imported)
        XCTAssertEqual(o(.whoop), .strapOwn)
        XCTAssertEqual(o(.detected), .legacyDetected)
        XCTAssertFalse(WorkoutLabelOrigin.strapOwn.isLabel(includeBeforeLog: true))
        XCTAssertFalse(WorkoutLabelOrigin.legacyDetected.isLabel(includeBeforeLog: true))
        XCTAssertTrue(WorkoutLabelOrigin.imported.isLabel(includeBeforeLog: false))
    }

    func testEveryOriginIsDecidedForAndOnlyTheListedOnesAreLabels() {
        let labels = WorkoutLabelOrigin.allCases.filter { $0.isLabel(includeBeforeLog: false) }
        XCTAssertEqual(Set(labels), [.typedByPerson, .editedAfterSuggestion, .imported])
    }

    // MARK: - Replay

    private func f(durationMin: Double = 30, meanHR: Double, peakHR: Int, hrr: Double?, hrCV: Double, still: Double = 0, walk: Double = 0, run: Double = 0,
                   ticks: Double = 0, motionVar: Double, kcal: Double?) -> WorkoutClassFeatures {
        WorkoutClassFeatures(durationSec: durationMin * 60, meanHR: meanHR, peakHR: peakHR, meanHRRPct: hrr, hrCV: hrCV, stillFraction: still,
                             walkFraction: walk, runFraction: run, tickCoverage: ticks, motionVariance: motionVar, motionCV: 0.5, kcalPerMin: kcal)
    }

    /// Two distinct shapes for each of the five classes (the same ones the classifier's own tests prove it recovers).
    private func labelled() -> [LabelledWorkoutWindow] {
        [
            .init(id: "run1", label: .run, features: f(meanHR: 155, peakHR: 168, hrr: 70, hrCV: 0.04, still: 0.05, walk: 0.1, run: 0.8, ticks: 0.9, motionVar: 0.20, kcal: 11)),
            .init(id: "run2", label: .run, features: f(meanHR: 160, peakHR: 172, hrr: 72, hrCV: 0.03, motionVar: 0.25, kcal: 12)),
            .init(id: "walk1", label: .walk, features: f(meanHR: 96, peakHR: 104, hrr: 22, hrCV: 0.05, still: 0.1, walk: 0.85, run: 0.05, ticks: 0.9, motionVar: 0.03, kcal: 3.5)),
            .init(id: "walk2", label: .walk, features: f(meanHR: 118, peakHR: 128, hrr: 38, hrCV: 0.04, still: 0.05, walk: 0.9, run: 0.05, ticks: 0.85, motionVar: 0.05, kcal: 5)),
            .init(id: "str1", label: .strength, features: f(meanHR: 140, peakHR: 172, hrr: 65, hrCV: 0.18, still: 0.85, walk: 0.05, run: 0.05, ticks: 0.9, motionVar: 0.03, kcal: 5)),
            .init(id: "str2", label: .strength, features: f(meanHR: 110, peakHR: 145, hrr: 42, hrCV: 0.14, still: 0.8, walk: 0.1, run: 0.1, ticks: 0.7, motionVar: 0.02, kcal: 4)),
            .init(id: "cyc1", label: .cycle, features: f(meanHR: 145, peakHR: 158, hrr: 60, hrCV: 0.03, still: 0.9, walk: 0.05, run: 0.05, ticks: 0.9, motionVar: 0.015, kcal: 9)),
            .init(id: "cyc2", label: .cycle, features: f(meanHR: 120, peakHR: 132, hrr: 40, hrCV: 0.04, motionVar: 0.01, kcal: 6)),
            .init(id: "ski1", label: .ski, features: f(durationMin: 120, meanHR: 128, peakHR: 165, hrr: 55, hrCV: 0.16, still: 0.85, walk: 0.1, run: 0.05, ticks: 0.6, motionVar: 0.25, kcal: 7)),
            .init(id: "ski2", label: .ski, features: f(durationMin: 150, meanHR: 108, peakHR: 150, hrr: 38, hrCV: 0.14, still: 0.85, walk: 0.1, run: 0.05, ticks: 0.5, motionVar: 0.20, kcal: 5)),
        ]
    }

    func testReplayRecoversEveryInjectedShapeNotJustOne() {
        let report = WorkoutClassReplay.evaluate(labelled())
        XCTAssertEqual(report.total, 10)
        for c in [CoarseWorkoutClass.walk, .run, .strength, .cycle, .ski] {
            XCTAssertEqual(report.labelCounts[c], 2)
            XCTAssertEqual(report.confusion[c]?[c], 2, "\(c) should be recovered for both injected shapes; row: \(String(describing: report.confusion[c]))")
            XCTAssertEqual(report.recall(c) ?? -1, 1.0, accuracy: 1e-9)
            XCTAssertEqual(report.precision(c) ?? -1, 1.0, accuracy: 1e-9)
        }
        XCTAssertEqual(report.accuracy ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.abstained, 0)
        XCTAssertEqual(report.confidentlyWrong, 0)
        XCTAssertEqual(report.topTwoAccuracy ?? -1, 1.0, accuracy: 1e-9)
    }

    /// A classifier that always says "run": the report must show the misses, not flatter itself.
    private struct AlwaysRun: WorkoutTypeClassifying {
        func classify(_ features: WorkoutClassFeatures) -> WorkoutClassPrediction {
            WorkoutClassPrediction(predictedClass: .run, confidence: 0.9, scores: [.run: 0.9, .walk: 0.1])
        }
    }

    func testReplayShowsMissesForAClassifierThatIsWrongOnPurpose() {
        let report = WorkoutClassReplay.evaluate(labelled(), classifier: AlwaysRun())
        XCTAssertEqual(report.correct, 2, "only the two run windows are right")
        XCTAssertEqual(report.accuracy ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertEqual(report.confidentlyWrong, 8)
        XCTAssertEqual(report.recall(.run) ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.precision(.run) ?? -1, 0.2, accuracy: 1e-9, "it said run ten times and was right twice")
        XCTAssertEqual(report.recall(.cycle) ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertNil(report.precision(.cycle), "it never said cycle")
        // Truth among the top two (run, walk): run x2 and walk x2 hit, the other six do not.
        XCTAssertEqual(report.topTwoHits, 4)
        XCTAssertEqual(report.topTwoAccuracy ?? -1, 0.4, accuracy: 1e-9)
    }

    private struct AlwaysOther: WorkoutTypeClassifying {
        func classify(_ features: WorkoutClassFeatures) -> WorkoutClassPrediction {
            WorkoutClassPrediction(predictedClass: .other, confidence: 0.1, scores: [:])
        }
    }

    func testAbstainingIsCountedSeparatelyFromBeingWrong() {
        var w = labelled()
        w.append(.init(id: "yoga", label: .other, features: f(meanHR: 90, peakHR: 100, hrr: 20, hrCV: 0.05, motionVar: 0.005, kcal: 2)))
        let report = WorkoutClassReplay.evaluate(w, classifier: AlwaysOther())
        XCTAssertEqual(report.abstained, 10, "ten named sports were left generic")
        XCTAssertEqual(report.confidentlyWrong, 0)
        XCTAssertEqual(report.correct, 1, "the one 'other' window was named correctly as other")
        XCTAssertEqual(report.specificTotal, 10, "the 'other' window is not a specific sport")
    }

    func testEmptyReplayIsHonestAboutHavingNothing() {
        let report = WorkoutClassReplay.evaluate([])
        XCTAssertEqual(report.total, 0)
        XCTAssertNil(report.accuracy)
        XCTAssertNil(report.topTwoAccuracy)
        XCTAssertEqual(WorkoutClassReplay.summaryLines(report), ["No labelled windows to check yet."])
    }

    func testReplayIsDeterministic() {
        XCTAssertEqual(WorkoutClassReplay.evaluate(labelled()), WorkoutClassReplay.evaluate(labelled()))
        XCTAssertEqual(WorkoutClassReplay.evaluate(labelled().reversed()), WorkoutClassReplay.evaluate(labelled()), "order of windows must not matter")
    }

    // MARK: - Readiness

    func testReadinessNeedsEnoughLabelsPerClass() {
        let counts: [CoarseWorkoutClass: Int] = [.walk: 30, .run: WorkoutClassReplay.minLabelsPerClass, .cycle: WorkoutClassReplay.minLabelsPerClass - 1,
                                                 .strength: 2, .other: 400]
        XCTAssertEqual(WorkoutClassReplay.classesReadyToLearn(counts), [.walk, .run], "cycle is one short, strength has two, and 'other' never counts")
        XCTAssertEqual(WorkoutClassReplay.classesReadyToLearn([:]), [])
    }

    func testSummaryReportsWhatWasMeasured() {
        let lines = WorkoutClassReplay.summaryLines(WorkoutClassReplay.evaluate(labelled()))
        XCTAssertTrue(lines.contains("Windows checked: 10"))
        XCTAssertTrue(lines.contains("Named correctly: 100%"))
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("run: 2 labelled, recall 100%") }))
        XCTAssertTrue(lines.last?.contains("none yet") == true, "two labels per class is nowhere near enough to learn from; the summary must say so")
    }
}
