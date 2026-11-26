import Foundation
import StrandAnalytics
#if os(iOS)
import UserNotifications
#endif

/// The early wake's settings and marks. The strap stays armed at the wake time throughout: the early wake only adds a buzz before it.
enum EarlyWake {
    /// Off until the person turns it on: it is an experiment.
    static let enabledKey = "alarm.earlyWake.enabled"
    /// The wake time (epoch seconds) already turned off after an early ring, so it is not armed or announced again.
    static let doneKey = "alarm.earlyWake.doneFor"
    /// The wake time already rung early, so it rings early once.
    static let rangKey = "alarm.earlyWake.rangFor"
    /// When the early ring began; while it lasts, a double tap turns the alarm off.
    static let ringingKey = "alarm.earlyWake.ringingSince"
    /// The planner's sleep need in minutes (the iPhone's sleep goal); 8 hours when it was never set.
    static let sleepNeedKey = "nuna.goal.sleepMinutes"
    /// How long the early ring goes on, and how often it buzzes.
    static let ringSeconds: TimeInterval = 120
    static let buzzEverySeconds: TimeInterval = 12
    /// The strap streams from this long before the wake time.
    static let streamLeadSeconds: TimeInterval = 10 * 3600

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// What the early wake holds while the app runs.
@MainActor
final class EarlyWakeState {
    var lastCheck = Date.distantPast
    var lastSyncAsk = Date.distantPast
    var checking = false
    var ringing: Task<Void, Never>?
}

extension AppModel {
    /// The wake time that comes next, as armed on the strap and shown on the screens. One already turned off after an early ring is passed over.
    func nextAlarmDate(from now: Date = Date()) -> Date? {
        let done = UserDefaults.standard.double(forKey: EarlyWake.doneKey)
        let from = done > now.timeIntervalSince1970 ? Date(timeIntervalSince1970: done) : now
        return Self.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes, weekdays: behavior.smartAlarmWeekdays,
                                       overrides: WindDownNudge.perDayWakeOverrides, from: from)
    }

    // MARK: My Schedule

    /// While My Schedule drives the alarm, the alarm's settings show the one that comes next: its time, mode and goal.
    func mirrorScheduledAlarm(from now: Date = Date()) {
        let schedule = AlarmSchedule.load()
        guard schedule.drives else { return }
        let done = UserDefaults.standard.double(forKey: EarlyWake.doneKey)
        let from = done > now.timeIntervalSince1970 ? Date(timeIntervalSince1970: done) : now
        guard let next = Self.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes, weekdays: Set(schedule.days.keys),
                                                 overrides: schedule.days.mapValues(\.minutes), from: from),
              let plan = schedule.days[Calendar.current.component(.weekday, from: next)] else { return }
        if behavior.smartAlarmMinutes != plan.minutes { behavior.smartAlarmMinutes = plan.minutes }
        if behavior.smartAlarmMode != plan.mode { behavior.smartAlarmMode = plan.mode }
        if behavior.smartAlarmGoal != plan.goal { behavior.smartAlarmGoal = plan.goal }
    }

    /// Saves My Schedule and writes it into the alarm; turning it off puts back the alarm there was before.
    func setAlarmSchedule(_ new: AlarmSchedule) {
        var schedule = new
        let old = AlarmSchedule.load()
        if schedule.drives {
            schedule.before = old.drives ? old.before : AlarmSchedule.Before(
                minutes: behavior.smartAlarmMinutes, mode: behavior.smartAlarmMode, goal: behavior.smartAlarmGoal,
                weekdays: behavior.smartAlarmWeekdays.sorted(), overrides: WindDownNudge.perDayWakeOverrides)
            schedule.save()
            for day in 1...7 { WindDownNudge.setWakeOverride(weekday: day, minutes: schedule.days[day]?.minutes) }
            behavior.smartAlarmWeekdays = schedule.days.count == 7 ? [] : Set(schedule.days.keys)
        } else {
            let before = old.drives ? old.before : nil
            schedule.before = nil
            schedule.save()
            if let before {
                for day in 1...7 { WindDownNudge.setWakeOverride(weekday: day, minutes: before.overrides[day]) }
                behavior.smartAlarmWeekdays = Set(before.weekdays)
                behavior.smartAlarmMinutes = before.minutes
                behavior.smartAlarmMode = before.mode
                behavior.smartAlarmGoal = before.goal
            }
        }
        applySmartAlarm()
    }

    // MARK: Early wake

    /// Whether the strap can be asked to buzz for an alarm at all.
    private var strapTakesAlarm: Bool { behavior.smartAlarmEnabled && Self.wristAlertsOn && !(whoop5Detected && !PuffinExperiment.isEnabled) }

    /// Holds the strap's stream open for the night before an alarm that may ring early, and lets it go otherwise.
    func updateAlarmStreamWindow(latest: Date?) {
        guard let latest, EarlyWake.isEnabled, strapTakesAlarm, behavior.smartAlarmMode != SmartWake.Mode.exact.rawValue else {
            ble.setAlarmStreamWindow(nil)
            return
        }
        ble.setAlarmStreamWindow(latest.addingTimeInterval(-EarlyWake.streamLeadSeconds)...latest)
    }

    /// One look at the night, from the strap's keep-alive tick and after a sync. Outside the hour before the wake time it does nothing.
    func earlyWakeTick(afterSync: Bool = false, now: Date = Date()) {
        guard EarlyWake.isEnabled else { return }
        // The night may have passed without a re-arm, so the settings are brought to today's alarm first.
        mirrorScheduledAlarm(from: now)
        guard strapTakesAlarm,
              let mode = SmartWake.Mode(rawValue: behavior.smartAlarmMode), mode != .exact,
              let latest = nextAlarmDate(from: now), SmartWake.inWindow(now: now, latest: latest),
              UserDefaults.standard.double(forKey: EarlyWake.rangKey) != latest.timeIntervalSince1970,
              !earlyWake.checking, afterSync || now.timeIntervalSince(earlyWake.lastCheck) >= 240 else { return }
        earlyWake.lastCheck = now
        earlyWake.checking = true
        // The strap hands its records over every quarter hour on its own; in the window they are asked for about every ten minutes.
        if !afterSync, now.timeIntervalSince(earlyWake.lastSyncAsk) >= 600 {
            earlyWake.lastSyncAsk = now
            ble.requestSync(.manual)
        }
        let stored = UserDefaults.standard.integer(forKey: EarlyWake.sleepNeedKey)
        let need = Double(stored > 0 ? stored : 8 * 60)
        let goal = behavior.smartAlarmGoal
        let strap = deviceRegistry?.activeDeviceId ?? "my-whoop"
        Task { [weak self] in
            guard let self else { return }
            defer { self.earlyWake.checking = false }
            let night = await self.intelligence.nightSoFar(strapId: strap)
            let checked = Date()
            let decision = SmartWake.decide(now: checked, latest: latest, mode: mode, needMin: need, goalPercent: goal, night: night)
            let age = night.map { Int(checked.timeIntervalSince($0.dataEnd) / 60) }
            self.live.append(log: "Early wake: \(mode.rawValue) → \(decision) (asleep \(night.map { Int($0.asleepMin) } ?? -1) min of \(Int(need)) at \(goal)%, "
                + "recovery \(night?.recovery.map { Int($0.rounded()) } ?? -1), data \(age ?? -1) min old)")
            // The alarm may have been changed or turned off while the night was being read.
            guard decision == .wake, EarlyWake.isEnabled, self.strapTakesAlarm, self.nextAlarmDate() == latest else { return }
            self.ringEarly(for: latest)
        }
    }

    /// Buzzes the strap for up to two minutes. A double tap turns the alarm off; otherwise the strap is armed at the wake time again, so it still rings then.
    private func ringEarly(for latest: Date) {
        let defaults = UserDefaults.standard
        defaults.set(latest.timeIntervalSince1970, forKey: EarlyWake.rangKey)
        defaults.set(Date().timeIntervalSince1970, forKey: EarlyWake.ringingKey)
        live.append(log: "Early wake: ringing before the armed wake time")
        AppModel.postSmartAlarm()
        earlyWake.ringing?.cancel()
        earlyWake.ringing = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < EarlyWake.ringSeconds {
                self?.ble.buzzStrapOnce()
                try? await Task.sleep(nanoseconds: UInt64(EarlyWake.buzzEverySeconds * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            UserDefaults.standard.removeObject(forKey: EarlyWake.ringingKey)
            // Not turned off: make sure the wake time is still on the strap.
            if self.strapTakesAlarm, latest > Date() { self.ble.armStrapAlarm(at: latest) }
        }
    }

    /// A double tap during the early ring: the buzzing stops, this wake time is done with and the next one is armed. Returns whether the tap was used.
    func dismissEarlyRing(at now: Date) -> Bool {
        let defaults = UserDefaults.standard
        let since = defaults.double(forKey: EarlyWake.ringingKey)
        guard since > 0, now.timeIntervalSince1970 - since <= EarlyWake.ringSeconds + EarlyWake.buzzEverySeconds else { return false }
        earlyWake.ringing?.cancel()
        earlyWake.ringing = nil
        defaults.removeObject(forKey: EarlyWake.ringingKey)
        defaults.set(defaults.double(forKey: EarlyWake.rangKey), forKey: EarlyWake.doneKey)
        live.append(log: "Double-tap → early alarm turned off")
        stopHaptics()
        #if os(iOS)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["smart-alarm-wake"])
        #endif
        applySmartAlarm()
        return true
    }
}
