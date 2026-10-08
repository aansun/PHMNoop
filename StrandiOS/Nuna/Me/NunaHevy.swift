#if os(iOS)
import SwiftUI
import StrandDesign
import StrandImport

/// What the Hevy screen does and says. Imports run one at a time, on a button, and can be stopped; nothing runs in the background.
@MainActor
final class NunaHevyModel: ObservableObject {
    enum Job { case history, routines }

    @Published private(set) var connected = HevyKeyStore.hasKey
    @Published private(set) var userName = UserDefaults.standard.string(forKey: "nuna.hevy.userName")
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var error: String?
    @Published private(set) var result: (job: Job, summary: HevyImportSummary)?
    private var task: Task<Void, Never>?

    private func client() -> HevyClient? {
        HevyKeyStore.read().map { HevyClient(apiKey: $0, transport: HevyTransport.live()) }
    }

    func message(for failure: Error) -> String {
        switch failure as? HevyClient.Failure {
        case .unauthorized?: return String(localized: "Hevy refused the key. Check that it is typed right, that it has not been revoked, and that the account has API access (Hevy Pro).")
        case .rateLimited?: return String(localized: "Hevy asked to slow down. Wait a minute and try again.")
        case .http(let code)?: return String(localized: "Hevy answered with an error (\(code)). Try again later.")
        case .network?: return String(localized: "Could not reach Hevy. Check the connection and try again.")
        case .cancelled?: return String(localized: "Stopped.")
        case nil: return failure.localizedDescription
        }
    }

    /// Keep the key and check it is real: a wrong key fails here with a clear message, not as an empty history later.
    func connect(key: String) {
        guard !busy else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true; error = nil; result = nil; status = String(localized: "Checking the key…")
        task = Task {
            defer { busy = false; status = nil }
            do {
                let info = try await HevyClient(apiKey: trimmed, transport: HevyTransport.live()).userInfo()
                guard HevyKeyStore.save(trimmed) else { error = String(localized: "The Keychain would not keep the key."); return }
                connected = true
                userName = info?.name
                UserDefaults.standard.set(info?.name, forKey: "nuna.hevy.userName")
            } catch {
                self.error = message(for: error)
            }
        }
    }

    func disconnect() {
        task?.cancel()
        HevyKeyStore.clear()
        UserDefaults.standard.removeObject(forKey: "nuna.hevy.userName")
        connected = false; userName = nil; result = nil; error = nil; status = nil; busy = false
    }

    func cancel() { task?.cancel() }

    func run(_ job: Job, repo: Repository) {
        guard !busy, let client = client() else { return }
        busy = true; error = nil; result = nil; status = String(localized: "Starting…")
        task = Task {
            defer { busy = false; status = nil }
            let progress: @Sendable (String) -> Void = { text in Task { @MainActor in self.status = text } }
            do {
                let summary = job == .history
                    ? try await HevyImporter.importHistory(client: client, repo: repo, progress: progress)
                    : try await HevyImporter.importRoutines(client: client, repo: repo, progress: progress)
                result = (job, summary)
            } catch {
                self.error = message(for: error)
                // A key Hevy no longer accepts is not worth keeping.
                if (error as? HevyClient.Failure) == .unauthorized { connected = HevyKeyStore.hasKey }
            }
        }
    }
}

/// Hevy (HevyConnect): your own API key in the Keychain, then two buttons, one for the workout history and one for the routines. Read only.
struct NunaHevyView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(HevyExperiment.enabledKey) private var enabled = false
    @StateObject private var model = NunaHevyModel()
    @State private var key = ""

    var body: some View {
        NunaDetailScreen("Hevy", trailing: AnyView(NunaChip("Experimental"))) {
            NunaCard(highlight: enabled) {
                NunaToggleRow("Enable Hevy", subtitle: "Off by default. While it is off, no request is made to Hevy", systemImage: "dumbbell", isOn: $enabled).padding(.vertical, 8)
            }
            if !enabled { needs } else if !model.connected { setup } else { connected }
            if let s = model.status { HStack(spacing: 10) { ProgressView().tint(NunaPalette.textSecondary); Text(verbatim: s).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } }
            if let e = model.error { Text(verbatim: e).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil) }
            if let r = model.result { resultCard(r.job, r.summary) }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Off

    private var needs: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaSettingsGroup("What you need") {
                NunaListRow("Hevy with API access", description: "The API is part of Hevy Pro", systemImage: "person.crop.circle")
                NunaDivider()
                NunaListRow("Your own API key", description: "Made in Hevy, in its developer settings", systemImage: "key")
            }
            nunaFootnote("PHMN only reads from Hevy: your workouts and your routines. Nothing is written to Hevy, and nothing happens unless you tap an import button.")
        }
    }

    // MARK: Key

    private var setup: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    nunaTrendsCap("API key")
                    Text("Paste the key you made in Hevy. It is kept in this iPhone's Keychain and sent only to Hevy, to read your data.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NunaFormField("Key") {
                        SecureField("", text: $key, prompt: Text("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    let empty = key.trimmingCharacters(in: .whitespaces).isEmpty
                    Button { model.connect(key: key); key = "" } label: {
                        Text("Connect").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.busy || empty).opacity(model.busy || empty ? 0.4 : 1)
                    Text("Never shown again after it is saved").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
            }
            NunaSettingsGroup("Where to find it") {
                step(1, "Open Hevy and go to its settings.")
                NunaDivider()
                step(2, "Open the developer or API section and create a key.")
                NunaDivider()
                step(3, "Copy it here, then tap Connect.")
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30)
            Text(text).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            Spacer(minLength: 0)
        }.padding(.vertical, 12)
    }

    // MARK: Connected

    private var connected: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.nuna(size: 22)).foregroundStyle(NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        if let n = model.userName { Text(verbatim: n).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }
                    Spacer()
                    Button { model.disconnect() } label: {
                        Text("Disconnect").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.busy)
                }
            }
            NunaSettingsGroup("Import") {
                importRow("Workout history", "Every set of every workout, as gym sessions", "clock.arrow.circlepath", .history)
                NunaDivider()
                importRow("Routines", "As programs, with Hevy's folders as groups", "list.bullet.rectangle", .routines)
            }
            if model.busy {
                Button { model.cancel() } label: {
                    Text("Stop").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            nunaFootnote("Importing again updates what came from Hevy and leaves what you logged here alone. A workout you already have at the same moment is kept as it is. Disconnect removes the key from this iPhone; what was imported stays.")
        }
    }

    private func importRow(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String, _ job: NunaHevyModel.Job) -> some View {
        Button { model.run(job, repo: repo) } label: {
            NunaListRow(title, description: subtitle, systemImage: icon, showsChevron: true)
        }.buttonStyle(.plain).disabled(model.busy).opacity(model.busy ? 0.5 : 1)
    }

    // MARK: Result

    private func resultCard(_ job: NunaHevyModel.Job, _ s: HevyImportSummary) -> some View {
        var lines: [String] = []
        let total = s.added + s.updated
        if total == 0 && s.alreadyHere == 0 {
            lines.append(job == .history ? String(localized: "No workouts found in Hevy.") : String(localized: "No routines found in Hevy."))
        } else {
            if job == .history {
                lines.append(s.added == 1 ? String(localized: "Added 1 workout") : String(localized: "Added \(s.added) workouts"))
                if s.sets > 0 { lines.append(String(localized: "\(s.sets) sets")) }
                if let a = s.first, let b = s.last {
                    let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
                    let lo = f.string(from: a), hi = f.string(from: b)
                    lines.append(lo == hi ? lo : "\(lo) – \(hi)")
                }
            } else {
                lines.append(s.added == 1 ? String(localized: "Added 1 program") : String(localized: "Added \(s.added) programs"))
                if s.groups > 0 { lines.append(s.groups == 1 ? String(localized: "1 group") : String(localized: "\(s.groups) groups")) }
            }
            if s.updated > 0 { lines.append(String(localized: "\(s.updated) updated")) }
            if s.alreadyHere > 0 { lines.append(String(localized: "\(s.alreadyHere) already here")) }
        }
        if s.skipped > 0 { lines.append(String(localized: "\(s.skipped) could not be read")) }
        return NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 8) {
                nunaTrendsCap("Done")
                Text(verbatim: lines.joined(separator: " · ")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if s.vocabularyFull {
                    Text("The list of remembered exercises is full, so some exercises were not classified by muscle.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
