#if DEBUG && os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// DEBUG-only: the half of the `--demo-seed` year that lives outside the daily tables, so every Nuna screen has a year of its own data to
/// walk: water, mood check-ins (with factors, energy and a note), breathing sessions, period starts, the nutrition diary with saved foods
/// and a plan, a short conversation with Anya, and a few guided live sessions. It reads the recovery the main seeder wrote and lets each
/// of these follow the body (a poor night, a low mood, less water), deterministic like the rest.
///
/// Runs once per install (a marker in `UserDefaults`), after `AppleDemoSeeder`, and only if that seeder left a year of daily rows. Nothing
/// here is real data and the whole file is stripped from a Release build.
@MainActor
enum NunaDemoYear {
    private static let markerKey = "demo.year.seeded.v1"
    private static let days = 365

    static func seedIfRequested(repo: Repository, store: WhoopStore) async {
        if AppleDemoSeeder.requested { busyDays(now: Int(Date().timeIntervalSince1970)) }
        guard AppleDemoSeeder.requested, !UserDefaults.standard.bool(forKey: markerKey) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys: [String] = (0..<days).map { Repository.localDayKey(cal.date(byAdding: .day, value: -(days - 1 - $0), to: today) ?? today) }
        guard let first = keys.first, let last = keys.last,
              let metrics = try? await store.dailyMetrics(deviceId: AppleDemoSeeder.whoop, from: first, to: last), metrics.count > 60 else { return }
        var recovery: [String: Double] = [:]
        var restingHr: [String: Int] = [:]
        for m in metrics { recovery[m.day] = m.recovery ?? 60; restingHr[m.day] = m.restingHr ?? 56 }
        var rng = SplitMix64(seed: 0xBEEF_2026)
        let now = Int(Date().timeIntervalSince1970)

        await water(keys: keys, recovery: recovery, rng: &rng, repo: repo, store: store)
        await mood(keys: keys, recovery: recovery, rng: &rng, store: store)
        breathing(keys: keys, recovery: recovery, restingHr: restingHr, rng: &rng, now: now)
        await period(keys: keys, rng: &rng, store: store)
        await nutrition(keys: keys, rng: &rng, repo: repo, store: store, now: now)
        await anya(store: store, now: now)
        await liveSessions(keys: keys, recovery: recovery, rng: &rng, store: store, today: today)

        UserDefaults.standard.set(true, forKey: markerKey)
        await repo.refresh()
        NSLog("NunaDemoYear: seeded water, mood, breathing, period, nutrition, Anya and live sessions over \(keys.count) days.")
    }

    // MARK: Water

    /// A total per day, less on a poor-recovery day; the last week through the same taps the Hydration screen makes (cups, a bottle), so the
    /// per-drink list behind the total has entries to edit and delete.
    private static func water(keys: [String], recovery: [String: Double], rng: inout SplitMix64, repo: Repository, store: WhoopStore) async {
        UserDefaults.standard.set(true, forKey: HydrationStore.enabledKey)
        var points: [MetricPoint] = []
        for key in keys.dropLast(7) {
            let ml = gauss(&rng, 2150 + ((recovery[key] ?? 60) - 60) * 4, 380).clamped(900, 3600)
            points.append(MetricPoint(day: key, key: HydrationStore.key, value: (ml / 50).rounded() * 50))
        }
        _ = try? await store.upsertMetricSeries(points, deviceId: HydrationStore.sourceId)
        for (n, key) in keys.suffix(7).enumerated() {
            let target = n == 6 ? 1250 : Int(gauss(&rng, 2200, 300).clamped(1400, 3200))
            var total = 0
            while total < target {
                let cup = [250, 250, 330, 500][rng.nextInt(0, 4)]
                _ = await repo.logHydration(amountMl: cup, day: key)
                total += cup
            }
        }
    }

    // MARK: Mood

    private static func mood(keys: [String], recovery: [String: Double], rng: inout SplitMix64, store: WhoopStore) async {
        let factors = ["work", "family", "exercise", "sleep", "caffeine", "social", "travel"]
        let notes = ["Slow start, better after a walk.", "Good session at the gym.", "Busy day, little time to eat properly.",
                     "Early night helped.", "Too much coffee.", "Quiet weekend.", "Long meeting day.", "Dinner with friends."]
        var points: [MetricPoint] = []
        for (i, key) in keys.enumerated() where rng.nextDouble() < 0.93 {
            let rec = recovery[key] ?? 60
            let value = Int((2.0 + rec / 100.0 * 2.4 + gauss(&rng, 0.0, 0.7)).rounded()).clamped(1, 5)
            points.append(MetricPoint(day: key, key: MoodStore.moodKey, value: Double(value)))
            if i >= keys.count - 90 {
                var picked: [String] = []
                for _ in 0..<(1 + rng.nextInt(0, 3)) { let f = factors[rng.nextInt(0, factors.count)]; if !picked.contains(f) { picked.append(f) } }
                NunaMoodExtras.save(NunaMoodExtras(factors: picked, energy: (rec / 100.0 + gauss(&rng, 0.0, 0.1)).clamped(0.1, 0.95),
                                                   note: rng.nextDouble() < 0.3 ? notes[rng.nextInt(0, notes.count)] : ""), day: key)
            }
        }
        _ = try? await store.upsertMetricSeries(points, deviceId: MoodStore.moodDeviceId)
    }

    // MARK: Breathing

    /// About 70 sessions across the year, a few a week lately: heart rate sinking and the beat-to-beat variability rising over a session.
    private static func breathing(keys: [String], recovery: [String: Double], restingHr: [String: Int], rng: inout SplitMix64, now: Int) {
        NunaBreathLog.clear()
        let templates = BreathTemplates.all.filter(\.advisable)
        var chosen = Set<Int>()
        while chosen.count < 70 {
            // Squared so the recent weeks are denser than the early months.
            let u = rng.nextDouble()
            chosen.insert(Int(u * u * Double(keys.count - 1)))
        }
        for daysAgo in chosen.sorted(by: >) {
            let key = keys[keys.count - 1 - daysAgo]
            let template = templates[rng.nextInt(0, templates.count)]
            let seconds = template.minutes * 60 + rng.nextInt(-20, 25)
            let hour = template.goal == .sleep ? 22 : (rng.nextDouble() < 0.5 ? 7 : 13)
            guard let date = Calendar.current.date(bySettingHour: hour, minute: rng.nextInt(0, 50), second: 0,
                                                   of: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()) else { continue }
            let startTs = Int(date.timeIntervalSince1970)
            guard startTs < now - seconds else { continue }
            let step = 10
            let points = max(2, seconds / step)
            let hrStart = Double(restingHr[key] ?? 56) + 12 + gauss(&rng, 0, 3)
            let hrEnd = hrStart - (6 + gauss(&rng, 0, 1.5).atLeast(0))
            let rmssdStart = (28 + (recovery[key] ?? 60) * 0.3 + gauss(&rng, 0, 4)).clamped(15, 90)
            let rmssdEnd = rmssdStart * (1.12 + rng.nextDouble() * 0.25)
            let hrSeries = (0..<points).map { hrStart + (hrEnd - hrStart) * Double($0) / Double(points - 1) + gauss(&rng, 0, 1.2) }
            let rmssdSeries = (0..<points).map { rmssdStart + (rmssdEnd - rmssdStart) * Double($0) / Double(points - 1) + gauss(&rng, 0, 2.5) }
            NunaBreathLog.append(NunaBreathRecord(
                startTs: startTs, seconds: seconds, goal: template.goal.rawValue, templateId: template.id, protocolId: template.protocolId,
                breaths: seconds / 10, hrStart: hrSeries.first, hrEnd: hrSeries.last, hrAvg: hrSeries.reduce(0, +) / Double(points),
                rmssdStart: rmssdSeries.first, rmssdAvg: rmssdSeries.reduce(0, +) / Double(points), rmssdPeak: rmssdSeries.max(),
                hrSeries: hrSeries, rmssdSeries: rmssdSeries, haptics: rng.nextDouble() < 0.5))
        }
    }

    private static let busyKey = "demo.breath.busy.ids"

    /// Two days with three breathing sessions each, one of every kind: yesterday 15 minutes in all, the day before 19 (past the top of the chart).
    private static func busyDays(now: Int) {
        // They sit at fixed days before today, so each launch takes the previous copies out and writes them again where "yesterday" now is.
        for id in (UserDefaults.standard.stringArray(forKey: busyKey) ?? []).compactMap(UUID.init(uuidString:)) { NunaBreathLog.delete(id) }
        var ids: [String] = []
        defer { UserDefaults.standard.set(ids, forKey: busyKey) }
        let cal = Calendar.current
        func add(_ daysAgo: Int, _ hour: Int, _ minutes: Int, _ protocolId: String, template: BreathTemplate? = nil) {
            guard let base = cal.date(byAdding: .day, value: -daysAgo, to: Date()), let at = cal.date(bySettingHour: hour, minute: 10, second: 0, of: base) else { return }
            let start = Int(at.timeIntervalSince1970)
            guard start < now - minutes * 60 else { return }
            let record = NunaBreathRecord(
                startTs: start, seconds: minutes * 60, goal: BreathGoal.calm.rawValue, templateId: template?.id, protocolId: template?.protocolId ?? protocolId,
                breaths: template == nil ? 0 : minutes * 6, hrStart: nil, hrEnd: nil, hrAvg: nil, rmssdStart: nil, rmssdAvg: nil, rmssdPeak: nil,
                hrSeries: [], rmssdSeries: [], haptics: false)
            NunaBreathLog.append(record); ids.append(record.id.uuidString)
        }
        let box = BreathTemplates.template(id: "focus_box"), slow = BreathTemplates.template(id: "calm_slow")
        add(1, 7, 5, "", template: box); add(1, 13, 6, NunaBreathKind.resonanceId); add(1, 21, 4, NunaBreathKind.calmMeId)
        add(2, 7, 5, "", template: slow); add(2, 12, 8, NunaBreathKind.resonanceId); add(2, 20, 6, NunaBreathKind.calmMeId)
    }

    // MARK: Cycle

    private static func period(keys: [String], rng: inout SplitMix64, store: WhoopStore) async {
        var points: [MetricPoint] = []
        var index = keys.count - 1 - 9
        while index >= 0 {
            points.append(MetricPoint(day: keys[index], key: CycleTrackingStore.periodStartKey, value: CycleTrackingStore.loggedValue))
            index -= 28 + rng.nextInt(-2, 3)
        }
        _ = try? await store.upsertMetricSeries(points, deviceId: CycleTrackingStore.sourceId)
    }

    // MARK: Nutrition

    private static let breakfasts: [(String, Double, Double, Double, Double)] = [
        ("Oatmeal with banana", 320, 11, 58, 6), ("Scrambled eggs on toast", 410, 24, 32, 20), ("Greek yogurt with berries", 240, 18, 26, 6),
        ("Nasi uduk with egg", 520, 17, 70, 19), ("Protein smoothie", 290, 28, 30, 6),
    ]
    private static let lunches: [(String, Double, Double, Double, Double)] = [
        ("Chicken rice bowl", 640, 42, 74, 16), ("Nasi padang, chicken", 780, 40, 85, 28), ("Tuna sandwich", 460, 30, 45, 16),
        ("Gado-gado", 520, 21, 48, 28), ("Soto ayam with rice", 560, 33, 62, 15),
    ]
    private static let dinners: [(String, Double, Double, Double, Double)] = [
        ("Grilled salmon, vegetables, rice", 620, 40, 58, 22), ("Beef stir-fry with rice", 690, 38, 70, 25), ("Tempeh and tofu curry", 540, 30, 52, 22),
        ("Pasta with turkey ragu", 650, 36, 78, 17), ("Ayam bakar, lalapan, rice", 600, 41, 60, 19),
    ]
    private static let snacks: [(String, Double, Double, Double, Double)] = [
        ("Apple", 95, 0.5, 25, 0.3), ("Almonds, 30 g", 175, 6, 6, 15), ("Protein bar", 210, 20, 22, 7), ("Banana", 105, 1.3, 27, 0.4),
        ("Boiled eggs ×2", 155, 13, 1, 11),
    ]

    /// Every day of the year with breakfast, lunch, dinner and most days a snack, a few days unlogged; today only breakfast so far. A plan is
    /// saved so the Strategy and the daily target read as set.
    private static func nutrition(keys: [String], rng: inout SplitMix64, repo: Repository, store: WhoopStore, now: Int) async {
        let ud = UserDefaults.standard
        ud.set(true, forKey: NunaNutritionPrefs.hasPlan)
        ud.set(true, forKey: NunaNutritionPrefs.nudges)
        ud.set(-0.25, forKey: NunaNutritionPrefs.paceKgPerWeek)
        ud.set(NunaNutritionPrefs.defaultProteinPerKg, forKey: NunaNutritionPrefs.proteinPerKg)
        ud.set(NunaNutritionPrefs.defaultFatShare, forKey: NunaNutritionPrefs.fatShare)
        ud.set(2250, forKey: NunaNutritionPrefs.targetKcal)

        var rows: [FoodEntryRow] = []
        let cal = Calendar.current
        for (i, key) in keys.enumerated() {
            let isToday = i == keys.count - 1
            if !isToday && rng.nextDouble() < 0.03 { continue }
            guard let dayDate = cal.date(from: DateComponents(
                year: Int(key.prefix(4)), month: Int(key.dropFirst(5).prefix(2)), day: Int(key.suffix(2)))) else { continue }
            let start = Int(cal.startOfDay(for: dayDate).timeIntervalSince1970)
            var meals: [(String, [(String, Double, Double, Double, Double)], Int)] = [("breakfast", breakfasts, 8 * 3600)]
            if !isToday {
                meals.append(("lunch", lunches, 12 * 3600 + 1800))
                meals.append(("dinner", dinners, 19 * 3600))
                if rng.nextDouble() < 0.7 { meals.append(("snack", snacks, 16 * 3600)) }
            }
            for (meal, pool, offset) in meals {
                let item = pool[rng.nextInt(0, pool.count)]
                let scale = 0.85 + rng.nextDouble() * 0.35
                rows.append(FoodEntryRow(
                    id: "demo-food-\(key)-\(meal)", deviceId: repo.deviceId, day: key, meal: meal, name: item.0,
                    kcal: (item.1 * scale).rounded(), proteinG: (item.2 * scale).rounded(), carbsG: (item.3 * scale).rounded(), fatG: (item.4 * scale).rounded(),
                    source: rng.nextDouble() < 0.07 ? "anya" : (rng.nextDouble() < 0.25 ? "saved" : "manual"), createdAt: start + offset))
            }
        }
        _ = try? await store.upsertFoodEntries(rows)

        let saved = breakfasts + lunches.prefix(2) + dinners.prefix(2) + snacks.prefix(3)
        for (i, item) in saved.enumerated() {
            try? await store.upsertSavedFood(SavedFoodRow(
                id: "demo-saved-\(i)", deviceId: repo.deviceId, name: item.0, kcal: item.1, proteinG: item.2, carbsG: item.3, fatG: item.4,
                useCount: 3 + rng.nextInt(0, 38), updatedAt: now - rng.nextInt(0, 60) * 86_400))
        }
    }

    // MARK: Anya

    private static func anya(store: WhoopStore, now: Int) async {
        let thread: [(String, String)] = [
            ("user", "How did I sleep this week?"),
            ("assistant", "You averaged about 7 h 10 min, with a steady bedtime around 23:10. Deep sleep held at roughly a fifth of the night. Two late screens in bed cost you some efficiency on Tuesday and Thursday."),
            ("user", "Why was my Recovery low on Thursday?"),
            ("assistant", "Your HRV dipped about 12% under your baseline and your resting heart rate was 3 bpm above it. Alcohol the evening before and a late coffee are logged in your journal, and both tend to move those two numbers in your own history."),
            ("user", "What should I do tomorrow?"),
            ("assistant", "Keep it moderate: a 30–40 minute easy session in zones 1–3 fits a Recovery in the 60s. Water early, magnesium in the evening, and aim to be in bed by 23:00."),
        ]
        let rows = thread.enumerated().map { i, m in
            CoachMessageRow(id: "demo-coach-\(i)", role: m.0, text: m.1, provider: "demo", createdAt: now - (thread.count - i) * 90, orderIndex: i)
        }
        try? await store.replaceCoachMessages(rows)
    }

    // MARK: Guided live sessions

    private static func liveSessions(keys: [String], recovery: [String: Double], rng: inout SplitMix64, store: WhoopStore, today: Date) async {
        let start = Int(today.timeIntervalSince1970)
        for daysAgo in [3, 6, 10, 14, 19, 26, 33, 41, 52, 60] {
            let key = keys[keys.count - 1 - daysAgo]
            let startTs = start - daysAgo * 86_400 + 18 * 3600 + rng.nextInt(0, 40) * 60
            let total = Double(2400 + rng.nextInt(0, 1800))
            let inBand = total * (0.6 + rng.nextDouble() * 0.25)
            let below = (total - inBand) * 0.55
            let row = LiveSessionRow(
                startTs: startTs, endTs: startTs + Int(total), chargeAtStart: recovery[key], floorBpm: 118, ceilingBpm: 148,
                inBandSec: inBand, belowSec: below, aboveSec: total - inBand - below, pushCount: rng.nextInt(2, 9), easeCount: rng.nextInt(1, 6), hrSource: "whoop")
            _ = try? await store.upsertLiveSession(row, deviceId: AppleDemoSeeder.whoop)
        }
    }

    // MARK: helpers

    private static func gauss(_ rng: inout SplitMix64, _ mean: Double, _ sd: Double) -> Double {
        let u1 = max(1e-9, rng.nextDouble()), u2 = rng.nextDouble()
        return mean + sd * (Foundation.sqrt(-2.0 * Foundation.log(u1)) * Foundation.cos(2.0 * Double.pi * u2))
    }
}

private extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { Swift.min(Swift.max(self, lo), hi) }
}

private extension Double {
    func atLeast(_ lo: Double) -> Double { Swift.max(self, lo) }
}
#endif
