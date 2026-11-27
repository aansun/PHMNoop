import XCTest
@testable import StrandAnalytics

final class AnyaToolsTests: XCTestCase {
    func testEveryToolHasAClosedSchema() {
        XCTAssertEqual(AnyaTools.definitions.compactMap { $0["name"] as? String }, AnyaTools.Name.allCases.map(\.rawValue))
        for tool in AnyaTools.definitions {
            let schema = tool["input_schema"] as? [String: Any]
            XCTAssertEqual(schema?["additionalProperties"] as? Bool, false, "\(tool["name"] ?? "")")
            XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: tool))
        }
    }

    func testARangeIsClampedAndNeverRunsIntoTheFuture() {
        let r = AnyaTools.range(["days": 5000], today: "2026-03-10", standard: 30, most: 730)
        XCTAssertEqual(r.days, 730)
        let earlier = AnyaTools.range(["days": "7", "end_date": "2026-03-01"], today: "2026-03-10", standard: 30, most: 730)
        XCTAssertEqual(earlier.from, "2026-02-23")
        XCTAssertEqual(earlier.to, "2026-03-01")
        XCTAssertEqual(AnyaTools.range(["end_date": "2027-01-01"], today: "2026-03-10", standard: 3, most: 9).to, "2026-03-10")
        XCTAssertEqual(AnyaTools.range(["end_date": "yesterday"], today: "2026-03-10", standard: 3, most: 9).from, "2026-03-08")
    }

    func testLongRangesAreAveraged() {
        XCTAssertEqual(AnyaTools.group([:], days: 30), .day)
        XCTAssertEqual(AnyaTools.group([:], days: 90), .week)
        XCTAssertEqual(AnyaTools.group([:], days: 365), .month)
        XCTAssertEqual(AnyaTools.group(["group": "day"], days: 365), .day)
    }

    func testATableShowsMissingAsADashAndCountsDaysInAnAverage() {
        let rows: [(day: String, values: [Double?])] = [("2026-03-02", [60, nil]), ("2026-03-03", [70, 50]), ("2026-03-04", [nil, nil])]
        XCTAssertEqual(AnyaTools.table(columns: ["a", "b"], rows: rows, group: .day), "date | a | b\n2026-03-02 | 60 | -\n2026-03-03 | 70 | 50")
        XCTAssertTrue(AnyaTools.table(columns: ["a", "b"], rows: rows, group: .week).hasSuffix("week of 2026-03-02 | 65 (2) | 50 (1)"))
        XCTAssertEqual(AnyaTools.table(columns: ["a"], rows: [("2026-03-02", [nil])], group: .day), "No data in this period.")
    }

    func testSessionTotalsAreCountedForTheModel() {
        let totals = AnyaTools.sessionTotals([("Run", 30), ("Yoga", nil), ("Run", 45.4)])
        XCTAssertTrue(totals.hasSuffix("3 sessions, 75 min. By sport: Run 2 (75 min), Yoga 1 (0 min)."), totals)
        let long = "header\n" + totals + "\n" + (1...100).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertTrue(AnyaTools.capped(long, limit: 80).hasPrefix("header\n" + totals + "\n"))
    }

    func testACappedAnswerKeepsTheNewestLines() {
        let text = "header\n" + (1...100).map { "line \($0)" }.joined(separator: "\n")
        let capped = AnyaTools.capped(text, limit: 60)
        XCTAssertTrue(capped.hasPrefix("header\n"))
        XCTAssertTrue(capped.hasSuffix("line 100"))
        XCTAssertFalse(capped.contains("line 1\n"))
    }
}

final class AnyaAboutYouTests: XCTestCase {
    func testNotesAddUpWithoutRepeating() {
        var about = AnyaAboutYou()
        XCTAssertEqual(about.promptBlock, "")
        XCTAssertTrue(about.note(.equipment, " dumbbells "))
        XCTAssertTrue(about.note(.equipment, "Dumbbells"))
        XCTAssertTrue(about.note(.equipment, "a bike"))
        XCTAssertEqual(about[.equipment], "dumbbells; a bike")
        XCTAssertTrue(about.note(.equipment, "only a bike", replacing: true))
        XCTAssertTrue(about.promptBlock.hasSuffix("- Equipment and places: only a bike"))
        XCTAssertFalse(about.note(.goals, "  "))
        XCTAssertFalse(about.note(.equipment, String(repeating: "x", count: AnyaAboutYou.longest)))
        XCTAssertEqual(about[.equipment], "only a bike")
    }

    func testItIsStoredAndClearedWithItsLastLine() {
        let defaults = UserDefaults(suiteName: "anya-about-you-test")!
        defer { defaults.removePersistentDomain(forName: "anya-about-you-test") }
        var about = AnyaAboutYou()
        about[.goals] = "10 km"
        about.save(defaults)
        XCTAssertEqual(AnyaAboutYou.load(defaults), about)
        about[.goals] = ""
        about.save(defaults)
        XCTAssertNil(defaults.data(forKey: AnyaAboutYou.defaultsKey))
    }
}

final class AnthropicWireTests: XCTestCase {
    func testOnlyNewerModelsAreSentAnEffort() {
        XCTAssertTrue(AnthropicWire.takesEffort("claude-haiku-5-5"))
        XCTAssertTrue(AnthropicWire.takesEffort("claude-sonnet-4-6"))
        XCTAssertFalse(AnthropicWire.takesEffort("claude-haiku-4-5"))
        XCTAssertFalse(AnthropicWire.takesEffort("claude-3-5-sonnet-latest"))
        let body = AnthropicWire.body(model: "claude-haiku-5-5", system: "s", messages: [], stream: true)
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["thinking"])
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
    }

    func testAReplyThatBeginsWithThinkingStillHasItsText() {
        let content: [[String: Any]] = [["type": "thinking", "thinking": "", "signature": "x"], ["type": "text", "text": "Halo"]]
        XCTAssertEqual(AnthropicWire.text(ofContent: content), "Halo")
    }

    func testAStreamedToolRoundIsRebuiltWhole() {
        var message = AnthropicStreamMessage()
        let events = [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Sebentar."}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t1","name":"get_workouts","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"days\":"}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":" 14}"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
        ]
        let text = events.compactMap { message.ingest($0) }.joined()
        XCTAssertEqual(text, "Sebentar.")
        XCTAssertEqual(message.stopReason, "tool_use")
        XCTAssertEqual(message.toolUses, [.init(id: "t1", name: "get_workouts", inputJSON: "{\"days\": 14}")])
        XCTAssertEqual(message.content[0]["signature"] as? String, "abc")
        XCTAssertEqual((message.content[2]["input"] as? [String: Any])?["days"] as? Int, 14)
    }

    func testACallThatArrivedHalfIsNotRun() {
        var message = AnthropicStreamMessage()
        message.ingest(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"get_profile","input":{}}}"#)
        message.ingest(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"da"}}"#)
        XCTAssertEqual(message.toolUses, [])
    }
}
