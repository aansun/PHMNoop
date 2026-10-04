#if os(iOS)
import SwiftUI
import StrandDesign

/// "Saya": the Nuna settings hub (docs/nuna/mockups/Personalize.dc.html).
///
/// Phase 0 builds the hub and the Appearance / Experience path. Every other row opens the closest
/// existing screen until its Nuna replacement lands (Phase 7).
struct NunaMeView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Me")
                profileCard
                section("Account and device") {
                    row("Persona", "Profile, heart-rate zones, goals", "person.fill", NunaPalette.charge) { SettingsView() }
                    NunaDivider()
                    row("Devices", deviceSubtitle, "applewatch", nil) { NunaDevicesView() }
                    NunaDivider()
                    row("Anya", "AI coach, memory, providers", "sparkles", nil) { NunaAnyaSettingsView() }
                }
                section("Appearance") {
                    row("Appearance", "Experience, theme, language, units", "slider.horizontal.3", NunaPalette.effortText) { NunaAppearanceView() }
                    NunaDivider()
                    row("Widgets and Lock Screen", "Home and lock screen widgets", "square.grid.2x2.fill", NunaPalette.charge) { SettingsView() }
                }
                section("Notifications and automation") {
                    row("Notifications", "Reminders and alerts", "bell.fill", NunaPalette.effortText) { AutomationsView() }
                    NunaDivider()
                    row("Strap automations", "Double-tap, haptics, reminders", "applewatch.radiowaves.left.and.right", NunaPalette.charge) { AutomationsView() }
                    NunaDivider()
                    row("Optional features", "Water, journal, workout detection", "checkmark.circle.fill", nil) { SettingsView() }
                }
                section("Data") {
                    row("Apple Health", "Permissions, what is read and written", "heart.text.square.fill", nil) { NunaAppleHealthView() }
                    NunaDivider()
                    row("Data and integrations", "Strava, import, export", "square.and.arrow.up", nil) { DataSourcesView() }
                    NunaDivider()
                    row("Backup", "Back up and restore", "clock.arrow.circlepath", NunaPalette.charge) { BackupSyncView() }
                    NunaDivider()
                    row("Privacy", "Everything stays on this iPhone", "lock.shield.fill", nil) { SettingsView() }
                }
                section("More") {
                    row("Advanced and experiments", "Baseline, HRV, Test Centre", "flame.fill", NunaPalette.restText) { SettingsView() }
                    NunaDivider()
                    row("About and help", "Version, how it works, credits", "info.circle.fill", nil) { AboutView() }
                }
                Text("PHMNOOP · a fork of NOOP. Not a medical device.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NunaPalette.textMuted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .nunaScreenBackground()
    }

    private var deviceSubtitle: LocalizedStringKey {
        if live.connected, let pct = live.batteryPct { return "Connected · \(Int(pct.rounded()))%" }
        return live.connected ? "Connected" : "Not connected"
    }

    private var profileCard: some View {
        NavigationLink { SettingsView() } label: {
            NunaCard {
                HStack(spacing: 16) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.system(size: NunaTypeSize.h2 - 1, weight: .heavy))
                            .foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: "\(profile.age) · \(Int(profile.heightCm.rounded())) cm · \(String(format: "%.1f", profile.weightKg)) kg")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func section<Rows: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaSectionHeader(title)
            NunaCard(small: true) {
                VStack(spacing: 0) { rows() }
            }
        }
    }

    private func row<Destination: View>(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String,
                                        _ tint: Color?, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            NunaListRow(title, subtitle: subtitle, systemImage: icon, tint: tint, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}
#endif
