import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore
#if os(iOS)
import UIKit
#endif

/// iOS-only Strava experiment surface. It intentionally lives outside the shared Settings screen so the
/// macOS target remains unchanged. Network access is opt-in, OAuth is explicit, and automatic upload is
/// separately opt-in.
struct StravaSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(StravaExperiment.enabledKey) private var experimentEnabled = false
    @AppStorage(StravaExperiment.automaticUploadKey) private var automaticUpload = false
    @StateObject private var model = StravaSettingsModel()
    @State private var workouts: [WorkoutRow] = []
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var credentialsExpanded = false

    private var uploadableWorkouts: [WorkoutRow] {
        workouts.filter { StravaEligibility.canUpload($0) }
    }

    private var pendingUploadWorkouts: [WorkoutRow] {
        uploadableWorkouts.filter { model.record(for: $0) == nil }
    }

    var body: some View {
        ScreenScaffold(title: "Strava", subtitle: "Experimental activity uploads",
                       onRefresh: { await loadWorkouts() }, topBackground: liquidScaffoldSky()) {
            experimentCard
            if experimentEnabled {
                credentialsCard
                connectionCard
                activityCard
            }
        }
        .task(id: "\(experimentEnabled)-\(automaticUpload)") {
            await loadWorkouts()
        }
        .onAppear {
            clientID = model.savedClientID
            clientSecret = model.savedClientSecret
        }
    }

    private var experimentCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Strava integration", overline: "Experimental")
            NoopCard(tint: StrandPalette.metricRose) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable Strava integration", isOn: $experimentEnabled)
                        .tint(StrandPalette.accent)
                    Text(experimentEnabled
                         ? "When enabled, NOOP can connect to Strava and upload workouts manually or automatically."
                         : "Off by default. No Strava request is made while this experiment is disabled.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Connection", overline: "Strava account")
            NoopCard(tint: model.isConnected ? StrandPalette.statusPositive : StrandPalette.metricRose) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: model.isConnected ? "checkmark.circle.fill" : "link")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(model.isConnected ? StrandPalette.statusPositive : StrandPalette.metricRose)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.isConnected ? "Connected" : "Not connected")
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(model.athleteName.map { "Strava · \($0)" } ?? "OAuth scope: activity:write + activity:read_all")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    if !model.isConfigured {
                        Text("Save the Client ID and Client Secret above before connecting.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusWarning)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }

                    HStack(spacing: 10) {
                        Button(model.isConnected ? "Connected" : "Connect Strava") {
                            Task { await model.connect() }
                        }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        .disabled(model.busy || model.isConnected || !model.isConfigured)

                        if model.isConnected {
                            Button("Disconnect") {
                                Task { await model.disconnect() }
                            }
                            .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                            .disabled(model.busy)
                        }
                    }
                    if let status = model.statusText {
                        Text(status)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Strava API", overline: "Bring your own Strava app")
            NoopCard(tint: StrandPalette.accent) {
                DisclosureGroup(isExpanded: $credentialsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Create your own Strava API app, then enter its Client ID and Client Secret here. NOOP keeps both values in Apple Keychain and uses them only for the explicit Strava connection.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)

                        TextField("Client ID", text: $clientID)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .tint(StrandPalette.accent)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(StrandPalette.hairline, lineWidth: 1))
                            .disabled(model.isConnected || model.busy)

                        SecureField("Client Secret", text: $clientSecret)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .tint(StrandPalette.accent)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(StrandPalette.hairline, lineWidth: 1))
                            .disabled(model.isConnected || model.busy)

                        HStack(spacing: 10) {
                            Button("Save credentials") {
                                _ = model.saveCredentials(clientID: clientID, clientSecret: clientSecret)
                            }
                            .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                            .disabled(model.isConnected || model.busy || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if model.isConfigured {
                                Button("Clear") {
                                    model.clearCredentials()
                                    clientID = ""
                                    clientSecret = ""
                                }
                                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: false))
                                .disabled(model.isConnected || model.busy)
                            }
                        }

                        Divider().overlay(StrandPalette.hairline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Strava app setup")
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("1. Open Strava → Settings → My API Application.")
                            Text("2. Copy Client ID and Client Secret into the fields above.")
                            Text("3. Set Authorization Callback Domain to localhost.")
                            Text("4. Save here, then tap Connect Strava.")
                        }
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Callback URI")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(StravaCredentials.redirectURI)
                                    .font(StrandFont.footnote.monospaced())
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button("Copy") {
                                    #if os(iOS)
                                    UIPasteboard.general.string = StravaCredentials.redirectURI
                                    #endif
                                    model.statusText = String(localized: "Callback URI copied.")
                                }
                                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: false))
                            }
                            Text("Requested permissions: activity:write and activity:read_all")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("API credentials")
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(model.isConfigured ? "Saved securely in Keychain" : "Not configured")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .tint(StrandPalette.accent)
            }
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Activities", overline: automaticUpload ? "Automatic upload" : "Manual upload")
            NoopCard(tint: StrandPalette.effortColor) {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Automatic upload", isOn: $automaticUpload)
                        .tint(StrandPalette.accent)
                        .padding(.bottom, 10)
                    Text(automaticUpload
                         ? "New GPS and treadmill workouts are uploaded after they finish. Connect Strava first; uploads are never sent while the experiment is disabled."
                         : "GPS workouts and treadmill sessions can be uploaded as FIT activities. Tap Upload for each activity.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                        .padding(.bottom, 14)

                    if pendingUploadWorkouts.isEmpty {
                        Text(uploadableWorkouts.isEmpty
                             ? "No GPS or treadmill workouts are available yet."
                             : "All recent GPS and treadmill workouts are already synced to Strava.")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(pendingUploadWorkouts, id: \.startTs) { row in
                            activityRow(row)
                            if row.startTs != pendingUploadWorkouts.last?.startTs {
                                Divider().overlay(StrandPalette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ row: WorkoutRow) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: sportSymbol(row.sport))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StrandPalette.effortColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(WorkoutSource.displaySport(row.sport))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(activityDate(row.startTs))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Upload") {
                Task { await model.upload(row) }
            }
            .buttonStyle(NoopButtonStyle(.secondary, fullWidth: false))
            .disabled(model.busy || !model.isConnected)
        }
        .padding(.vertical, 11)
    }

    private func loadWorkouts() async {
        let rows = await repo.workoutRows(days: 4000)
        await MainActor.run {
            workouts = Array(rows.filter { StravaEligibility.canUpload($0) }
                .sorted { $0.startTs > $1.startTs }.prefix(50))
        }
        await model.reconcileRecentUploads(rows: rows)
    }

    private func activityDate(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

#if DEBUG
#Preview("Strava") {
    NavigationStack { StravaSettingsView() }
        .environmentObject(Repository(deviceId: "preview"))
        .preferredColorScheme(.dark)
}
#endif
