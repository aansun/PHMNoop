#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Apple Health permissions and sync, kept in one place under Me (HealthPermissions mockup).
/// iOS asks for access as one set, so this page shows what is read and what is written rather than a switch
/// per type, and turning access off is done in iOS, which never deletes data.
struct NunaAppleHealthView: View {
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel

    private let reads: [(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
        ("figure.walk", "Steps", "Read from your iPhone"),
        ("scalemass", "Weight and body composition", "Read only, from your scale"),
        ("ruler", "Waist", "Fills your profile for the VO₂max estimate"),
        ("heart", "Heart rate and vitals", "Heart rate, HRV, oxygen, breathing"),
        ("drop", "Water and caffeine", "Drinks logged in other apps"),
        ("figure.run", "Workouts and energy", "Energy, workouts and routes"),
    ]
    private let writes: [(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
        ("figure.walk", "Estimated strap steps", "Without double counting with your iPhone"),
        ("heart", "Heart rate", "Continuous heart rate from the strap"),
        ("waveform.path.ecg", "Nightly vitals", "Resting heart rate, HRV, blood oxygen, respiratory rate"),
        ("moon", "Sleep", "Stages from the strap"),
        ("flame", "Workouts", "Run, walk, cycle and other sessions"),
    ]

    var body: some View {
        NunaDetailScreen("Apple Health") {
            statusCard
            if health.auth == .authorized || health.auth == .unknown || health.auth == .denied {
                NunaTitleRow(title: "Read from Health") { EmptyView() }
                list(reads, tag: "Read")
                NunaTitleRow(title: "Written to Health") { EmptyView() }
                list(writes, tag: "Written")
                NunaCard(small: true) {
                    NunaListRow("Steps without double counting", subtitle: "A sample NOOP wrote is never read back as a phone step", systemImage: "info.circle")
                }
            }
            Button {
                if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
            } label: {
                Text("Open iOS Health settings").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            Text("Access is managed by iOS. Turning it off there does not delete data.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
        }
    }

    private var statusCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 48, height: 48).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: syncCaption).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    switch health.auth {
                    case .authorized: NunaChip(health.syncing ? "Syncing" : "Connected", color: NunaPalette.charge)
                    case .unavailable, .entitlementMissing: NunaChip("Unavailable", color: NunaPalette.warning)
                    default: NunaChip("Not connected", color: NunaPalette.warning)
                    }
                }
                switch health.auth {
                case .entitlementMissing:
                    Text("This install can't connect to Apple Health directly. It was signed with a profile that doesn't include Apple's Health permission, so there is nothing to enable. Bring your data in with a Health export in Data and integrations.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                case .unavailable:
                    Text("Apple Health isn't available on this device.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                case .authorized:
                    Button { Task { await sync() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.nuna(size: 14, weight: .bold))
                            Text("Sync now").font(.nuna(size: 15, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(health.syncing).opacity(health.syncing ? 0.5 : 1)
                default:
                    Button {
                        Task {
                            await health.requestAuthorization()
                            await sync()
                        }
                    } label: {
                        Text("Enable Apple Health").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                    if health.auth == .denied {
                        Text("If you don't see the prompt, allow PHMNOOP under Settings › Health › Data Access & Devices.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let err = health.lastError {
                    Text(verbatim: err).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }

    private var syncCaption: String {
        guard let last = health.lastSync else { return String(localized: "Not synced yet") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM jj:mm")
        return String(localized: "Last synced \(f.string(from: last))")
    }

    private func list(_ rows: [(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey)], tag: LocalizedStringKey) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { i in
                    if i > 0 { NunaDivider() }
                    NunaListRow(rows[i].title, subtitle: rows[i].subtitle, systemImage: rows[i].icon) {
                        NunaChip(tag, color: health.auth == .authorized ? NunaPalette.charge : nil)
                    }
                }
            }
        }
    }

    private func sync() async {
        await HealthSyncRefreshCoordinator.run(
            sync: { await health.sync() },
            refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
    }
}
#endif
