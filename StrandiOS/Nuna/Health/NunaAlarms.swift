#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

// MARK: - Shared helpers

enum NunaAlarmFormat {
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func weekdayName(_ dow: Int) -> String {
        let names = [String(localized: "Sunday"), String(localized: "Monday"), String(localized: "Tuesday"),
                     String(localized: "Wednesday"), String(localized: "Thursday"), String(localized: "Friday"),
                     String(localized: "Saturday")]
        return (1...7).contains(dow) ? names[dow - 1] : String(localized: "Day \(dow)")
    }

    static func weekdayShort(_ dow: Int) -> String {
        switch dow {
        case 1: return String(localized: "Sun")
        case 2: return String(localized: "Mon")
        case 3: return String(localized: "Tue")
        case 4: return String(localized: "Wed")
        case 5: return String(localized: "Thu")
        case 6: return String(localized: "Fri")
        case 7: return String(localized: "Sat")
        default: return "?"
        }
    }

    static func date(minutes: Int) -> Date {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        return Calendar.current.date(from: c) ?? Date()
    }

    static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 7) * 60 + (c.minute ?? 0)
    }

    static func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// The wind-down reminder's settings, shared by the Health row and the detail screen so both read one state.
@MainActor
final class NunaWindDownState: ObservableObject {
    @Published var isOn = WindDownNudge.isEnabled
    @Published var wakeMinutes = WindDownNudge.wakeMinutes
    @Published var overrides = WindDownNudge.perDayWakeOverrides
    @Published var perDayOn = WindDownNudge.hasPerDayOverrides
    @Published var showDenied = false

    var reminderMinutes: Int { WindDownNudge.nudgeMinuteOfDay() }

    func reload() {
        isOn = WindDownNudge.isEnabled; wakeMinutes = WindDownNudge.wakeMinutes
        overrides = WindDownNudge.perDayWakeOverrides; perDayOn = WindDownNudge.hasPerDayOverrides
    }

    /// Flip the reminder. Reverts and raises the Settings alert when notifications are denied.
    func setOn(_ on: Bool) {
        isOn = on
        WindDownNudge.setEnabled(on) { [weak self] outcome in
            if outcome == .denied { self?.isOn = false; self?.showDenied = true }
        }
    }

    func setWake(_ m: Int) { wakeMinutes = m; WindDownNudge.setWakeMinutes(m) }
}

private extension View {
    func nunaDeniedAlert(_ isPresented: Binding<Bool>) -> some View {
        alert(String(localized: "Notifications are off"), isPresented: isPresented) {
            Button(String(localized: "Open Settings")) { NunaAlarmFormat.openNotificationSettings() }
            Button(String(localized: "Not now"), role: .cancel) {}
        } message: {
            Text("Turn on notifications for NOOP in Settings to get your wind-down reminder.")
        }
    }
}

private func nunaCaption(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

private func nunaNote(_ t: LocalizedStringKey, warn: Bool = false) -> some View {
    Text(t).font(.nuna(size: 13, weight: .semibold))
        .foregroundStyle(warn ? NunaPalette.warning : NunaPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Rows for the Health Sleep tab

/// The two rows under the naps card: strap smart alarm and bedtime reminder, each a link to its detail
/// screen with the switch on the right.
struct NunaSleepAlarmRows: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @StateObject private var wind = NunaWindDownState()

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    NavigationLink(value: NunaTodayRoute.smartAlarm) {
                        NunaListRow("Smart strap alarm", subtitle: alarmSubtitle, systemImage: "alarm.fill")
                    }.buttonStyle(.plain)
                    Toggle("", isOn: $behavior.smartAlarmEnabled).labelsHidden().tint(NunaPalette.charge)
                        .accessibilityLabel(Text("Smart strap alarm"))
                }
                NunaDivider()
                HStack(spacing: 8) {
                    NavigationLink(value: NunaTodayRoute.windDown) {
                        NunaListRow("Bedtime reminder", subtitle: reminderSubtitle, systemImage: "moon.zzz.fill")
                    }.buttonStyle(.plain)
                    Toggle("", isOn: Binding(get: { wind.isOn }, set: { wind.setOn($0) })).labelsHidden().tint(NunaPalette.charge)
                        .accessibilityLabel(Text("Bedtime reminder"))
                }
            }
        }
        .onChange(of: behavior.smartAlarmEnabled) { _, _ in model.applySmartAlarm() }
        .onAppear { wind.reload() }
        .nunaDeniedAlert($wind.showDenied)
    }

    private var alarmSubtitle: LocalizedStringKey {
        behavior.smartAlarmEnabled ? "Wake \(NunaAlarmFormat.clock(behavior.smartAlarmMinutes)) · buzz on your wrist" : "Off · buzz on your wrist"
    }

    private var reminderSubtitle: LocalizedStringKey {
        wind.isOn ? "\(NunaAlarmFormat.clock(wind.reminderMinutes)) · \(WindDownNudge.leadMinutes) min before bed" : "Off · a calm evening nudge"
    }
}

// MARK: - Smart alarm detail

struct NunaSmartAlarmView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage("alarm.rejectStreak") private var rejectStreak = 0
    @State private var overrides = WindDownNudge.perDayWakeOverrides

    var body: some View {
        NunaDetailScreen("Smart alarm") {
            hero
            settingsCard
            if behavior.smartAlarmEnabled && rejectStreak >= 2 { rejectedCard }
            honestyCard
        }
        .onChange(of: behavior.smartAlarmEnabled) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmMinutes) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmWeekdays) { _, _ in model.applySmartAlarm() }
        .onAppear { overrides = WindDownNudge.perDayWakeOverrides }
    }

    private var willArm: Bool { !(model.whoop5Detected && !PuffinExperiment.isEnabled) }

    private func nextAlarm(from now: Date = Date()) -> Date? {
        guard behavior.smartAlarmEnabled, willArm else { return nil }
        return AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes, weekdays: behavior.smartAlarmWeekdays,
                                           overrides: overrides, from: now)
    }

    private func countdown(from now: Date) -> String? {
        guard let next = nextAlarm(from: now) else { return nil }
        let seconds = next.timeIntervalSince(now)
        guard seconds >= 60 else { return String(localized: "Alarm in less than a minute") }
        let f = DateComponentsFormatter()
        f.calendar = { var c = Calendar.current; c.locale = AppLanguage.activeLocale; return c }()
        f.unitsStyle = .full; f.allowedUnits = [.day, .hour, .minute]; f.zeroFormattingBehavior = .dropAll; f.maximumUnitCount = 3
        guard let span = f.string(from: seconds), !span.isEmpty else { return nil }
        return String(localized: "Alarm in \(span)")
    }

    private func stamp(from now: Date) -> String? {
        nextAlarm(from: now).map { d in
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM jj:mm")
            return f.string(from: d)
        }
    }

    private var hero: some View {
        NunaCard(highlight: behavior.smartAlarmEnabled) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    nunaCaption("Morning")
                    Spacer()
                    NunaChip(behavior.smartAlarmEnabled ? "On" : "Off", color: behavior.smartAlarmEnabled ? NunaPalette.charge : nil)
                }
                Text(verbatim: NunaAlarmFormat.clock(behavior.smartAlarmMinutes))
                    .font(.nuna(size: 56, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(56)).foregroundStyle(NunaPalette.textPrimary)
                TimelineView(.periodic(from: .now, by: 60)) { tick in
                    VStack(alignment: .leading, spacing: 2) {
                        if let c = countdown(from: tick.date) {
                            Text(verbatim: c).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            if let s = stamp(from: tick.date) {
                                Text(verbatim: s).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        } else {
                            Text(behavior.smartAlarmEnabled ? "Not armed on this strap" : "Turn it on to buzz your wrist at wake time")
                                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var settingsCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                NunaToggleRow("Wake me with a strap buzz", subtitle: "Arms the strap to buzz at your wake time, even if NOOP is closed.",
                              systemImage: "alarm.fill", isOn: $behavior.smartAlarmEnabled)
                if behavior.smartAlarmEnabled {
                    NunaDivider()
                    HStack {
                        Text("Wake at").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: Binding(get: { NunaAlarmFormat.date(minutes: behavior.smartAlarmMinutes) },
                                                          set: { behavior.smartAlarmMinutes = NunaAlarmFormat.minutes($0) }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden().accessibilityLabel(Text("Strap alarm wake time"))
                    }
                    .frame(minHeight: 52)
                    NunaDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Repeat").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 12)
                        HStack(spacing: 8) {
                            ForEach(NunaAlarmFormat.weekdayOrder, id: \.self) { dow in
                                let on = SmartAlarmView.alarmWeekdayIsSelected(dow, in: behavior.smartAlarmWeekdays)
                                Button {
                                    behavior.smartAlarmWeekdays = SmartAlarmView.alarmToggledWeekday(dow, in: behavior.smartAlarmWeekdays)
                                } label: {
                                    Text(verbatim: String(NunaAlarmFormat.weekdayShort(dow).prefix(1)))
                                        .font(.nuna(size: 13, weight: .heavy))
                                        .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textSecondary)
                                        .frame(maxWidth: .infinity).frame(height: 40)
                                        .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: NunaAlarmFormat.weekdayName(dow)))
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        Text(verbatim: SmartAlarmView.alarmWeekdaySummary(behavior.smartAlarmWeekdays))
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        if !overrides.isEmpty {
                            nunaNote("Some days have a time of their own, set in the bedtime reminder.")
                        }
                    }
                    NunaDivider().padding(.top, 12)
                    strapNotes.padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder private var strapNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.whoop5Detected && !PuffinExperiment.isEnabled {
                nunaNote("Your WHOOP 5/MG won't arm this until Experimental mode is on (Settings, Experimental). Right now your wake time is saved but the strap is NOT armed.", warn: true)
            } else if model.whoop5Detected {
                nunaNote("Armed on the strap itself with the experimental 5/MG command. A strap-driven wake is still unconfirmed on 5/MG, so keep a backup alarm.")
            } else {
                nunaNote("Armed on the strap itself, so it can buzz at your wake time even if your phone is asleep or NOOP is closed. Keep a backup alarm for anything you truly can't miss.")
                Button { model.ble.getStrapAlarm() } label: {
                    Text("Check what the strap has stored").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var rejectedCard: some View {
        NunaCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NunaPalette.warning)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your strap isn't accepting the alarm").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    nunaNote("The strap keeps reporting a different time than NOOP sends, so its alarm won't fire at your wake time. Reset the strap in the official WHOOP app (or fully charge it and reconnect), and keep your phone's Clock alarm as your wake until it takes.")
                }
            }
        }
    }

    private var honestyCard: some View {
        NunaCard(small: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash").foregroundStyle(NunaPalette.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("The strap alarm is a silent buzz, not a sound").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    nunaNote("It buzzes your wrist from the strap's own firmware and can't sound a loud alarm. A backup notification is scheduled too, but Focus or silent mode can mute it. Keep your phone's Clock alarm as your real backup.")
                }
            }
        }
    }
}

// MARK: - Bedtime reminder detail

struct NunaWindDownView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @StateObject private var wind = NunaWindDownState()

    var body: some View {
        NunaDetailScreen("Bedtime reminder") {
            hero
            settingsCard
            if wind.isOn { perDayCard }
        }
        .onAppear { wind.reload() }
        .nunaDeniedAlert($wind.showDenied)
    }

    private var hero: some View {
        NunaCard(highlight: wind.isOn) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    nunaCaption("Tonight")
                    Spacer()
                    NunaChip(wind.isOn ? "On" : "Off", color: wind.isOn ? NunaPalette.charge : nil)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    timeBlock("Wind down", wind.isOn ? NunaAlarmFormat.clock(wind.reminderMinutes) : "—")
                    Image(systemName: "arrow.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    timeBlock("Usual wake", NunaAlarmFormat.clock(wind.wakeMinutes))
                    Spacer(minLength: 0)
                }
                nunaNote(wind.isOn ? "A calm nudge \(WindDownNudge.sleepNeedMinutes / 60)h \(WindDownNudge.leadMinutes)m before your usual wake time."
                                   : "Turn on the reminder to land at your usual wake time rested.")
            }
        }
    }

    private func timeBlock(_ label: LocalizedStringKey, _ time: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            nunaCaption(label)
            Text(verbatim: time).font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private var settingsCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                NunaListRow("Remind me to wind down", description: "A calm evening reminder, timed from your wake time and usual sleep need. It's a suggestion, not an alarm.",
                            systemImage: "moon.zzz.fill") {
                    Toggle("", isOn: Binding(get: { wind.isOn }, set: { wind.setOn($0) })).labelsHidden().tint(NunaPalette.charge)
                }
                if wind.isOn {
                    NunaDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your usual wake time").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("This time does not wake you. It only decides when the evening reminder fires.")
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                        Spacer(minLength: 8)
                        DatePicker("", selection: Binding(get: { NunaAlarmFormat.date(minutes: wind.wakeMinutes) },
                                                          set: { wind.setWake(NunaAlarmFormat.minutes($0)) }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden().accessibilityLabel(Text("Your usual wake time"))
                    }
                    .padding(.vertical, 12)
                    Text("You'll be reminded around \(NunaAlarmFormat.clock(wind.reminderMinutes)).")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    if behavior.smartAlarmEnabled {
                        Text("Your strap alarm is what wakes you, at \(NunaAlarmFormat.clock(behavior.smartAlarmMinutes)).")
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).padding(.top, 6).textCase(nil)
                    }
                }
            }
        }
    }

    private var perDayCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                NunaListRow("Different wake time per day", description: "A lie-in at the weekend, say. These times move your strap alarm AND the evening reminder on those days.") {
                    Toggle("", isOn: Binding(get: { wind.perDayOn }, set: { on in
                        wind.perDayOn = on
                        if !on {
                            for d in 1...7 { WindDownNudge.setWakeOverride(weekday: d, minutes: nil) }
                            wind.overrides = [:]
                            model.applySmartAlarm()
                        }
                    })).labelsHidden().tint(NunaPalette.charge)
                }
                if wind.perDayOn {
                    ForEach(NunaAlarmFormat.weekdayOrder, id: \.self) { d in
                        NunaDivider()
                        dayRow(d)
                    }
                    Text(untouched).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.top, 10)
                }
            }
        }
    }

    private var untouched: String {
        guard behavior.smartAlarmEnabled else { return String(localized: "Days you leave alone use the usual wake time above.") }
        let alarm = NunaAlarmFormat.clock(behavior.smartAlarmMinutes), usual = NunaAlarmFormat.clock(wind.wakeMinutes)
        return String(localized: "Days you leave alone keep your strap alarm at \(alarm), and time the reminder from \(usual).")
    }

    private func dayRow(_ d: Int) -> some View {
        let has = wind.overrides[d] != nil
        let effective = wind.overrides[d] ?? wind.wakeMinutes
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: NunaAlarmFormat.weekdayName(d)).font(.nuna(size: 15, weight: .bold))
                    .foregroundStyle(has ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                if !has { Text("no time of its own").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
            }
            Spacer(minLength: 0)
            if has {
                Button {
                    WindDownNudge.setWakeOverride(weekday: d, minutes: nil); wind.overrides[d] = nil; model.applySmartAlarm()
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear \(NunaAlarmFormat.weekdayName(d)) override, use the default wake time"))
            }
            DatePicker("", selection: Binding(get: { NunaAlarmFormat.date(minutes: effective) }, set: { date in
                let m = NunaAlarmFormat.minutes(date)
                WindDownNudge.setWakeOverride(weekday: d, minutes: m); wind.overrides[d] = m; model.applySmartAlarm()
            }), displayedComponents: .hourAndMinute)
                .labelsHidden().accessibilityLabel(Text("\(NunaAlarmFormat.weekdayName(d)) wake time"))
        }
        .frame(minHeight: 52)
    }
}
#endif
