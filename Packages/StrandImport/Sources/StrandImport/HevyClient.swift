import Foundation

// A read-only client for Hevy's own API (https://api.hevyapp.com/docs), for a person who brings their own API key.
//
// Everything here is Foundation-only and pure: the network is a closure the caller supplies (`HevyClient.Transport`), so the paging, the
// retry and the parsing run in tests against canned bodies. Nothing is ever written to Hevy: the client has GET requests only.
//
// The shapes follow Hevy's published OpenAPI spec as far as `HevyAPI` already did (workouts, exercise templates, user info) and its
// routines and routine folders. Every field is read tolerantly -- this is another server's data -- and an element that cannot be used is
// skipped and counted, never fatal.

// MARK: - Models

public extension HevyAPI {

    /// One set as Hevy stores it.
    struct WorkoutSet: Sendable, Equatable {
        public let index: Int
        /// `normal`, `warmup`, `dropset` or `failure`; anything else is kept as given.
        public let type: String
        public let weightKg: Double?
        public let reps: Int?
        public let rpe: Double?
        public let durationSeconds: Double?
        public let distanceMeters: Double?
        public var isWarmup: Bool { type == "warmup" || type == "warm_up" || type == "warm-up" }
    }

    struct WorkoutExercise: Sendable, Equatable {
        public let title: String
        public let templateId: String?
        public let notes: String?
        public let sets: [WorkoutSet]
    }

    /// A workout with every set, which is what a progress chart and a "previous" column are made of. The CSV lane keeps only totals.
    struct Workout: Sendable, Equatable {
        public let id: String
        public let title: String?
        public let start: Date
        public let end: Date
        public let exercises: [WorkoutExercise]
        public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    }

    struct RoutineSet: Sendable, Equatable {
        public let type: String
        public let weightKg: Double?
        public let reps: Int?
        public let repRangeStart: Int?
        public let repRangeEnd: Int?
        public let durationSeconds: Double?
        public var isWarmup: Bool { type == "warmup" || type == "warm_up" || type == "warm-up" }
    }

    struct RoutineExercise: Sendable, Equatable {
        public let title: String
        public let templateId: String?
        public let restSeconds: Int?
        public let notes: String?
        public let sets: [RoutineSet]
    }

    struct Routine: Sendable, Equatable {
        public let id: String
        public let title: String
        public let folderId: String?
        public let notes: String?
        public let exercises: [RoutineExercise]
    }

    struct RoutineFolder: Sendable, Equatable {
        public let id: String
        public let title: String
        public let index: Int
    }
}

// MARK: - Parsing

public extension HevyAPI {

    /// A set count, rep count or index off a JSON number, bounded so `Int(_:)` cannot trap on a hostile value.
    private static func int(_ any: Any?) -> Int? {
        guard let d = LiftingImporter.jsonDouble(any), d.isFinite, d >= 0, d < 1e6 else { return nil }
        return Int(d)
    }

    private static func positive(_ any: Any?) -> Double? {
        guard let d = LiftingImporter.jsonDouble(any), d.isFinite, d > 0, d < 1e7 else { return nil }
        return d
    }

    /// An id as text, whether Hevy sends it as a string or as a number (folder ids are numbers).
    private static func idString(_ any: Any?) -> String? {
        if let s = any as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let n = any as? NSNumber, !(any is Bool) { return n.stringValue }
        return nil
    }

    private static func text(_ any: Any?) -> String? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// `GET /v1/workouts` with every set. A workout with no id, no usable start or no exercises is skipped and counted.
    static func parseWorkouts(data: Data, zone: TimeZone = .current) -> Page<Workout> {
        parsePage(data, key: "workouts") { w in
            guard let id = idString(w["id"]),
                  let startStr = w["start_time"] as? String, let start = LiftingImporter.parseDate(startStr, zone: zone) else { return nil }
            let end = (w["end_time"] as? String).flatMap { LiftingImporter.parseDate($0, zone: zone) }.map { max($0, start) } ?? start
            let exercises: [WorkoutExercise] = ((w["exercises"] as? [Any]) ?? []).compactMap { e in
                guard let ex = e as? [String: Any], let title = text(ex["title"]) else { return nil }
                let sets: [WorkoutSet] = ((ex["sets"] as? [Any]) ?? []).enumerated().compactMap { i, s in
                    guard let st = s as? [String: Any] else { return nil }
                    return WorkoutSet(index: int(st["index"]) ?? i,
                                      type: ((st["type"] as? String) ?? "normal").lowercased(),
                                      weightKg: positive(st["weight_kg"]), reps: int(st["reps"]), rpe: positive(st["rpe"]),
                                      durationSeconds: positive(st["duration_seconds"]), distanceMeters: positive(st["distance_meters"]))
                }
                return WorkoutExercise(title: title, templateId: idString(ex["exercise_template_id"]), notes: text(ex["notes"]), sets: sets)
            }.filter { !$0.sets.isEmpty }
            guard !exercises.isEmpty else { return nil }
            return Workout(id: id, title: text(w["title"]), start: start, end: end, exercises: exercises)
        }
    }

    /// `GET /v1/routines`. A routine with no id or no title is unusable; one with no exercises is kept (it is still a named program).
    static func parseRoutines(data: Data) -> Page<Routine> {
        parsePage(data, key: "routines") { r in
            guard let id = idString(r["id"]), let title = text(r["title"]) else { return nil }
            let exercises: [RoutineExercise] = ((r["exercises"] as? [Any]) ?? []).compactMap { e in
                guard let ex = e as? [String: Any], let exTitle = text(ex["title"]) else { return nil }
                let sets: [RoutineSet] = ((ex["sets"] as? [Any]) ?? []).compactMap { s in
                    guard let st = s as? [String: Any] else { return nil }
                    let range = st["rep_range"] as? [String: Any]
                    return RoutineSet(type: ((st["type"] as? String) ?? "normal").lowercased(),
                                      weightKg: positive(st["weight_kg"]), reps: int(st["reps"]),
                                      repRangeStart: int(range?["start"]), repRangeEnd: int(range?["end"]),
                                      durationSeconds: positive(st["duration_seconds"]))
                }
                return RoutineExercise(title: exTitle, templateId: idString(ex["exercise_template_id"]),
                                       restSeconds: int(ex["rest_seconds"]), notes: text(ex["notes"]), sets: sets)
            }
            return Routine(id: id, title: title, folderId: idString(r["folder_id"]), notes: text(r["notes"]) ?? text(r["description"]), exercises: exercises)
        }
    }

    /// `GET /v1/routine_folders`.
    static func parseRoutineFolders(data: Data) -> Page<RoutineFolder> {
        parsePage(data, key: "routine_folders") { f in
            guard let id = idString(f["id"]), let title = text(f["title"]) else { return nil }
            return RoutineFolder(id: id, title: title, index: int(f["index"]) ?? 0)
        }
    }
}

// MARK: - Client

/// Pages through Hevy's read endpoints. The transport is the only thing that touches the network, so a test hands it canned bodies.
public struct HevyClient: Sendable {

    public struct Response: Sendable {
        public let status: Int
        public let body: Data
        public init(status: Int, body: Data) { self.status = status; self.body = body }
    }

    /// A GET of `path` with `query` and the person's key. Throws for a connection that never produced a response.
    public typealias Transport = @Sendable (_ path: String, _ query: [String: String], _ apiKey: String) async throws -> Response

    public enum Failure: Error, Equatable, Sendable {
        /// The key was refused (HTTP 401 or 403): wrong, revoked, or the account has no API access.
        case unauthorized
        case rateLimited
        case http(Int)
        case network(String)
        case cancelled
    }

    /// The largest page each endpoint accepts. Hevy answers an oversized `pageSize` with an error, so these are not tuning knobs.
    public enum PageSize { public static let workouts = 10, routines = 10, folders = 10, templates = 100 }

    /// Safety bound on a runaway `page_count`.
    public static let maxPages = 1000

    private let apiKey: String
    private let transport: Transport
    private let sleep: @Sendable (Double) async -> Void

    public init(apiKey: String, transport: @escaping Transport,
                sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.sleep = sleep
    }

    /// One GET, with a short wait and a second try when Hevy says to slow down (HTTP 429). Other failures are not retried.
    private func get(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let r: Response
            do { r = try await transport(path, query, apiKey) }
            catch is CancellationError { throw Failure.cancelled }
            catch { throw Failure.network(error.localizedDescription) }
            switch r.status {
            case 200..<300: return r.body
            case 401, 403: throw Failure.unauthorized
            case 429:
                attempt += 1
                if attempt > 3 { throw Failure.rateLimited }
                await sleep(Double(attempt) * 2)
            default: throw Failure.http(r.status)
            }
        }
    }

    /// Whose key it is, so a wrong one fails with a clear message before anything is read.
    public func userInfo() async throws -> HevyAPI.UserInfo? { HevyAPI.parseUserInfo(data: try await get("/v1/user/info")) }

    public func workoutCount() async throws -> Int? { HevyAPI.parseWorkoutCount(data: try await get("/v1/workouts/count")) }

    /// Every page of a paged endpoint, in order. `progress` gets (page, pageCount) after each page.
    private func all<Element: Sendable>(
        _ path: String, pageSize: Int,
        parse: (Data) -> HevyAPI.Page<Element>,
        progress: @Sendable (Int, Int) -> Void
    ) async throws -> (items: [Element], skipped: Int) {
        var items: [Element] = []
        var skipped = 0
        var page = 1
        while page <= Self.maxPages {
            let data = try await get(path, ["page": String(page), "pageSize": String(pageSize)])
            let parsed = parse(data)
            items += parsed.items; skipped += parsed.skipped
            progress(parsed.page, parsed.pageCount)
            guard parsed.hasMore, parsed.page == page else { break }   // a repeated page number would loop forever
            page += 1
        }
        return (items, skipped)
    }

    public func workouts(zone: TimeZone = .current, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> (items: [HevyAPI.Workout], skipped: Int) {
        try await all("/v1/workouts", pageSize: PageSize.workouts, parse: { HevyAPI.parseWorkouts(data: $0, zone: zone) }, progress: progress)
    }

    public func routines(progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> (items: [HevyAPI.Routine], skipped: Int) {
        try await all("/v1/routines", pageSize: PageSize.routines, parse: HevyAPI.parseRoutines, progress: progress)
    }

    public func routineFolders() async throws -> [HevyAPI.RoutineFolder] {
        try await all("/v1/routine_folders", pageSize: PageSize.folders, parse: HevyAPI.parseRoutineFolders, progress: { _, _ in }).items
    }

    public func exerciseTemplates(progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [HevyAPI.ExerciseTemplate] {
        try await all("/v1/exercise_templates", pageSize: PageSize.templates, parse: HevyAPI.parseExerciseTemplates, progress: progress).items
    }
}
