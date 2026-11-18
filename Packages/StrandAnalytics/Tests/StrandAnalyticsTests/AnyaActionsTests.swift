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

final class AnyaLabBlockTests: XCTestCase {
    func testLabBlockParsesAndKeepsTextVerbatim() {
        let r = "Here is what I read.\n```anya-lab\n{\"day\":\"2026-10-07\",\"results\":[{\"marker\":\"LDL cholesterol\",\"value\":3.1,\"unit\":\"mmol/L\",\"range\":\"<3.4\"},{\"marker\":\"Glucose\",\"value\":\"5,1\",\"day\":\"2026-10-01\",\"note\":\"fasted\"}]}\n```"
        guard case .lab(let l)? = AnyaActions.parse(r).last else { return XCTFail() }
        XCTAssertEqual(l.day, "2026-10-07")
        XCTAssertEqual(l.results.count, 2)
        XCTAssertEqual(l.results[0].unit, "mmol/L"); XCTAssertEqual(l.results[0].range, "<3.4")
        XCTAssertEqual(l.results[1].value, 5.1); XCTAssertEqual(l.results[1].day, "2026-10-01")
        XCTAssertEqual(AnyaActions.proseOnly(r), "Here is what I read.")
    }

    func testBadResultsAreDroppedAndAnEmptyBlockIsNotACard() {
        let r = "```anya-lab\n{\"day\":\"2026-13-40\",\"results\":[{\"marker\":\"\",\"value\":1},{\"marker\":\"X\",\"value\":\"abc\"},{\"marker\":\"Y\",\"value\":2,\"day\":\"soon\"}]}\n```"
        guard case .lab(let l)? = AnyaActions.parse(r).first else { return XCTFail() }
        XCTAssertNil(l.day)
        XCTAssertEqual(l.results.map(\.marker), ["Y"])
        XCTAssertNil(l.results[0].day)
        XCTAssertTrue(AnyaActions.parse("```anya-lab\n{\"results\":[]}\n```").isEmpty)
    }

    func testResultCapAndTheInstructionMentionsTheBlock() {
        let many = (0..<250).map { "{\"marker\":\"M\($0)\",\"value\":\($0)}" }.joined(separator: ",")
        guard case .lab(let l)? = AnyaActions.parse("```anya-lab\n{\"results\":[\(many)]}\n```").first else { return XCTFail() }
        XCTAssertEqual(l.results.count, 200)
        XCTAssertTrue(AnyaActions.instruction.contains("anya-lab"))
    }

    func testBareChartJSONWithOtherNamesIsDrawnAndKeptOutOfProse() {
        let reply = "You've had solid sleep recently.\n\n{\"title\":\"Sleep Performance - Last 14 Days\",\"metrics\":[\"sleep_duration\",\"sleep_stages\"],\"days\":14}"
        let blocks = AnyaActions.parse(reply)
        XCTAssertEqual(blocks.count, 2)
        if case .text(let t) = blocks[0] { XCTAssertEqual(t, "You've had solid sleep recently.") } else { XCTFail("prose first") }
        if case .chart(let c) = blocks[1] {
            XCTAssertEqual(c.metrics, ["sleep_performance"]); XCTAssertEqual(c.days, 14)
        } else { XCTFail("a chart") }
    }

    func testBraceTextWithoutMetricsStaysProse() {
        let blocks = AnyaActions.parse("Use {curly} braces {\"a\":1} freely.")
        XCTAssertEqual(blocks.count, 1)
        if case .text = blocks[0] {} else { XCTFail("prose") }
    }

    func testAWeekInTheQuestionMeansSevenDays() {
        XCTAssertEqual(AnyaActions.requestedDays(in: "make grafik sleep performance last week"), 7)
        XCTAssertEqual(AnyaActions.requestedDays(in: "buat grafik mingguan hrv"), 7)
        XCTAssertEqual(AnyaActions.requestedDays(in: "grafik HRV 1 minggu terakhir"), 7)
        XCTAssertEqual(AnyaActions.requestedDays(in: "grafik hrv pekan ini"), 7)
        XCTAssertEqual(AnyaActions.requestedDays(in: "show recovery for 2 weeks"), 14)
        XCTAssertEqual(AnyaActions.requestedDays(in: "grafik dua minggu"), 14)
        XCTAssertNil(AnyaActions.requestedDays(in: "buat grafik hrv"))
        XCTAssertNil(AnyaActions.requestedDays(in: "what did I do on the weekend"))
        XCTAssertNil(AnyaActions.requestedDays(in: nil))
    }
}

/// A model that does not follow the `anya-…` naming still gets its card, and nothing it writes shows as raw JSON or a stray marker.
final class AnyaLooseFenceTests: XCTestCase {
    private let workoutJSON = #"{"title":"Latihan ringan malam","sport":"Latihan ringan","minutes":20,"zone":4}"#

    private func workouts(_ blocks: [AnyaBlock]) -> [AnyaWorkoutSpec] { blocks.compactMap { if case .workout(let w) = $0 { return w } else { return nil } } }
    private func texts(_ blocks: [AnyaBlock]) -> [String] { blocks.compactMap { if case .text(let t) = $0 { return t } else { return nil } } }

    func testAJsonFenceThatReadsAsAWorkoutBecomesTheCard() {
        let reply = "Latihan ringan 20 menit.\n```json\n\(workoutJSON)\n```\nLakukan dengan pelan."
        let blocks = AnyaActions.parse(reply)
        XCTAssertEqual(workouts(blocks).first?.minutes, 20)
        XCTAssertEqual(workouts(blocks).first?.zone, 4)
        XCTAssertEqual(texts(blocks), ["Latihan ringan 20 menit.", "Lakukan dengan pelan."])
        XCTAssertFalse(AnyaActions.proseOnly(reply).contains("{"), "raw JSON never reaches the prose")
    }

    func testTheJsonOnTheSameLineAsTheFenceAndAnUnnamedFenceBothRead() {
        XCTAssertEqual(workouts(AnyaActions.parse("Ok.\n```json \(workoutJSON)```")).count, 1)
        XCTAssertEqual(workouts(AnyaActions.parse("Ok.\n```\n\(workoutJSON)\n```")).count, 1)
    }

    func testOtherSpellingsOfTheNameStillCount() {
        XCTAssertEqual(workouts(AnyaActions.parse("```anya_workout\n\(workoutJSON)\n```")).count, 1)
        XCTAssertEqual(workouts(AnyaActions.parse("```workout\n\(workoutJSON)\n```")).count, 1)
        XCTAssertEqual(workouts(AnyaActions.parse("```Anya-Workout\n\(workoutJSON)\n```")).count, 1)
    }

    func testTheKindIsReadFromTheKeysAndNothingIsGuessed() {
        let chart = AnyaActions.parse("```json\n{\"metrics\":[\"hrv\"],\"days\":14}\n```")
        XCTAssertEqual(chart.count, 1)
        if case .chart(let c) = chart[0] { XCTAssertEqual(c.metrics, ["hrv"]) } else { XCTFail("a chart") }
        // JSON that is none of the blocks stays where it was, fenced, in the prose.
        let other = AnyaActions.parse("Here you go.\n```json\n{\"colour\":\"red\"}\n```")
        XCTAssertEqual(workouts(other).count, 0)
        XCTAssertTrue(texts(other).joined().contains("colour"))
    }

    func testCodeInAnotherLanguageStaysAsItIs() {
        let reply = "Try:\n```swift\nlet x = 1\n```\nDone."
        let blocks = AnyaActions.parse(reply)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(texts(blocks)[0].contains("let x = 1"))
    }

    func testAnOpenFenceIsHiddenWhileTheReplyStreams() {
        XCTAssertEqual(texts(AnyaActions.parse("Latihan ringan.\n```json\n{\"title\":\"Lat")), ["Latihan ringan."])
        XCTAssertEqual(texts(AnyaActions.parse("Latihan ringan.\n```anya-work")), ["Latihan ringan."])
    }

    func testAnUnknownAnyaNameIsDroppedAsBefore() {
        XCTAssertEqual(texts(AnyaActions.parse("Hi.\n```anya-banana\n{\"a\":1}\n```\nBye.")), ["Hi.", "Bye."])
    }

    func testQuoteMarkersDoNotShowAsStrayArrows() {
        let blocks = AnyaActions.parse("> Latihan malam: ringan 20 menit.\n>Jaga tidur.\nBiasa.")
        XCTAssertEqual(texts(blocks), ["Latihan malam: ringan 20 menit.\nJaga tidur.\nBiasa."])
        XCTAssertEqual(AnyaActions.withoutQuoteMarkers("a > b"), "a > b", "only a marker at the start of a line goes")
    }
}
