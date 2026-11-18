import XCTest
@testable import StrandAnalytics

final class FeedbackIssueTests: XCTestCase {
    private let details = FeedbackIssue.Details(app: "3.0.0", build: "417", os: "26.5", device: "iPhone18,3", language: "id")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { l, _ in l })
    }

    func testTheIssueIsOnTheProjectsRepositoryAndCarriesTitleBodyAndLabel() throws {
        let url = try XCTUnwrap(FeedbackIssue.url(repo: "aansun/PHMNoop", kind: .problem, details: details))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/aansun/PHMNoop/issues/new")
        let q = query(url)
        XCTAssertEqual(q["title"], "Problem: ")
        XCTAssertEqual(q["labels"], "bug")
        XCTAssertTrue(q["body"]?.contains("## What happened?") == true)
    }

    func testFeedbackAndProblemAreDifferentOutlines() throws {
        let f = query(try XCTUnwrap(FeedbackIssue.url(repo: "a/b", kind: .feedback, details: details)))
        XCTAssertEqual(f["title"], "Feedback: ")
        XCTAssertEqual(f["labels"], "feedback")
        XCTAssertTrue(f["body"]?.contains("## What would you like to tell us?") == true)
        XCTAssertFalse(f["body"]?.contains("Steps to reproduce") == true)
    }

    func testTheDetailsAreOnlyTheVersionsThePhoneAndTheLanguage() {
        let b = FeedbackIssue.body(.problem, details)
        for line in ["App: PHMN 3.0.0 (417)", "iOS: 26.5", "Device: iPhone18,3", "Language: id"] { XCTAssertTrue(b.contains(line), line) }
        // Exactly these four facts and nothing else is added.
        XCTAssertEqual(b.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count, 4)
    }

    func testAPlusInTheTextSurvivesAsAPlusAndNewlinesAreEncoded() throws {
        var d = details; d.app = "3.0.0+beta"
        let url = try XCTUnwrap(FeedbackIssue.url(repo: "a/b", kind: .feedback, details: d))
        XCTAssertFalse(url.absoluteString.contains("+"), "a bare + would be read as a space")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertTrue(url.absoluteString.contains("%0A"))
        XCTAssertEqual(query(url)["body"]?.contains("3.0.0+beta"), true)
    }
}
