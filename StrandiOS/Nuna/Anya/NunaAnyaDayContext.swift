#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// Gathers the numbers for `AnyaDayContext` on this iPhone. The session is the one `NunaDayPlanResult` returns, so Anya and the
/// Plan card read the same plan from one function and cannot disagree about it.
enum NunaAnyaDayContext {

    @MainActor static func build(repo: Repository, profile: ProfileStore, now: Date = Date()) async -> String {
        let days = repo.days
        let plan = await NunaDayPlanResult.load(repo: repo, profile: profile)
        let scored = days.compactMap(\.strain).filter { $0 > 0 }.suffix(30).sorted()
        let usual = scored.isEmpty ? nil : scored[scored.count / 2]
        let todayKey = repo.today?.day ?? Repository.localDayKey(now)
        let today = days.last(where: { $0.day == todayKey })?.strain
        let week = days.suffix(7).compactMap(\.strain).reduce(0, +)
        let goal = UserDefaults.standard.double(forKey: "nuna.goal.weeklyEffort")

        // Need and debt use the Sleep tab's own functions, main sleep only (naps are not credited here).
        let need = SleepModel.debtNeedMin(days: days)
        let ledger = SleepDebt.ledger(series: days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: need / 60)
        let midsleep = await repo.habitualMidsleepSec()

        // The wearer's own rating of the last sessions, from the same store the review screen writes.
        let rows = await repo.workoutRows(days: 14)
        let feelings = rows.prefix(6).compactMap { r -> String? in
            guard let f = NunaWorkoutReviewStore.load(startTs: r.startTs, sport: r.sport).feelingValue else { return nil }
            return "\(r.sport), \(f.plain)"
        }

        // The band the Today card judges the day by: Charge sets how much Effort is worth aiming for.
        let band = CoupledView.optimalStrainRange(recovery: plan.map { Double($0.charge) })
        let input = AnyaDayContext.Input(
            now: now,
            chargePct: plan.map { Double($0.charge) },
            sessionTitle: plan?.title,
            sessionKind: plan?.plan.kind.rawValue,
            sessionMainZone: plan?.plan.mainZone,
            sessionEffortLow: plan?.plan.effortLow,
            sessionEffortHigh: plan?.plan.effortHigh,
            todayEffort: today,
            effortTargetLow: band.map { Double($0.lowerBound) / UnitFormatter.effortScaleFactor },
            effortTargetHigh: band.map { Double($0.upperBound) / UnitFormatter.effortScaleFactor },
            usualEffort: usual,
            weekEffort: week > 0 ? week : nil,
            weeklyEffortGoal: goal > 0 ? goal : nil,
            sleepNeedMin: ledger.nightCount > 0 ? need : nil,
            sleepDebtMin: ledger.nightCount > 0 ? ledger.magnitudeMin : nil,
            habitualMidsleepSec: midsleep,
            sessionFeelings: feelings)
        return AnyaDayContext.block(input)
    }
}
#endif
