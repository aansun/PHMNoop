#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import WhoopStore

/// Strava (Strava.dc, StravaSetup.dc, StravaConnected.dc): off, set up, then connected with the activities waiting and
/// uploaded. Uses the same model, credentials (Keychain) and uploader as the Default screen; nothing is requested from
/// Strava while the integration is off.
struct NunaStravaView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(StravaExperiment.enabledKey) private var enabled = false
    @AppStorage(StravaExperiment.automaticUploadKey) private var automatic = false
    @AppStorage(StravaExperiment.autoDetectKey) private var detectFromStrava = true
    @StateObject private var model = StravaSettingsModel()
    @State private var workouts: [WorkoutRow] = []
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var editingCredentials = false
    @State private var importDays = 30

    private var uploadable: [WorkoutRow] {
        workouts.filter { StravaEligibility.canUpload($0) }
    }
    private var pending: [WorkoutRow] { uploadable.filter { model.record(for: $0) == nil } }
    private var done: [WorkoutRow] { uploadable.filter { model.record(for: $0)?.isComplete == true } }

    var body: some View {
        NunaDetailScreen("Strava", trailing: AnyView(NunaChip("Experimental"))) {
            NunaCard(highlight: enabled) {
                NunaToggleRow("Enable Strava", subtitle: "Off by default. While it is off, no request is made to Strava", systemImage: "figure.run.circle", isOn: $enabled).padding(.vertical, 8)
            }
            if !enabled { needs } else if !model.isConnected { setup } else { connected }
            if let s = model.statusText { Text(verbatim: s).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(enabled)") { await load() }
        .onAppear { clientID = model.savedClientID; clientSecret = model.savedClientSecret }
    }

    // MARK: Off

    private var needs: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaSettingsGroup("What you need") {
                NunaListRow("A Strava account", description: "With access to My API Application", systemImage: "person.crop.circle")
                NunaDivider()
                NunaListRow("Your own API app", description: "A Client ID and Client Secret from Strava", systemImage: "key")
                NunaDivider()
                NunaListRow("A GPS, treadmill or gym workout", subtitle: "Gym counts only when logged in PHMN, not from Hevy or Apple Health", systemImage: "figure.run")
            }
            nunaFootnote("NOOP uses your own Strava API app. The Client ID and Secret are kept in this iPhone's Keychain and used only when you connect or upload. The activity goes to Strava as a FIT file.")
        }
    }

    // MARK: Set up and connect

    private var setup: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    nunaTrendsCap("API credentials")
                    Text("Create your Strava API app, then fill in its Client ID and Client Secret. Both are kept in the Keychain.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NunaFormField("Client ID") { TextField("", text: $clientID, prompt: Text("123456").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numberPad).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    NunaFormField("Client Secret") { SecureField("", text: $clientSecret, prompt: Text("••••••••••••••••").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    HStack(spacing: 10) {
                        Button { _ = model.saveCredentials(clientID: clientID, clientSecret: clientSecret) } label: {
                            Text("Save credentials").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain).disabled(model.busy || clientID.trimmingCharacters(in: .whitespaces).isEmpty || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(clientID.trimmingCharacters(in: .whitespaces).isEmpty || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                        if model.isConfigured {
                            Button { model.clearCredentials(); clientID = ""; clientSecret = "" } label: {
                                Text("Clear").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 20).frame(height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Never shown again after it is saved").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
            }
            NunaSettingsGroup("How to set up the Strava app") {
                stepRow(1, "Open Strava > Settings > My API Application.")
                NunaDivider()
                stepRow(2, "Copy the Client ID and Client Secret into the fields above.")
                NunaDivider()
                stepRow(3, "Set the Authorization Callback Domain to localhost.")
                NunaDivider()
                stepRow(4, "Save here, then tap Connect Strava.")
            }
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 8) {
                    nunaTrendsCap("Callback URI")
                    HStack {
                        Text(verbatim: StravaCredentials.redirectURI).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(NunaPalette.textPrimary).textSelection(.enabled)
                        Spacer()
                        Button { UIPasteboard.general.string = StravaCredentials.redirectURI; model.statusText = String(localized: "Callback URI copied.") } label: {
                            Text("Copy").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    Text("Permissions asked for: activity:write and activity:read_all.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("Connection")
                    Text(model.isConfigured ? "Ready to connect" : "Not connected").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    if !model.isConfigured { Text("Save the credentials first").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    Button { Task { await model.connect() } } label: {
                        Text("Connect Strava").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.busy || !model.isConfigured).opacity(model.isConfigured ? 1 : 0.4)
                }
            }
        }
    }

    // MARK: Connected

    private var connected: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard(highlight: true) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connected").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: model.athleteName.map { "Strava · \($0)" } ?? "Strava").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    Button { Task { await model.disconnect() } } label: {
                        Text("Disconnect").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 38).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.busy)
                }
            }
            NunaCard(small: true) {
                NunaToggleRow("Upload automatically", subtitle: "New GPS, treadmill and gym workouts are uploaded when they finish", systemImage: "arrow.up.circle", isOn: $automatic).padding(.vertical, 8)
            }
            NunaCard(small: true) {
                NunaToggleRow("Find workouts on Strava", subtitle: "A workout on Strava that PHMN does not have, and the strap has heart rate for, shows in Today's activities to process", systemImage: "arrow.down.circle", isOn: $detectFromStrava).padding(.vertical, 8)
            }
            importCard
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("Waiting to upload")
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        if pending.isEmpty { Text(uploadable.isEmpty ? "No GPS, treadmill or gym workouts yet." : "Everything recent is already on Strava.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16) }
                        ForEach(Array(pending.enumerated()), id: \.element.startTs) { i, r in
                            if i > 0 { NunaDivider() }
                            row(r) {
                                Button { Task { await model.upload(r) } } label: {
                                    Text("Upload").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 16).frame(height: 34).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                                }.buttonStyle(.plain).disabled(model.busy)
                            }
                        }
                    }
                }
            }
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("Already uploaded")
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(done.prefix(8).enumerated()), id: \.element.startTs) { i, r in
                                if i > 0 { NunaDivider() }
                                row(r) { NunaChip("Uploaded", color: NunaPalette.charge) }
                            }
                        }
                    }
                }
            }
            nunaFootnote("Uploaded as FIT files: GPS and treadmill workouts, and gym sessions you logged in PHMN. Gym data from Hevy or Apple Health, and sports without GPS, are not included. Nothing is uploaded while the integration is off.")
        }
    }

    /// The way in from Strava: workouts done with another app and shared there, such as Hevy. Only those the strap has heart rate for come in.
    private var importCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader("Import from Strava")
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Bring in workouts you logged in another app and shared to Strava, such as Hevy. Only those the strap recorded heart rate for come in, and Effort comes from the strap, never from Strava.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    HStack(spacing: 8) {
                        ForEach([7, 30, 90], id: \.self) { d in
                            Button { importDays = d } label: {
                                Text("Last \(d) days").font(.nuna(size: 13, weight: .bold)).foregroundStyle(importDays == d ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(importDays == d ? NunaPalette.textPrimary : NunaPalette.glassStrong, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { Task { await model.importFromStrava(days: importDays, repo: repo) } } label: {
                        Text(model.busy ? "Importing…" : "Import workouts").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.busy).opacity(model.busy ? 0.5 : 1)
                    if let r = model.importSummary {
                        Text(verbatim: String(localized: "Added \(r.added) · already here \(r.alreadyHere) · no strap heart rate \(r.noHeartRate)"))
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row<Trailing: View>(_ r: WorkoutRow, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            NunaIconTile(sportSymbol(r.sport))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: WorkoutSource.displaySport(r.sport)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: NunaWorkoutFormat.day(r.startTs) + " · " + NunaWorkoutFormat.clock(r.startTs)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 6)
            trailing()
        }.padding(.vertical, 12)
    }

    private func stepRow(_ n: Int, _ t: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30)
            Text(t).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            Spacer(minLength: 0)
        }.padding(.vertical, 12)
    }

    private func load() async {
        guard enabled else { return }
        let rows = await repo.workoutRows(days: 4000)
        workouts = Array(rows.filter { StravaEligibility.canUpload($0) }.sorted { $0.startTs > $1.startTs }.prefix(50))
        await model.reconcileRecentUploads(rows: rows)
    }
}
#endif
