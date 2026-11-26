#if os(iOS)
import SwiftUI
import StrandDesign

/// The row on the Blood pressure page that says when the reminder comes, and opens its settings.
struct NunaBPReminderRow: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(NunaBPReminder.enabledKey) private var on = false
    @AppStorage(NunaBPReminder.morningKey) private var morning = NunaBPReminder.defaultMorning
    @AppStorage(NunaBPReminder.morningOnKey) private var morningOn = true
    @AppStorage(NunaBPReminder.eveningKey) private var evening = NunaBPReminder.defaultEvening
    @AppStorage(NunaBPReminder.eveningOnKey) private var eveningOn = true
    @State private var open = false

    private var summary: String {
        let times = [morningOn ? NunaAlarmFormat.clock(morning) : nil, eveningOn ? NunaAlarmFormat.clock(evening) : nil].compactMap { $0 }
        return on && !times.isEmpty ? times.joined(separator: " · ") : String(localized: "Off")
    }

    var body: some View {
        Button { open = true } label: {
            NunaCard(small: true) { NunaListRow("Measurement reminder", subtitle: LocalizedStringKey(summary), systemImage: "bell", showsChevron: true) }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { NunaBPReminderSheet().environmentObject(repo).nunaSheetChrome(detents: [.medium, .large]) }
    }
}

/// The reminder's settings: on or off, a morning and an evening time, each of which may be left out.
struct NunaBPReminderSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NunaBPReminder.enabledKey) private var on = false
    @AppStorage(NunaBPReminder.morningKey) private var morning = NunaBPReminder.defaultMorning
    @AppStorage(NunaBPReminder.morningOnKey) private var morningOn = true
    @AppStorage(NunaBPReminder.eveningKey) private var evening = NunaBPReminder.defaultEvening
    @AppStorage(NunaBPReminder.eveningOnKey) private var eveningOn = true
    @State private var denied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Measurement reminder").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                NunaCard(small: true) {
                    NunaListRow("Remind me to measure", description: "A notification at the times below, on this phone only.", systemImage: "bell") {
                        Toggle("", isOn: $on).labelsHidden().tint(NunaPalette.charge).accessibilityLabel(Text("Remind me to measure"))
                    }
                }
                if on {
                    time("Morning", minutes: $morning, on: $morningOn)
                    time("Evening", minutes: $evening, on: $eveningOn)
                }
                if denied {
                    Button { NunaAlarmFormat.openNotificationSettings() } label: {
                        Text("Notifications are off for PHMN. Turn them on in Settings.").font(.nuna(size: 13.5, weight: .semibold))
                            .foregroundStyle(NunaPalette.warning).textCase(nil).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                Text("A time is skipped when you measured within the three hours before it. Reminders are planned ten days ahead, so open the app now and then.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 24)
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .onChange(of: on) { _, _ in plan() }
        .onChange(of: morning) { _, _ in plan() }
        .onChange(of: morningOn) { _, _ in plan() }
        .onChange(of: evening) { _, _ in plan() }
        .onChange(of: eveningOn) { _, _ in plan() }
        .task { if on { plan() } }
    }

    private func time(_ title: LocalizedStringKey, minutes: Binding<Int>, on enabled: Binding<Bool>) -> some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                if enabled.wrappedValue {
                    DatePicker("", selection: Binding(get: { NunaAlarmFormat.date(minutes: minutes.wrappedValue) },
                                                      set: { minutes.wrappedValue = NunaAlarmFormat.minutes($0) }), displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityLabel(Text(title))
                }
                Toggle("", isOn: enabled).labelsHidden().tint(NunaPalette.charge).accessibilityLabel(Text(title))
            }
        }
    }

    private func plan() {
        Task {
            let readings = await NunaBP.load(repo).map(\.takenAt)
            denied = !(await NunaBPReminder.schedule(readings: readings))
        }
    }
}
#endif
