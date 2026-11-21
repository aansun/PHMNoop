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
    /// True when the figure shown is the one Apple Health counted (it was higher than the strap's, or the strap had none).
    @Published private(set) var stepsFromPhone = false
    @Published private(set) var calories: Double?
    @Published private(set) var sleepMinutes: Double?
    @Published private(set) var workouts: [WorkoutRow] = []
    /// Latest value of the slower-moving metrics the Your Cards section can show.
    @Published private(set) var extras: [String: Double] = [:]
    @Published private(set) var loaded = false
    /// The one-line readiness read the Default Today synthesis uses, so both experiences say the same thing.
    @Published private(set) var readiness: ReadinessEngine.Readiness?
    /// Today's hourly stress curve (nil on past days or when it could not be scored).
    @Published private(set) var stressCurve: DaytimeStress.Result?
    /// Typical high-stress minutes for today's weekday, for the Stress card's comparison; today only, and only once it has been worked out.
    @Published private(set) var stressTypicalMin: Int?
    /// The wearer's usual stress, 0 to 3, for the Stress card's arrow.
    @Published private(set) var stressBaseline: Double?
    /// Whether the stress reading is ready or still learning the person (it needs 14 nights). While it is not ready every stress field here is
    /// nil: nothing about stress is shown until the baseline is complete.
    @Published private(set) var stressStatus: StressStatus = .calibrating(nights: 0)
    /// The WHOOP-reference reading of the day on show, with its three categories (Total day, Non-activity, Sleep).
    @Published private(set) var stressWhoop: WhoopStress.Result?
    /// Change against the previous day that has a value: HRV in ms, resting HR in bpm.
    @Published private(set) var hrvDelta: Double?
    @Published private(set) var restingHrDelta: Double?
    @Published private(set) var respiratoryDelta: Double?
    @Published private(set) var spo2Delta: Double?
    /// The reading before the one shown, for the figures that compare with it (steps, calories, sleep, stress, weight, skin temperature and the
    /// weekly Fitness Age and VO2max), keyed `steps`, `calories`, `sleep`, `stress`, `weight`, `skin_temp`, `body_age`,
    /// `vo2max_est`. A key is missing when there is no earlier reading. HRV, resting heart rate, respiratory rate and blood oxygen
    /// keep their deltas above.
    @Published private(set) var previous: [String: Double] = [:]

    var isToday: Bool { dayOffset == 0 }

    /// Re-reads today's stress curve on its own, so the Stress card and screen follow the day without a full reload. Cheap when no new
    /// heart rate has arrived: the curve is memoised on a fingerprint of today's samples.
    func refreshStress(repo: Repository) async {
        guard isToday else { return }
        let status = await StressEngine.shared.status(repo: repo)
        let whoop = status.isReady ? await StressDayCurve.whoopToday(repo: repo, now: Date()) : nil
        if whoop != stressWhoop || status != stressStatus { applyStress(whoop, status: status, today: true) }
    }

    /// Takes a reading (or none, while calibrating) and sets every stress field from it.
    private func applyStress(_ w: WhoopStress.Result?, status: StressStatus, today: Bool) {
        stressStatus = status
        stressWhoop = w
        guard let w else { stressCurve = nil; stress = nil; stressBaseline = nil; return }
        stressCurve = WhoopStress.daytimeResult(w, tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        if today {
            stress = w.current.map { min(max($0, 0), 3) }
        } else {
            let waking = w.epochs.filter { $0.kind == .waking }.compactMap(\.level)
            stress = waking.isEmpty ? nil : waking.reduce(0, +) / Double(waking.count)
        }
        // After calibration the person's usual waking state sits at neutral, 1.5: that is what the baseline is set from.
        stressBaseline = 1.5
    }

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
        // Calibrated reading first; then the strap's estimate (experiment on), carried a few days like the other vitals.
        spo2 = row?.spo2Pct ?? (today ? Repository.lastSpo2Day(days: repo.days, todayKey: key)?.spo2Pct : nil)
            ?? repo.spo2Estimate(dayKey: key, carry: today)
        sleepMinutes = row?.totalSleepMin
        readiness = ReadinessEngine.evaluate(days: repo.days, today: key)
        // Change against the night BEFORE the one the value came from. A value carried from the last
        // scored night is compared with the night before that, not with itself.
        func change(_ value: Double?, source: DailyMetric?, _ field: (DailyMetric) -> Double?) -> Double? {
            guard let value, let src = source ?? row else { return nil }
            guard let prev = repo.days.last(where: { $0.day < src.day && field($0) != nil }), let p = field(prev) else { return nil }
            return value - p
        }
        let hrvSrc = row?.avgHrv != nil ? row : (today ? Repository.lastHrvDay(days: repo.days, todayKey: key) : nil)
        let rhrSrc = row?.restingHr != nil ? row : (today ? Repository.lastRestingHrDay(days: repo.days, todayKey: key) : nil)
        let respSrc = row?.respRateBpm != nil ? row : (today ? Repository.lastRespDay(days: repo.days, todayKey: key) : nil)
        let spo2Src = row?.spo2Pct != nil ? row : (today ? Repository.lastVitalsDay(days: repo.days, todayKey: key) : nil)
        hrvDelta = change(hrv, source: hrvSrc) { $0.avgHrv }
        restingHrDelta = change(restingHr, source: rhrSrc) { $0.restingHr.map(Double.init) }
        respiratoryDelta = change(respiratory, source: respSrc) { $0.respRateBpm }
        spo2Delta = change(spo2, source: spo2Src) { $0.spo2Pct }

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
        async let stepsA = repo.exploreSeries(key: "steps_est", source: "my-whoop")
        async let appleA = repo.appleDailyRows()
        async let workoutsA = repo.workoutRows()

        let restSeries = await restA
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        rest = TodayView.freshRestScore(todayValue: restByDay[key], lastDay: restSeries.last?.day,
                                        lastValue: restSeries.last?.value, isTodaySelected: today, todayKey: key)


        // Steps and calories: measured on the strap first, then Apple Health, then the on-device estimate.
        let stepsSeries = await stepsA
        let stepsByDay = Dictionary(stepsSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let estSteps = stepsByDay[key] ?? (today ? stepsSeries.last?.value : nil)
        let appleKey = TodayView.appleHealthDayKey(selectedDayKey: key, localDayKey: Repository.localDayKey(Date()), isToday: today)
        let apple = await appleA
        let appleSteps = apple.filter { $0.day == appleKey }.compactMap { $0.steps }.max()
        let appleKcal = apple.filter { $0.day == appleKey }.compactMap { $0.activeKcal }.max()
        // Each source counts only part of the walking (the strap its arm swing, the phone what it carried), so neither is more than the truth: the higher one
        // is the better figure. The on-device estimate is only the last resort.
        let strapSteps = row?.steps.map(Double.init)
        let phoneSteps = appleSteps.map(Double.init)
        stepsFromPhone = (phoneSteps ?? 0) > (strapSteps ?? 0)
        steps = [strapSteps, phoneSteps].compactMap { $0 }.max() ?? estSteps
        // The calories page reads the stored `energy_kcal` series first, so the card does too (the latest day for today, as the steps do).
        let kcalSeries = (await repo.exploreSeries(key: "energy_kcal", source: "my-whoop", days: 30)).filter { $0.value > 0 }
        let kcalByDay = Dictionary(kcalSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        calories = kcalByDay[key] ?? appleKcal ?? row?.activeKcalEst ?? (today ? kcalSeries.last?.value : nil)

        var ex: [String: Double] = [:]
        var prev: [String: Double] = [:]
        for k in ["body_age", "vo2max_est", "skin_temp"] {
            let points = await repo.exploreSeries(key: k, source: "my-whoop", days: 60)
            if let v = points.last?.value { ex[k] = v }
            if points.count >= 2 { prev[k] = points[points.count - 2].value }
        }
        let weights = await repo.exploreSeries(key: "weight", source: "apple-health", days: 90)
        if let w = weights.last?.value { ex["weight"] = w }
        if weights.count >= 2 { prev["weight"] = weights[weights.count - 2].value }
        extras = ex

        // The day before the one shown, for the figures that are a day's total.
        let prevKey = Repository.localDayKey(cal.date(byAdding: .day, value: -1, to: selectedLogicalDay) ?? selectedLogicalDay)
        let prevDay = repo.days.first(where: { $0.day == prevKey })
        if let s = [prevDay?.steps.map(Double.init), apple.filter({ $0.day == prevKey }).compactMap({ $0.steps }).max().map(Double.init)].compactMap({ $0 }).max() ?? stepsByDay[prevKey] {
            prev["steps"] = s
        }
        if let c = kcalByDay[prevKey] ?? apple.filter({ $0.day == prevKey }).compactMap({ $0.activeKcal }).max() ?? prevDay?.activeKcalEst { prev["calories"] = c }
        if let m = repo.days.last(where: { $0.day < key && $0.totalSleepMin != nil })?.totalSleepMin { prev["sleep"] = m }
        previous = prev
        // The curve is scored as of "now" for today and as of the end of the day for a past day.
        let curveNow = today ? Date() : (cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart) ?? dayStart)
        let stressState = await StressEngine.shared.status(repo: repo)
        let whoop = stressState.isReady ? await StressDayCurve.whoopToday(repo: repo, now: curveNow) : nil
        applyStress(whoop, status: stressState, today: today)

        workouts = (await workoutsA).filter { $0.startTs >= from && $0.startTs < to }
        loaded = true
        if today {
            // After the screen is up: it reads four earlier days of heart rate, once a day.
            stressTypicalMin = StressTypical.cached()
            Task { [weak self] in
                let typical = await StressTypical.load(repo: repo)
                self?.stressTypicalMin = typical
            }
        } else {
            stressTypicalMin = nil
        }
    }
}
#endif
