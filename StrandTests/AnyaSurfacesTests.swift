import XCTest
@testable import Strand

final class AnyaSurfacesTests: XCTestCase {

    private var all: [AnyaSurface] {
        AnyaSurface.Topic.allCases.map { .page($0) } + AnyaSurface.Module.allCases.map { .chat($0) } + [.brief]
    }

    /// Every surface says what it reads, what to do when the reading is poor, what to do when it is good, what to avoid, and how long it may run.
    func testEveryProfileIsComplete() {
        for s in all {
            let p = AnyaSurface.profile(s)
            XCTAssertFalse(p.focus.isEmpty, "\(s)")
            XCTAssertFalse(p.reads.isEmpty, "\(s)")
            XCTAssertFalse(p.improve.isEmpty, "\(s)")
            XCTAssertFalse(p.maintain.isEmpty, "\(s)")
            XCTAssertFalse(p.watch.isEmpty, "\(s)")
            XCTAssertTrue((50...130).contains(p.words), "\(s) allows \(p.words) words")
        }
    }

    /// The page contract (read, explain, advise) holds for page cards; a question in a sheet is a conversation.
    func testInstructionsCarryTheContract() {
        for t in AnyaSurface.Topic.allCases {
            let text = AnyaSurface.pageInstruction(t)
            XCTAssertTrue(text.contains("one concrete step"), "\(t)")
            XCTAssertTrue(text.contains("Never invent a figure"), "\(t)")
            XCTAssertTrue(text.contains("No metaphors"), "\(t)")
        }
        for m in AnyaSurface.Module.allCases {
            let text = AnyaSurface.chatInstruction(m)
            XCTAssertTrue(text.contains("the way you normally talk"), "\(m)")
            XCTAssertTrue(text.contains("No diagnosis"), "\(m)")
            XCTAssertFalse(text.contains(AnyaSurface.contract), "a chat is not held to the page contract")
        }
    }

    /// The contract does not use words the model copies into its answers (labels, or the phrase it once echoed in every reply).
    func testTheContractHasNoLabelsToEcho() {
        for word in ["READ:", "EXPLAIN:", "ADVISE:", "HEADLINE:"] { XCTAssertFalse(AnyaSurface.contract.contains(word), word) }
        XCTAssertTrue(AnyaSurface.contract.contains("never the phrases"))
    }

    func testTopicsFromMetricKeysAndTitles() {
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "hrv", title: "HRV"), .hrv)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "rhr", title: "Resting heart rate"), .restingHR)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "resp_rate", title: "Respiratory rate"), .vitals)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "spo2_candidate", title: "Blood oxygen"), .vitals)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "skin_temp", title: "Skin temperature"), .skinTemp)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "weight", title: "Weight"), .weight)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "", title: "Recovery"), .recovery)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "", title: "Strain"), .strain)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "", title: "sleep"), .sleep)
        XCTAssertEqual(AnyaSurface.Topic.of(metricKey: "steps_est", title: "Steps"), .other)
    }

    func testModulesFromContextNames() {
        XCTAssertEqual(AnyaSurface.Module.of(context: "Today"), .today)
        XCTAssertEqual(AnyaSurface.Module.of(context: "Health"), .health)
        XCTAssertEqual(AnyaSurface.Module.of(context: "Breathing"), .breathing)
        XCTAssertEqual(AnyaSurface.Module.of(context: "workouts"), .workouts)
        XCTAssertEqual(AnyaSurface.Module.of(context: "nutrition"), .nutrition)
        XCTAssertEqual(AnyaSurface.Module.of(context: "device"), .device)
        XCTAssertEqual(AnyaSurface.Module.of(context: "trends"), .trends)
        XCTAssertEqual(AnyaSurface.Module.of(context: "sleep"), .sleep)
    }
}
