import XCTest
@testable import StrandAnalytics

final class VitalityEngineTests: XCTestCase {

    /// An average-for-their-age person nets ~0 hazard → Body Age == chronological age, Vitality 50.
    func testAveragePersonReadsAtTheirAge() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 60, vo2max: 45, expectedVO2max: 45,
            sleepHours: 7.5, sleepConsistency: 0.70, rmssd: 45, rmssdNorm: 45, steps: 7000))!
        XCTAssertEqual(r.bodyAge, 40, accuracy: 0.01)
        XCTAssertEqual(r.vitality, 50, accuracy: 0.01)
        XCTAssertEqual(r.deltaYears, 0, accuracy: 0.01)
        XCTAssertEqual(r.factorsUsed, 6)
    }

    /// A clearly healthy person reads younger + higher vitality (hand-computed Δage ≈ −7.34).
    func testHealthyPersonIsYounger() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 52, vo2max: 55.5, expectedVO2max: 45,
            sleepHours: 7.5, sleepConsistency: 0.9, rmssd: 54, rmssdNorm: 45, steps: 11000))!
        XCTAssertEqual(r.bodyAge, 32.66, accuracy: 0.1)
        XCTAssertEqual(r.vitality, 68.35, accuracy: 0.2)
        XCTAssertGreaterThan(r.deltaYears, 0)   // younger than chrono age
    }

    /// A clearly unhealthy person reads older + lower vitality (hand-computed Δage ≈ +9.95).
    func testUnhealthyPersonIsOlder() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 80, vo2max: 34.5, expectedVO2max: 45,
            sleepHours: 5.5, sleepConsistency: 0.5, rmssd: 31.5, rmssdNorm: 45, steps: 3000))!
        XCTAssertEqual(r.bodyAge, 49.95, accuracy: 0.1)
        XCTAssertEqual(r.vitality, 25.14, accuracy: 0.2)
        XCTAssertLessThan(r.deltaYears, 0)      // older than chrono age
    }

    /// Below the minimum-factor honesty gate → nil (don't show a number on too little data).
    func testNilBelowMinFactors() {
        XCTAssertNil(VitalityEngine.compute(.init(chronoAge: 40, restingHR: 65, sleepHours: 7.5))) // 2 factors
        XCTAssertNotNil(VitalityEngine.compute(.init(chronoAge: 40, restingHR: 65, sleepHours: 7.5,
                                                     sleepConsistency: 0.75)))                     // 3 factors
    }

    /// Body Age + Vitality stay within their clamped ranges at the extremes.
    func testClamps() {
        let young = VitalityEngine.compute(.init(
            chronoAge: 22, restingHR: 40, vo2max: 70, expectedVO2max: 40,
            sleepHours: 7.5, sleepConsistency: 1.0, rmssd: 90, rmssdNorm: 45, steps: 11000))!
        XCTAssertGreaterThanOrEqual(young.bodyAge, VitalityEngine.minBodyAge)
        XCTAssertLessThanOrEqual(young.vitality, 100)
        XCTAssertGreaterThanOrEqual(young.vitality, 0)

        let old = VitalityEngine.compute(.init(
            chronoAge: 85, restingHR: 110, vo2max: 12, expectedVO2max: 35,
            sleepHours: 3, sleepConsistency: 0.1, rmssd: 8, rmssdNorm: 30, steps: 200))!
        XCTAssertLessThanOrEqual(old.bodyAge, VitalityEngine.maxBodyAge)
        XCTAssertGreaterThanOrEqual(old.vitality, 0)
    }

    /// Someone exactly at each activity break-even adds no hazard, so the three new factors leave an average person at their age.
    func testActivityFactorsAtBreakEvenAreNeutral() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: VitalityEngine.restingHRBreakEven, sleepHours: 7.5, sleepConsistency: VitalityEngine.consistencyBreakEven,
            zonesLowMin: VitalityEngine.lowZoneBreakEven, zonesHighMin: VitalityEngine.highZoneBreakEven, strengthMin: VitalityEngine.strengthBreakEven))!
        XCTAssertEqual(r.bodyAge, 40, accuracy: 0.01)
        XCTAssertEqual(r.factorsUsed, 6)
    }

    /// No activity at all ages the wearer: each factor adds hazard against its break-even, in the order the curves give
    /// (zones 1–3 +0.151, zones 4–5 +0.012, strength +0.09, hand-computed), and the years follow from the shrink and the Gompertz slope.
    func testNoActivityAgesTheWearer() {
        let c = VitalityEngine.contributions(.init(chronoAge: 40, zonesLowMin: 0, zonesHighMin: 0, strengthMin: 0))
        XCTAssertEqual(c.first { $0.key == "zonesLow" }!.lnHazard, 0.151, accuracy: 1e-9)
        XCTAssertEqual(c.first { $0.key == "zonesHigh" }!.lnHazard, 0.012, accuracy: 1e-9)
        XCTAssertEqual(c.first { $0.key == "strength" }!.lnHazard, 0.09, accuracy: 1e-9)
        let r = VitalityEngine.compute(.init(chronoAge: 40, zonesLowMin: 0, zonesHighMin: 0, strengthMin: 0))!
        XCTAssertEqual(r.bodyAge, 40 + (0.151 + 0.012 + 0.09) * 0.75 / VitalityEngine.lnHazardPerYear, accuracy: 0.05)
    }

    /// More activity than the break-even reads younger, and each curve stops giving at its ceiling.
    func testActivityBeyondBreakEvenIsProtectiveAndSaturates() {
        let more = VitalityEngine.contributions(.init(chronoAge: 40, zonesLowMin: 300, zonesHighMin: 90, strengthMin: 120))
        XCTAssertLessThan(more.first { $0.key == "zonesLow" }!.lnHazard, 0)
        XCTAssertLessThan(more.first { $0.key == "zonesHigh" }!.lnHazard, 0)
        XCTAssertLessThan(more.first { $0.key == "strength" }!.lnHazard, 0)
        XCTAssertEqual(VitalityEngine.strengthEffect(60), VitalityEngine.strengthEffect(600), accuracy: 1e-12)
        XCTAssertEqual(VitalityEngine.highZoneEffect(120), VitalityEngine.highZoneEffect(900), accuracy: 1e-12)
        XCTAssertEqual(VitalityEngine.lowZoneEffect(600), VitalityEngine.lowZoneEffect(5000), accuracy: 1e-12)
    }

    /// The inputs that existed before are unchanged by the new ones being absent (the old callers read the same).
    func testExistingInputsUnchangedWithoutActivity() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 52, vo2max: 55.5, expectedVO2max: 45,
            sleepHours: 7.5, sleepConsistency: 0.9, rmssd: 54, rmssdNorm: 45, steps: 11000))!
        XCTAssertEqual(r.bodyAge, 32.66, accuracy: 0.1)
        XCTAssertEqual(r.factorsUsed, 6)
    }

    /// The per-factor years add up to the Body Age's distance from the calendar age (apart from the clamp).
    func testFactorYearsSumToTheBodyAge() {
        let inputs = VitalityEngine.Inputs(chronoAge: 40, restingHR: 60, sleepHours: 6, sleepConsistency: 0.7, rmssd: 60, rmssdNorm: 33,
                                           zonesLowMin: 40, zonesHighMin: 0, strengthMin: 30)
        let r = VitalityEngine.compute(inputs)!
        let total = r.contributions.reduce(0) { $0 + VitalityEngine.years(of: $1) }
        XCTAssertEqual(r.bodyAge, 40 + total, accuracy: 1e-9)
    }

    /// Lean body mass is neutral from its break-even up and reads +5.6 years at the 60.2% WHOOP's page showed, with the ceiling at 60%.
    func testLeanBodyMass() {
        func years(_ pct: Double) -> Double {
            let c = VitalityEngine.contributions(.init(chronoAge: 40, leanMassPct: pct)).first { $0.key == "leanMass" }!
            return VitalityEngine.years(of: c)
        }
        XCTAssertEqual(years(78), 0, accuracy: 1e-9)
        XCTAssertEqual(years(85), 0, accuracy: 1e-9)
        XCTAssertEqual(years(60.2), 5.6, accuracy: 0.05)
        XCTAssertEqual(years(60), years(45), accuracy: 1e-9)
        XCTAssertLessThan(years(70), years(65))
    }

    /// The VO₂ reference follows the two verified FRIEND medians at ages 25 and 75, by sex, and the clamp holds outside 20 to 80.
    func testExpectedVO2max() {
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 25, sex: "male"), 48.0, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 75, sex: "male"), 24.4, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 25, sex: "female"), 37.6, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 75, sex: "female"), 18.3, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 36.6, sex: "male"), 42.5, accuracy: 0.05)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 36.6, sex: "female"), 33.1, accuracy: 0.05)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 36.6, sex: "other"), (42.5 + 33.1) / 2, accuracy: 0.05)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 10, sex: "male"), VitalityEngine.expectedVO2max(age: 20, sex: "male"), accuracy: 1e-9)
    }

    func testRmssdNormByAge() {
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 20), 47, accuracy: 0.01)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 40), 33, accuracy: 0.01)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 45), 31, accuracy: 0.01)   // halfway 33→29
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 90), 20, accuracy: 0.01)   // clamps to last anchor
    }

    func testSleepConsistency() {
        XCTAssertEqual(VitalityEngine.sleepConsistency(nightlyHours: [7, 7, 7, 7])!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.sleepConsistency(nightlyHours: [6, 8, 6, 8])!, 0.857, accuracy: 0.005)
        XCTAssertNil(VitalityEngine.sleepConsistency(nightlyHours: [7, 7]))   // < 3 nights
    }

    /// Contributions carry the right sign: a low resting HR is protective (negative), a high one ages you.
    func testContributionSigns() {
        let lowRHR = VitalityEngine.contributions(.init(chronoAge: 40, restingHR: 50))
            .first { $0.key == "rhr" }!
        XCTAssertLessThan(lowRHR.lnHazard, 0)
        let highRHR = VitalityEngine.contributions(.init(chronoAge: 40, restingHR: 85))
            .first { $0.key == "rhr" }!
        XCTAssertGreaterThan(highRHR.lnHazard, 0)
    }
}
