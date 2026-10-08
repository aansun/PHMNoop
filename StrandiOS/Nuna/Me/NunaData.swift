#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Data and integrations (DataHub.dc)

struct NunaDataHubView: View {
    @EnvironmentObject private var health: HealthKitBridge
    @AppStorage(StravaExperiment.enabledKey) private var strava = false
    @AppStorage(HevyExperiment.enabledKey) private var hevy = false

    /// An integration that can be connected, in the order it is listed within its group.
    private struct Integration: Identifiable {
        let id: String
        let route: NunaMeRoute
        let title: LocalizedStringKey
        let icon: String
        let connected: Bool
    }

    private var integrations: [Integration] {
        [Integration(id: "strava", route: .strava, title: "Strava", icon: "figure.run", connected: strava && StravaTokenStore.isConnected),
         Integration(id: "hevy", route: .hevy, title: "Hevy", icon: "dumbbell", connected: hevy && HevyKeyStore.hasKey)]
    }

    var body: some View {
        NunaDetailScreen("Data and integrations") {
            appleHealthCard
            let on = integrations.filter(\.connected), off = integrations.filter { !$0.connected }
            if !on.isEmpty {
                nunaRuledHeader("Connected")
                VStack(spacing: 10) { ForEach(on) { row($0) } }
            }
            if !off.isEmpty {
                nunaRuledHeader("Not connected")
                VStack(spacing: 10) { ForEach(off) { row($0) } }
            }
            nunaRuledHeader("Your data")
            VStack(spacing: 10) {
                NavigationLink(value: NunaMeRoute.imports) {
                    NunaTileRow(icon: "square.and.arrow.down", title: "Import data", subtitle: nil)
                }.buttonStyle(.plain)
                NavigationLink(value: NunaMeRoute.backup) {
                    NunaTileRow(icon: "square.and.arrow.up", title: "Backup and export",
                                subtitle: FolderBackup.lastBackupMs > 0 ? LocalizedStringKey(String(localized: "Last backup \(Self.when(FolderBackup.lastBackupMs))")) : "Not backed up yet")
                }.buttonStyle(.plain)
            }
            nunaFootnote("Everything stays on this iPhone. Deleting an import never touches data recorded live from the strap.")
        }
    }

    /// Apple Health, large at the top: the iPhone's own health data is the main source after the strap.
    private var appleHealthCard: some View {
        NavigationLink(value: NunaMeRoute.appleHealth) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [NunaPalette.card, NunaPalette.rest.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(NunaPalette.ink.opacity(0.07)).frame(width: 118, height: 118)
                    RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(NunaPalette.ink.opacity(0.10), lineWidth: 1).frame(width: 118, height: 118)
                    Image(systemName: "heart.fill").font(.system(size: 52)).foregroundStyle(NunaPalette.alert.opacity(0.6))
                }
                .rotationEffect(.degrees(-14)).offset(x: 40, y: -6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square.fill").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 38, height: 38).background(NunaPalette.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Health").font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: healthStatus).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(health.auth == .authorized ? NunaPalette.charge : NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var healthStatus: String {
        switch health.auth {
        case .authorized: return String(localized: "Connected")
        case .unavailable, .entitlementMissing: return String(localized: "Unavailable")
        default: return String(localized: "Not connected")
        }
    }

    private func row(_ i: Integration) -> some View {
        NavigationLink(value: i.route) { NunaTileRow(icon: i.icon, title: i.title, subtitle: nil, connected: i.connected) }.buttonStyle(.plain)
    }

    static func when(_ ms: Int) -> String {
        let f = RelativeDateTimeFormatter(); f.locale = AppLanguage.activeLocale; f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: Double(ms) / 1000), relativeTo: Date())
    }
}

/// A full-width tile for one place to go: a quiet icon, the name in capitals and, when it is connected, a green tick.
struct NunaTileRow: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var connected = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.nuna(size: 14.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if connected {
                Image(systemName: "checkmark").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.charge)
                    .frame(width: 24, height: 24).background(NunaPalette.charge.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if subtitle != nil {
                Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15).frame(minHeight: 60)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Backup (Backup.dc)

struct NunaBackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var auto = FolderBackup.autoEnabled
    @State private var folder = FolderBackup.folderLabel()
    @State private var lastMs = FolderBackup.lastBackupMs
    @State private var keep = FolderBackup.keepCount
    @State private var snapshots: [FolderBackup.Snapshot] = []
    @State private var busy = false
    @State private var alert: (title: String, message: String)?
    @State private var restoreTarget: FolderBackup.Snapshot?

    var body: some View {
        NunaDetailScreen("Backup") {
            NunaCard(highlight: lastMs > 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("Status"); Spacer(); NunaChip(lastMs > 0 ? "Running" : "Not yet", color: lastMs > 0 ? NunaPalette.charge : nil) }
                    Text(verbatim: lastMs > 0 ? NunaDataHubView.when(lastMs) : "–").font(.nuna(size: 32, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "\(snapshots.count) backups kept")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Text("Saved in the folder you choose. Point it at iCloud Drive to reach every Apple device.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Button { backupNow() } label: {
                        Text(busy ? "Working…" : "Back up now").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(busy || !FolderBackup.hasFolder).opacity(FolderBackup.hasFolder ? 1 : 0.4)
                }
            }
            NunaSettingsGroup("Folder") {
                NunaListRow("Backup folder", subtitle: LocalizedStringKey(folder ?? String(localized: "Not chosen")), systemImage: "folder")
                NunaDivider()
                Button { chooseFolder() } label: { NunaListRow("Change folder", description: "Pick one in Files or iCloud Drive", systemImage: "folder.badge.gearshape", showsChevron: true) }.buttonStyle(.plain)
                if !FolderBackup.useInternalFolder {
                    NunaDivider()
                    Button { _ = FolderBackup.useNoopFolder(); folder = FolderBackup.folderLabel() } label: { NunaListRow("Use NOOP's own folder", description: "Inside Files > On My iPhone > NOOP", systemImage: "iphone", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            NunaSettingsGroup("Schedule") {
                NunaToggleRow("Daily backup", subtitle: "Once a day when NOOP is opened", systemImage: "calendar.badge.clock", isOn: Binding(get: { auto }, set: { auto = $0; FolderBackup.autoEnabled = $0 })).padding(.vertical, 8)
                NunaDivider()
                NunaStepRow(label: "Keep the last", value: "\(keep)", note: "Older ones are deleted, oldest first", canDecrement: keep > (FolderBackup.keepOptions.first ?? 1),
                            onMinus: { step(-1) }, onPlus: { step(1) })
            }
            if !snapshots.isEmpty {
                NunaSettingsGroup("Saved backups") {
                    ForEach(Array(snapshots.prefix(8).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { NunaDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: s.timeMs > 0 ? Self.date(s.timeMs) : s.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            }
                            Spacer()
                            Button { restoreTarget = s } label: { Text("Restore").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)) }.buttonStyle(.plain)
                        }.padding(.vertical, 12)
                    }
                }
            }
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(NunaPalette.warning)
                    Text("Backups are not encrypted. A folder that syncs to Drive, Dropbox or iCloud keeps a readable file. Choose the folder with care.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            nunaFootnote("Restoring replaces the data on this iPhone. Back up first if you are unsure.")
        }
        .task { snapshots = FolderBackup.listSnapshots() }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) { Button("OK", role: .cancel) {} } message: { Text(verbatim: alert?.message ?? "") }
        .alert("Restore this backup?", isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }), presenting: restoreTarget) { s in
            Button("Replace all data", role: .destructive) { restore(s) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("All current data is replaced by this backup. This cannot be undone.") }
    }

    private func step(_ d: Int) {
        let opts = FolderBackup.keepOptions
        guard let i = opts.firstIndex(of: keep) ?? opts.firstIndex(where: { $0 >= keep }) else { return }
        let n = opts[min(max(i + d, 0), opts.count - 1)]
        keep = n; FolderBackup.keepCount = n
    }

    private func chooseFolder() {
        busy = true
        Task {
            defer { busy = false }
            if await FolderBackup.pickFolder() != nil { folder = FolderBackup.folderLabel() }
            else if !FolderBackup.useInternalFolder { alert = (String(localized: "No folder selected"), String(localized: "NOOP didn't get a folder back from the picker. Use NOOP's own folder to back up inside NOOP instead.")) }
        }
    }

    private func backupNow() {
        busy = true
        Task {
            defer { busy = false }
            let ok = await FolderBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() })
            lastMs = FolderBackup.lastBackupMs; snapshots = FolderBackup.listSnapshots()
            alert = ok ? (String(localized: "Backed up"), String(localized: "Saved a backup to your folder.")) : (String(localized: "Backup problem"), String(localized: "Backup failed. Pick the folder again and try once more."))
        }
    }

    private func restore(_ s: FolderBackup.Snapshot) {
        restoreTarget = nil; busy = true
        Task {
            defer { busy = false }
            let r = await Task.detached(priority: .userInitiated) { FolderBackup.restore(snapshotNamed: s.name) }.value
            switch r {
            case .imported: alert = (String(localized: "Restored"), String(localized: "Fully quit and reopen NOOP to load it."))
            case .failure(let m): alert = (String(localized: "Restore problem"), m)
            default: alert = (String(localized: "Restore problem"), String(localized: "Couldn't restore that backup."))
            }
        }
    }

    private static func date(_ ms: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
#endif
