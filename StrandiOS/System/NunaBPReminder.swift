#if os(iOS)
import Foundation
import UserNotifications
import StrandAnalytics

/// The reminder to measure blood pressure, in the morning and in the evening.
///
/// A notification cannot look at the readings when it fires, so the coming ten days are planned one by one and planned again whenever the app opens, a
/// reading is saved, deleted or read from Apple Health, or the times change: a time that a reading already covers (`PressureLinks.reminderCovers`) is
/// left out. Off until the person turns it on.
enum NunaBPReminder {
    static let enabledKey = "bp.reminder.enabled"
    static let morningKey = "bp.reminder.morning"
    static let morningOnKey = "bp.reminder.morningOn"
    static let eveningKey = "bp.reminder.evening"
    static let eveningOnKey = "bp.reminder.eveningOn"
    static let defaultMorning = 7 * 60
    static let defaultEvening = 19 * 60
    /// How far ahead reminders are planned.
    static let days = 10
    private static let prefix = "bp.reminder."

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The times in use, minutes since local midnight.
    static var minutes: [Int] {
        let d = UserDefaults.standard
        func time(_ key: String, _ fallback: Int) -> Int { min(max(d.object(forKey: key) as? Int ?? fallback, 0), 24 * 60 - 1) }
        var out: [Int] = []
        if d.object(forKey: morningOnKey) as? Bool ?? true { out.append(time(morningKey, defaultMorning)) }
        if d.object(forKey: eveningOnKey) as? Bool ?? true { out.append(time(eveningKey, defaultEvening)) }
        return out
    }

    /// Plans the coming reminders from the readings there are now.
    @MainActor
    static func refresh(repo: Repository) async {
        // With the reminder off there is nothing to read the readings for.
        let readings = isEnabled ? await NunaBP.load(repo).map(\.takenAt) : []
        await schedule(readings: readings)
    }

    /// Replaces the planned reminders. Returns false when reminders are wanted but notifications are not allowed.
    @discardableResult
    static func schedule(readings: [Int], now: Date = Date()) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard isEnabled else { return true }

        // Asked only once the person has turned the reminder on.
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard [.authorized, .provisional, .ephemeral].contains(await center.notificationSettings().authorizationStatus) else { return false }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Blood pressure")
        content.body = String(localized: "Time to measure. Sit quietly for five minutes first.")
        content.sound = .default
        content.categoryIdentifier = NotificationPresenter.bloodPressureCategoryId

        let cal = Calendar.current
        for date in PressureLinks.reminderDates(now: now, minutes: minutes, readings: readings, days: days, calendar: cal) {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let id = "\(prefix)\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
            try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        return true
    }
}
#endif
