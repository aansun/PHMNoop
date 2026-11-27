#if os(iOS)
import Foundation
import SwiftUI
import UserNotifications
import StrandDesign
import StrandAnalytics

/// The evening check-in: one local notification a day at the chosen time, off until the person turns it on. It carries no figures and
/// contacts no one; Anya writes only when it is tapped (`AnyaCheckIn`).
@MainActor
enum NunaAnyaEvening {
    static let enabledKey = "anya.evening.enabled"
    static let timeKey = "anya.evening.minutes"
    static let defaultMinutes = 20 * 60 + 30

    static var isEnabled: Bool { CoachBriefScheduler.coachMasterEnabled && UserDefaults.standard.bool(forKey: enabledKey) }
    static var minutes: Int { UserDefaults.standard.object(forKey: timeKey) as? Int ?? defaultMinutes }

    /// Turns it on or off. Turning it on asks for notifications the first time; false means iOS will not show them, and it stays off.
    static func set(_ on: Bool) async -> Bool {
        let centre = UNUserNotificationCenter.current()
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            refresh()
            return true
        }
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        refresh()
        return granted
    }

    static func setMinutes(_ minutes: Int) {
        UserDefaults.standard.set(min(max(minutes, 0), 24 * 60 - 1), forKey: timeKey)
        refresh()
    }

    /// Brings the scheduled notification in line with the settings.
    static func refresh() {
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [AnyaCheckIn.eveningRequestId])
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Anya"
        content.body = String(localized: "How was your day? Tap to talk it over.")
        content.sound = .default
        content.categoryIdentifier = NotificationPresenter.anyaEveningCategoryId
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
        centre.add(UNNotificationRequest(identifier: AnyaCheckIn.eveningRequestId, content: content, trigger: trigger))
    }
}

/// The settings rows for the evening check-in.
struct NunaAnyaEveningCard: View {
    @State private var enabled = NunaAnyaEvening.isEnabled
    @State private var minutes = NunaAnyaEvening.minutes
    @State private var refused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NunaSettingsSwitch("Evening check-in", subtitle: "A reminder to talk your day over with Anya", systemImage: "moon.stars", isOn: Binding(get: { enabled }, set: { on in
                enabled = on
                Task { let ok = await NunaAnyaEvening.set(on); refused = !ok; if !ok { enabled = false } }
            }))
            if enabled {
                NunaSettingsCard {
                    HStack {
                        Text("Time").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                    }.padding(.vertical, 12)
                }
            }
            if refused {
                Text("Notifications are off for PHMN. Turn them on in iOS Settings first.").font(.nuna(size: 12.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date() }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (c.hour ?? 20) * 60 + (c.minute ?? 30)
            NunaAnyaEvening.setMinutes(minutes)
        })
    }
}

/// "About you": what Anya keeps in mind, in the person's hands. Each line can be written, changed or emptied here, and Anya adds to it from
/// a conversation, saying so when she does.
struct NunaAnyaAboutYouView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var about = AnyaAboutYou.load()

    static var interviewPrompt: String {
        String(localized: "Get to know me. Ask about my goals, my usual week, the equipment I have, any injuries or limits, and how I like to be coached, one question at a time, and save what I tell you.")
    }

    var body: some View {
        NunaDetailScreen("About you") {
            Text("What Anya keeps in mind when she coaches you. It stays on this iPhone and goes with your questions to the AI provider.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            ForEach(AnyaAboutYou.Field.allCases) { field in
                NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(field.title)).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        TextField("", text: Binding(get: { about[field] }, set: { about[field] = $0; about.save() }),
                                  prompt: Text(Self.hint(field)).foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                            .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1...5).textCase(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button {
                coach.pendingPrompt = Self.interviewPrompt
                router.openCoach()
            } label: {
                Text("Let Anya ask me").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain).disabled(!coach.isConfigured || !coach.dataConsent).opacity(coach.isConfigured && coach.dataConsent ? 1 : 0.4)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { about = AnyaAboutYou.load() }
    }

    private static func hint(_ field: AnyaAboutYou.Field) -> LocalizedStringKey {
        switch field {
        case .goals: return "Run 10 km under an hour by June"
        case .schedule: return "Train Monday, Wednesday, Saturday after work"
        case .equipment: return "Dumbbells at home, a treadmill at the gym"
        case .limits: return "Left knee sore on stairs"
        case .style: return "Be direct, keep it short"
        }
    }
}
#endif
