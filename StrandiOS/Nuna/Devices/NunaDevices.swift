#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandAnalytics
import WhoopStore

enum NunaDeviceRoute: Hashable {
    case detail(String)      // PairedDevice.id
    case battery, sync, help, helpHub, repair, log, models
}

extension View {
    func nunaDeviceDestinations() -> some View {
        navigationDestination(for: NunaDeviceRoute.self) { r in
            switch r {
            case .detail(let id): NunaDeviceDetailView(deviceId: id)
            case .battery: NunaDeviceBatteryView()
            case .sync: NunaDeviceSyncView()
            case .help: NunaDeviceHelpView()
            case .helpHub: NunaDeviceHelpHubView()
            case .repair: NunaDeviceRepairView()
            case .log: NunaDeviceLogView()
            case .models: NunaDeviceModelsView()
            }
        }
    }
}

/// What the Nuna device screens say about the connection, from the same state the Default screens read.
enum NunaDeviceFormat {
    static func clock(_ ts: TimeInterval) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("HH:mm"); return f.string(from: Date(timeIntervalSince1970: ts))
    }
    static func ago(_ ts: TimeInterval) -> String {
        let f = RelativeDateTimeFormatter(); f.locale = AppLanguage.activeLocale; f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }
    /// "3 days 4 hours" from a battery estimate.
    static func remaining(_ hours: Double) -> String {
        let h = Int(hours.rounded())
        if h >= 48 { return String(localized: "\(h / 24) days \(h % 24) hours") }
        return String(localized: "\(h) hours")
    }
    static func family(_ d: PairedDevice) -> String { d.model.isEmpty ? d.brand : d.model }
}

// MARK: - Devices (Devices.dc)

struct NunaDevicesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let registry = model.deviceRegistry { NunaDevicesContent(registry: registry) }
        else { NunaDetailScreen("Devices") { NunaCard(small: true) { Text("Opening your on-device data. Your paired bands appear here in a moment.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } } }
    }
}

private struct NunaDevicesContent: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var tab = 0
    @State private var showAdd = false
    @State private var switchTarget: PairedDevice?
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmRestart = false
    @State private var buzzed = false

    private var devices: [PairedDevice] { registry.devices.filter { $0.status != .archived } }
    private var active: PairedDevice? { devices.first { $0.status == .active } }
    private var others: [PairedDevice] { devices.filter { $0.status != .active } }
    private var removed: [PairedDevice] { registry.devices.filter { $0.status == .archived } }

    var body: some View {
        NunaDetailScreen("Devices", trailing: AnyView(NavigationLink(value: NunaDeviceRoute.helpHub) { NunaBareIcon("questionmark.circle") }.buttonStyle(.plain).accessibilityLabel(Text("Help")))) {
            if let d = active { deviceHeader(d) }
            NunaPageTabs([(value: 0, title: "Status"), (value: 1, title: "Advanced")], selection: $tab)
            if tab == 0 { statusTab } else { advancedTab }
        }
        .sheet(isPresented: $showAdd) {
            AddDeviceWizard(live: live) { showAdd = false }.environmentObject(model).environmentObject(live)
        }
        .alert("Make this your active strap?", isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }), presenting: switchTarget) { d in
            Button("Cancel", role: .cancel) { switchTarget = nil }
            Button("Make active") { registry.setActive(d.id); switchTarget = nil }
        } message: { d in Text("From now on \(d.displayName) provides your live data. The history of the other strap stays exactly as it is.") }
        .alert("Rename device", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let d = active { registry.rename(d.id, to: nameDraft) } }
        }
        .alert("Restart this strap?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { model.rebootStrap() }
        } message: { Text("It disconnects for about 30 seconds, then reconnects on its own. Your recorded data is kept.") }
    }

    // MARK: Status

    @ViewBuilder private var statusTab: some View {
        if let guide = live.reconnectGuide { repairBanner(guide) }
        if let d = active {
            hero(d)
            if live.lastSyncedAt != nil || live.backfilling { syncRow }
        } else {
            emptyCard
            addButton
        }
    }

    /// Who the strap is and whether it is connected, and when it last synced. Shown above both tabs.
    private func deviceHeader(_ d: PairedDevice) -> some View {
        let connected = live.connected
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(connected ? "Connected to" : "Not connected to").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(connected ? NunaPalette.charge : NunaPalette.textSecondary)
                    Button { nameDraft = d.nickname ?? d.displayName; renaming = true } label: {
                        HStack(spacing: 7) {
                            Text(verbatim: d.displayName).font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "pencil").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                    }.buttonStyle(.plain).accessibilityLabel(Text("Rename device"))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("Last sync").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    HStack(spacing: 6) {
                        Text(verbatim: live.lastSyncedAt.map(NunaDeviceFormat.clock) ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        phoneSyncIcon
                    }
                }
            }
        }
    }

    /// The strap at a glance, without a card: the name and whether it is connected, when it last synced, and the strap itself with its
    /// battery beside it (or, when it is not connected, the broken line to the phone and a button to reconnect).
    private func hero(_ d: PairedDevice) -> some View {
        let connected = live.connected
        let family = NunaDeviceFormat.family(d)
        return VStack(alignment: .leading, spacing: 8) {
            NunaDeviceStage(connected: connected, batteryPct: live.batteryPct, charging: live.charging == true,
                            model: family, estimate: live.batteryEstimate.map { "~" + NunaDeviceFormat.remaining($0.remainingHours) })
                .padding(.horizontal, -NunaSpacing.screenH)
            if !connected || live.backfilling {
                VStack(spacing: 6) {
                    Text(connected ? "Syncing history" : "Strap disconnected")
                        .font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(connected ? "Pulling what the strap recorded while it was away" : "Bring the strap close to the phone, then reconnect")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).textCase(nil)
                }.frame(maxWidth: .infinity)
            }
            if !connected {
                Button { model.disconnect(); model.ble.connect() } label: {
                    Text("Reconnect").font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 50)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 10)
            }
        }
    }

    /// The phone the strap last synced to: a phone with a tick, or crossed out when it never has.
    @ViewBuilder private var phoneSyncIcon: some View {
        if live.lastSyncedAt == nil {
            Image(systemName: "iphone.slash").font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
        } else {
            Image(systemName: "iphone").font(.nuna(size: 19, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                .overlay { Image(systemName: "checkmark").font(.nuna(size: 7, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).offset(y: -1) }
        }
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)); Text("Add a device").font(.nuna(size: 15, weight: .bold)) }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        }.buttonStyle(.plain)
    }

    // MARK: Advanced

    @ViewBuilder private var advancedTab: some View {
        if let d = active {
            HStack(alignment: .top, spacing: 0) {
                idTile("Device ID", Self.deviceID(d), "applewatch")
                idTile("Firmware", live.strapFirmware ?? "–", "cpu")
            }
            .padding(.top, 8)
            Text(verbatim: NunaDeviceFormat.family(d) + (live.strapRange?.firmwareLayout.map { " · " + String(localized: "History format") + " v\($0)" } ?? ""))
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 22) {
                actionButton("Add a device", nil, "plus.circle") { showAdd = true }
                if SourceCoordinator.isWhoop(d) {
                    actionButton("Reconnect", nil, "dot.radiowaves.left.and.right") { model.disconnect(); model.ble.connect() }
                    actionButton("Test vibration", buzzed ? String(localized: "Sent") : nil, "waveform", enabled: live.connected && live.bonded) {
                        model.buzzStrapOnce(); buzzed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { buzzed = false }
                    }
                    // A 4.0 has no safe restart frame, so the entry only exists for the 5/MG family (same rule as the strap's own detail screen).
                    if live.connected && !model.ble.isWhoop4 {
                        actionButton("Restart strap", "Disconnects for about 30 seconds, then reconnects on its own.", "power") { confirmRestart = true }
                    }
                }
                NavigationLink(value: NunaDeviceRoute.detail(d.id)) {
                    actionLabel("Manage this strap", nil, "slider.horizontal.3", enabled: true)
                }.buttonStyle(.plain)
            }
            .padding(.top, 10).padding(.bottom, 10)
        } else {
            addButton
        }
        if !others.isEmpty {
            nunaRuledHeader("Other WHOOP")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 12) {
                            NavigationLink(value: NunaDeviceRoute.detail(d.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: d.displayName).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: NunaDeviceFormat.family(d) + " · " + String(localized: "history kept")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if !d.isImportSource {
                                Button { switchTarget = d } label: {
                                    Text("Make active").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
        if !removed.isEmpty {
            nunaRuledHeader("Removed")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(removed.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaDeviceRoute.detail(d.id)) {
                            NunaListRow(LocalizedStringKey(d.displayName), description: "Data kept. Tap to add it back", systemImage: "archivebox", showsChevron: true)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A centred fact about the strap: a quiet icon, its name and the value.
    private func idTile(_ label: LocalizedStringKey, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textMuted).frame(height: 28)
            VStack(spacing: 4) {
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A button with its explanation underneath.
    private func actionButton(_ title: LocalizedStringKey, _ subtitle: String?, _ icon: String, enabled: Bool = true, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(title, subtitle, icon, enabled: enabled) }
            .buttonStyle(.plain).disabled(!enabled)
    }

    private func actionLabel(_ title: LocalizedStringKey, _ subtitle: String?, _ icon: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 56)
            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            if let subtitle {
                Text(verbatim: subtitle).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    private static func deviceID(_ d: PairedDevice) -> String {
        d.id == "my-whoop" ? (d.peripheralId.map { String($0.prefix(8)).uppercased() } ?? d.id) : d.id
    }

    private var emptyCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NunaIconTile("applewatch")
                Text("No strap yet").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text("Add your WHOOP to record heart rate, sleep and workouts. NOOP connects directly over Bluetooth, without the WHOOP app or any cloud.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var syncRow: some View {
        NavigationLink(value: NunaDeviceRoute.sync) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.backfilling ? "Syncing history…" : "Strap history pulled").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: live.backfilling ? String(localized: "\(live.syncChunksThisSession) packets so far")
                                                     : (live.lastSyncedAt.map { String(localized: "Last at \(NunaDeviceFormat.clock($0))") } ?? "")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Spacer()
                if live.connected && !live.backfilling {
                    Button { model.ble.syncNow() } label: {
                        Text("Sync now").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 16).frame(height: 36).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                } else { Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { NunaDivider() }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func repairBanner(_ guide: String) -> some View {
        NavigationLink(value: NunaDeviceRoute.repair) {
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NunaPalette.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can't connect: the strap's pairing was reset").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("See how to pair it again").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

}

/// The four ways to get unstuck, behind the question mark at the top right of Devices.
struct NunaDeviceHelpHubView: View {
    var body: some View {
        NunaDetailScreen("Help") {
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaDeviceRoute.battery) { NunaListRow("Battery", description: "Level, trend and care", systemImage: "battery.75percent", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.help) { NunaListRow("Strap not found?", description: "Steps to check, one by one", systemImage: "questionmark.circle", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.models) { NunaListRow("Models and support", description: "WHOOP 4.0, 5.0 and MG", systemImage: "square.stack.3d.up", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", description: "Copy it when reporting a problem", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Detail (DeviceDetail.dc, DeviceRestart.dc)

struct NunaDeviceDetailView: View {
    let deviceId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmRestart = false
    @State private var confirmRemove = false
    @State private var confirmDeleteData = false
    @State private var confirmForget = false
    @State private var buzzed = false

    private var registry: DeviceRegistry? { model.deviceRegistry }
    private var device: PairedDevice? { registry?.devices.first { $0.id == deviceId } }
    private var isActive: Bool { device?.status == .active }
    private var isWhoop: Bool { device.map(SourceCoordinator.isWhoop) ?? false }
    private var linked: Bool { isActive && live.connected }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(device?.displayName ?? String(localized: "Device"))) {
            if let d = device {
                header(d)
                info(d)
                if isActive && isWhoop { actions(d) }
                manage(d)
            } else {
                NunaCard(small: true) { Text("This device is no longer in the list.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .alert("Rename device", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { registry?.rename(deviceId, to: nameDraft) }
        }
        .alert("Restart this strap?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { model.rebootStrap() }
        } message: { Text("It disconnects for about 30 seconds, then reconnects on its own. Your recorded data is kept.") }
        .alert("Remove this device?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { registry?.archive(deviceId); dismiss() }
        } message: { Text("NOOP stops connecting to it. Its recorded data is kept and you can add it back.") }
        .alert("Delete all of this device's data?", isPresented: $confirmDeleteData) {
            Button("Cancel", role: .cancel) {}
            Button("Delete data", role: .destructive) {
                Task { guard let store = await model.repo.storeHandle() else { return }; await registry?.deleteDeviceData(deviceId, store: store) }
            }
        } message: { Text("This permanently deletes everything recorded from this device. It can't be undone.") }
        .alert("Remove it for good?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Remove for good", role: .destructive) {
                Task { guard let store = await model.repo.storeHandle() else { return }; await registry?.forget(deviceId, store: store); dismiss() }
            }
        } message: { Text("The device leaves the list completely. Data already recorded is kept.") }
    }

    private func header(_ d: PairedDevice) -> some View {
        NunaCard(highlight: linked) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NunaIconTile("applewatch")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: d.displayName).font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: NunaDeviceFormat.family(d)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    NunaChip(d.status == .archived ? "Removed" : (linked ? "Connected" : (isActive ? "Not connected" : "Paired")), color: linked ? NunaPalette.charge : nil)
                }
                if isActive, let pct = live.batteryPct {
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.battery) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: String(localized: "Battery \(Int(pct.rounded()))%")).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: live.charging == true ? String(localized: "Charging") : (live.batteryEstimate.map { String(localized: "Not charging · about \(NunaDeviceFormat.remaining($0.remainingHours))") } ?? String(localized: "Not charging")))
                                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func info(_ d: PairedDevice) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                row("Name", d.displayName, action: { nameDraft = d.nickname ?? d.displayName; renaming = true })
                NunaDivider()
                row("Model", NunaDeviceFormat.family(d))
                NunaDivider()
                row("Device ID", d.id == "my-whoop" ? (d.peripheralId.map { String($0.prefix(8)).uppercased() } ?? d.id) : d.id)
                if isActive, let fw = live.strapFirmware { NunaDivider(); row("Firmware", fw) }
                if isActive, let layout = live.strapRange?.firmwareLayout { NunaDivider(); row("History format", "v\(layout)") }
                NunaDivider()
                row("Added", Self.date(d.addedAt))
            }
        }
    }

    @ViewBuilder private func row(_ l: LocalizedStringKey, _ v: String, action: (() -> Void)? = nil) -> some View {
        let content = HStack {
            Text(l).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 12)
            Text(verbatim: v).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if action != nil { Image(systemName: "pencil").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
        }.padding(.vertical, 14).contentShape(Rectangle())
        if let action { Button(action: action) { content }.buttonStyle(.plain) } else { content }
    }

    private func actions(_ d: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader("Actions")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    action("Sync now", live.lastSyncedAt.map { String(localized: "Last at \(NunaDeviceFormat.clock($0))") } ?? String(localized: "Not synced yet"), "arrow.triangle.2.circlepath", enabled: live.connected && !live.backfilling) { model.ble.syncNow() }
                    NunaDivider()
                    action("Reconnect", "Disconnect, then scan again", "dot.radiowaves.left.and.right", enabled: true) { model.disconnect(); model.ble.connect() }
                    NunaDivider()
                    action("Test vibration", buzzed ? String(localized: "Sent") : String(localized: "The strap vibrates once to confirm"), "waveform", enabled: live.connected && live.bonded) {
                        model.buzzStrapOnce(); buzzed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { buzzed = false }
                    }
                    // A 4.0 has no safe restart frame, so the entry only exists for the 5/MG family (same rule as the Default screen).
                    if live.connected && !model.ble.isWhoop4 {
                        NunaDivider()
                        action("Restart strap", "Disconnects for about 30 seconds", "arrow.clockwise", enabled: true) { confirmRestart = true }
                    }
                }
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ subtitle: String, _ icon: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { NunaListRow(title, subtitle: LocalizedStringKey(subtitle), systemImage: icon, showsChevron: true) }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }

    private func manage(_ d: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader("Manage")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    if d.status == .archived {
                        action("Add it back", "Make it an active device again", "plus.circle", enabled: true) { registry?.setActive(d.id) }
                    } else if !isActive && !d.isImportSource {
                        action("Make active", "It provides your live data", "bolt", enabled: true) { registry?.setActive(d.id) }
                    } else if isActive {
                        NunaListRow("Active device", description: "It provides your live data", systemImage: "bolt.fill") { NunaChip("Active", color: NunaPalette.charge) }.padding(.vertical, 2)
                    }
                    if d.status != .archived {
                        NunaDivider()
                        Button { confirmRemove = true } label: { NunaListRow("Remove from the list", description: "Data stays and it can be added again", systemImage: "archivebox", showsChevron: true) }.buttonStyle(.plain)
                    }
                    NunaDivider()
                    Button { confirmDeleteData = true } label: { NunaListRow("Delete all data of this device", subtitle: "Permanent and cannot be undone", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
                    if d.status == .archived {
                        NunaDivider()
                        Button { confirmForget = true } label: { NunaListRow("Remove for good", description: "Takes it out of the list entirely", systemImage: "xmark.bin", showsChevron: true) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static func date(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
#endif
