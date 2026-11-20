#if DEBUG
import Foundation
import WhoopStore
import WhoopProtocol

// MARK: - DEBUG-only demo seed (Apple parity with Android's DemoSeeder)
// Seeds a comprehensive, self-contained synthetic dataset so a DEBUG build can walk every screen —
// Today, Sleep, Trends, Workouts, Health, Stress, Insights, Explore — with no strap and no import.
// This is the Apple twin of `android/.../data/DemoSeeder.kt` (same RNG seed, same physiology) and exists so we can
// render iOS + macOS for verification and marketing screenshots. The Apple window is a full year (365 days, the
// Android twin keeps 120): long enough for every Trends range, the yearly Fitness Age / Vitality curves, quarterly
// lab panels and a season of training blocks, two illness weeks and a deload every fourth week.
//
// Gating: the whole file is `#if DEBUG`, so it is stripped from every Release build (the shipped
// app). At runtime it only seeds when launched with `--demo-seed` AND the store has no daily rows,
// so it runs at most once and never clobbers real data. Everything here is SYNTHETIC and
// DETERMINISTIC (fixed seed) — nothing is real biometric data. Values are physiologically plausible
// and internally correlated (recovery ↔ HRV ↔ resting-HR ↔ sleep; strain ↔ workouts; a slow fitness
// drift) so the charts, trends and insights all read like a real account.
enum AppleDemoSeeder {

    static let whoop = "my-whoop"
    static let apple = "apple-health"
    private static let DAYS = 365
    /// Effort rescale factor: the old 0–21 strain scale → the new 0–100 Effort scale.
    private static let STRAIN_SCALE = 100.0 / 21.0
    /// Share of a day's steps taken in each hour: the commute, lunch and the evening, none while asleep.
    private static let hourShape: [Double] = [0, 0, 0, 0, 0, 0, 0.02, 0.09, 0.11, 0.06, 0.05, 0.06, 0.09, 0.07, 0.05, 0.05, 0.06, 0.11, 0.10, 0.05, 0.02, 0.01, 0, 0]

    private static let SPORTS = [
        "Running", "Cycling", "Strength", "HIIT", "Swimming", "Yoga", "Walking", "Rowing",
    ]
    private static let DISTANCE_SPORTS: Set<String> = ["Running", "Cycling", "Walking", "Swimming", "Rowing"]

    /// True when the process was launched asking for the demo seed (Xcode scheme arg or `simctl
    /// launch … --demo-seed`).
    static var requested: Bool { CommandLine.arguments.contains("--demo-seed") }

    /// Seed only if requested AND the store is empty. Safe to call on every launch.
    static func seedIfRequested(into store: WhoopStore) async {
        guard requested else { return }
        seedDemoDeviceIfNeeded(into: store)
        let existing = (try? await store.dailyMetrics(deviceId: whoop, from: "0000-00-00", to: "9999-99-99")) ?? []
        guard existing.isEmpty else { await seedLabBookIfNeeded(into: store); await seedSportExtrasIfNeeded(into: store); await seedLowIntensityExtrasIfNeeded(into: store); await seedRecoveryExtrasIfNeeded(into: store); await seedNapExtrasIfNeeded(into: store); return }
        do { try await seed(into: store) }
        catch { NSLog("AppleDemoSeeder: seed failed — \(error)") }
        await seedLabBookIfNeeded(into: store)
        await seedSportExtrasIfNeeded(into: store)
        await seedLowIntensityExtrasIfNeeded(into: store)
        await seedRecoveryExtrasIfNeeded(into: store)
        await seedNapExtrasIfNeeded(into: store)
    }

    /// DEBUG/demo-only: so the Devices screen renders with content under `--demo-seed`, pair a second
    /// (non-WHOOP) strap alongside the seeded WHOOP. If the registry only holds the WHOOP, add a
    /// `.paired` "Polar H10" — the screenshot then shows the WHOOP (Active) plus a paired strap. Status
    /// `.paired` (not `.active`) keeps the WHOOP active, so the SourceCoordinator stays dormant and the
    /// existing WHOOP path is untouched. No-op once a second device already exists.
    private static func seedDemoDeviceIfNeeded(into store: WhoopStore) {
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        guard let devices = try? registry.all() else { return }
        guard devices.allSatisfy({ $0.id == whoop }) else { return }  // only the seeded WHOOP present
        let now = Int(Date().timeIntervalSince1970)
        let polar = PairedDevice(
            id: "polar-h10-demo", brand: "Polar", model: "H10", nickname: nil,
            sourceKind: .liveBLE, capabilities: [.hr, .hrv], status: .paired,
            addedAt: now - 86_400, lastSeenAt: now - 3_600)
        try? registry.add(polar)
    }

    private static func seed(into store: WhoopStore) async throws {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let cal = Calendar.current
        let zone = TimeZone.current
        let startDay = cal.date(byAdding: .day, value: -(DAYS - 1), to: cal.startOfDay(for: Date()))!

        try? await store.upsertDevice(id: whoop, mac: nil, name: "WHOOP (demo)")

        var daily: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        var series: [MetricPoint] = []
        var appleRows: [AppleDaily] = []
        var appleSeries: [MetricPoint] = []
        var workouts: [WorkoutRow] = []
        var journal: [JournalEntry] = []
        var stepHours: [(ts: Int, steps: Int)] = []
        var streamDays: [StreamDay] = []

        var weight = 79.5
        var fitness = 0.0  // slow upward drift: HRV rises, resting-HR falls, VO2max climbs

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = zone
        isoFmt.dateFormat = "yyyy-MM-dd"

        for i in 0..<DAYS {
            let date = cal.date(byAdding: .day, value: i, to: startDay)!
            let day = isoFmt.string(from: date)
            let weekday = cal.component(.weekday, from: date)  // 1=Sun … 7=Sat
            let weekend = (weekday == 1 || weekday == 7)
            fitness += 0.012
            // Two illness spells (a flu in spring, a cold in autumn) and a lighter week every fourth week.
            let ill = (118..<123).contains(i) || (291..<295).contains(i)
            let deload = (i / 7) % 4 == 3

            // --- the day's habits (they move the night that follows, so the Insights have something to find) ---
            let drank = rng.nextDouble() < (weekend ? 0.34 : 0.10)
            let lateCaffeine = rng.nextDouble() < 0.30
            let screenInBed = rng.nextDouble() < 0.45
            let ateLate = rng.nextDouble() < 0.25
            let magnesium = rng.nextDouble() < 0.40
            let readBeforeBed = rng.nextDouble() < 0.35
            let sauna = rng.nextDouble() < (weekend ? 0.22 : 0.06)

            // --- training load for the day ---
            let pTrain = (weekend ? 0.40 : 0.62) * (deload ? 0.55 : 1.0)
            let trains = rng.nextDouble() < pTrain && !ill
            let isToday = i == DAYS - 1
            let nWorkouts = isToday ? 1 : (!trains ? 0 : (rng.nextDouble() < 0.22 ? 2 : 1))

            // --- sleep architecture ---
            let totalSleep = gauss(&rng, ill ? 485.0 : 430.0, 35.0).clamped(300.0, 560.0)
            let efficiency = (gauss(&rng, ill ? 85.0 : 89.0, 4.0) - (drank ? 3.0 : 0.0) - (screenInBed ? 1.2 : 0.0)).clamped(72.0, 98.0)
            let deep = (totalSleep * (gauss(&rng, 0.20, 0.03) + (magnesium ? 0.012 : 0) - (drank ? 0.02 : 0))).clamped(35.0, 130.0)
            let rem = (totalSleep * gauss(&rng, 0.23, 0.03)).clamped(45.0, 150.0)
            let light = (totalSleep - deep - rem).atLeast(60.0)
            let disturbances = Int(gauss(&rng, 6.0, 3.0).clamped(0.0, 18.0))

            // --- autonomic markers ---
            let hrv = (gauss(&rng, 78.0 + fitness * 1.5, 12.0) + (weekend ? 6 : 0) - Double(nWorkouts) * 4
                       - (ill ? 26 : 0) - (drank ? 9 : 0) + (sauna ? 3 : 0))
                .clamped(24.0, 150.0)
            let rhr = Int((gauss(&rng, 56.0 - fitness * 0.4, 3.0) + Double(nWorkouts) * 1.2
                           + (ill ? 7 : 0) + (drank ? 2.5 : 0)).clamped(42.0, 74.0))
            let spo2 = gauss(&rng, ill ? 95.2 : 96.5, 0.8).clamped(92.0, 100.0)
            let skinTempDev = gauss(&rng, ill ? 0.8 : 0.0, 0.25).clamped(-1.2, 1.8)
            let resp = gauss(&rng, ill ? 16.4 : 14.6, 0.9).clamped(11.0, 20.0)

            // --- recovery: a function of HRV, sleep quality and resting-HR ---
            let computedRecovery = (
                60 + (hrv - 70) * 0.55 + (efficiency - 85) * 0.6 + (totalSleep - 420) * 0.03 -
                    (Double(rhr) - 55) * 1.4 - Double(disturbances) * 0.8 + gauss(&rng, 0.0, 5.0)
                    - (ill ? 12.0 : 0.0) - (lateCaffeine ? 2.0 : 0.0)
            ).clamped(5.0, 99.0)
            // The last seven days are set by hand so every colour of the Charge scale shows (red under 34, yellow to 66, green from 67), oldest first.
            let lastWeekCharge: [Double] = [28, 58, 86, 31, 74, 49, 82]
            let daysBack = DAYS - 1 - i
            let recovery = daysBack < lastWeekCharge.count ? lastWeekCharge[lastWeekCharge.count - 1 - daysBack] : computedRecovery

            // --- strain (Effort): workout-driven, rescaled 0–21 → 0–100 ---
            let strain = (
                (nWorkouts == 0 ? gauss(&rng, 7.5, 1.8)
                 : gauss(&rng, 13.5, 2.4) + Double(nWorkouts - 1) * 2.5) * STRAIN_SCALE
            ).clamped(3.0 * STRAIN_SCALE, 100.0)

            daily.append(DailyMetric(
                day: day, totalSleepMin: round1(totalSleep), efficiency: round1(efficiency),
                deepMin: round1(deep), remMin: round1(rem), lightMin: round1(light),
                disturbances: disturbances, restingHr: rhr, avgHrv: round1(hrv),
                recovery: round1(recovery), strain: round1(strain), exerciseCount: nWorkouts,
                spo2Pct: round1(spo2), skinTempDevC: round2(skinTempDev), respRateBpm: round1(resp)))

            // Day Stress (0–3, the autonomic proxy against the wearer's own baseline): the mirror of Charge, a little noisier.
            let stress = (3.0 - recovery / 100.0 * 2.6 + gauss(&rng, 0.0, 0.25) + (ill ? 0.4 : 0.0)).clamped(0.1, 3.0)

            // --- sleep session: previous night ~23:10 → wake, with a REAL stage timeline so the
            //     hypnogram renders the computed segment path (not just the proportional bar). ---
            let onsetBase = cal.date(byAdding: .day, value: -1, to: date)!
            let onsetDay = cal.startOfDay(for: onsetBase)
            let onset = Int(onsetDay.timeIntervalSince1970) + 23 * 3600 + 10 * 60 + rng.nextInt(-1800, 1800)
            let inBedSec = Int((totalSleep + totalSleep * (100 - efficiency) / 100) * 60)
            sleeps.append(CachedSleepSession(
                startTs: onset, endTs: onset + inBedSec,
                efficiency: round1(efficiency), restingHr: rhr, avgHrv: round1(hrv),
                stagesJSON: segmentsJSON(onset: onset, deep: deep, rem: rem, light: light,
                                         awakeMin: Double(disturbances) * 1.6)))

            // --- long-format extras (body composition) under my-whoop ---
            series.append(MetricPoint(day: day, key: "stress", value: round2(stress)))
            weight += gauss(&rng, -0.02, 0.18)
            series.append(MetricPoint(day: day, key: "weightKg", value: round2(weight)))
            series.append(MetricPoint(day: day, key: "bodyFatPct",
                value: round1((18.0 - fitness * 0.2 + gauss(&rng, 0.0, 0.4)).clamped(10.0, 24.0))))
            // Export-verbatim sleep figures (same metricSeries keys the importers write), so the demo
            // Sleep tiles exercise the prefer-imported path.
            let demoNeedMin = (totalSleep + gauss(&rng, 25.0, 20.0)).clamped(420.0, 560.0)
            series.append(MetricPoint(day: day, key: "sleep_performance",
                value: round1(min(totalSleep / demoNeedMin * 100.0, 100.0))))
            series.append(MetricPoint(day: day, key: "sleep_consistency",
                value: round1(gauss(&rng, 80.0, 8.0).clamped(40.0, 100.0))))
            series.append(MetricPoint(day: day, key: "sleep_need_min", value: round1(demoNeedMin)))
            series.append(MetricPoint(day: day, key: "sleep_debt_min",
                value: round1((demoNeedMin - totalSleep).atLeast(0.0))))

            // --- Apple Health daily aggregate ---
            let stepsFullDay = Int(gauss(&rng, 8500.0, 2600.0).clamped(1200.0, 19000.0))
            // Today only counts the hours that have happened.
            let hourNow = cal.component(.hour, from: Date())
            let steps = isToday ? Int(Double(stepsFullDay) * hourShape[0...hourNow].reduce(0, +)) : stepsFullDay
            // The strap's own daily step series too, so the Steps detail page has a week to draw in a demo.
            series.append(MetricPoint(day: day, key: "steps", value: Double(steps)))
            // The weight a health-store sync leaves as its own daily series (the Weight card and page read it, with the one before).
            appleSeries.append(MetricPoint(day: day, key: "weight", value: round2(weight)))
            appleRows.append(AppleDaily(
                day: day, steps: steps,
                activeKcal: round1((Double(steps) * 0.045 + Double(nWorkouts) * 220).clamped(120.0, 1400.0)),
                basalKcal: round1(gauss(&rng, 1650.0, 40.0)),
                vo2max: round1((46 + fitness * 0.3 + gauss(&rng, 0.0, 0.5)).clamped(38.0, 56.0)),
                avgHr: Int(gauss(&rng, 72.0, 5.0)), maxHr: Int(gauss(&rng, 150.0, 12.0)),
                walkingHr: Int(gauss(&rng, 108.0, 6.0)), weightKg: round2(weight)))

            // Hourly steps for the last 90 days (the Steps screen's "which hours were recorded" strip): most of the
            // day's steps in the commute, lunch and evening hours, none while asleep.
            if i >= DAYS - 90 {
                let dayStartTs = Int(cal.startOfDay(for: date).timeIntervalSince1970)
                for h in 0..<(isToday ? hourNow + 1 : 24) where hourShape[h] > 0 {
                    stepHours.append((ts: dayStartTs + h * 3600, steps: Int(Double(stepsFullDay) * hourShape[h] * gauss(&rng, 1.0, 0.18).clamped(0.5, 1.6))))
                }
            }

            // --- workouts on training days ---
            var dayWorkouts: [(start: Int, end: Int, avg: Int, max: Int)] = []
            for k in 0..<nWorkouts {
                let sport = SPORTS[rng.nextInt(0, SPORTS.count)]
                let durSec = gauss(&rng, 48.0, 16.0).clamped(18.0, 110.0) * 60
                let hour = weekend ? 9 : 18
                let dayStart = cal.startOfDay(for: date)
                var start = Int(dayStart.timeIntervalSince1970) + hour * 3600 + rng.nextInt(0, 50) * 60 + k * 3600
                // Today's session has to be over already: earlier if the usual hour has not come yet.
                if isToday { start = Swift.min(start, Int(Date().timeIntervalSince1970) - Int(durSec) - 1800 - k * 5400) }
                let avg = Int(gauss(&rng, 138.0, 12.0))
                let src = rng.nextDouble() < 0.7 ? whoop : apple
                let zonesJSON: String? = src == whoop ? {
                    let z = [gauss(&rng, 15.0, 5.0), gauss(&rng, 30.0, 8.0), gauss(&rng, 28.0, 8.0),
                             gauss(&rng, 15.0, 6.0), gauss(&rng, 6.0, 3.0)].map { $0.clamped(0.0, 100.0) }
                    return "{\"zone1\":\(round1(z[0])),\"zone2\":\(round1(z[1])),\"zone3\":\(round1(z[2])),\"zone4\":\(round1(z[3])),\"zone5\":\(round1(z[4]))}"
                }() : nil
                workouts.append(WorkoutRow(
                    startTs: start, endTs: start + Int(durSec), sport: sport, source: src,
                    durationS: round1(durSec),
                    energyKcal: round1((durSec / 60) * gauss(&rng, 9.0, 2.0)),
                    avgHr: avg, maxHr: avg + Int(gauss(&rng, 22.0, 6.0)),
                    strain: round1((strain * gauss(&rng, 0.6, 0.1)).clamped(4.0 * STRAIN_SCALE, 100.0)),
                    distanceM: DISTANCE_SPORTS.contains(sport) ? round1(gauss(&rng, 6500.0, 2500.0).atLeast(500.0)) : nil,
                    zonesJSON: zonesJSON, notes: nil,
                    steps: (sport == "Running" || sport == "Walking") ? Int(durSec / 60 * (sport == "Running" ? 165.0 : 105.0)) : nil))
                dayWorkouts.append((start: start, end: start + Int(durSec), avg: avg, max: avg + 22))
            }

            // --- journal answers for the whole year (real catalog strings → Insights light up) ---
            let answers: [(String, Bool)] = [
                ("Did you drink any alcohol?", drank), ("Did you have caffeine late in the day?", lateCaffeine),
                ("Did you view a screen in bed?", screenInBed), ("Did you eat close to bedtime?", ateLate),
                ("Did you feel stressed?", stress > 1.6), ("Did you use a sauna?", sauna),
                ("Did you share your bed?", rng.nextDouble() < 0.55), ("Did you feel sick or ill?", ill),
                ("Did you take magnesium?", magnesium), ("Did you read before bed?", readBeforeBed),
            ]
            for (q, yes) in answers { journal.append(JournalEntry(day: day, question: q, answeredYes: yes, notes: nil)) }

            // --- the last three weeks also get real streams (heart rate, beats), so the intraday charts have something to draw ---
            if i >= DAYS - 22 {
                streamDays.append(StreamDay(dayStart: Int(cal.startOfDay(for: date).timeIntervalSince1970), onset: onset,
                                            wake: onset + inBedSec, rhr: rhr, hrv: hrv, workouts: dayWorkouts, ill: ill))
            }
        }

        // --- weekly Fitness Age + VO2max estimate (the engine stamps these on each week's
        //     Saturday; mirror that here so the Fitness Age screen renders under --demo-seed).
        //     Across the year Fitness Age goes ~42 → ~36 (younger) as the demo "fitness" drift climbs; vo2max ~44 → ~50.
        var fitnessAge = 42.0
        var vo2 = 44.0
        var vitality = 55.0      // weekly Vitality (0–100) trending up as the demo habits improve (55 → ~75)
        var bodyAgeDemo = 31.2   // Body Age (years) easing down to ~29, where the nine-factor reading of the demo week lands (a 30-year-old profile)
        for i in 0..<DAYS {
            let date = cal.date(byAdding: .day, value: i, to: startDay)!
            guard cal.component(.weekday, from: date) == 7 else { continue }  // 7 = Saturday
            let day = isoFmt.string(from: date)
            series.append(MetricPoint(day: day, key: "fitness_age",
                value: round1((fitnessAge + gauss(&rng, 0.0, 0.3)).clamped(34.0, 44.0))))
            series.append(MetricPoint(day: day, key: "vo2max_est",
                value: round1((vo2 + gauss(&rng, 0.0, 0.4)).clamped(42.0, 52.0))))
            series.append(MetricPoint(day: day, key: "vitality",
                value: round1((vitality + gauss(&rng, 0.0, 1.0)).clamped(40.0, 80.0))))
            series.append(MetricPoint(day: day, key: "body_age",
                value: round1((bodyAgeDemo + gauss(&rng, 0.0, 0.2)).clamped(27.0, 34.0))))
            let weeks = Double(DAYS) / 7.0
            fitnessAge -= 6.0 / weeks  // ~6 yr younger across the Saturdays of the year
            vo2 += 6.0 / weeks
            vitality += 20.0 / weeks
            bodyAgeDemo -= 2.0 / weeks
        }

        _ = try await store.upsertDailyMetrics(daily, deviceId: whoop)
        _ = try await store.upsertSleepSessions(sleeps, deviceId: whoop)
        _ = try await store.upsertMetricSeries(series, deviceId: whoop)
        _ = try await store.upsertAppleDaily(appleRows, deviceId: apple)
        _ = try await store.upsertMetricSeries(appleSeries, deviceId: apple)
        if !workouts.isEmpty { _ = try await store.upsertWorkouts(workouts, deviceId: whoop) }
        if !journal.isEmpty { _ = try await store.upsertJournal(journal, deviceId: "noop-journal") }
        if !stepHours.isEmpty { _ = try await store.upsertAppleStepHours(stepHours, deviceId: apple) }
        try await seedStreams(streamDays, into: store, rng: &rng)
        // Two programs and a year of finished runs of them (an upper day and a lower day each week, a lighter week every fourth, the odd
        // missed one and none while ill), the weights climbing, so the gym screens (a program's progress, an exercise's chart, records
        // and history) have a whole season to show under `--demo-seed`.
        typealias GymPlan = [(String, LiftMuscle, [LiftMuscle], [(Double, Int)])]
        let planUpper: GymPlan = [
            ("Bench Press", .chest, [.triceps, .frontDelts], [(40, 10), (60, 8), (60, 8), (62.5, 6)]),
            ("Barbell Row", .lats, [.upperBack], [(50, 10), (60, 8), (60, 8)]),
            ("Overhead Press", .frontDelts, [.triceps], [(30, 10), (35, 8), (35, 7)]),
            ("Lat Pulldown", .lats, [.biceps], [(45, 12), (50, 10), (50, 10)]),
        ]
        let planLower: GymPlan = [
            ("Back Squat", .quads, [.glutes, .lowerBack], [(60, 8), (80, 6), (80, 6), (82.5, 5)]),
            ("Romanian Deadlift", .hamstrings, [.glutes, .lowerBack], [(60, 10), (70, 8), (70, 8)]),
            ("Leg Press", .quads, [.glutes], [(100, 12), (120, 10), (120, 10)]),
            ("Standing Calf Raise", .calves, [], [(40, 15), (45, 12), (45, 12)]),
        ]
        let programs: [(id: String, name: String, plan: GymPlan)] = [
            ("demo-prog-1", "Upper push/pull", planUpper), ("demo-prog-2", "Lower body", planLower),
        ]
        for p in programs {
            _ = try await store.upsertLiftPrograms([LiftProgramRow(id: p.id, deviceId: whoop, name: p.name, note: "Bar 20 kg plus plates", createdAt: 1, updatedAt: 1, archived: false)])
            _ = try await store.replaceLiftProgramItems(programId: p.id, items: p.plan.enumerated().map { i, e in
                LiftProgramItemRow(id: "\(p.id)-\(i)", deviceId: whoop, programId: p.id, ord: i, exercise: e.0, targetSets: e.3.count, targetRepsLow: e.3.first?.1,
                                   targetRepsHigh: nil, targetRpe: nil, targetWeightKg: e.3.last?.0, restSec: 90, note: nil)
            })
        }
        let todayStart = Int(cal.startOfDay(for: Date()).timeIntervalSince1970)
        var gymRun = 0
        for week in stride(from: (DAYS - 14) / 7, through: 0, by: -1) {
            let lighter = ((DAYS - 14) / 7 - week) % 4 == 3
            for (slot, daysIntoWeek) in [(0, 5), (1, 2)] {
                let daysAgo = week * 7 + daysIntoWeek
                let dayIndex = DAYS - 1 - daysAgo
                if (118..<123).contains(dayIndex) || (291..<295).contains(dayIndex) || rng.nextDouble() < 0.12 { continue }
                gymRun += 1
                let program = programs[slot]
                let gymStart = todayStart - daysAgo * 86_400 + 18 * 3600 + rng.nextInt(0, 40) * 60
                let gymEnd = gymStart + (52 + rng.nextInt(0, 18)) * 60
                let sessionId = "demo-gym-\(gymRun)"
                // About +0.25 kg a week on the main lifts across the year, a notch less in a lighter week.
                let climb = Double((DAYS - 14) / 7 - week) * 0.25 - 6.0 - (lighter ? 4.0 : 0.0)
                _ = try await store.upsertWorkouts([WorkoutRow(
                    startTs: gymStart, endTs: gymEnd, sport: "Strength Training", source: "manual", durationS: Double(gymEnd - gymStart),
                    energyKcal: 340 + Double(gymRun % 7) * 12, avgHr: 112 + gymRun % 9, maxHr: 148 + gymRun % 11, strain: 30 + Double(gymRun % 8) * 1.3,
                    distanceM: nil, zonesJSON: nil, notes: program.name, steps: nil)], deviceId: whoop)
                _ = try await store.upsertLiftSessions([LiftSessionRow(
                    id: sessionId, deviceId: whoop, startTs: gymStart, endTs: gymEnd, sport: "Strength Training",
                    programId: program.id, programName: program.name, sessionRpe: nil, note: nil)])
                var ord = 0
                var liftSets: [LiftSetRow] = []
                for (name, primary, secondary, work) in program.plan {
                    for (i, w) in work.enumerated() {
                        let heavy = name == "Lat Pulldown" || name == "Leg Press" || name == "Back Squat"
                        let weight = max(5, (w.0 + (heavy ? climb * 2 : climb)) * 4).rounded() / 4
                        liftSets.append(LiftSetRow(
                            id: "\(sessionId)-\(ord)", deviceId: whoop, sessionId: sessionId, ord: ord, exercise: name, primaryMuscle: primary,
                            secondaryMuscles: secondary, setIndex: i + 1, weightKg: weight, reps: max(1, w.1 + rng.nextInt(-1, 2)), rpe: nil, isWarmup: false,
                            startTs: gymStart + ord * 240, endTs: gymStart + ord * 240 + 60, restSec: 90, note: nil))
                        ord += 1
                    }
                }
                _ = try await store.upsertLiftSets(liftSets)
            }
        }
        NSLog("AppleDemoSeeder: seeded \(daily.count) days, \(workouts.count) workouts.")
    }

    /// A lab book: a blood panel taken twice, a blood pressure reading and the body measurements, with the reference range typed in as a person
    /// would from their own report, so the Lab Book screens can be looked at under `--demo-seed`. Added on its own, so a device that was seeded
    /// before the Lab Book existed gets it too.
    private static func seedLabBookIfNeeded(into store: WhoopStore) async {
        let existing = (try? await store.labMarkers(deviceId: whoop, category: "bloodPanel")) ?? []
        guard existing.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        // would from their own report, so the Lab Book screens can be looked at under `--demo-seed`.
        // Five panels across the year, a quarter apart: cholesterol and vitamin D improving, glucose settling, blood pressure coming down.
        let panels: [(ago: Int, ldl: Double, hdl: Double, glucose: Double, vitD: Double, ferritin: Double, tsh: Double?, sys: Double, dia: Double, pulse: Double, weight: Double, waist: Double?)] = [
            (350, 4.0, 1.1, 5.7, 38, 54, nil, 134, 88, 74, 79.0, 90.0),
            (260, 3.8, 1.1, 5.6, 42, 57, 3.9, 131, 86, 73, 78.4, 88.5),
            (170, 3.6, 1.2, 5.4, 46, 62, nil, 128, 84, 71, 77.2, 87.0),
            (95, 3.4, 1.2, 5.3, 55, 60, 4.2, 124, 82, 69, 76.1, 85.8),
            (14, 3.1, 1.3, 5.1, 68, 58, 4.8, 118, 78, 66, 75.0, 84.5),
        ]
        let labDays: [(Int, [(String, String, Double, String, String?)])] = panels.map { p in
            var items: [(String, String, Double, String, String?)] = [
                ("ldl", "bloodPanel", p.ldl, "mmol/L", "0 - 3.4"), ("hdl", "bloodPanel", p.hdl, "mmol/L", "1 - 2.2"),
                ("fasting_glucose", "bloodPanel", p.glucose, "mmol/L", "3.9 - 5.6"), ("vitamin_d", "bloodPanel", p.vitD, "nmol/L", "50 - 125"),
                ("ferritin", "bloodPanel", p.ferritin, "µg/L", "30 - 300"),
                ("bp_systolic", "bloodPressure", p.sys, "mmHg", "90 - 120"), ("bp_diastolic", "bloodPressure", p.dia, "mmHg", "60 - 80"),
                ("resting_pulse", "bloodPressure", p.pulse, "bpm", "60 - 100"), ("weight", "bodyMeasurement", p.weight, "kg", nil),
            ]
            if let tsh = p.tsh { items.append(("tsh", "bloodPanel", tsh, "mIU/L", "0.4 - 4.0")) }
            if let waist = p.waist { items.append(("waist", "bodyMeasurement", waist, "cm", nil)) }
            return (p.ago, items)
        }
        var labRows: [LabMarkerRow] = []
        for (ago, items) in labDays {
            let at = now - ago * 86_400 + 8 * 3_600
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(at)))
            for (key, category, value, unit, range) in items {
                labRows.append(LabMarkerRow(id: "demo-lab-\(key)-\(ago)", deviceId: whoop, markerKey: key, category: category, day: day, takenAt: at, value: value,
                                            valueText: nil, unit: unit, source: "manual", note: nil, referenceText: range))
            }
        }
        _ = try? await store.upsertLabMarkers(labRows)
    }

    // MARK: - streams

    /// One seeded night plus its day, for the stream generator below.
    private struct StreamDay {
        let dayStart: Int
        let onset: Int
        let wake: Int
        let rhr: Int
        let hrv: Double
        let workouts: [(start: Int, end: Int, avg: Int, max: Int)]
        let ill: Bool
    }

    /// Real streams for the last three weeks, laid on the same nights, wake times and workouts the daily rows describe: a heart rate every
    /// 4 s (the Stress reading wants about 150 samples in ten minutes; a night that sinks to the resting rate and rises toward morning, a day with walking bursts, a workout that climbs to its average),
    /// the wrist's motion at the same pace, and the beat-to-beat intervals of the last eighteen nights plus a five-minute window every ten minutes by day (the stress calibration needs fourteen nights), so the intraday charts (Today's
    /// heart rate, the Stress breakdown, a workout's curve, the sleep heart-rate line) have something to draw. Written under the WHOOP id the
    /// daily rows use, in chunks.
    private static func seedStreams(_ days: [StreamDay], into store: WhoopStore, rng: inout SplitMix64) async throws {
        guard days.count > 1 else { return }
        let cal = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        var gravity: [GravitySample] = []
        var lastBeatTs = Int.min
        var sameSecond = 0
        // The wrist's gravity vector wanders over the unit sphere; the step between two records is what the motion gate reads, so a
        // night is nearly still, a desk hour twitches, and a walk or a workout turns the wrist by a third of a g or more each time.
        var gTheta = 0.4
        var gPhi = 0.9
        func move(_ ts: Int, _ delta: Double, _ angle: Double) {
            gTheta += delta * Foundation.cos(angle)
            gPhi = (gPhi + delta * Foundation.sin(angle)).clamped(0.3, 2.8)
            gravity.append(GravitySample(ts: ts, x: Foundation.sin(gPhi) * Foundation.cos(gTheta), y: Foundation.sin(gPhi) * Foundation.sin(gTheta),
                                         z: Foundation.cos(gPhi)))
        }
        func beat(_ at: Double, _ ms: Double) {
            let ts = Int(at)
            if ts == lastBeatTs { sameSecond += 1 } else { lastBeatTs = ts; sameSecond = 0 }
            rr.append(RRInterval(ts: ts, rrMs: Int(ms.rounded()), ord: sameSecond, seq: sameSecond))
        }

        for (n, d) in days.enumerated() {
            let beatsFromHere = n >= days.count - 18
            let span = Double(max(1, d.wake - d.onset))

            // Asleep: sinks from falling-asleep levels to the resting rate in the first hours, ripples with the ~90 min cycles, rises toward morning.
            func asleepBpm(_ t: Double) -> Double {
                let x = (t - Double(d.onset)) / span
                return Double(d.rhr) - 3.0 + 9.0 * Foundation.exp(-4.0 * x) + 4.0 * x * x * x
                    + 2.5 * Foundation.sin(2.0 * Double.pi * (t - Double(d.onset)) / 5400.0)
            }
            var t = d.onset
            while t < d.wake && t < now {
                hr.append(HRSample(ts: t, bpm: Int((asleepBpm(Double(t)) + gauss(&rng, 0.0, 1.4)).clamped(38.0, 140.0))))
                // Still, but for a turn in bed about every 25 minutes.
                move(t, t % 1500 < 10 ? gauss(&rng, 0.45, 0.1).atLeast(0.25) : Swift.abs(gauss(&rng, 0.0, 0.012)), rng.nextDouble() * 2 * Double.pi)
                t += 4
            }
            if beatsFromHere {
                var bt = Double(d.onset)
                while bt < Double(min(d.wake, now)) {
                    let mean = 60_000.0 / asleepBpm(bt).clamped(38.0, 140.0)
                    // White beat-to-beat noise: successive differences then have an RMSSD of about 1.3 × sigma, so scale to the seeded HRV.
                    let ms = (mean + gauss(&rng, 0.0, d.hrv / 1.414 * 0.92)).clamped(400.0, 1700.0)
                    beat(bt, ms)
                    bt += ms / 1000.0
                }
            }

            // Awake until the next night (or now). A slow tension wave runs through the day (two sines with phases of their own, 0…1): the heart rate
            // rides a few beats higher and the variability thinner when it peaks, so the Stress screen has calm hours and tense ones to tell apart.
            let phaseA = rng.nextDouble() * 2 * Double.pi
            let phaseB = rng.nextDouble() * 2 * Double.pi
            func tension(_ at: Int) -> Double {
                let x = Double(at - d.wake)
                return (0.5 + 0.34 * Foundation.sin(2.0 * Double.pi * x / 11_000.0 + phaseA) + 0.22 * Foundation.sin(2.0 * Double.pi * x / 4_300.0 + phaseB)).clamped(0.0, 1.0)
            }
            let awakeEnd = min(n + 1 < days.count ? days[n + 1].onset : now, now)
            var base = Double(d.rhr) + 14.0
            var burst = 0.0
            t = d.wake
            while t < awakeEnd {
                if (t - d.wake) % 600 == 0 {
                    let hour = Double(cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(t))))
                    base = Double(d.rhr) + 14.0 + 4.0 * Foundation.sin(2.0 * Double.pi * (hour - 14.0) / 24.0)
                    burst = rng.nextDouble() < 0.12 ? gauss(&rng, 14.0, 6.0).atLeast(0.0) : 0.0
                }
                var bpm = base + burst + 6.0 * tension(t) - 3.0 + gauss(&rng, 0.0, 2.5)
                var training = false
                for w in d.workouts where t > w.end && t < w.end + 1200 {
                    // The heart rate takes a while to come down after a session.
                    bpm = Swift.max(bpm, base + (Double(w.avg) - base) * 0.65 * Foundation.exp(-Double(t - w.end) / 360.0))
                }
                for w in d.workouts where t >= w.start && t <= w.end {
                    training = true
                    let up = Swift.min(1.0, Double(t - w.start) / 240.0)
                    let down = Swift.min(1.0, Double(w.end - t) / 120.0)
                    let level = base + (Double(w.avg) - base) * up * down
                    bpm = Swift.min(Double(w.max), level * (1.0 + 0.07 * Foundation.sin(2.0 * Double.pi * Double(t) / 300.0)) + gauss(&rng, 0.0, 3.0))
                }
                hr.append(HRSample(ts: t, bpm: Int(bpm.clamped(45.0, 195.0))))
                let step = training ? gauss(&rng, 0.5, 0.15).atLeast(0.25) : (burst > 16 ? gauss(&rng, 0.32, 0.12).atLeast(0.05) : Swift.abs(gauss(&rng, 0.0, 0.03)))
                move(t, step, rng.nextDouble() * 2 * Double.pi)
                t += 4
            }
            if beatsFromHere {
                var w = d.wake + 600
                while w + 300 < awakeEnd && w < d.wake + 13 * 3600 {
                    var bt = Double(w)
                    let tense = tension(w + 150)
                    while bt < Double(w + 300) {
                        let ms = (60_000.0 / (Double(d.rhr) + 11.0 + 6.0 * tense) + gauss(&rng, 0.0, d.hrv * 0.4 * (1.2 - 0.5 * tense))).clamped(350.0, 1500.0)
                        beat(bt, ms)
                        bt += ms / 1000.0
                    }
                    w += 600
                }
            }
        }

        let chunk = 50_000
        for from in stride(from: 0, to: hr.count, by: chunk) {
            _ = try await store.insert(Streams(hr: Array(hr[from..<Swift.min(from + chunk, hr.count)])), deviceId: whoop)
        }
        for from in stride(from: 0, to: rr.count, by: chunk) {
            _ = try await store.insert(Streams(rr: Array(rr[from..<Swift.min(from + chunk, rr.count)])), deviceId: whoop)
        }
        for from in stride(from: 0, to: gravity.count, by: chunk) {
            _ = try await store.insert(Streams(gravity: Array(gravity[from..<Swift.min(from + chunk, gravity.count)])), deviceId: whoop)
        }
    }

    // MARK: - Sessions with a map and a gym session

    /// Sessions to look at the map and the gym screens under `--demo-seed`: a run, a ride and a walk each with a GPS route (a few earlier ones of
    /// the same sport and some HIIT, so the 30-day averages and the typical zone ranges have something to stand on), and a strength session
    /// today with its sets and a heart rate. Added once, kept apart from the year so an install seeded before this still gets them.
    private static func seedSportExtrasIfNeeded(into store: WhoopStore) async {
        let now = Int(Date().timeIntervalSince1970)
        let recent = (try? await store.workouts(deviceId: whoop, from: now - 40 * 86_400, to: now + 86_400, limit: 2_000)) ?? []
        guard !recent.contains(where: { $0.notes == "demo-extras" }) else { return }
        var rng = SplitMix64(seed: 0xD0E5)
        // sport, hours ago it started, minutes, kilometres (0 = no route), average and highest heart rate, zone shares (%)
        typealias Plan = (sport: String, ago: Double, min: Double, km: Double, avg: Int, max: Int, zones: [Double])
        let plans: [Plan] = [
            ("Running", 4.6, 38, 6.1, 156, 178, [4, 12, 30, 40, 14]),
            ("Running", 5 * 24 + 2, 41, 6.4, 151, 174, [6, 16, 34, 36, 8]),
            ("Running", 12 * 24 + 3, 35, 5.6, 158, 181, [3, 10, 28, 42, 17]),
            ("Running", 19 * 24 + 1, 44, 7.0, 149, 172, [8, 20, 36, 30, 6]),
            ("Running", 26 * 24 + 2, 39, 6.2, 154, 176, [5, 14, 32, 38, 11]),
            ("Cycling", 26, 62, 24.6, 138, 164, [10, 28, 38, 20, 4]),
            ("Cycling", 6 * 24 + 4, 55, 21.3, 134, 160, [12, 32, 36, 16, 4]),
            ("Cycling", 13 * 24 + 5, 70, 28.1, 140, 167, [9, 26, 38, 21, 6]),
            ("Cycling", 20 * 24 + 3, 58, 22.8, 136, 162, [11, 30, 36, 18, 5]),
            ("Walking", 50, 43, 3.6, 108, 142, [30, 46, 20, 4, 0]),
            ("Walking", 4 * 24 + 1, 36, 3.0, 104, 138, [34, 44, 18, 4, 0]),
            ("Walking", 8 * 24 + 2, 48, 4.1, 110, 144, [28, 46, 21, 5, 0]),
            ("Walking", 15 * 24 + 1, 40, 3.4, 106, 140, [32, 45, 19, 4, 0]),
            ("HIIT", 4 * 24 + 6, 36, 0, 158, 184, [3, 9, 22, 46, 20]),
            ("HIIT", 9 * 24 + 7, 40, 0, 154, 181, [4, 11, 26, 44, 15]),
            ("HIIT", 16 * 24 + 6, 33, 0, 160, 186, [2, 8, 20, 48, 22]),
            ("HIIT", 23 * 24 + 7, 38, 0, 152, 180, [5, 12, 28, 42, 13]),
        ]
        var rows: [WorkoutRow] = []
        var routes: [(route: WorkoutRoute, startTs: Int, sport: String)] = []
        var hr: [HRSample] = []
        func addHeartRate(start: Int, end: Int, avg: Int, peak: Int) {
            var t = start - 300
            while t <= end + 120 {
                let up = Swift.min(1.0, Swift.max(0.0, Double(t - start) / 240.0 + 0.2))
                let down = Swift.min(1.0, Swift.max(0.0, Double(end + 120 - t) / 180.0))
                let level = 66.0 + (Double(avg) - 66.0) * up * down
                let bpm = level * (1.0 + 0.06 * Foundation.sin(2.0 * Double.pi * Double(t) / 420.0)) + gauss(&rng, 0.0, 2.0)
                hr.append(HRSample(ts: t, bpm: Int(bpm.clamped(50.0, Double(peak)))))
                t += 5
            }
        }
        for (i, p) in plans.enumerated() {
            let start = now - Int(p.ago * 3600), end = start + Int(p.min * 60)
            var distance: Double?
            if p.km > 0 {
                let pts = loopRoute(km: p.km, seed: i, rng: &rng)
                let meters = RouteMath.totalMeters(pts)
                distance = round1(meters)
                routes.append((WorkoutRoute(polyline: RouteMath.encode(pts), distanceM: meters, elevationGainM: round1(8 + p.km * 3.5)), start, p.sport))
            }
            let z = p.zones
            let zonesJSON = "{\"zone1\":\(z[0]),\"zone2\":\(z[1]),\"zone3\":\(z[2]),\"zone4\":\(z[3]),\"zone5\":\(z[4])}"
            rows.append(WorkoutRow(
                startTs: start, endTs: end, sport: p.sport, source: whoop, durationS: p.min * 60, energyKcal: round1(p.min * (p.sport == "Walking" ? 5.2 : 10.8)),
                avgHr: p.avg, maxHr: p.max, strain: round1(Double(p.avg - 60) * p.min / 60 * 0.62 * (p.sport == "Walking" ? 0.5 : 1.0) + 8),
                distanceM: distance, zonesJSON: zonesJSON, notes: i == 0 ? "demo-extras" : nil,
                steps: p.sport == "Running" ? Int(p.min * 164) : (p.sport == "Walking" ? Int(p.min * 128) : nil)))
            if p.ago < 30 * 24 { addHeartRate(start: start, end: end, avg: p.avg, peak: p.max) }
        }
        // A strength session today, a couple of hours before the run.
        let gymStart = now - Int(2.2 * 3600), gymEnd = gymStart + 58 * 60
        rows.append(WorkoutRow(startTs: gymStart, endTs: gymEnd, sport: "Strength Training", source: "manual", durationS: Double(gymEnd - gymStart), energyKcal: 362,
                               avgHr: 121, maxHr: 158, strain: 36.4, distanceM: nil, zonesJSON: nil, notes: "Upper push/pull", steps: nil))
        addHeartRate(start: gymStart, end: gymEnd, avg: 124, peak: 158)
        do {
            _ = try await store.upsertWorkouts(rows, deviceId: whoop)
            for from in stride(from: 0, to: hr.count, by: 50_000) {
                _ = try await store.insert(Streams(hr: Array(hr[from..<Swift.min(from + 50_000, hr.count)])), deviceId: whoop)
            }
            RouteStore.storeAll(routes)
            let sessionId = "demo-gym-today"
            _ = try await store.upsertLiftSessions([LiftSessionRow(id: sessionId, deviceId: whoop, startTs: gymStart, endTs: gymEnd, sport: "Strength Training",
                                                                   programId: "demo-prog-1", programName: "Upper push/pull", sessionRpe: nil, note: nil)])
            let plan: [(String, LiftMuscle, [LiftMuscle], [(Double, Int)])] = [
                ("Bench Press", .chest, [.triceps, .frontDelts], [(45, 10), (65, 8), (65, 8), (67.5, 6)]),
                ("Barbell Row", .lats, [.upperBack], [(55, 10), (65, 8), (65, 8)]),
                ("Overhead Press", .frontDelts, [.triceps], [(32.5, 10), (37.5, 8), (37.5, 7)]),
                ("Lat Pulldown", .lats, [.biceps], [(50, 12), (55, 10), (55, 10)]),
            ]
            var ord = 0
            var sets: [LiftSetRow] = []
            for (name, primary, secondary, work) in plan {
                for (i, w) in work.enumerated() {
                    sets.append(LiftSetRow(id: "\(sessionId)-\(ord)", deviceId: whoop, sessionId: sessionId, ord: ord, exercise: name, primaryMuscle: primary,
                                           secondaryMuscles: secondary, setIndex: i + 1, weightKg: w.0, reps: w.1, rpe: nil, isWarmup: false,
                                           startTs: gymStart + 300 + ord * 240, endTs: gymStart + 300 + ord * 240 + 60, restSec: 90, note: nil))
                    ord += 1
                }
            }
            _ = try await store.upsertLiftSets(sets)
        } catch { NSLog("AppleDemoSeeder: sport extras failed — \(error)") }
    }

    /// Stretching sessions in which the heart rate stays low (zone 0 and zone 1) and has no map, to look at the low-intensity log under
    /// `--demo-seed`: a handful over the last three weeks, so the milestone count and the impact on recovery have days to stand on. Added once.
    private static func seedLowIntensityExtrasIfNeeded(into store: WhoopStore) async {
        let now = Int(Date().timeIntervalSince1970)
        let recent = (try? await store.workouts(deviceId: whoop, from: now - 40 * 86_400, to: now + 86_400, limit: 2_000)) ?? []
        guard !recent.contains(where: { $0.notes == "demo-low" }) else { return }
        var rng = SplitMix64(seed: 0x57E7C4)
        // hours ago it started, minutes
        let plans: [(ago: Double, min: Double)] = [(7, 13), (3 * 24 + 7, 18), (6 * 24 + 8, 15), (9 * 24 + 7, 20), (12 * 24 + 8, 14), (17 * 24 + 7, 16), (21 * 24 + 8, 19)]
        var rows: [WorkoutRow] = []
        var hr: [HRSample] = []
        for (i, p) in plans.enumerated() {
            let start = now - Int(p.ago * 3600), end = start + Int(p.min * 60)
            rows.append(WorkoutRow(startTs: start, endTs: end, sport: "Stretching", source: whoop, durationS: p.min * 60, energyKcal: round1(p.min * 3.4),
                                   avgHr: 84 + i % 3, maxHr: 97 + i % 4, strain: round1(1.6 + Double(i % 3) * 0.4), distanceM: nil, zonesJSON: nil,
                                   notes: i == 0 ? "demo-low" : nil, steps: nil))
            var t = start - 300
            while t <= end + 120 {
                let up = Swift.min(1.0, Swift.max(0.0, Double(t - start) / 180.0 + 0.2))
                let down = Swift.min(1.0, Swift.max(0.0, Double(end + 120 - t) / 120.0))
                let level = 64.0 + (84.0 - 64.0) * up * down
                let wave = 1.0 + 0.05 * Foundation.sin(2.0 * Double.pi * Double(t) / 150.0) + 0.03 * Foundation.sin(2.0 * Double.pi * Double(t) / 47.0)
                hr.append(HRSample(ts: t, bpm: Int((level * wave + gauss(&rng, 0.0, 1.6)).clamped(52.0, 104.0))))
                t += 5
            }
        }
        do {
            _ = try await store.upsertWorkouts(rows, deviceId: whoop)
            for from in stride(from: 0, to: hr.count, by: 50_000) {
                _ = try await store.insert(Streams(hr: Array(hr[from..<Swift.min(from + 50_000, hr.count)])), deviceId: whoop)
            }
        } catch { NSLog("AppleDemoSeeder: low-intensity extras failed — \(error)") }
    }

    /// Afternoon naps over the last week, to look at the Naps page under `--demo-seed`: a short one, a longer one, a day with none, a day with
    /// two and a long one the wearer added by hand. Each carries a stage timeline and a calm heart rate. Added once.
    private static func seedNapExtrasIfNeeded(into store: WhoopStore) async {
        let cal = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        let recent = (try? await store.sleepSessions(deviceId: whoop, from: now - 8 * 86_400, to: now + 86_400, limit: 200)) ?? []
        guard !recent.contains(where: { $0.endTs - $0.startTs < 3 * 3_600 }) else { return }
        var rng = SplitMix64(seed: 0x4E4150)
        // days back, start (minutes after midnight), minutes light / deep / rem / awake, added by hand
        let plans: [(back: Int, at: Int, light: Double, deep: Double, rem: Double, awake: Double, manual: Bool)] = [
            (0, 14 * 60 + 5, 20, 0, 0, 2, false),
            (1, 13 * 60 + 40, 38, 6, 8, 6, false),
            (3, 15 * 60 + 10, 34, 5, 7, 6, false),
            (3, 18 * 60 + 20, 18, 0, 0, 3, false),
            (5, 13 * 60 + 15, 48, 14, 18, 10, true),
        ]
        var sessions: [CachedSleepSession] = []
        var hr: [HRSample] = []
        for p in plans {
            let total = Int((p.light + p.deep + p.rem + p.awake) * 60)
            // A nap that has not happened yet today (the afternoon is still ahead) moves to the same hour six days back.
            var back = p.back
            func startTs(_ b: Int) -> Int {
                Int(cal.date(byAdding: .day, value: -b, to: cal.startOfDay(for: Date()))!.timeIntervalSince1970) + p.at * 60
            }
            if startTs(back) + total > now - 300 { back += 6 }
            let start = startTs(back)
            var t = start
            var parts: [String] = []
            func seg(_ stage: String, _ minutes: Double) {
                let secs = Int(minutes * 60)
                guard secs > 0 else { return }
                parts.append("{\"start\":\(t),\"end\":\(t + secs),\"stage\":\"\(stage)\"}")
                t += secs
            }
            seg("light", p.light * 0.4); seg("deep", p.deep * 0.6); seg("light", p.light * 0.3)
            seg("rem", p.rem); seg("deep", p.deep * 0.4); seg("light", p.light * 0.3); seg("wake", p.awake)
            let end = start + total
            sessions.append(CachedSleepSession(
                startTs: start, endTs: end, efficiency: round1(((p.light + p.deep + p.rem) / (p.light + p.deep + p.rem + p.awake) * 100).clamped(70.0, 98.0)),
                restingHr: 58 + Int(rng.nextInt(-2, 3)), avgHrv: round1(gauss(&rng, 74.0, 6.0)),
                stagesJSON: "[" + parts.joined(separator: ",") + "]", userEdited: p.manual))
            var ts = start
            while ts <= end {
                let level = 63.0 - 6.0 * Foundation.sin(Double.pi * Double(ts - start) / Double(max(total, 1)))
                hr.append(HRSample(ts: ts, bpm: Int((level + gauss(&rng, 0.0, 1.8)).clamped(48.0, 80.0))))
                ts += 10
            }
        }
        do {
            _ = try await store.upsertSleepSessions(sessions, deviceId: whoop)
            _ = try await store.insert(Streams(hr: hr), deviceId: whoop)
        } catch { NSLog("AppleDemoSeeder: nap extras failed — \(error)") }
    }

    /// Recovery activities (breathwork, a cold shower) for the Charge tab, with a calm heart rate on the breathwork: added once.
    private static func seedRecoveryExtrasIfNeeded(into store: WhoopStore) async {
        let now = Int(Date().timeIntervalSince1970)
        let recent = (try? await store.workouts(deviceId: whoop, from: now - 40 * 86_400, to: now + 86_400, limit: 2_000)) ?? []
        guard !recent.contains(where: { $0.notes == "demo-recovery" }) else { return }
        var rng = SplitMix64(seed: 0xB2EA7)
        let plans: [(sport: String, ago: Double, min: Double)] = [("Breathwork", 3.0, 20), ("Breathwork", 2 * 24 + 5, 15), ("Breathwork", 6 * 24 + 4, 20), ("Cold shower", 4 * 24 + 6, 5), ("Breathwork", 11 * 24 + 5, 12)]
        var rows: [WorkoutRow] = []
        var hr: [HRSample] = []
        for (i, p) in plans.enumerated() {
            let start = now - Int(p.ago * 3600), end = start + Int(p.min * 60)
            rows.append(WorkoutRow(startTs: start, endTs: end, sport: p.sport, source: whoop, durationS: p.min * 60, energyKcal: nil, avgHr: p.sport == "Breathwork" ? 66 : nil,
                                   maxHr: p.sport == "Breathwork" ? 78 : nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: i == 0 ? "demo-recovery" : nil, steps: nil))
            guard p.sport == "Breathwork" else { continue }
            var t = start - 300
            while t <= end + 120 {
                let calm = 1.0 + 0.04 * Foundation.sin(2.0 * Double.pi * Double(t) / 60.0)
                hr.append(HRSample(ts: t, bpm: Int((64.0 * calm + gauss(&rng, 0.0, 1.2)).clamped(52.0, 84.0))))
                t += 5
            }
        }
        do {
            _ = try await store.upsertWorkouts(rows, deviceId: whoop)
            for from in stride(from: 0, to: hr.count, by: 50_000) {
                _ = try await store.insert(Streams(hr: Array(hr[from..<Swift.min(from + 50_000, hr.count)])), deviceId: whoop)
            }
        } catch { NSLog("AppleDemoSeeder: recovery extras failed — \(error)") }
    }

    /// A closed loop of about `km` kilometres around a park in Jakarta, wobbled so no two look alike, one point every few seconds.
    private static func loopRoute(km: Double, seed: Int, rng: inout SplitMix64) -> [RouteMath.LatLng] {
        let radiusDeg = km / (2 * Double.pi) / 111.0
        let centre = (lat: -6.2185 + Double(seed % 5) * 0.004, lon: 106.8020 + Double(seed % 3) * 0.005)
        let phase = Double(seed) * 0.9
        let n = Swift.max(120, Int(km * 38))
        return (0...n).map { i in
            let a = 2 * Double.pi * Double(i) / Double(n)
            let r = radiusDeg * (1 + 0.14 * Foundation.sin(3 * a + phase) + 0.07 * Foundation.sin(5 * a + 1 + phase))
            return RouteMath.LatLng(centre.lat + r * Foundation.sin(a) + gauss(&rng, 0.0, 0.000008), centre.lon + r * 1.05 * Foundation.cos(a) + gauss(&rng, 0.0, 0.000008))
        }
    }

    // MARK: - helpers

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    /// Box–Muller normal sample, matching DemoSeeder.gauss exactly.
    private static func gauss(_ rng: inout SplitMix64, _ mean: Double, _ sd: Double) -> Double {
        let u1 = rng.nextDouble().clamped(1e-9, 1.0)
        let u2 = rng.nextDouble()
        return mean + sd * (Foundation.sqrt(-2.0 * Foundation.log(u1)) * Foundation.cos(2.0 * Double.pi * u2))
    }

    /// A plausible light→deep→rem cycle as the COMPUTED segment array
    /// [{"start":epoch,"end":epoch,"stage":"light"|"deep"|"rem"|"wake"}] that SleepView.decodeSegments
    /// reads, laid end-to-end from `onset`.
    private static func segmentsJSON(onset: Int, deep: Double, rem: Double, light: Double, awakeMin: Double) -> String {
        var t = onset
        var parts: [String] = []
        func seg(_ stage: String, _ minutes: Double) {
            let secs = Int(minutes * 60)
            guard secs > 0 else { return }
            parts.append("{\"start\":\(t),\"end\":\(t + secs),\"stage\":\"\(stage)\"}")
            t += secs
        }
        seg("light", light * 0.35); seg("deep", deep * 0.6); seg("light", light * 0.30)
        seg("rem", rem * 0.6); seg("deep", deep * 0.4); seg("light", light * 0.35)
        seg("rem", rem * 0.4); seg("wake", awakeMin)
        return "[" + parts.joined(separator: ",") + "]"
    }
}

/// Deterministic SplitMix64 PRNG — gives a fixed, reproducible demo dataset across runs (the Apple
/// counterpart of Kotlin's `Random(0xC0FFEE)`). Not for any security use.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)  // 2^53
    }

    /// Uniform Int in [lower, upper).
    mutating func nextInt(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        let span = UInt64(upper - lower)
        return lower + Int(next() % span)
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
    func atLeast(_ lo: Double) -> Double { Swift.max(self, lo) }
}
#endif
