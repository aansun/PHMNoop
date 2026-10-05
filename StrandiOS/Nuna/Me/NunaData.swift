#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Data and integrations (DataHub.dc)

struct NunaDataHubView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(StravaExperiment.enabledKey) private var strava = false

    var body: some View {
        NunaDetailScreen("Data and integrations") {
            Text("Everything stays on this iPhone. Bring your history in once, then it is yours.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaSettingsGroup("Connected") {
                NavigationLink(value: NunaMeRoute.appleHealth) { NunaListRow("Apple Health", subtitle: "Permissions, what is read and written", systemImage: "heart.text.square", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.strava) { NunaListRow("Strava", subtitle: "Upload GPS and treadmill workouts · experimental", systemImage: "figure.run.circle", showsChevron: true) { NunaChip(strava ? "On" : "Off", color: strava ? NunaPalette.charge : nil) } }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Import once") {
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("WHOOP export (.zip)", subtitle: "Recovery, strain, sleep and workouts", systemImage: "doc.zipper", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Apple Health export (.zip)", subtitle: "Years of heart rate, HRV and sleep", systemImage: "heart.text.square", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Nutrition (.csv)", subtitle: "Cronometer or MacroFactor", systemImage: "fork.knife", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Lifting log (Hevy or Liftosaur)", subtitle: "Each workout becomes a strength session", systemImage: "dumbbell", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Workout file (GPX, TCX, FIT)", subtitle: "One workout from another brand", systemImage: "map", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Share out") {
                NavigationLink(value: NunaMeRoute.backup) { NunaListRow("Export data", subtitle: "Every metric as CSV, only when you ask", systemImage: "square.and.arrow.up", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.backup) { NunaListRow("Backup and restore", subtitle: FolderBackup.lastBackupMs > 0 ? LocalizedStringKey(String(localized: "Last \(Self.when(FolderBackup.lastBackupMs))")) : "Not backed up yet", systemImage: "clock.arrow.circlepath", showsChevron: true) }.buttonStyle(.plain)
            }
            nunaFootnote("Deleting an import never touches data recorded live from the strap.")
        }
    }

    static func when(_ ms: Int) -> String {
        let f = RelativeDateTimeFormatter(); f.locale = AppLanguage.activeLocale; f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: Double(ms) / 1000), relativeTo: Date())
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
                Button { chooseFolder() } label: { NunaListRow("Change folder", subtitle: "Pick one in Files or iCloud Drive", systemImage: "folder.badge.gearshape", showsChevron: true) }.buttonStyle(.plain)
                if !FolderBackup.useInternalFolder {
                    NunaDivider()
                    Button { _ = FolderBackup.useNoopFolder(); folder = FolderBackup.folderLabel() } label: { NunaListRow("Use NOOP's own folder", subtitle: "Inside Files > On My iPhone > NOOP", systemImage: "iphone", showsChevron: true) }.buttonStyle(.plain)
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
