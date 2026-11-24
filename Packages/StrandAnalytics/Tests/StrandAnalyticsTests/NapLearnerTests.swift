import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class NapLearnerTests: XCTestCase {

    private func f(_ minutes: Double, resting: Double, mean: Double? = nil, band: Double? = 0.7, still: Double = 0.003) -> NapWindowFeatures {
        NapWindowFeatures(durationMin: minutes, restingRatio: resting, meanRatio: mean ?? resting + 0.05, bandAsleepFraction: band, stillness: still)
    }

    func testRulesMatchTheStagersDaytimeBarAtItsEdges() {
        // Under 20 minutes: never. 20 to 90: a clear dip with the strap's verdict, or a deeper dip without one. 90 and over: the ordinary 0.95.
        XCTAssertFalse(NapRules.passes(durationS: 19 * 60, restingRatio: 0.7, bandAsleepFraction: 0.9))
        XCTAssertTrue(NapRules.passes(durationS: 40 * 60, restingRatio: 0.90, bandAsleepFraction: 0.55))
        XCTAssertFalse(NapRules.passes(durationS: 40 * 60, restingRatio: 0.90, bandAsleepFraction: 0.3))
        XCTAssertFalse(NapRules.passes(durationS: 40 * 60, restingRatio: 0.90, bandAsleepFraction: nil))
        XCTAssertTrue(NapRules.passes(durationS: 40 * 60, restingRatio: 0.86, bandAsleepFraction: nil))
        XCTAssertTrue(NapRules.passes(durationS: 100 * 60, restingRatio: 0.94, bandAsleepFraction: nil))
        XCTAssertFalse(NapRules.passes(durationS: 100 * 60, restingRatio: 0.96, bandAsleepFraction: 0.9))
        XCTAssertFalse(NapRules.passes(durationS: 40 * 60, restingRatio: nil, bandAsleepFraction: 0.9))
    }

    /// Windows of two clearly different shapes, several of each, so a model cannot be fitted to one number.
    private func windows(naps: Int, notNaps: Int) -> [LabelledNapWindow] {
        var out: [LabelledNapWindow] = []
        for i in 0..<naps { out.append(.init(id: "n\(i)", isNap: true, features: f(30 + Double(i) * 4, resting: 0.84 + Double(i % 3) * 0.02, band: 0.6 + Double(i % 3) * 0.1, still: 0.002))) }
        for i in 0..<notNaps { out.append(.init(id: "x\(i)", isNap: false, features: f(25 + Double(i) * 5, resting: 0.97 + Double(i % 3) * 0.02, mean: 1.02, band: 0.05 + Double(i % 3) * 0.05, still: 0.004))) }
        return out
    }

    func testNothingIsTrainedWithoutEnoughOfBothKinds() {
        XCTAssertNil(NapLearner.train([], now: 1))
        XCTAssertNil(NapLearner.train(windows(naps: 20, notNaps: 5), now: 1), "five deleted windows are too few, however many naps")
        XCTAssertNil(NapLearner.train(windows(naps: 5, notNaps: 20), now: 1))
        XCTAssertNotNil(NapLearner.train(windows(naps: 6, notNaps: 6), now: 1))
    }

    func testItSeparatesTheTwoShapesAndGivesAProbability() throws {
        let model = try XCTUnwrap(NapLearner.train(windows(naps: 10, notNaps: 10), now: 5))
        XCTAssertEqual(model.positives, 10)
        XCTAssertEqual(model.negatives, 10)
        let nap = try XCTUnwrap(NapLearner.probability(model, f(40, resting: 0.86, band: 0.7, still: 0.002)))
        let notNap = try XCTUnwrap(NapLearner.probability(model, f(40, resting: 0.98, mean: 1.02, band: 0.1, still: 0.004)))
        XCTAssertGreaterThan(nap, 0.8)
        XCTAssertLessThan(notNap, 0.2)
    }

    func testAModelFromAnotherFeatureLayoutIsIgnored() throws {
        let m = try XCTUnwrap(NapLearner.train(windows(naps: 6, notNaps: 6), now: 1))
        let old = NapLearnerModel(trainedAt: 1, positives: m.positives, negatives: m.negatives, mean: m.mean, scale: m.scale, weights: m.weights, bias: m.bias, featureVersion: 0)
        XCTAssertNil(NapLearner.probability(old, f(40, resting: 0.86)))
    }

    func testLeaveOneOutComparesTheLearnerWithTheRulesOnTheSameWindows() throws {
        // A nap the rules reject (a deep dip is not enough alone for 45 minutes with a thin band share) and a false nap the rules accept.
        var w = windows(naps: 8, notNaps: 8)
        w.append(.init(id: "missed", isNap: true, features: f(45, resting: 0.89, band: 0.4, still: 0.002)))
        w.append(.init(id: "false", isNap: false, features: f(45, resting: 0.9, band: 0.6, still: 0.0045)))
        let cmp = try XCTUnwrap(NapLearnerReplay.leaveOneOut(w))
        XCTAssertEqual(cmp.windows, 18)
        XCTAssertGreaterThanOrEqual(cmp.rulesMissedNaps, 1)
        XCTAssertGreaterThanOrEqual(cmp.rulesFalseNaps, 1)
        XCTAssertNil(NapLearnerReplay.leaveOneOut(windows(naps: 3, notNaps: 3)), "too little to compare")
    }

    func testFeaturesFromTheStrapsStreams() throws {
        let start = 1_700_000_000
        var hr: [HRSample] = (0..<(8 * 3600)).map { HRSample(ts: start - 4 * 3600 + $0, bpm: 76) }       // a waking baseline of 76
        for i in 0..<(40 * 60) { hr[4 * 3600 + i] = HRSample(ts: start + i, bpm: 62) }                    // a 40-minute dip to 62
        let grav = (0..<(40 * 60)).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let band = (0..<(40 * 60)).map { (ts: start + $0, state: $0 < 600 ? 1 : 2) }                       // still for 10 minutes, then asleep
        let feat = try XCTUnwrap(NapFeatureExtractor.extract(start: start, end: start + 40 * 60 - 1, hr: hr, gravity: grav, band: band))
        XCTAssertEqual(feat.durationMin, 40, accuracy: 0.1)
        XCTAssertEqual(feat.restingRatio, 62.0 / 76.0, accuracy: 0.02)
        XCTAssertEqual(feat.bandAsleepFraction ?? 0, 0.75, accuracy: 0.02)
        XCTAssertEqual(feat.stillness, 0, accuracy: 1e-9)
        XCTAssertNil(NapFeatureExtractor.extract(start: start, end: start + 30, hr: hr, gravity: grav, band: band), "half a minute of heart rate says nothing")
    }
}
