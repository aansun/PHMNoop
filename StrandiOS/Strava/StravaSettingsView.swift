import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

/// iOS-only Strava experiment surface. It intentionally lives outside the shared Settings screen so the
/// macOS target remains unchanged. Network access is opt-in, OAuth is explicit, and automatic upload is
/// separately opt-in.
struct StravaSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(StravaExperiment.enabledKey) private var experimentEnabled = false
    @AppStorage(StravaExperiment.automaticUploadKey) private var automaticUpload = false
    @StateObject private var model = StravaSettingsModel()
    @State private var workouts: [WorkoutRow] = []

    private var uploadableWorkouts: [WorkoutRow] {
        workouts.filter { row in
            if StravaActivityType.isTreadmill(row.sport) { return true }
            guard let route = RouteStore.load(startTs: row.startTs, sport: row.sport) else { return false }
            return RouteMath.decode(route.polyline).count >= 2
        }
    }

    private var pendingUploadWorkouts: [WorkoutRow] {
        uploadableWorkouts.filter { model.record(for: $0) == nil }
    }

    var body: some View {
        ScreenScaffold(title: "Strava", subtitle: "Experimental activity uploads",
                       onRefresh: { await loadWorkouts() }, topBackground: liquidScaffoldSky()) {
            experimentCard
            if experimentEnabled {
                connectionCard
                activityCard
            }
        }
        .task(id: "\(experimentEnabled)-\(automaticUpload)") {
            await loadWorkouts()
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
                        .fixedSize(horizontal: false, vertical: true)
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
                        Text("Add STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, and STRAVA_REDIRECT_URI to your local Config/BundleIdSecrets.xcconfig, then rebuild the iOS app.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusWarning)
                            .fixedSize(horizontal: false, vertical: true)
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                        .fixedSize(horizontal: false, vertical: true)
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
            workouts = Array(rows.filter {
                StravaActivityType.isTreadmill($0.sport)
                    || RouteStore.load(startTs: $0.startTs, sport: $0.sport) != nil
            }
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
