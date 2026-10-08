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
    @StateObject private var model = StravaSettingsModel()
    @State private var workouts: [WorkoutRow] = []
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var editingCredentials = false

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
                    Text(model.isConfigured ? "Ready to connect" : "Not connected").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
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
                        Text("Connected").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
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
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
