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
    private var hour: Int { Calendar.current.component(.hour, from: Date()) }

    var body: some View {
        NunaWithApp { app in
            content(running: app.activeWorkout)
        }
        .task(id: repo.refreshSeq) {
            let key = Repository.localDayKey(Date())
            journalDone = await repo.nativeJournalDays(from: key, to: key).contains(key)
        }
    }

    // MARK: States

    @ViewBuilder private func content(running: AppModel.ActiveWorkout?) -> some View {
        if let running {
            // 1. A session is running: how long, the heart rate now, and a way straight back into it.
            RunningSessionCard(running: running, effort: shown(running.liveStrain), onResume: { router.requestedDestination = .activeWorkout }, onCoach: onCoach)
        } else if hour >= 20 && !journalDone {
            // 5. Evening: close the day in the journal.
            NunaAnyaCard(verbatim: String(localized: "How was today? Fill in your journal and mood"),
                         detail: eveningDetail, progress: nil,
                         buttonTitle: "Journal", onButton: { router.requestedDestination = .journal }, action: onCoach)
        } else if let last = workouts.last {
            // 3. A session is done: what it earned, against the target. 4. With the target met, rest comes next.
            doneCard(last)
        } else if hour >= 20 {
            NunaAnyaCard(verbatim: String(localized: "Wind down for tonight"),
                         detail: String(localized: "An earlier night is the best thing for tomorrow's Charge."), progress: nil, action: onCoach)
        } else if targetMet, let t = target {
            NunaAnyaCard(verbatim: String(localized: "Today's Effort target is reached"),
                         detail: String(format: String(localized: "Effort %@ of %@. Keep the rest of the day easy and eat and drink well."), shown(effort ?? 0), targetText(t)),
                         progress: progress, action: onCoach)
        } else {
            // 2. Nothing done yet: the plan.
            NunaAnyaCard(verbatim: plan?.title ?? fallbackLine, detail: planDetail, progress: nil,
                         buttonTitle: "Start",
                         onButton: {
                             if let r = plan { router.plannedSession = .init(title: r.title, minutes: r.plan.totalMinutes, zone: r.plan.mainZone) }
                             router.requestedDestination = .activeWorkout
                         }, action: onCoach)
        }
    }

    @ViewBuilder private func doneCard(_ w: WorkoutRow) -> some View {
        let minutes = Int(((w.durationS ?? Double(w.endTs - w.startTs)) / 60).rounded())
        let title = String(format: String(localized: "%@ · %d min done"), w.sport, minutes)
        let earned = w.strain.map { String(format: String(localized: "Effort +%@"), shown($0)) }
        if let t = target, let effort {
            if targetMet {
                // The plan is fulfilled: no Start button, only recovery.
                NunaAnyaCard(verbatim: title,
                             detail: [earned, String(format: String(localized: "Target %@ reached"), targetText(t)),
                                      String(localized: "Rest, water and an early night now.")].compactMap { $0 }.joined(separator: " · "),
                             progress: min(effort / t.high, 1), progressColor: NunaPalette.charge, action: onCoach)
            } else {
                NunaAnyaCard(verbatim: title,
                             detail: [earned, String(format: String(localized: "%@ of %@ target"), shown(effort), targetText(t))].compactMap { $0 }.joined(separator: " · "),
                             progress: effort / t.high, buttonTitle: "View", onButton: { router.requestedDestination = .workouts }, action: onCoach)
            }
        } else {
            NunaAnyaCard(verbatim: title, detail: earned, progress: nil,
                         buttonTitle: "View", onButton: { router.requestedDestination = .workouts }, action: onCoach)
        }
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
