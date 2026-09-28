#if os(iOS)
import Foundation
import UserNotifications
import WhoopStore

/// Posts an optional, on-device summary after a live workout is saved on iOS.
///
/// This is the iOS counterpart of Android's post-workout report. It is deliberately opt-in and
/// default-off: enabling it never backfills old workouts, and every notification is built locally from
/// the saved WorkoutRow. No account, server, or external analytics service is involved.
enum WorkoutReportNotifier {
    static let enabledKey = "behavior.postWorkoutSummary"

    /// Ask at the moment the user enables the feature, matching the other notification automations.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post one summary for a newly saved live workout. The request identifier is stable for the
    /// workout start, so a repeated save callback cannot create duplicate banners.
    static func post(row: WorkoutRow) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let copy = copy(for: row)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "workout-summary-\(row.startTs)",
                content: content,
                trigger: nil)
            center.add(request)
        }
    }

    /// Pure copy builder kept separate from UserNotifications so formatting stays deterministic and
    /// easy to validate without a device or notification permission.
    static func copy(for row: WorkoutRow) -> (title: String, body: String) {
        let sport = WorkoutSource.displaySport(row.sport)
        var details: [String] = []

        if let effort = row.strain {
            let scale = UnitPrefs.resolveEffortScale(
                UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
            details.append(String(localized: "Effort \(UnitFormatter.effortDisplay(effort, scale: scale))/\(UnitFormatter.effortScaleMax(scale))"))
        }
        if let duration = row.durationS, duration > 0 {
            details.append(durationLabel(duration))
        }
        if let avgHr = row.avgHr {
            details.append(String(localized: "Avg HR \(avgHr) bpm"))
        }

        let body = details.isEmpty
            ? String(localized: "Your \(sport.lowercased()) workout was saved on this iPhone.")
            : details.joined(separator: " · ")
        return (String(localized: "Workout logged: \(sport)"), body)
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(localized: "\(hours)h \(minutes)m") }
        return String(localized: "\(minutes)m")
    }
}
#endif
