import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics

/// Where the stress reading is: still learning the person, or ready to show.
///
/// The WHOOP-reference reading (`WhoopStress`) needs 14 nights of the person's own sleep to set its baseline and its two waking
/// constants. Until those nights are in, nothing about stress is shown (a figure from a half-built baseline would look exact and not be),
/// and the surfaces say how far along it is.
enum StressStatus: Equatable {
    case calibrating(nights: Int)
    case ready

    var isReady: Bool { if case .ready = self { return true } else { return false } }
    /// Nights read so far, capped at what is required.
    var nights: Int {
        switch self { case .calibrating(let n): return min(n, StressEngine.requiredNights); case .ready: return StressEngine.requiredNights }
    }
}

/// Builds and keeps the stress calibration, and reads a day of stress against it.
///
/// - A main night is the longest sleep of at least four hours that ends on a local day. It counts toward the 14 once its heart rate and HRV
///   could be read (a night the strap was not worn for is skipped, not guessed).
/// - The baseline is the newest 14 such nights; the two waking constants are set from the waking, sedentary epochs of the newest 60 days
///   (`WhoopStress.calibrated`, `WhoopStress.Calibration.wakeDays`). The record is kept in `UserDefaults` and rebuilt when a newer night arrives or the method's version changes.
/// - Nothing here changes `DaytimeStress`, which stays in the package as the previous formula.
@MainActor
final class StressEngine {
    static let shared = StressEngine()
    static let requiredNights = WhoopStress.Calibration.requiredNights

    private static let calibrationKey = "stress.whoopCalibration.v1"
    private static let nightsKey = "stress.nightFigures.v1"
    /// How many of the newest main nights are looked at while finding 14 readable ones.
    private static let nightsExamined = 40

    /// The waking, sedentary readings of one day: heart rates in tenths of a beat and RMSSDs in milliseconds, with the fingerprint of the
    /// day's heart rate so a day that has gained samples since is read again.
    private struct WakingDay: Codable, Equatable {
        var count: Int
        var maxTs: Int
        var hr: [Int]
        var rmssd: [Int]
        var sleepHR: [Int] = []
    }

    private struct NightRecord: Codable, Equatable {
        var day: String
        var start: Int
        var end: Int
        var rhr: Double
        var rmssd: Double
    }

    private var calibrationCache: WhoopStress.Calibration?
    private var statusCache: (stamp: String, status: StressStatus)?
    private var inFlight: Task<StressStatus, Never>?
    private var dayMemo: [String: WhoopStress.Result] = [:]
    private var dayMemoOrder: [String] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.calibrationKey),
           let c = try? JSONDecoder().decode(WhoopStress.Calibration.self, from: data), c.version == WhoopStress.Calibration.version {
            calibrationCache = c
        }
    }

    // MARK: Status

    /// The calibration state. Cheap when nothing new has arrived: it only lists the sessions and compares the newest night with the record.
    func status(repo: Repository) async -> StressStatus {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.computeStatus(repo: repo) }
        inFlight = task
        let s = await task.value
        inFlight = nil
        return s
    }

    /// The calibration, or nil while it is still being built.
    func calibration(repo: Repository) async -> WhoopStress.Calibration? {
        guard await status(repo: repo).isReady else { return nil }
        return calibrationCache
    }

    private func computeStatus(repo: Repository) async -> StressStatus {
        let sessions = await repo.allSleepSessions(days: 4000)
        let mains = Self.mainNights(sessions)
        guard let newest = mains.last else { return .calibrating(nights: 0) }
        let stamp = "\(newest.day)-\(mains.count)-\(sessions.count)"
        if let c = statusCache, c.stamp == stamp, !(c.status.isReady && calibrationCache == nil) { return c.status }

        // The record is good while no newer night has arrived.
        if let cal = calibrationCache, cal.newestNight == newest.day, cal.version == WhoopStress.Calibration.version {
            statusCache = (stamp, .ready)
            return .ready
        }

        // Find readable nights, newest first, reading each night's heart rate and R-R at most once (the figures are kept).
        var known = Self.loadNights()
        var readable: [NightRecord] = []
        for n in mains.reversed().prefix(Self.nightsExamined) {
            if let k = known[n.day], k.start == n.start, k.end == n.end { readable.append(k); if readable.count == Self.requiredNights { break }; continue }
            guard let fp = await repo.hrFingerprint(from: n.start, to: n.end), fp.count > Int(0.2 * Double(n.end - n.start)) else { continue }
            let hr = await repo.hrSamples(from: n.start, to: n.end, limit: 200_000)
            let rr = await repo.rrIntervals(from: n.start, to: n.end, limit: 200_000)
            guard let f = WhoopStress.nightFigures(hr: hr, rr: rr, from: n.start, to: n.end) else { continue }
            let rec = NightRecord(day: n.day, start: n.start, end: n.end, rhr: f.rhr, rmssd: f.rmssd)
            known[n.day] = rec
            readable.append(rec)
            if readable.count == Self.requiredNights { break }
        }
        Self.saveNights(known)

        guard readable.count >= Self.requiredNights else {
            calibrationCache = nil
            let s = StressStatus.calibrating(nights: readable.count)
            statusCache = (stamp, s)
            return s
        }
        let base = readable.sorted { $0.day < $1.day }
        guard let baseline = WhoopStress.Baseline.from(nightlyRMSSD: base.map(\.rmssd), nightlyRestingHR: base.map(\.rhr)) else {
            return .calibrating(nights: readable.count)
        }
        // The newest readable night may be older than the newest night (one the strap was not worn for): the record still stands then.
        if let cal = calibrationCache, cal.newestNight == base.last!.day, cal.version == WhoopStress.Calibration.version {
            statusCache = (stamp, .ready)
            return .ready
        }
        let tuning = await wakingConstants(repo: repo, nights: base, baseline: baseline, sessions: sessions)
        let cal = WhoopStress.Calibration(baseline: baseline, tuning: tuning, newestNight: base.last!.day)
        calibrationCache = cal
        if let data = try? JSONEncoder().encode(cal) { UserDefaults.standard.set(data, forKey: Self.calibrationKey) }
        dayMemo = [:]; dayMemoOrder = []
        statusCache = (stamp, .ready)
        return .ready
    }

    /// The two waking constants, read from the waking, sedentary epochs of the newest `Calibration.wakeDays` days that have data.
    ///
    /// A day's readings are kept (`WakingDay`), so a rebuild reads the raw samples of the days that are new or have changed and no others:
    /// the first build goes through every day once, and each morning after it through one or two.
    private func wakingConstants(repo: Repository, nights: [NightRecord], baseline: WhoopStress.Baseline, sessions: [CachedSleepSession]) async -> WhoopStress.Tuning {
        let cal = Calendar.current
        let sleeps = sessions.filter { $0.endTs - $0.effectiveStartTs >= 20 * 60 }.map { $0.effectiveStartTs...$0.endTs }
        let works = await repo.workoutRows(days: 4000).filter { $0.endTs > $0.startTs }.map { $0.startTs...$0.endTs }
        let last = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(nights.last!.end)))
        guard var day = cal.date(byAdding: .day, value: -(WhoopStress.Calibration.wakeDays - 1), to: last) else { return WhoopStress.Tuning() }
        var kept = Self.loadWakingDays()
        var used: [String: WakingDay] = [:]
        while day <= last {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            let from = Int(day.timeIntervalSince1970), to = Int(next.timeIntervalSince1970) - 1
            let key = Repository.localDayKey(day)
            day = next
            guard let fp = await repo.hrFingerprint(from: from, to: to), fp.count > 3_600 else { continue }
            if let k = kept[key], k.count == fp.count, k.maxTs == fp.maxTs, !k.sleepHR.isEmpty || k.hr.isEmpty { used[key] = k; continue }
            let hr = await repo.hrSamples(from: from - 600, to: to, limit: 200_000)
            let rr = await repo.rrIntervals(from: from - 600, to: to, limit: 200_000)
            let g = await repo.gravitySamplesUnion(from: from - 600, to: to, limit: 200_000)
            let w = await Task.detached(priority: .utility) {
                WhoopStress.wakingReadings(WhoopStress.analyze(hr: hr, rr: rr, gravity: g, sleep: sleeps, activities: works,
                                                               baseline: baseline, from: from, to: to).epochs)
            }.value
            let rec = WakingDay(count: fp.count, maxTs: fp.maxTs, hr: w.hr.map { Int(($0 * 10).rounded()) }, rmssd: w.rmssd.map { Int($0.rounded()) }, sleepHR: w.sleepHR.map { Int(($0 * 10).rounded()) })
            kept[key] = rec
            used[key] = rec
        }
        Self.saveWakingDays(kept)
        let hr = used.values.flatMap { $0.hr.map { Double($0) / 10 } }
        let rmssd = used.values.flatMap { $0.rmssd.map(Double.init) }
        let asleep = used.values.flatMap { $0.sleepHR.map { Double($0) / 10 } }
        return WhoopStress.calibrated(WhoopStress.Tuning(), wakingHR: hr, wakingRMSSD: rmssd, sleepHR: asleep, baseline: baseline)
    }

    // MARK: A day of stress

    /// The reading of the span `from` to `to` (unix seconds), or nil while the calibration is still being built.
    func day(repo: Repository, from: Int, to: Int) async -> WhoopStress.Result? {
        guard let cal = await calibration(repo: repo) else { return nil }
        guard let fp = await repo.hrFingerprint(from: from, to: to) else { return nil }
        // `to` is rounded to a 5-minute epoch: for today it is "now", and the data's own fingerprint already says whether anything arrived.
        let key = "\(from)-\(to / 300)-\(fp.count)-\(fp.maxTs)-\(cal.newestNight)"
        if let hit = dayMemo[key] { return hit }
        let hr = await repo.hrSamples(from: from - 600, to: to, limit: 200_000)
        guard !hr.isEmpty else { return nil }
        let rr = await repo.rrIntervals(from: from - 600, to: to, limit: 200_000)
        let g = await repo.gravitySamplesUnion(from: from - 600, to: to, limit: 200_000)
        let sessions = await repo.allSleepSessions(days: 4000)
        let sleeps = sessions.filter { $0.endTs - $0.effectiveStartTs >= 20 * 60 }.map { $0.effectiveStartTs...$0.endTs }
        let works = await repo.workoutRows(days: 4000).filter { $0.endTs > $0.startTs }.map { $0.startTs...$0.endTs }
        let tuning = cal.tuning, baseline = cal.baseline
        let result = await Task.detached(priority: .utility) {
            WhoopStress.analyze(hr: hr, rr: rr, gravity: g, sleep: sleeps, activities: works, baseline: baseline, from: from, to: to, tuning: tuning)
        }.value
        dayMemo[key] = result
        dayMemoOrder.append(key)
        if dayMemoOrder.count > 12 { dayMemo[dayMemoOrder.removeFirst()] = nil }
        return result
    }

    // MARK: Nights

    private static func mainNights(_ sessions: [CachedSleepSession]) -> [(day: String, start: Int, end: Int)] {
        var best: [String: (start: Int, end: Int)] = [:]
        for s in sessions where s.endTs - s.effectiveStartTs >= 4 * 3600 {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            if let cur = best[day], cur.end - cur.start >= s.endTs - s.effectiveStartTs { continue }
            best[day] = (s.effectiveStartTs, s.endTs)
        }
        return best.keys.sorted().map { (day: $0, start: best[$0]!.start, end: best[$0]!.end) }
    }

    private static func loadNights() -> [String: NightRecord] {
        guard let data = UserDefaults.standard.data(forKey: nightsKey), let m = try? JSONDecoder().decode([String: NightRecord].self, from: data) else { return [:] }
        return m
    }

    /// The kept waking days live in a file, not in `UserDefaults`: sixty days of readings are too much for a preference.
    private static var wakingDaysURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("stress-waking-days.json")
    }

    private static func loadWakingDays() -> [String: WakingDay] {
        guard let url = wakingDaysURL, let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([String: WakingDay].self, from: data) else { return [:] }
        return m
    }

    private static func saveWakingDays(_ m: [String: WakingDay]) {
        guard let url = wakingDaysURL else { return }
        // A little more than the window, so a day that drops out of it and comes back (a clock change) is not read twice.
        let kept = Dictionary(uniqueKeysWithValues: m.sorted { $0.key > $1.key }.prefix(WhoopStress.Calibration.wakeDays + 10).map { ($0.key, $0.value) })
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: url, options: .atomic) }
    }

    private static func saveNights(_ m: [String: NightRecord]) {
        // Keep the last 90 nights; the figures are tiny but a long-lived install should not grow them without bound.
        let kept = Dictionary(uniqueKeysWithValues: m.sorted { $0.key > $1.key }.prefix(90).map { ($0.key, $0.value) })
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: nightsKey) }
    }
}
