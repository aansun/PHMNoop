import XCTest
@testable import Strand

/// The climb worked out from GPS altitudes: smoothed so a flat walk does not climb, and a real hill counts once.
final class RouteMathClimbTests: XCTestCase {
    func testFlatWalkWithJitterHasNoClimb() {
        let alts = (0..<400).map { i in 20 + (i.isMultiple(of: 2) ? 1.2 : -1.2) }
        XCTAssertEqual(RouteMath.climbMeters(altitudes: alts) ?? -1, 0, accuracy: 0.5)
    }

    func testAHillIsCountedOnceNotOncePerFix() {
        let up = (0..<300).map { 20 + 30 * Double($0) / 299 }
        let down = (0..<300).map { 50 - 30 * Double($0) / 299 }
        let climb = RouteMath.climbMeters(altitudes: up + down) ?? -1
        XCTAssertEqual(climb, 30, accuracy: 4)
    }

    func testTooFewReadingsSayNothing() {
        XCTAssertNil(RouteMath.climbMeters(altitudes: [1, 2, 3]))
        XCTAssertNil(RouteMath.climbMeters(altitudes: []))
    }
}
