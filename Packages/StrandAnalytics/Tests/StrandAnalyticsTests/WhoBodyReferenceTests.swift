import XCTest
@testable import StrandAnalytics

final class WhoBodyReferenceTests: XCTestCase {
    func testWeightRangeFollowsBmi18_5ToUnder25() throws {
        let r = try XCTUnwrap(WhoBodyReference.weightRangeKg(heightCm: 178))
        XCTAssertEqual(r.low, 18.5 * 1.78 * 1.78, accuracy: 1e-9)
        XCTAssertEqual(r.high, 24.99 * 1.78 * 1.78, accuracy: 1e-9)
        XCTAssertEqual(r.low, 58.6, accuracy: 0.05)
        XCTAssertEqual(r.high, 79.2, accuracy: 0.05)
    }

    func testNoRangeForAnUnbelievableHeight() {
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: 0))
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: 60))
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: .nan))
    }

    func testWaistCeilingBySex() {
        XCTAssertEqual(WhoBodyReference.waistCeilingCm(sex: "male"), 94)
        XCTAssertEqual(WhoBodyReference.waistCeilingCm(sex: "Female"), 80)
        XCTAssertNil(WhoBodyReference.waistCeilingCm(sex: "nonbinary"))
        XCTAssertNil(WhoBodyReference.waistCeilingCm(sex: ""))
    }
}

final class WhoNutritionReferenceTests: XCTestCase {
    func testBmiClassesUseTheWhoCutOffs() {
        XCTAssertEqual(WhoNutritionReference.bmiClass(18.4), .underweight)
        XCTAssertEqual(WhoNutritionReference.bmiClass(18.5), .normal)
        XCTAssertEqual(WhoNutritionReference.bmiClass(24.99), .normal)
        XCTAssertEqual(WhoNutritionReference.bmiClass(25), .overweight)
        XCTAssertEqual(WhoNutritionReference.bmiClass(30), .obese)
    }

    func testSharesAddUpAndEmptyIsNil() throws {
        let s = try XCTUnwrap(WhoNutritionReference.shares(proteinG: 135, carbsG: 252, fatG: 67))
        XCTAssertEqual(s.protein + s.carbs + s.fat, 1, accuracy: 1e-9)
        XCTAssertEqual(s.fat, 603.0 / 2151.0, accuracy: 1e-9)
        XCTAssertNil(WhoNutritionReference.shares(proteinG: 0, carbsG: 0, fatG: 0))
        XCTAssertTrue(WhoNutritionReference.fatShareRange.contains(0.28)); XCTAssertFalse(WhoNutritionReference.carbShareRange.contains(0.44))
    }
}

final class AnyaPlanExplanationTests: XCTestCase {
    func testExplanationIsKeptAndCapped() {
        let long = String(repeating: "x", count: 1200)
        guard case .plan(let p)? = AnyaActions.parse("```anya-plan\n{\"targetKcal\":2000,\"explanation\":\"\(long)\"}\n```").first else { return XCTFail() }
        XCTAssertEqual(p.explanation?.count, 900)
        guard case .plan(let q)? = AnyaActions.parse("```anya-plan\n{\"targetKcal\":2000}\n```").first else { return XCTFail() }
        XCTAssertNil(q.explanation)
        XCTAssertTrue(AnyaActions.planInstruction.contains("0.83"))
    }
}
