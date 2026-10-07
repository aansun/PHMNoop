#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Anya's card on Today, reacting to the day as it goes: the plan in the morning, the session while it runs, what it earned once it is
/// done against today's Effort target, a rest note when the target is met, and a prompt for the journal in the evening. Everything is
/// worked out from data the app already has; nothing here calls a model.
///
/// The Effort target is the band the Coupled screen uses: today's Charge sets how much Effort is worth aiming for (green 14 to 18,
/// yellow 10 to 14, red 4 to 10 on the 0 to 21 axis), shown on the Effort scale chosen in Settings.
struct NunaAnyaTodayCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    let plan: NunaDayPlanResult?
    let fallbackLine: String
    let workouts: [WorkoutRow]
    /// Stored 0 to 100 Effort so far today.
    let effort: Double?
    let charge: Double?
    let onCoach: () -> Void
    /// Opens the breathing exercise.
    let onBreathe: () -> Void
    /// Opens the wind-down screen.
    let onWindDown: () -> Void
    /// What the evening read looks at.
    var stressNow: Double?
    var stressHighMin: Int?
    var restingHr: Double?
    var hrvDelta: Double?
    var restingHrDelta: Double?
    var sleepMinutes: Double?
    @AppStorage(NunaGoals.sleepMinutes) private var sleepGoal = 0

    @State private var journalDone = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Today's Effort target on the stored axis, from Charge. Nil while Charge is unknown: no band is guessed.
    private var target: (low: Double, high: Double)? {
        guard let band = CoupledView.optimalStrainRange(recovery: charge) else { return nil }
        return (Double(band.lowerBound) / UnitFormatter.effortScaleFactor, Double(band.upperBound) / UnitFormatter.effortScaleFactor)
    }
    private func shown(_ stored: Double) -> String { UnitFormatter.effortDisplay(stored, scale: scale) }
    private func targetText(_ t: (low: Double, high: Double)) -> String {
        // Whole numbers: a band is a rough aim, and "66.7 to 85.7" reads like a precision it does not have.
        let lo = Int(UnitFormatter.effortValue(t.low, scale: scale).rounded()), hi = Int(UnitFormatter.effortValue(t.high, scale: scale).rounded())
        return "\(lo)–\(hi)"
    }
    private var progress: Double? {
        guard let t = target, let effort else { return nil }
        return effort / t.high
    }
    private var targetMet: Bool {
        guard let t = target, let effort else { return false }
        return effort >= t.low
    }

    /// How long the card keeps talking about a session that just ended, before it goes back to the plan.
    private static let afterWorkoutWindow: TimeInterval = 60 * 60

    var body: some View {
        // Re-evaluated every minute, so the card lets go of a session on its own once the hour is up.
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            NunaWithApp { app in
                content(running: app.activeWorkout, bpm: app.live.connected ? app.bpm : nil, now: tick.date)
            }
        }
        .task(id: repo.refreshSeq) {
            let key = Repository.localDayKey(Date())
            journalDone = await repo.nativeJournalDays(from: key, to: key).contains(key)
        }
    }

    // MARK: States

    /// The session that ended within the last hour, if any.
    private func justFinished(_ now: Date) -> WorkoutRow? {
        workouts.last { now.timeIntervalSince1970 - Double($0.endTs) <= Self.afterWorkoutWindow && now.timeIntervalSince1970 >= Double($0.endTs) }
    }

    /// One card, never two. It carries only the headline; the rest of the line and what to do about it are in the Anya sheet.
    @ViewBuilder private func content(running: AppModel.ActiveWorkout?, bpm: Int?, now: Date) -> some View {
        let hourNow = Calendar.current.component(.hour, from: now)
        if let running {
            // 1. A session is running.
            RunningSessionCard(running: running, effort: shown(running.liveStrain), onResume: { router.requestedDestination = .activeWorkout }, onCoach: onCoach)
        } else if justFinished(now) != nil {
            // 2. A session has just ended: its own screen already carries Anya's read of it, so Today says nothing for the hour.
            EmptyView()
        } else if hourNow >= 19 {
            // 3. Evening: whether to breathe, sleep early or go straight to bed, with the journal as a second thing to do while it is open.
            eveningCard(now: now, bpm: bpm, hour: hourNow)
        } else if targetMet, let v = reached(now: now, bpm: bpm, hour: hourNow, last: workouts.last) {
            verdictCard(v, progress: progress)
        } else if !workouts.isEmpty, let next = nextSession(after: workouts.last, hour: hourNow) {
            // 4. Earlier today, and the target is still open: the rest of it, as one more session.
            suggestionCard(next)
        } else {
            // 5. Nothing done yet: the plan.
            NunaAnyaCard(verbatim: plan?.title ?? fallbackLine, detail: planDetail, progress: nil,
                         buttonTitle: "Start",
                         onButton: {
                             if let r = plan { router.plannedSession = .init(title: r.title, minutes: r.plan.totalMinutes, zone: r.plan.mainZone) }
                             router.requestedDestination = .activeWorkout
                         }, action: onCoach)
        }
    }

    private func eveningCard(now: Date, bpm: Int?, hour: Int) -> some View {
        let v = evening(now: now, bpm: bpm, hour: hour, last: workouts.last)
        let title = v?.title ?? String(localized: "Wind down for tonight")
        var detail = v?.detail ?? String(localized: "An earlier night is the best thing for tomorrow's Charge.")
        var more: [NunaAnyaCardAction] = []
        if hour >= 20 && !journalDone {
            let prompt = String(localized: "How was today? Fill in your journal and mood")
            detail += "\n\n" + [prompt, eveningDetail].compactMap { $0 }.joined(separator: " · ")
            more = [NunaAnyaCardAction(title: "Journal", perform: { router.requestedDestination = .journal })]
        }
        switch v?.action {
        case .breathe?:
            return NunaAnyaCard(verbatim: title, detail: detail, buttonTitle: "Breathe", onButton: onBreathe, moreActions: more, action: onCoach)
        case .windDown?:
            return NunaAnyaCard(verbatim: title, detail: detail, buttonTitle: "Wind down", onButton: onWindDown, moreActions: more, action: onCoach)
        default:
            return NunaAnyaCard(verbatim: title, detail: detail, buttonTitle: more.isEmpty ? nil : "Journal",
                                onButton: more.isEmpty ? nil : { router.requestedDestination = .journal }, action: onCoach)
        }
    }

    // MARK: How the day should end

    private func inputs(now: Date, bpm: Int?, hour: Int, last: WorkoutRow?) -> NunaAnyaDayInputs {
        let t = target
        return NunaAnyaDayInputs(
            hour: hour,
            minutesSinceWorkout: last.map { max(0, Int(now.timeIntervalSince1970 - Double($0.endTs)) / 60) },
            bpm: bpm, restingHr: restingHr, stressNow: stressNow, stressHighMin: stressHighMin,
            sleepMin: sleepMinutes, sleepNeedMin: sleepGoal > 0 ? Double(sleepGoal) : 480,
            effort: effort, targetLow: t?.low, targetHigh: t?.high, hrvDelta: hrvDelta, restingHrDelta: restingHrDelta)
    }

    private func evening(now: Date, bpm: Int?, hour: Int, last: WorkoutRow?) -> NunaAnyaDayVerdict? {
        NunaAnyaDayRead.evening(inputs(now: now, bpm: bpm, hour: hour, last: last), effortShown: shown)
    }

    private func reached(now: Date, bpm: Int?, hour: Int, last: WorkoutRow?) -> NunaAnyaDayVerdict? {
        guard let t = target else { return nil }
        return NunaAnyaDayRead.targetReached(inputs(now: now, bpm: bpm, hour: hour, last: last), effortShown: shown, band: targetText(t))
    }

    @ViewBuilder private func verdictCard(_ v: NunaAnyaDayVerdict, progress: Double? = nil) -> some View {
        switch v.action {
        case .breathe:
            NunaAnyaCard(verbatim: v.title, detail: v.detail, progress: progress, buttonTitle: "Breathe", onButton: onBreathe, action: onCoach)
        case .windDown:
            NunaAnyaCard(verbatim: v.title, detail: v.detail, progress: progress, buttonTitle: "Wind down", onButton: onWindDown, action: onCoach)
        case .none:
            NunaAnyaCard(verbatim: v.title, detail: v.detail, progress: progress, action: onCoach)
        }
    }

    // MARK: What to do with the rest of the target

    private struct NextSession { let zone: Int; let minutes: Int; let effortLow: Double?; let effortHigh: Double?; let left: Double; let feeling: NunaWorkoutFeeling? }

    /// A session sized to the Effort still missing from today's target, from the wearer's own Effort per minute (as the plan does): zone 2 or 3,
    /// 15 to 60 minutes. A session called hard keeps it to zone 2 and short; one called very hard leaves nothing to suggest, only rest.
    /// Nil when the target is met, unknown, or the day is too far gone for another session.
    private func nextSession(after last: WorkoutRow?, hour: Int) -> NextSession? {
        guard let t = target, let effort, effort < t.low, hour < 20 else { return nil }
        let feeling = last.flatMap { NunaWorkoutReviewStore.load(startTs: $0.startTs, sport: $0.sport).feelingValue }
        if feeling == .veryHard { return nil }
        let left = t.low - effort
        let perMinute = plan?.effortPerMinute
        func minutes(_ zone: Int) -> Int? {
            guard let perMinute else { return nil }
            let factor: Double = zone == 2 ? 0.7 : 1.0
            let m = left / (perMinute * factor)
            return Int((m / 5).rounded()) * 5
        }
        var zone = 2
        if feeling != .hard, (charge ?? 0) >= 50, let m2 = minutes(2), m2 > 45, let m3 = minutes(3), m3 >= 15 { zone = 3 }
        var mins = minutes(zone) ?? 30
        mins = min(max(mins, 15), feeling == .hard ? 30 : 60)
        var lo: Double?, hi: Double?
        if let perMinute {
            let mid = perMinute * (zone == 2 ? 0.7 : 1.0) * Double(mins)
            lo = mid * 0.8; hi = mid * 1.2
        }
        return NextSession(zone: zone, minutes: mins, effortLow: lo, effortHigh: hi, left: left, feeling: feeling)
    }

    private func suggestionCard(_ n: NextSession) -> some View {
        var detail = [String(format: String(localized: "%@ Effort left for today's target"), shown(n.left))]
        if let lo = n.effortLow, let hi = n.effortHigh {
            detail.append(String(format: String(localized: "about +%@–%@"), shown(lo), shown(hi)))
            if hi < n.left * 0.8 { detail.append(String(localized: "not all of it in one go")) }
        }
        if let f = n.feeling, f == .hard { detail.append(String(localized: "You called the last one challenging, so this stays easy")) }
        let title = String(format: String(localized: "Another %d min in zone %d"), n.minutes, n.zone)
        return NunaAnyaCard(verbatim: title, detail: detail.joined(separator: " · "), progress: nil,
                            buttonTitle: "Start",
                            onButton: {
                                router.plannedSession = .init(title: title, minutes: n.minutes, zone: n.zone)
                                router.requestedDestination = .activeWorkout
                            }, action: onCoach)
    }

    private var planDetail: String? {
        guard let t = target else { return nil }
        return String(format: String(localized: "Today's Effort target %@"), targetText(t))
    }

    private var eveningDetail: String? {
        guard let effort else { return nil }
        if let t = target { return String(format: String(localized: "Effort %@ of %@ today"), shown(effort), targetText(t)) }
        return String(format: String(localized: "Effort %@ today"), shown(effort))
    }
}

/// The card while a session is on. Its minutes tick on their own; the heart rate follows the strap.
private struct RunningSessionCard: View {
    let running: AppModel.ActiveWorkout
    let effort: String
    let onResume: () -> Void
    let onCoach: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { tick in
            let secs = max(0, Int(running.elapsed(at: tick.date)))
            let time = secs >= 3600 ? String(format: "%d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60) : String(format: "%d:%02d", secs / 60, secs % 60)
            var parts = [time]
            if let bpm = model.bpm { parts.append(String(format: String(localized: "%d bpm"), bpm)) }
            parts.append(String(format: String(localized: "Effort +%@"), effort))
            return NunaAnyaCard(verbatim: String(localized: "Session in progress"),
                                detail: String(localized: String.LocalizationValue(running.sport)) + " · " + parts.joined(separator: " · "),
                                progress: nil, buttonTitle: "Resume", onButton: onResume, action: onCoach)
        }
    }
}
#endif
