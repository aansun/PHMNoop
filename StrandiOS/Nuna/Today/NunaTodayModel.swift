#if os(iOS)
import Foundation
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Everything the Nuna Today screen shows for one selected day.
///
/// This is a deliberately smaller twin of the loading in `LiquidTodayView.load()`: the same repository
/// reads and the same resolvers (`ChargeDisplay`, `TodayView.freshRestScore`, `StrainScorer.effectiveEffort`,
/// `StressModel`), without the sparkline, hosted-card and day-cycle machinery that Nuna does not draw.
/// Display only: nothing is computed or stored differently.
@MainActor
final class NunaTodayModel: ObservableObject {
    /// 0 = today, 1 = yesterday, ...
    @Published var dayOffset = 0

    @Published private(set) var day: DailyMetric?
    @Published private(set) var charge: LiquidTodayView.ChargeDisplay = .noData
    /// Stored Effort on NOOP's 0-100 axis (live for today, stored for past days).
    @Published private(set) var effort: Double?
    @Published private(set) var rest: Double?
    @Published private(set) var stress: Double?
    @Published private(set) var hrv: Double?
    @Published private(set) var restingHr: Double?
    @Published private(set) var respiratory: Double?
    @Published private(set) var spo2: Double?
    @Published private(set) var steps: Double?
    @Published private(set) var calories: Double?
    @Published private(set) var sleepMinutes: Double?
    @Published private(set) var workouts: [WorkoutRow] = []
    @Published private(set) var loaded = false

    var isToday: Bool { dayOffset == 0 }

    private var selectedLogicalDay: Date {
        let base = Repository.logicalDay(Date())
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: base) ?? base
    }

    func dayKey(repo: Repository) -> String {
        if dayOffset == 0, let key = repo.today?.day { return key }
        return Repository.localDayKey(selectedLogicalDay)
    }

    /// Date shown in the header pill.
    var displayDate: Date { selectedLogicalDay }

    func load(repo: Repository, profile: ProfileStore) async {
        let key = dayKey(repo: repo)
        let today = isToday
        let row = today ? (repo.today ?? repo.days.last(where: { $0.day == key }))
                        : repo.days.last(where: { $0.day == key })
        day = row

        // Charge, with the same carry / calibration rules as the other Today screens.
        let calNights = today
            ? RecoveryScorer.calibrationNights(nightlyHrv: repo.days.map(\.avgHrv), dayKeys: repo.days.map(\.day),
                                               hasRecovery: row?.recovery != nil)
            : nil
        let prior = TodayView.lastScoredRecoveryDay(days: repo.days, selectedDayKey: key, isToday: today,
                                                    todayScored: row?.recovery != nil, isCalibrating: calNights != nil)
        charge = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: row?.recovery, priorScored: prior,
                                                       calibrationNights: calNights, todayKey: key)

        // Vitals carried from the last night that has them (today only; a past day shows its own row).
        hrv = row?.avgHrv ?? (today ? Repository.lastHrvDay(days: repo.days, todayKey: key)?.avgHrv : nil)
        restingHr = (row?.restingHr ?? (today ? Repository.lastRestingHrDay(days: repo.days, todayKey: key)?.restingHr : nil)).map(Double.init)
        respiratory = row?.respRateBpm ?? (today ? Repository.lastRespDay(days: repo.days, todayKey: key)?.respRateBpm : nil)
        spo2 = row?.spo2Pct ?? (today ? Repository.lastVitalsDay(days: repo.days, todayKey: key)?.spo2Pct : nil)
        sleepMinutes = row?.totalSleepMin

        // Live Effort for today over midnight..now, stored Effort otherwise.
        var live: Double?
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedLogicalDay)
        let from = Int(dayStart.timeIntervalSince1970)
        let to: Int = today ? Int(Date().timeIntervalSince1970)
                            : Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)
        if today {
            let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
            let maxHR = profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil
            let restHR = row?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
            live = StrainScorer.strain(hr, maxHR: maxHR, restingHR: restHR, method: PuffinExperiment.effortMethod, sex: profile.sex)
        }
        effort = StrainScorer.effectiveEffort(live: live, stored: row?.strain)

        async let restA = repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        async let stressA = repo.series(key: "stress", source: "my-whoop")
        async let stepsA = repo.exploreSeries(key: "steps_est", source: "my-whoop")
        async let appleA = repo.appleDailyRows()
        async let workoutsA = repo.workoutRows()

        let restSeries = await restA
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        rest = TodayView.freshRestScore(todayValue: restByDay[key], lastDay: restSeries.last?.day,
                                        lastValue: restSeries.last?.value, isTodaySelected: today, todayKey: key)

        let stored = await stressA
        let daysSnapshot = repo.days
        stress = await Task.detached(priority: .utility) {
            StressModel(days: daysSnapshot, stored: stored)?.score
        }.value

        // Steps and calories: measured on the strap first, then Apple Health, then the on-device estimate.
        let stepsSeries = await stepsA
        let stepsByDay = Dictionary(stepsSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let estSteps = stepsByDay[key] ?? (today ? stepsSeries.last?.value : nil)
        let appleKey = TodayView.appleHealthDayKey(selectedDayKey: key, localDayKey: Repository.localDayKey(Date()), isToday: today)
        let apple = await appleA
        let appleSteps = apple.filter { $0.day == appleKey }.compactMap { $0.steps }.max()
        let appleKcal = apple.filter { $0.day == appleKey }.compactMap { $0.activeKcal }.max()
        steps = row?.steps.map(Double.init) ?? appleSteps.map(Double.init) ?? estSteps
        calories = appleKcal ?? row?.activeKcalEst

        workouts = (await workoutsA).filter { $0.startTs >= from && $0.startTs < to }
        loaded = true
    }
}
#endif
