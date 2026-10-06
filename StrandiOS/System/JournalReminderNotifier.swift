#if os(iOS)
import Foundation
import UserNotifications

/// The evening nudge to write the journal. A card in Today was the only reminder before; this adds the notification itself.
///
/// Notifications cannot look at the journal when they fire, so the next seven evenings are scheduled one by one and refreshed whenever the
/// app opens, the switch or the time changes, or an entry is saved: an evening whose entry is already written is simply left out.
enum JournalReminderNotifier {
    static let minuteKey = "journal.reminder.minuteOfDay"
    static let defaultMinute = 21 * 60
    private static let prefix = "journal.reminder."
    private static let days = 7

    static var minuteOfDay: Int {
        let v = UserDefaults.standard.object(forKey: minuteKey) as? Int ?? defaultMinute
        return min(max(v, 0), 1439)
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PuffinExperiment.journalReminderKey) as? Bool ?? true
    }

    /// Re-plans the coming evenings. `loggedToday` is whether today's entry exists; pass nil to look it up.
    @MainActor
    static func refresh(repo: Repository) async {
        let today = Date()
        let key = Repository.localDayKey(today)
        let logged = await repo.nativeJournalDays(from: key, to: key).contains(key)
        await schedule(loggedToday: logged)
    }

    static func schedule(loggedToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard isEnabled else { return }

        // Ask once, and only when the reminder is on: a prompt with no context would be refused.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard [.authorized, .provisional, .ephemeral].contains(await center.notificationSettings().authorizationStatus) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Journal")
        content.body = String(localized: "A minute to write today's journal?")
        content.sound = .default

        let cal = Calendar.current
        let minute = minuteOfDay
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = minute / 60
            comps.minute = minute % 60
            guard let fire = cal.date(from: comps), fire > Date() else { continue }
            if offset == 0 && loggedToday { continue }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)",
                                                        content: content, trigger: trigger))
        }
    }
}
#endif
