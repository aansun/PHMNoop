import XCTest
@testable import StrandImport

/// The Hevy read client: what it asks for, how it pages, and how it reads what comes back. The network is a canned closure.
final class HevyClientTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }
    private let utc = TimeZone(identifier: "UTC")!

    /// Records every request and answers from a script.
    private final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [(path: String, query: [String: String], key: String)] = []
        private(set) var waits: [Double] = []
        var answer: @Sendable (Int, String, [String: String]) -> HevyClient.Response
        init(_ answer: @escaping @Sendable (Int, String, [String: String]) -> HevyClient.Response) { self.answer = answer }
        func transport() -> HevyClient.Transport {
            { [self] path, query, key in
                lock.lock(); calls.append((path, query, key)); let n = calls.count; lock.unlock()
                return answer(n, path, query)
            }
        }
        func sleeper() -> @Sendable (Double) async -> Void { { [self] s in lock.lock(); waits.append(s); lock.unlock() } }
    }

    private func ok(_ json: String) -> HevyClient.Response { .init(status: 200, body: Data(json.utf8)) }

    // MARK: Parsing

    func testAWorkoutKeepsEverySetWithItsType() {
        let page = HevyAPI.parseWorkouts(data: data("""
        {"page":1,"page_count":1,"workouts":[
         {"id":"w1","title":"Push","start_time":"2026-10-01T08:00:00+00:00","end_time":"2026-10-01T09:00:00+00:00","exercises":[
           {"index":0,"title":"Bench Press (Barbell)","exercise_template_id":"T1","notes":"slow","sets":[
             {"index":0,"type":"warmup","weight_kg":40,"reps":10},
             {"index":1,"type":"normal","weight_kg":80,"reps":8,"rpe":8.5},
             {"index":2,"type":"failure","weight_kg":80,"reps":6}]},
           {"index":1,"title":"Plank","sets":[{"index":0,"type":"normal","duration_seconds":60}]}]},
         {"title":"no id","start_time":"2026-10-02T08:00:00+00:00","exercises":[{"title":"X","sets":[{"reps":1}]}]},
         {"id":"w3","title":"Empty","start_time":"2026-10-03T08:00:00+00:00","exercises":[]}]}
        """), zone: utc)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.skipped, 2, "no id, and no exercises")
        let w = page.items[0]
        XCTAssertEqual(w.id, "w1"); XCTAssertEqual(w.title, "Push")
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 3600)
        XCTAssertEqual(w.exercises.count, 2)
        XCTAssertEqual(w.exercises[0].templateId, "T1")
        XCTAssertEqual(w.exercises[0].sets.map(\.type), ["warmup", "normal", "failure"])
        XCTAssertTrue(w.exercises[0].sets[0].isWarmup)
        XCTAssertEqual(w.exercises[0].sets[1].rpe, 8.5)
        XCTAssertEqual(w.exercises[1].sets[0].durationSeconds, 60)
        XCTAssertNil(w.exercises[1].sets[0].reps)
        XCTAssertEqual(w.setCount, 4)
    }

    func testAHostileRepCountIsDroppedNotTrapped() {
        let page = HevyAPI.parseWorkouts(data: data("""
        {"workouts":[{"id":"w","start_time":"2026-10-01T08:00:00+00:00","exercises":[{"title":"Curl","sets":[{"type":"normal","weight_kg":10,"reps":1e300}]}]}]}
        """), zone: utc)
        XCTAssertEqual(page.items.first?.exercises.first?.sets.first?.reps, nil)
    }

    func testARoutineReadsRepRangesRestAndANumericFolderId() {
        let page = HevyAPI.parseRoutines(data: data("""
        {"page":1,"page_count":1,"routines":[
          {"id":"r1","title":"Sesi B","folder_id":42,"notes":"home","exercises":[
            {"title":"Romanian Deadlift (Barbell)","rest_seconds":30,"notes":"hamstring","exercise_template_id":"T9","sets":[
              {"type":"normal","weight_kg":60,"rep_range":{"start":10,"end":15}},
              {"type":"normal","rep_range":{"start":10,"end":15}}]}]},
          {"id":"r2","title":"Bare","folder_id":null,"exercises":[]},
          {"id":"r3","exercises":[]}]}
        """))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.skipped, 1, "a routine with no title")
        let r = page.items[0]
        XCTAssertEqual(r.folderId, "42")
        XCTAssertEqual(r.notes, "home")
        XCTAssertEqual(r.exercises[0].restSeconds, 30)
        XCTAssertEqual(r.exercises[0].sets.count, 2)
        XCTAssertEqual(r.exercises[0].sets[0].repRangeStart, 10)
        XCTAssertEqual(r.exercises[0].sets[0].repRangeEnd, 15)
        XCTAssertEqual(r.exercises[0].sets[0].weightKg, 60)
        XCTAssertNil(page.items[1].folderId)
    }

    func testFoldersReadAStringOrNumericId() {
        let page = HevyAPI.parseRoutineFolders(data: data(#"{"routine_folders":[{"id":7,"title":"PPL","index":1},{"id":"x","title":"Home"},{"id":9}]}"#))
        XCTAssertEqual(page.items.map(\.id), ["7", "x"])
        XCTAssertEqual(page.items.map(\.title), ["PPL", "Home"])
        XCTAssertEqual(page.skipped, 1)
    }

    // MARK: The client

    func testItPagesToTheLastPageAndAsksForTheLargestPageSize() async throws {
        let wire = Wire { n, _, q in
            let page = Int(q["page"] ?? "1") ?? 1
            return self.ok("""
            {"page":\(page),"page_count":3,"workouts":[{"id":"w\(page)","start_time":"2026-10-0\(page)T08:00:00+00:00","exercises":[{"title":"Squat","sets":[{"type":"normal","weight_kg":100,"reps":5}]}]}]}
            """)
        }
        let client = HevyClient(apiKey: "  secret-key \n", transport: wire.transport(), sleep: wire.sleeper())
        let got = try await client.workouts(zone: utc)
        XCTAssertEqual(got.items.map(\.id), ["w1", "w2", "w3"])
        XCTAssertEqual(wire.calls.count, 3)
        XCTAssertEqual(wire.calls.map { $0.query["page"] }, ["1", "2", "3"])
        XCTAssertTrue(wire.calls.allSatisfy { $0.query["pageSize"] == "10" && $0.path == "/v1/workouts" })
        XCTAssertTrue(wire.calls.allSatisfy { $0.key == "secret-key" }, "the key is trimmed and sent on every request")
    }

    func testARepeatedPageNumberEndsTheLoopInsteadOfSpinning() async throws {
        let wire = Wire { _, _, _ in self.ok(#"{"page":1,"page_count":5,"routines":[]}"#) }
        let client = HevyClient(apiKey: "k", transport: wire.transport(), sleep: wire.sleeper())
        _ = try await client.routines()
        XCTAssertEqual(wire.calls.count, 2, "page 1 answered page 1 again, so it stops rather than asking for page 3")
    }

    func testARefusedKeyIsReportedAsSuch() async {
        for status in [401, 403] {
            let wire = Wire { _, _, _ in .init(status: status, body: Data()) }
            let client = HevyClient(apiKey: "bad", transport: wire.transport(), sleep: wire.sleeper())
            do { _ = try await client.userInfo(); XCTFail("should throw") }
            catch { XCTAssertEqual(error as? HevyClient.Failure, .unauthorized) }
            XCTAssertEqual(wire.calls.count, 1, "no retry on a refused key")
        }
    }

    func testRateLimitingWaitsAndTriesAgain() async throws {
        let wire = Wire { n, _, _ in n < 3 ? .init(status: 429, body: Data()) : self.ok(#"{"data":{"id":"u1","name":"aansun"}}"#) }
        let client = HevyClient(apiKey: "k", transport: wire.transport(), sleep: wire.sleeper())
        let info = try await client.userInfo()
        XCTAssertEqual(info?.name, "aansun")
        XCTAssertEqual(wire.calls.count, 3)
        XCTAssertEqual(wire.waits, [2, 4], "a growing wait")
    }

    func testRateLimitingGivesUpAfterThreeWaits() async {
        let wire = Wire { _, _, _ in .init(status: 429, body: Data()) }
        let client = HevyClient(apiKey: "k", transport: wire.transport(), sleep: wire.sleeper())
        do { _ = try await client.userInfo(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? HevyClient.Failure, .rateLimited) }
        XCTAssertEqual(wire.calls.count, 4)
    }

    func testAServerErrorAndAConnectionFailureAreDistinct() async {
        let down = Wire { _, _, _ in .init(status: 500, body: Data()) }
        do { _ = try await HevyClient(apiKey: "k", transport: down.transport(), sleep: down.sleeper()).workoutCount(); XCTFail() }
        catch { XCTAssertEqual(error as? HevyClient.Failure, .http(500)) }

        struct Boom: Error {}
        let transport: HevyClient.Transport = { _, _, _ in throw Boom() }
        do { _ = try await HevyClient(apiKey: "k", transport: transport).workoutCount(); XCTFail() }
        catch { if case .network = (error as? HevyClient.Failure) ?? .cancelled {} else { XCTFail("expected .network, got \(error)") } }
    }

    func testTemplatesAskForPagesOfAHundred() async throws {
        let wire = Wire { _, _, _ in self.ok(#"{"page":1,"page_count":1,"exercise_templates":[{"id":"T1","title":"Bench Press (Barbell)","primary_muscle_group":"chest","secondary_muscle_groups":["triceps","shoulders"]}]}"#) }
        let got = try await HevyClient(apiKey: "k", transport: wire.transport(), sleep: wire.sleeper()).exerciseTemplates()
        XCTAssertEqual(wire.calls.first?.query["pageSize"], "100")
        XCTAssertEqual(got.first?.primaryMuscleGroup, .chest)
        XCTAssertEqual(got.first?.secondaryMuscleGroups, [.triceps, .shoulders])
    }

    func testTheClientOnlyEverReads() async throws {
        // The transport has no verb: a path and a query, answered with a body. There is nothing to POST with.
        let wire = Wire { _, _, _ in self.ok(#"{"page":1,"page_count":1,"routine_folders":[]}"#) }
        _ = try await HevyClient(apiKey: "k", transport: wire.transport(), sleep: wire.sleeper()).routineFolders()
        XCTAssertEqual(wire.calls.first?.path, "/v1/routine_folders")
    }
}
