import XCTest
@testable import StrandAnalytics

final class TrendInsightsTests: XCTestCase {

    func testShiftCrossesMonthAndYear() {
        XCTAssertEqual(TrendInsights.shift("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(TrendInsights.shift("2026-03-01", by: -1), "2026-02-28")
        XCTAssertNil(TrendInsights.shift("nope", by: 1))
    }

    func testWeekday() {
        // 2026-10-04 is a Sunday.
        XCTAssertEqual(TrendInsights.weekday("2026-10-04"), 1)
        XCTAssertEqual(TrendInsights.weekday("2026-10-05"), 2)
    }

    func testZoneCountsUsesLowerBounds() {
        // Edges 10, 14, 18: 9.9 | 10 and 13.9 | 14 and 17.9 | 18 and above.
        XCTAssertEqual(TrendInsights.zoneCounts([9.9, 10, 13.9, 14, 17.9, 18, 20], edges: [10, 14, 18]), [1, 2, 2, 2])
        XCTAssertEqual(TrendInsights.zoneCounts([], edges: [10]), [0, 0])
    }

    func testWeekdayMeans() {
        let m = TrendInsights.weekdayMeans([("2026-10-04", 60), ("2026-10-11", 80), ("2026-10-05", 50)])
        XCTAssertEqual(m[1] ?? 0, 70, accuracy: 1e-9)
        XCTAssertEqual(m[2] ?? 0, 50, accuracy: 1e-9)
        XCTAssertNil(m[3])
    }

    func testWeeklyTotalsAndGaps() {
        var s: [(day: String, value: Double)] = []
        for k in 0..<7 { s.append((TrendInsights.shift("2026-10-04", by: -k)!, 10)) }       // last week: 70
        s.append((TrendInsights.shift("2026-10-04", by: -8)!, 5))                            // week before: 5 only
        let t = TrendInsights.weeklyTotals(s, lastDay: "2026-10-04", weeks: 3)
        XCTAssertEqual(t.map(\.total), [5, 70])   // third week back has nothing and is dropped
    }

    func testBucketsNextDay() {
        // Effort today, Charge tomorrow. Two light days -> 80 and 70, one hard day -> 40.
        let effort: [(day: String, value: Double)] = [("2026-10-01", 5), ("2026-10-02", 6), ("2026-10-03", 16)]
        let charge: [(day: String, value: Double)] = [("2026-10-02", 80), ("2026-10-03", 70), ("2026-10-04", 40)]
        let b = TrendInsights.buckets(driver: effort, outcome: charge, edges: [10, 14], lag: 1)
        XCTAssertEqual(b.map(\.n), [2, 0, 1])
        XCTAssertEqual(b[0].meanOutcome ?? 0, 75, accuracy: 1e-9)
        XCTAssertNil(b[1].meanOutcome)
        XCTAssertEqual(b[2].meanOutcome ?? 0, 40, accuracy: 1e-9)
    }

    func testBucketsSameDayAndMissingOutcome() {
        let rest: [(day: String, value: Double)] = [("2026-10-01", 90), ("2026-10-02", 70)]
        let charge: [(day: String, value: Double)] = [("2026-10-01", 76)]
        let b = TrendInsights.buckets(driver: rest, outcome: charge, edges: [78], lag: 0)
        XCTAssertEqual(b.map(\.n), [0, 1])
        XCTAssertEqual(b[1].meanOutcome ?? 0, 76, accuracy: 1e-9)
    }

    func testPairsSkipUnmatched() {
        let p = TrendInsights.pairs(driver: [("2026-10-01", 1), ("2026-10-02", 2)], outcome: [("2026-10-03", 9)], lag: 1)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].day, "2026-10-02"); XCTAssertEqual(p[0].y, 9)
    }

    func testStrengthLabels() {
        XCTAssertEqual(TrendInsights.strength(0.29), .weak)
        XCTAssertEqual(TrendInsights.strength(-0.59), .moderate)
        XCTAssertEqual(TrendInsights.strength(0.68), .strong)
    }

    func testLongestStreak() {
        let s: [(day: String, value: Double)] = [("2026-09-01", 70), ("2026-09-02", 80), ("2026-09-03", 30), ("2026-09-04", 90),
                                                 ("2026-09-05", 91), ("2026-09-06", 92), ("2026-09-08", 95)]
        let r = TrendInsights.longestStreak(s, atLeast: 67)
        XCTAssertEqual(r?.length, 3); XCTAssertEqual(r?.endDay, "2026-09-06")
        XCTAssertNil(TrendInsights.longestStreak([("2026-09-01", 10)], atLeast: 67))
    }

    func testLoadRatio() {
        // Blocks 10, 10, 10, 10, 10, 20: mean 11.67, last 20 -> 1.714.
        XCTAssertEqual(TrendInsights.loadRatio(blocks: [10, 10, 10, 10, 10, 20]) ?? 0, 20.0 / (70.0 / 6.0), accuracy: 1e-9)
        XCTAssertNil(TrendInsights.loadRatio(blocks: [0, 0, 0, 0, 5, 6], minBlocks: 3))   // only two loaded blocks
        XCTAssertNil(TrendInsights.loadRatio(blocks: [10, 12], minBlocks: 3))
    }

    func testLoadBandEdges() {
        XCTAssertEqual(TrendInsights.loadBand(0.79), .under)
        XCTAssertEqual(TrendInsights.loadBand(0.8), .optimal)
        XCTAssertEqual(TrendInsights.loadBand(1.3), .optimal)
        XCTAssertEqual(TrendInsights.loadBand(1.4), .high)
        XCTAssertEqual(TrendInsights.loadBand(1.6), .excessive)
    }

    func testFormState() {
        XCTAssertEqual(TrendInsights.formState(2.5), .fresh)
        XCTAssertEqual(TrendInsights.formState(-1.7), .balanced)
        XCTAssertEqual(TrendInsights.formState(-4), .loaded)
        XCTAssertEqual(TrendInsights.formState(-9), .overreached)
    }
}
