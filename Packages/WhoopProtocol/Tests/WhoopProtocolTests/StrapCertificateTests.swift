import XCTest
@testable import WhoopProtocol

final class StrapCertificateTests: XCTestCase {
    func testTheLineAStrapSentSplitAcrossTwoFrames() {
        var scanner = StrapCertificateScanner()
        // The way a 5.0 / MG sends it: the word is cut in two.
        XCTAssertEqual(scanner.ingest(" 7, 123456789: BLE: Stored certi", sequence: 10), [])
        XCTAssertEqual(scanner.ingest("ficate is valid", sequence: 11), [], "an unfinished line is not read yet")
        XCTAssertEqual(scanner.ingest("\n 7, 123456789: BLE: Turn off real", sequence: 12),
                       [StrapCertificateReport(verdict: .valid, message: "BLE: Stored certificate is valid")])
    }

    func testNegativeWordingsAreNotTakenForValid() {
        for line in ["7, 1: BLE: Stored certificate is invalid", "BLE: Stored certificate is not valid", "BLE: certificate expired",
                     "BLE: Stored certificate has been revoked", "BLE: invalid certificate"] {
            XCTAssertEqual(StrapCertificateReport.read(line: line)?.verdict, .invalid, line)
        }
    }

    func testOtherWordsAreKeptWithoutAVerdict() {
        let r = StrapCertificateReport.read(line: "7, 5: BLE: Loading certificate")
        XCTAssertNotNil(r)
        XCTAssertNil(r?.verdict)
        XCTAssertEqual(r?.message, "BLE: Loading certificate")
        XCTAssertNil(StrapCertificateReport.read(line: "BLE: History burst success"))
    }

    func testAGapInTheSequenceDropsTheHalfLine() {
        var scanner = StrapCertificateScanner()
        _ = scanner.ingest("BLE: Stored certi", sequence: 1)
        XCTAssertEqual(scanner.ingest("ficate is valid\n", sequence: 40), [])
        // A few places taken by event records are ordinary.
        _ = scanner.ingest("BLE: Stored certi", sequence: 254)
        XCTAssertEqual(scanner.ingest("ficate is valid\n", sequence: 1).first?.verdict, .valid, "the sequence wraps at 256")
    }

    func testTheLogRemembersAChange() {
        var log = StrapCertificateLog()
        let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000), t2 = Date(timeIntervalSince1970: 3_000)
        let valid = StrapCertificateReport(verdict: .valid, message: "BLE: Stored certificate is valid")
        XCTAssertFalse(log.record(valid, at: t0), "the first verdict is not a change")
        XCTAssertFalse(log.record(valid, at: t1))
        XCTAssertEqual(log.since, t0)
        XCTAssertEqual(log.lastSeen, t1)
        XCTAssertNil(log.previous)
        XCTAssertTrue(log.record(StrapCertificateReport(verdict: .invalid, message: "BLE: Stored certificate is invalid"), at: t2))
        XCTAssertEqual(log.verdict, .invalid)
        XCTAssertEqual(log.previous?.verdict, .valid)
        XCTAssertEqual(log.since, t2)
        // A line written earlier and handed over late says nothing about now.
        XCTAssertFalse(log.record(valid, at: t1))
        XCTAssertEqual(log.verdict, .invalid)
        XCTAssertEqual(log.lastSeen, t2)
        // A line without a verdict changes nothing that was concluded.
        XCTAssertFalse(log.record(StrapCertificateReport(verdict: nil, message: "BLE: Loading certificate"), at: t2))
        XCTAssertEqual(log.verdict, .invalid)
        XCTAssertEqual(log.otherMessage, "BLE: Loading certificate")
        let data = try! JSONEncoder().encode(log)
        XCTAssertEqual(try! JSONDecoder().decode(StrapCertificateLog.self, from: data), log)
    }
}
