import XCTest
@testable import StrandAnalytics

/// The shadow learner: it must learn a person's own shapes, say nothing when it has not learned enough, and be graded without seeing the window it predicts.
final class PersonalWorkoutClassifierTests: XCTestCase {

    private func features(hrr: Double, cv: Double, still: Double, walk: Double, run: Double, motionVar: Double = 0.02, motionCV: Double = 0.8,
                          minutes: Double = 40) -> WorkoutClassFeatures {
        WorkoutClassFeatures(durationSec: minutes * 60, meanHR: 100 + hrr, peakHR: 140, meanHRRPct: hrr, hrCV: cv,
                             stillFraction: still, walkFraction: walk, runFraction: run, tickCoverage: 0.8,
                             motionVariance: motionVar, motionCV: motionCV, kcalPerMin: nil)
    }

    /// Several distinct shapes per class, so the model is not fitted to one number.
    private func windows(walk: Int = 6, run: Int = 6, strength: Int = 6) -> [LabelledWorkoutWindow] {
        var out: [LabelledWorkoutWindow] = []
        for i in 0..<walk {
            out.append(.init(id: "w\(i)", label: .walk, features: features(hrr: 38 + Double(i % 3) * 3, cv: 0.07, still: 0.1, walk: 0.85, run: 0.05, minutes: 35 + Double(i))))
        }
        for i in 0..<run {
            out.append(.init(id: "r\(i)", label: .run, features: features(hrr: 68 + Double(i % 3) * 3, cv: 0.06, still: 0.05, walk: 0.1, run: 0.85, minutes: 28 + Double(i))))
        }
        for i in 0..<strength {
            out.append(.init(id: "s\(i)", label: .strength, features: features(hrr: 45 + Double(i % 3) * 2, cv: 0.2 + Double(i % 2) * 0.03, still: 0.8, walk: 0.15, run: 0.0,
                                                                              motionVar: 0.06, motionCV: 1.8, minutes: 45 + Double(i))))
        }
        return out
    }

    func testLearnsThePersonsOwnClassesAndNamesAFreshWindow() throws {
        let model = try XCTUnwrap(PersonalWorkoutClassifier.train(windows(), now: 100))
        XCTAssertEqual(model.total, 18)
        XCTAssertEqual(Set(model.classes.keys), ["walk", "run", "strength"])
        let learner = PersonalWorkoutClassifier(model: model)
        XCTAssertEqual(learner.classify(features(hrr: 40, cv: 0.07, still: 0.1, walk: 0.8, run: 0.1)).predictedClass, .walk)
        XCTAssertEqual(learner.classify(features(hrr: 70, cv: 0.06, still: 0.05, walk: 0.1, run: 0.85)).predictedClass, .run)
        XCTAssertEqual(learner.classify(features(hrr: 46, cv: 0.22, still: 0.8, walk: 0.15, run: 0, motionVar: 0.06, motionCV: 1.8, minutes: 46)).predictedClass, .strength)
    }

    func testNothingToLearnWithTooFewWindowsOrOneClass() {
        XCTAssertNil(PersonalWorkoutClassifier.train([], now: 1))
        // Two windows per class are below the minimum, so no class qualifies.
        XCTAssertNil(PersonalWorkoutClassifier.train(windows(walk: 2, run: 2, strength: 2), now: 1))
        // One class alone cannot discriminate anything.
        XCTAssertNil(PersonalWorkoutClassifier.train(windows(walk: 8, run: 0, strength: 0), now: 1))
        // A class with only two windows is left out while the others are learned.
        let model = PersonalWorkoutClassifier.train(windows(walk: 6, run: 6, strength: 2), now: 1)
        XCTAssertEqual(Set(model?.classes.keys.map { $0 } ?? []), ["walk", "run"])
    }

    func testOtherLabelsAreNeverTrainedOn() {
        let extra = (0..<10).map { LabelledWorkoutWindow(id: "o\($0)", label: .other, features: features(hrr: 50, cv: 0.1, still: 0.5, walk: 0.3, run: 0.2)) }
        let model = PersonalWorkoutClassifier.train(windows() + extra, now: 1)
        XCTAssertNil(model?.classes["other"])
        XCTAssertEqual(model?.total, 18)
    }

    func testConfidenceGrowsWithTheNumberOfWindowsItLearnedFrom() throws {
        let small = try XCTUnwrap(PersonalWorkoutClassifier.train(windows(walk: 3, run: 3, strength: 0), now: 1))
        let large = try XCTUnwrap(PersonalWorkoutClassifier.train(windows(walk: 20, run: 20, strength: 0), now: 1))
        let probe = features(hrr: 40, cv: 0.07, still: 0.1, walk: 0.85, run: 0.05)
        let a = PersonalWorkoutClassifier(model: small).classify(probe).confidence
        let b = PersonalWorkoutClassifier(model: large).classify(probe).confidence
        XCTAssertLessThan(a, b, "a model of six windows must not claim what one of forty can")
        XCTAssertLessThanOrEqual(a, 6.0 / 30.0 + 1e-9)
    }

    func testAnUnrelatedShapeIsLeftToTheRulesNotForcedIntoAClass() throws {
        let model = try XCTUnwrap(PersonalWorkoutClassifier.train(windows(), now: 1))
        let learner = PersonalWorkoutClassifier(model: model)
        // Halfway between a walk and a run: the learner is not sure and abstains.
        let p = learner.classify(features(hrr: 53, cv: 0.065, still: 0.075, walk: 0.475, run: 0.45, minutes: 31))
        XCTAssertTrue(p.predictedClass == .other || p.scores[p.predictedClass]! < 0.9)
    }

    func testModelFromAnOlderFeatureLayoutIsIgnored() throws {
        let model = try XCTUnwrap(PersonalWorkoutClassifier.train(windows(), now: 1))
        let old = PersonalClassifierModel(trainedAt: model.trainedAt, total: model.total, classes: model.classes, featureVersion: 0)
        XCTAssertEqual(PersonalWorkoutClassifier(model: old).classify(features(hrr: 40, cv: 0.07, still: 0.1, walk: 0.8, run: 0.1)).predictedClass, .other)
    }

    func testLeaveOneOutNeverGradesAWindowOnItself() {
        // Each class has exactly three windows, so with one held out only two remain and the class cannot be named: the learner must not get credit
        // for a window it would have memorised.
        let w = windows(walk: 3, run: 3, strength: 3)
        let cmp = PersonalLearnerReplay.leaveOneOut(w)
        XCTAssertEqual(cmp.windows, 9)
        XCTAssertEqual(cmp.learnerCouldName, 0, "held out, each class falls to two windows and is no longer learnable")
        XCTAssertEqual(cmp.learnerCorrect, 0)
    }

    func testLeaveOneOutScoresTheLearnerAgainstTheRulesOnTheSameWindows() {
        let cmp = PersonalLearnerReplay.leaveOneOut(windows(walk: 8, run: 8, strength: 8))
        XCTAssertEqual(cmp.windows, 24)
        XCTAssertEqual(cmp.learnerCouldName, 24)
        XCTAssertGreaterThanOrEqual(cmp.learnerCorrect, 20, "clean, well separated personal shapes are learned")
        XCTAssertNotNil(cmp.rulesAccuracy)
        XCTAssertEqual(PersonalLearnerReplay.trainedClasses(windows(walk: 8, run: 8, strength: 2)), [.walk, .run])
    }
}
