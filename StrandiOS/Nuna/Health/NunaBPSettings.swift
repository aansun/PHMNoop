#if os(iOS)
import SwiftUI
import StrandDesign

/// Behind the gear on the Blood pressure page: the measurement reminder (on or off, a morning and an evening time, each of which may be left out) and
/// reading from Apple Health.
struct NunaBPSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @AppStorage(NunaBPReminder.enabledKey) private var on = false
    @AppStorage(NunaBPReminder.morningKey) private var morning = NunaBPReminder.defaultMorning
    @AppStorage(NunaBPReminder.morningOnKey) private var morningOn = true
    @AppStorage(NunaBPReminder.eveningKey) private var evening = NunaBPReminder.defaultEvening
    @AppStorage(NunaBPReminder.eveningOnKey) private var eveningOn = true
    @State private var denied = false
    @State private var reading = false

    var body: some View {
        NunaDetailScreen("Blood pressure settings", centersTitle: true) {
            VStack(alignment: .leading, spacing: 10) {
                NunaSectionHeader("Measurement reminder")
                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        NunaToggleRow("Reminder", systemImage: "bell", isOn: $on)
                        if on {
                            NunaDivider()
                            time("Morning", minutes: $morning, on: $morningOn)
                            NunaDivider()
                            time("Evening", minutes: $evening, on: $eveningOn)
                        }
                    }
                }
                if denied {
                    Button { NunaAlarmFormat.openNotificationSettings() } label: {
                        Text("Notifications are off for PHMN. Turn them on in Settings.").font(.nuna(size: 15, weight: .semibold))
                            .foregroundStyle(NunaPalette.warning).textCase(nil).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
                note("A notification on this phone. A time is skipped when you measured within the three hours before it. Reminders are planned ten days ahead, so open the app now and then.")
            }
            VStack(alignment: .leading, spacing: 10) {
                NunaSectionHeader("Apple Health")
                NunaCard(small: true) { appleHealth }
                note("Blood pressure your cuff's app saves in Apple Health is added to your readings.")
            }
        }
        .onChange(of: on) { _, _ in plan() }
        .onChange(of: morning) { _, _ in plan() }
        .onChange(of: morningOn) { _, _ in plan() }
        .onChange(of: evening) { _, _ in plan() }
        .onChange(of: eveningOn) { _, _ in plan() }
        .task { if on { plan() } }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }

    private func time(_ title: LocalizedStringKey, minutes: Binding<Int>, on enabled: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            // In line with the title above, past its icon.
            Text(title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).padding(.leading, 44)
            Spacer(minLength: 8)
            if enabled.wrappedValue {
                DatePicker("", selection: Binding(get: { NunaAlarmFormat.date(minutes: minutes.wrappedValue) },
                                                  set: { minutes.wrappedValue = NunaAlarmFormat.minutes($0) }), displayedComponents: .hourAndMinute)
                    .labelsHidden().accessibilityLabel(Text(title))
            }
            Toggle("", isOn: enabled).labelsHidden().tint(NunaPalette.charge).accessibilityLabel(Text(title))
        }
        .frame(minHeight: 56)
    }

    private func plan() {
        Task {
            let readings = await NunaBP.load(repo).map(\.takenAt)
            denied = !(await NunaBPReminder.schedule(readings: readings))
        }
    }

    // MARK: Apple Health

    @ViewBuilder private var appleHealth: some View {
        switch health.auth {
        case .authorized:
            Button { readHealth() } label: {
                NunaListRow("Apple Health", subtitle: reading ? "Reading…" : "Read automatically. Tap to read now", systemImage: "heart.text.square", showsChevron: true)
            }
            .buttonStyle(.plain).disabled(reading)
        case .entitlementMissing, .unavailable:
            NunaListRow("Apple Health", subtitle: "Not available in this build. Typed readings work as usual", systemImage: "heart.slash")
        default:
            Button { readHealth(connect: true) } label: {
                NunaListRow("Connect Apple Health", subtitle: reading ? "Reading…" : "Not connected", systemImage: "heart.text.square", showsChevron: true)
            }
            .buttonStyle(.plain).disabled(reading)
        }
    }

    /// A full Health pass also asks for any reading permission this version added, blood pressure among them.
    private func readHealth(connect: Bool = false) {
        reading = true
        Task {
            if connect { await health.requestAuthorization() }
            _ = await health.sync(days: 30)
            await PHMBloodPressureImport.sync(repo: repo)
            reading = false
        }
    }
}
#endif
