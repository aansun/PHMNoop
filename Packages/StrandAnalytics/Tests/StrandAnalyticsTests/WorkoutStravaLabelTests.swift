import XCTest
import WhoopStore
@testable import StrandAnalytics

/// Tests for reading Strava-sourced workouts as labels: the notes format that keeps Strava's own sport type, the type-to-class map, the rule that
/// decides between the type and the name PHMN gave it, the Strava origin, and the evidence kind that keeps heart-rate-only windows apart.
final class WorkoutStravaLabelTests: XCTestCase {

    // MARK: Notes format

    func testNotesKeepTheStravaTypeAndTheTitle() {
        XCTAssertEqual(WorkoutSportMap.stravaNotes(title: "Evening ski", stravaType: "NordicSki"), "Strava · NordicSki · Evening ski")
        XCTAssertEqual(WorkoutSportMap.stravaNotes(title: nil, stravaType: "Run"), "Strava · Run")
        XCTAssertEqual(WorkoutSportMap.stravaNotes(title: "  ", stravaType: nil), "Strava")
    }

    func testAnUnknownTypeIsNotWrittenIntoTheNotes() {
        XCTAssertEqual(WorkoutSportMap.stravaNotes(title: "Lunch", stravaType: "Segway"), "Strava · Lunch",
                       "only Strava's own sport types are kept, so a title can never be mistaken for one")
    }

    func testTheTypeIsReadBackFromTheNotes() {
        XCTAssertEqual(WorkoutSportMap.stravaType(fromNotes: "Strava · NordicSki · Evening ski"), "NordicSki")
        XCTAssertEqual(WorkoutSportMap.stravaType(fromNotes: "Strava · Ride"), "Ride")
        XCTAssertTrue(WorkoutSportMap.isStravaNotes("Strava · NordicSki · Evening ski"))
    }

    func testOldNotesWithOnlyATitleHaveNoType() {
        // Made before the type was kept: "Strava · <title>". A title is not a Strava type.
        XCTAssertNil(WorkoutSportMap.stravaType(fromNotes: "Strava · Morning run in the park"))
        XCTAssertTrue(WorkoutSportMap.isStravaNotes("Strava · Morning run in the park"))
        XCTAssertNil(WorkoutSportMap.stravaType(fromNotes: "Strava"))
    }

    func testNotesThatAreNotFromStravaAreNotRecognised() {
        for n in [nil, "", "Felt great", "My Strava ride", "Stravaganza", "strava · Run"] as [String?] {
            XCTAssertFalse(WorkoutSportMap.isStravaNotes(n), "'\(n ?? "nil")' is not a Strava row")
            XCTAssertNil(WorkoutSportMap.stravaType(fromNotes: n))
        }
    }

    func testWriteThenReadRoundTrips() {
        for type in ["Run", "TrailRun", "NordicSki", "WeightTraining", "VirtualRide"] {
            let notes = WorkoutSportMap.stravaNotes(title: "Some title · with a dot", stravaType: type)
            XCTAssertEqual(WorkoutSportMap.stravaType(fromNotes: notes), type)
        }
    }

    // MARK: Type to class

    func testStravaTypesMapToTheirClass() {
        let cases: [(String, CoarseWorkoutClass)] = [
            ("Run", .run), ("VirtualRun", .run), ("TrailRun", .run),
            ("Walk", .walk), ("Hike", .walk),
            ("Ride", .cycle), ("EBikeRide", .cycle), ("GravelRide", .cycle), ("MountainBikeRide", .cycle), ("VirtualRide", .cycle),
            ("WeightTraining", .strength),
            ("AlpineSki", .ski), ("Snowboard", .ski),
            ("NordicSki", .other), ("BackcountrySki", .other), ("RollerSki", .other), ("Handcycle", .other),
            ("Yoga", .other), ("Swim", .other), ("Tennis", .other), ("Crossfit", .other),
        ]
        for (type, expected) in cases { XCTAssertEqual(WorkoutSportMap.coarseClass(forStravaType: type), expected, type) }
    }

    func testGenericAndUnknownStravaTypesAreNotLabels() {
        XCTAssertNil(WorkoutSportMap.coarseClass(forStravaType: "Workout"))
        XCTAssertNil(WorkoutSportMap.coarseClass(forStravaType: "HighIntensityIntervalTraining"))
        XCTAssertNil(WorkoutSportMap.coarseClass(forStravaType: "Segway"))
    }

    // MARK: Which wins, the type or the name

    func testWithNoStravaTypeTheNameIsTheLabel() {
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Running", stravaType: nil), .run)
        XCTAssertNil(WorkoutSportMap.labelClass(sport: "Workout", stravaType: nil))
    }

    func testTheImportersLossyNameDoesNotHideACrossCountrySki() {
        // The importer saves NordicSki and BackcountrySki as "Skiing". Read as a name that is downhill; the type says otherwise.
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Skiing", stravaType: "NordicSki"), .other)
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Skiing", stravaType: "BackcountrySki"), .other)
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Skiing", stravaType: "AlpineSki"), .ski, "a real alpine ski stays ski")
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Cycling", stravaType: "Handcycle"), .other, "Handcycle is saved as Cycling")
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Cycling", stravaType: "Ride"), .cycle)
    }

    func testAChangeByThePersonBeatsTheStravaType() {
        // They imported a Ride and then renamed it Hiking: the name is theirs now.
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Hiking", stravaType: "Ride"), .walk)
        // The importer saved NordicSki as "Skiing"; the person changed it to "Running": their word.
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Running", stravaType: "NordicSki"), .run)
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Strength Training", stravaType: "Walk"), .strength)
    }

    func testAGenericNameFallsBackToTheStravaType() {
        XCTAssertEqual(WorkoutSportMap.labelClass(sport: "Workout", stravaType: "Run"), .run)
        XCTAssertNil(WorkoutSportMap.labelClass(sport: "Workout", stravaType: "Workout"))
    }

    // MARK: Origin

    func testAManualRowFromStravaIsItsOwnOriginAndALabel() {
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000,
                                              notes: "Strava · Run · Morning")
        XCTAssertEqual(o, .stravaImported)
        XCTAssertTrue(o.isLabel(includeBeforeLog: false))
    }

    func testAStravaRowIsALabelEvenFromBeforeTheLogBegan() {
        let before = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 1_000, suggestions: [], logStartedAt: 5_000, notes: "Strava")
        XCTAssertEqual(before, .stravaImported, "its sport came from Strava, so the missing log does not matter")
        let noLog = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 9_000, suggestions: [], logStartedAt: nil, notes: "Strava · Run")
        XCTAssertEqual(noLog, .stravaImported)
    }

    func testOrdinaryNotesDoNotMakeAStravaRow() {
        let o = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000, notes: "Felt great")
        XCTAssertEqual(o, .typedByPerson)
        let none = WorkoutLabelProvenance.origin(source: .manual, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000)
        XCTAssertEqual(none, .typedByPerson, "notes are optional, and absent notes change nothing")
    }

    func testStravaNotesOnANonManualSourceDoNotChangeItsOrigin() {
        let o = WorkoutLabelProvenance.origin(source: .whoop, sport: "Running", startTs: 10_000, suggestions: [], logStartedAt: 5_000, notes: "Strava")
        XCTAssertEqual(o, .strapOwn)
    }

    func testTheLabelOriginsNowIncludeStrava() {
        let labels = WorkoutLabelOrigin.allCases.filter { $0.isLabel(includeBeforeLog: false) }
        XCTAssertEqual(Set(labels), [.typedByPerson, .editedAfterSuggestion, .imported, .stravaImported])
    }

    // MARK: Evidence kind

    func testEvidenceIsFullWhenTicksOrGravityAreThere() {
        XCTAssertEqual(WorkoutWindowEvidence.of(tickCoverage: 0.9, gravitySamples: 0), .full)
        XCTAssertEqual(WorkoutWindowEvidence.of(tickCoverage: 0, gravitySamples: WorkoutWindowEvidence.minGravitySamples), .full)
        XCTAssertEqual(WorkoutWindowEvidence.of(tickCoverage: WorkoutTypeClassifier.minTickCoverage, gravitySamples: 0), .full)
    }

    func testEvidenceIsHeartRateOnlyWithoutMotion() {
        XCTAssertEqual(WorkoutWindowEvidence.of(tickCoverage: 0, gravitySamples: 0), .heartRateOnly)
        XCTAssertEqual(WorkoutWindowEvidence.of(tickCoverage: WorkoutTypeClassifier.minTickCoverage - 0.01, gravitySamples: WorkoutWindowEvidence.minGravitySamples - 1),
                       .heartRateOnly, "just under both bars is still not enough")
    }
}
