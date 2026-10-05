import XCTest
@testable import StrandAnalytics

final class AnyaActionsTests: XCTestCase {
    func testChartBlockBetweenProse() {
        let r = "Here is your HRV.\n```anya-chart\n{\"title\":\"HRV\",\"metrics\":[\"hrv\",\"rhr\"],\"days\":14}\n```\nIt dipped midweek."
        let b = AnyaActions.parse(r)
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0], .text("Here is your HRV."))
        XCTAssertEqual(b[1], .chart(AnyaChartSpec(title: "HRV", metrics: ["hrv", "rhr"], days: 14)))
        XCTAssertEqual(b[2], .text("It dipped midweek."))
        XCTAssertEqual(AnyaActions.proseOnly(r), "Here is your HRV.\n\nIt dipped midweek.")
    }

    func testChartRejectsUnknownMetricsAndClampsDays() {
        let ok = AnyaActions.parse("```anya-chart\n{\"metric\":\"HRV\",\"days\":9999}\n```")
        XCTAssertEqual(ok, [.chart(AnyaChartSpec(title: nil, metrics: ["hrv"], days: 365))])
        XCTAssertTrue(AnyaActions.parse("```anya-chart\n{\"metrics\":[\"bitcoin\"]}\n```").isEmpty)
        let many = AnyaActions.parse("```anya-chart\n{\"metrics\":[\"hrv\",\"rhr\",\"spo2\",\"weight\",\"hrv\"],\"days\":1}\n```")
        XCTAssertEqual(many, [.chart(AnyaChartSpec(title: nil, metrics: ["hrv", "rhr", "spo2"], days: 7))])
    }

    func testProgramIsClampedAndEmptyDaysDropped() {
        let json = """
        ```anya-program
        {"name":"  Full body ","days":[{"title":"A","items":[{"exercise":"Squat","sets":99,"repsLow":12,"repsHigh":8,"restSec":9000},{"exercise":"","sets":3}]},{"title":"Empty","items":[]}]}
        ```
        """
        guard case .program(let p)? = AnyaActions.parse(json).first else { return XCTFail() }
        XCTAssertEqual(p.name, "Full body")
        XCTAssertEqual(p.days.count, 1)
        XCTAssertEqual(p.days[0].items, [AnyaProgramItem(exercise: "Squat", sets: 10, repsLow: 8, repsHigh: 12, restSec: 600, note: nil)])
    }

    func testProgramCapsDaysAndExercises() {
        let items = (0..<20).map { "{\"exercise\":\"E\($0)\"}" }.joined(separator: ",")
        let days = (0..<10).map { "{\"title\":\"D\($0)\",\"items\":[\(items)]}" }.joined(separator: ",")
        guard case .program(let p)? = AnyaActions.parse("```anya-program\n{\"name\":\"x\",\"days\":[\(days)]}\n```").first else { return XCTFail() }
        XCTAssertEqual(p.days.count, 7)
        XCTAssertEqual(p.days[0].items.count, 12)
    }

    func testWorkout() {
        let b = AnyaActions.parse("```anya-workout\n{\"title\":\"Easy run\",\"sport\":\"Running\",\"minutes\":2,\"zone\":9}\n```")
        XCTAssertEqual(b, [.workout(AnyaWorkoutSpec(title: "Easy run", sport: "Running", minutes: 5, zone: 5, note: nil))])
        XCTAssertTrue(AnyaActions.parse("```anya-workout\n{\"minutes\":30}\n```").isEmpty)
    }

    func testOpenFenceWhileStreamingIsHiddenAndInvalidJsonFallsBackToText() {
        XCTAssertEqual(AnyaActions.parse("Working on it.\n```anya-chart\n{\"metrics\":[\"hr"), [.text("Working on it.")])
        XCTAssertEqual(AnyaActions.parse("Sure.\n```anya-chart"), [.text("Sure.")])
        XCTAssertEqual(AnyaActions.parse("```anya-chart\nnot json\n```"), [.text("not json")])
    }

    func testPlainReplyAndOtherFencesUntouched() {
        XCTAssertEqual(AnyaActions.parse("Just text."), [.text("Just text.")])
        XCTAssertEqual(AnyaActions.parse("```swift\nlet x = 1\n```"), [.text("```swift\nlet x = 1\n```")])
        XCTAssertEqual(AnyaActions.proseOnly(""), "")
    }

    func testInstructionNamesEveryBlock() {
        for tag in ["anya-chart", "anya-program", "anya-workout"] { XCTAssertTrue(AnyaActions.instruction.contains(tag)) }
        for m in AnyaActions.chartMetrics { XCTAssertTrue(AnyaActions.instruction.contains(m), m) }
    }
}
