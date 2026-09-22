import Foundation
import WhoopStore
#if os(iOS)
import UIKit
#endif

@MainActor
final class StravaSettingsModel: ObservableObject {
    @Published private(set) var isConnected = StravaTokenStore.isConnected
    @Published private(set) var athleteName: String?
    @Published private(set) var records: [StravaUploadRecord] = StravaActivityStore.load()
    @Published private(set) var busy = false
    @Published var statusText: String?

    var isConfigured: Bool { StravaCredentials.fromBundle != nil }

    init() {
        athleteName = StravaTokenStore.load()?.athleteName
    }

    func connect() async {
        guard StravaExperiment.isEnabled else { return }
        guard let credentials = StravaCredentials.fromBundle else {
            statusText = StravaError.notConfigured.localizedDescription
            return
        }
        setBusy(true)
        defer { setBusy(false) }
        do {
            let tokens = try await StravaOAuthProvider(credentials: credentials)
                .authorize(presentationAnchor: stravaPresentationAnchor())
            isConnected = true
            athleteName = tokens.athleteName
            statusText = StravaExperiment.isAutomaticUploadEnabled
                ? String(localized: "Connected to Strava. New GPS workouts will upload automatically.")
                : String(localized: "Connected to Strava. Uploads remain manual.")
        } catch {
            statusText = message(for: error)
        }
    }

    func disconnect() async {
        guard let credentials = StravaCredentials.fromBundle else {
            StravaTokenStore.clear()
            isConnected = false
            athleteName = nil
            return
        }
        setBusy(true)
        defer { setBusy(false) }
        if StravaTokenStore.isConnected {
            try? await StravaAPIClient(credentials: credentials).deauthorize()
        }
        StravaTokenStore.clear()
        isConnected = false
        athleteName = nil
        statusText = String(localized: "Strava disconnected.")
    }

    func upload(_ row: WorkoutRow) async {
        guard StravaExperiment.isEnabled else { return }
        guard isConnected else {
            statusText = StravaError.notConnected.localizedDescription
            return
        }
        guard let route = RouteStore.load(startTs: row.startTs, sport: row.sport),
              RouteMath.decode(route.polyline).count >= 2 else {
            statusText = StravaError.noRoute.localizedDescription
            return
        }
        guard let credentials = StravaCredentials.fromBundle else {
            statusText = StravaError.notConfigured.localizedDescription
            return
        }

        setBusy(true)
        defer { setBusy(false) }
        do {
            let client = StravaAPIClient(credentials: credentials)
            let response = try await client.upload(row: row, route: RouteMath.decode(route.polyline))
            let record = StravaUploadRecord(
                workoutKey: workoutKey(for: row), startTs: row.startTs, sport: row.sport,
                uploadId: response.id, activityId: response.activityId,
                status: response.status ?? "Processing", message: response.message ?? response.error,
                updatedAt: Date())
            StravaActivityStore.save(record)
            records = StravaActivityStore.load()
            if let activityId = response.activityId {
                statusText = "Uploaded to Strava · activity \(activityId)"
            } else {
                statusText = String(localized: "Uploaded to Strava. Strava is processing the activity.")
            }
        } catch {
            statusText = message(for: error)
        }
    }

    func record(for row: WorkoutRow) -> StravaUploadRecord? {
        StravaActivityStore.record(for: workoutKey(for: row))
    }

    static func workoutKey(for row: WorkoutRow) -> String {
        "\(row.startTs)|\(row.sport)"
    }

    private func workoutKey(for row: WorkoutRow) -> String {
        Self.workoutKey(for: row)
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func setBusy(_ value: Bool) {
        busy = value
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = value
        #endif
    }
}
