import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

/// Minutes in each of the five heart-rate zones, read from the stored heart-rate samples. One reader for the HR zones pages, the plan and the Body Age, so
/// the time one of them states is the time the others state. The zones are the bands the Effort is scored in (50–60 … 90–100% of the heart-rate reserve),
/// each day against its own resting heart rate.
enum ZoneMinutes {
    @MainActor private static func reserve(repo: Repository, age: Int) -> (maxHR: Double, resting: [String: Double], latest: Double) {
        let maxHR = age > 0 ? StrainScorer.tanakaHRmax(age: Double(age)) : Double(StrainScorer.defaultMaxHR())
        let restingByDay = Dictionary(repo.days.compactMap { d in d.restingHr.map { (d.day, Double($0)) } }, uniquingKeysWith: { _, l in l })
        let latest = repo.days.last(where: { $0.restingHr != nil })?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        return (maxHR, restingByDay, latest)
    }

    /// Every day's five zone totals, read one day at a time so a long window is never cut short by the sample limit of a single read.
    @MainActor static func perDay(repo: Repository, age: Int, days: [Date]) async -> [Date: [Double]] {
        let cal = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        let (maxHR, restingByDay, latestResting) = reserve(repo: repo, age: age)
        var out: [Date: [Double]] = [:]
        await withTaskGroup(of: (Date, [Double]).self) { group in
            var running = 0
            for day in days {
                if running >= 4, let done = await group.next() { out[done.0] = done.1; running -= 1 }
                let from = Int(day.timeIntervalSince1970)
                let nextDay = Int((cal.date(byAdding: .day, value: 1, to: day) ?? day).timeIntervalSince1970)
                guard from < now else { out[day] = [Double](repeating: 0, count: 5); continue }
                let resting = restingByDay[Repository.localDayKey(day)] ?? latestResting
                group.addTask { [repo] in
                    let samples = await repo.hrSamples(from: from, to: min(nextDay - 1, now), limit: 200_000)
                    let minutes = HRZones.timeInZone(samples, zoneSet: .reserveBands(maxHR: maxHR, restingHR: resting)).seconds.map { $0 / 60 }
                    return (day, minutes)
                }
                running += 1
            }
            for await done in group { out[done.0] = done.1 }
        }
        return out
    }
}

extension WorkoutSource {
    /// Strength work: lifting sessions and anything the catalogue names as strength training.
    static func isStrength(_ r: WorkoutRow) -> Bool {
        if classify(r.source) == .lifting { return true }
        let s = r.sport.lowercased()
        return s.contains("strength") || s.contains("lift") || s.contains("weight") || s.contains("gym") || s.contains("crossfit")
    }
}

/// Reads one week of a wearer's data into the `VitalityEngine.WeekData` the Body Age is worked out from. The weekly job that stores `body_age`, the Health
/// screen's breakdown and the fitness age page's card all read through here, so the number stored, the factors listed and the figure drawn are made from the same
/// week the same way.
enum VitalityWeekReader {
    /// Where a hand entry lives (a VO₂ max, a body measurement), apart from the estimates.
    static let manualSource = "noop-manual"

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// - Parameters:
    ///   - days: the week's daily rows (seven days ending on the week's last day).
    ///   - vo2Estimate: the VO₂ max the weekly job worked out for the week; used only when the wearer's waist is set (the estimate that needs no waist runs far high).
    @MainActor static func read(repo: Repository, days: [DailyMetric], age: Int, sex: String, waistCm: Double, vo2Estimate: Double?) async -> VitalityEngine.WeekData {
        let sorted = days.sorted { $0.day < $1.day }
        let weekEnd = sorted.last?.day ?? ""
        let dates = sorted.compactMap { dayParser.date(from: $0.day) }
        let cal = Calendar.current
        // How far back the series reads must reach the week, however old it is.
        let first = dates.first ?? Date()
        let lookback = max(60, (cal.dateComponents([.day], from: first, to: Date()).day ?? 0) + 40)

        var data = VitalityEngine.WeekData(chronoAge: Double(age), sex: sex)
        data.restingHRs = sorted.compactMap { $0.restingHr }.map(Double.init)
        data.sleepNights = sorted.compactMap { $0.totalSleepMin }.map { $0 / 60 }.filter { $0 > 0 }

        let consistency = Dictionary((await repo.exploreSeries(key: "sleep_consistency", source: "my-whoop", days: lookback)).map { ($0.day, $0.value) },
                                     uniquingKeysWith: { _, l in l })
        data.storedConsistency = sorted.compactMap { consistency[$0.day] }

        let estimated = Dictionary((await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: lookback)).map { ($0.day, $0.value) },
                                   uniquingKeysWith: { _, l in l })
        data.steps = sorted.compactMap { d in d.steps.map(Double.init) ?? estimated[d.day] }

        // Zones and strength. A week with no minutes in any zone has no heart-rate samples left to read, so the zones are left out then.
        let zones = await ZoneMinutes.perDay(repo: repo, age: age, days: dates)
        if zones.values.reduce(0.0, { $0 + $1.reduce(0, +) }) > 0 {
            data.zonesLowMin = zones.values.reduce(0.0) { $0 + $1[0] + $1[1] + $1[2] }
            data.zonesHighMin = zones.values.reduce(0.0) { $0 + $1[3] + $1[4] }
        }
        let from = Int(first.timeIntervalSince1970)
        let to = Int((cal.date(byAdding: .day, value: 1, to: dates.last ?? Date()) ?? Date()).timeIntervalSince1970)
        data.strengthMin = await repo.workoutRows(days: lookback).filter { $0.startTs >= from && $0.startTs < to && WorkoutSource.isStrength($0) }
            .reduce(0.0) { $0 + (($1.durationS ?? Double($1.endTs - $1.startTs)) / 60) }

        // Cardio fitness: the latest figure the wearer entered up to the week's end, else the estimate when it was worked out with their waist.
        let entered = (await repo.exploreSeries(key: "vo2max_est", source: manualSource, days: lookback + 365)).filter { $0.day <= weekEnd }.max { $0.day < $1.day }?.value
        data.cardioVO2 = entered ?? (waistCm > 0 ? vo2Estimate : nil)

        // Lean body mass: what the mean body fat of the 30 days up to the week's end leaves of 100%, Apple Health with a hand entry winning for its day.
        var fat: [String: Double] = [:]
        for source in ["apple-health", manualSource] {
            for p in await repo.exploreSeries(key: "body_fat", source: source, days: lookback + 30) { fat[p.day] = p.value }
        }
        let fatFrom = Repository.localDayKey(cal.date(byAdding: .day, value: -29, to: dates.last ?? Date()) ?? Date())
        let recent = fat.filter { $0.key >= fatFrom && $0.key <= weekEnd }.map(\.value)
        data.leanMassPct = recent.isEmpty ? nil : 100 - recent.reduce(0, +) / Double(recent.count)
        return data
    }
}
