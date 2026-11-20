import XCTest
@testable import StrandAnalytics

final class AnyaPageInsightTests: XCTestCase {
    func testParsesTheFourParagraphs() {
        let reply = """
        HEADLINE: HRV is 13% above your usual, which is good.
        SEE: 93 ms against a 30-day average of 82 ms.
        MEAN: A rested night and a lighter day before it fit this rise.
        DO: Keep the same bedtime and go easy on alcohol so it holds.
        """
        let i = AnyaPageInsight.parse(reply)
        XCTAssertEqual(i?.headline, "HRV is 13% above your usual, which is good.")
        XCTAssertEqual(i?.see, "93 ms against a 30-day average of 82 ms.")
        XCTAssertEqual(i?.mean, "A rested night and a lighter day before it fit this rise.")
        XCTAssertEqual(i?.advice, "Keep the same bedtime and go easy on alcohol so it holds.")
    }

    func testToleratesMarkdownLowerCaseAndTextBeforeTheFirstLabel() {
        let reply = """
        Sure, here is the read.
        **HEADLINE:** Sleep was short, needs attention.
        ## see:
        6h 10m against the 7h 15m you need.
        **MEAN**: Two short nights in a row.
        **DO:** Be asleep 30 minutes earlier tonight.
        """
        let i = AnyaPageInsight.parse(reply)
        XCTAssertEqual(i?.headline, "Sleep was short, needs attention.")
        XCTAssertEqual(i?.see, "6h 10m against the 7h 15m you need.")
        XCTAssertEqual(i?.advice, "Be asleep 30 minutes earlier tonight.")
    }

    func testAMultiLineParagraphIsJoined() {
        let i = AnyaPageInsight.parse("HEADLINE: Fine.\nMEAN: First line\nsecond line.\nDO: Keep going.")
        XCTAssertEqual(i?.mean, "First line second line.")
    }

    func testNoHeadlineOrNothingToExplainIsNotAnInsight() {
        XCTAssertNil(AnyaPageInsight.parse("Your body is holding steady, like a tree."))
        XCTAssertNil(AnyaPageInsight.parse("SEE: 93 ms.\nDO: Rest."))
        XCTAssertNil(AnyaPageInsight.parse("HEADLINE: Only a headline."))
    }

    func testAWordThatStartsALabelIsNotALabel() {
        // "Seeing" and "Done" start with SEE and DO but are not followed by a colon.
        XCTAssertNil(AnyaPageInsight.parse("Seeing the figures, all good.\nDone for today."))
    }

    func testMarkdownLeavesOutEmptyParts() {
        let i = AnyaPageInsight(headline: "Fine.", see: "93 ms.", mean: "", advice: "Keep going.")
        XCTAssertEqual(i.markdown(seeTitle: "What I see", meanTitle: "What it means", adviceTitle: "What to do"),
                       "Fine.\n\n**What I see**\n93 ms.\n\n**What to do**\nKeep going.")
    }
}
