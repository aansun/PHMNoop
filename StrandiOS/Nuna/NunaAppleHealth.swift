#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Apple Health, kept short: what the connection is, a button to connect, and a pointer to where iOS keeps the details. iOS asks for access
/// as one set and owns the per-type switches (Health > Sharing > Apps), so this page does not list them again; turning access off there
/// never deletes data.
struct NunaAppleHealthView: View {
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NunaDetailScreen("Apple Health") {
            VStack(spacing: 22) {
                logos
                dataTypes
            }
            .frame(maxWidth: .infinity).padding(.top, 8)
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 14) {
                Text(heading).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text("PHMN reads your steps, weight, waist, heart rate, water and workouts from Apple Health, and writes the strap's steps, heart rate, nightly vitals, sleep and workouts back, without counting a step twice.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Text("What is read and written is set in Health under Sharing, Apps, PHMN. Turning it off there never deletes data.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Button {
                    if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                } label: {
                    HStack(spacing: 10) {
                        Text("Open Health permissions").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                    }.foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 44)
                }.buttonStyle(.plain)
                if let err = health.lastError {
                    Text(verbatim: err).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    private var heading: LocalizedStringKey { health.auth == .authorized ? "Connected to Apple Health" : "Connect to Apple Health" }

    // MARK: The picture

    private var logos: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white).frame(width: 84, height: 84)
                .overlay { Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.5), Color(red: 1, green: 0.15, blue: 0.3)], startPoint: .top, endPoint: .bottom)) }
            HStack(spacing: 0) {
                Circle().fill(NunaPalette.textMuted).frame(width: 7, height: 7)
                Rectangle().fill(NunaPalette.textMuted.opacity(0.7)).frame(width: 34, height: 1.5)
                Circle().fill(NunaPalette.textMuted).frame(width: 7, height: 7)
            }
            Image("PHMNMark").resizable().scaledToFit().frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
    }

    private var dataTypes: some View {
        HStack(spacing: 10) {
            ForEach(["figure.walk", "scalemass", "heart", "moon", "flame"], id: \.self) { symbol in
                Image(systemName: symbol).font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 50, height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.textMuted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    // MARK: The button

    @ViewBuilder private var actionBar: some View {
        VStack(spacing: 8) {
            switch health.auth {
            case .entitlementMissing:
                note("This install can't connect to Apple Health directly. It was signed with a profile that doesn't include Apple's Health permission. Bring your data in with a Health export under Import data.")
            case .unavailable:
                note("Apple Health isn't available on this device.")
            case .authorized:
                outlineButton(health.syncing ? "Syncing…" : "Sync now") { Task { await sync() } }.disabled(health.syncing)
                Text(verbatim: syncCaption).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            default:
                outlineButton("Connect") { Task { await health.requestAuthorization(); await sync() } }
                if health.auth == .denied {
                    note("If you don't see the prompt, allow PHMN under Settings, Health, Data Access & Devices.")
                }
            }
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 96)
        .frame(maxWidth: .infinity)
        .background(NunaPalette.canvas.opacity(0.96))
    }

    private func outlineButton(_ title: LocalizedStringKey, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.charge)
                .frame(maxWidth: .infinity).frame(height: 54)
                .overlay(Capsule().strokeBorder(NunaPalette.charge, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).textCase(nil)
    }

    private var syncCaption: String {
        guard let last = health.lastSync else { return String(localized: "Not synced yet") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM jj:mm")
        return String(localized: "Last synced \(f.string(from: last))")
    }

    private func sync() async {
        await HealthSyncRefreshCoordinator.run(
            sync: { await health.sync() },
            refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
    }
}
#endif
