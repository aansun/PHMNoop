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
                ? String(localized: "Connected to Strava. New GPS and treadmill workouts will upload automatically.")
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
        let storedRoute = RouteStore.load(startTs: row.startTs, sport: row.sport)
        let route = storedRoute.map { RouteMath.decode($0.polyline) } ?? []
        guard route.count >= 2 || StravaActivityType.isTreadmill(row.sport) else {
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
            let initialResponse = try await client.upload(
                row: row,
                route: route,
                elevationGainM: storedRoute?.elevationGainM)
            let response = try await client.waitForUploadCompletion(initialResponse)
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

    /// Reconciles only the recent local upload ledger with Strava. A successful match keeps the
    /// activity hidden from the upload list; a previously completed ledger entry missing remotely is
    /// removed so the workout becomes uploadable again after the user deletes it on Strava.
    func reconcileRecentUploads(rows: [WorkoutRow]) async {
        guard StravaExperiment.isEnabled, isConnected,
              let credentials = StravaCredentials.fromBundle else { return }

        let now = Int(Date().timeIntervalSince1970)
        let cutoff = now - 7 * 86_400
        let recentRows = rows.filter { $0.startTs >= cutoff && $0.startTs <= now + 86_400 }

        setBusy(true)
        do {
            let client = StravaAPIClient(credentials: credentials)
            let remote = try await client.recentActivities(after: cutoff, before: now + 86_400)

            // Rebuild a missing local ledger entry from our stable external id. This covers a
            // reinstall or a cleared UserDefaults ledger without creating a duplicate in Strava.
            for row in recentRows where record(for: row) == nil {
                guard let match = Self.remoteActivity(for: workoutKey(for: row), in: remote) else { continue }
                StravaActivityStore.save(StravaUploadRecord(
                    workoutKey: workoutKey(for: row), startTs: row.startTs, sport: row.sport,
                    uploadId: nil, activityId: match.id, status: "Uploaded", message: nil, updatedAt: Date()))
            }

            var local = StravaActivityStore.load().filter { $0.startTs >= cutoff }
            let processingGraceCutoff = Date().addingTimeInterval(-15 * 60)

            var missingKeys = Set<String>()
            for record in local where record.activityId == nil && record.uploadId != nil {
                // The activity feed can lag behind the upload endpoint. Ask Strava directly for
                // every still-processing upload so a completed activity is not left in Processing.
                guard let uploadId = record.uploadId else { continue }
                if let upload = try? await client.uploadStatus(uploadId: uploadId) {
                    if upload.activityId != nil || upload.error != nil || upload.message != nil {
                        var updated = record
                        updated.activityId = upload.activityId
                        updated.status = upload.status ?? (upload.activityId == nil ? "Processing" : "Uploaded")
                        updated.message = upload.message ?? upload.error
                        updated.updatedAt = Date()
                        StravaActivityStore.save(updated)
                        if upload.error != nil {
                            missingKeys.insert(record.workoutKey)
                        }
                    }
                }
            }
            local = StravaActivityStore.load().filter { $0.startTs >= cutoff }
            for record in local {
                let match = remote.first { activity in
                    if let activityId = record.activityId, activity.id == activityId { return true }
                    guard let externalId = activity.externalId else { return false }
                    return Self.externalIDMatches(externalId, workoutKey: record.workoutKey)
                }

                if let match {
                    var updated = record
                    updated.activityId = match.id ?? record.activityId
                    updated.status = "Uploaded"
                    updated.message = nil
                    updated.updatedAt = Date()
                    StravaActivityStore.save(updated)
                } else if record.activityId == nil && record.uploadId != nil {
                    // The upload endpoint still owns this record. It may not be visible in the
                    // athlete feed yet, so keep it until that endpoint reports a terminal result.
                    if !missingKeys.contains(record.workoutKey) { continue }
                } else if record.updatedAt < processingGraceCutoff {
                    // Completed records that disappeared from Strava are eligible for re-upload.
                    missingKeys.insert(record.workoutKey)
                }
            }
            StravaActivityStore.remove(workoutKeys: missingKeys)
            records = StravaActivityStore.load()
            setBusy(false)

            // Automatic mode also handles a recent activity that was deleted remotely.
            if StravaExperiment.isAutomaticUploadEnabled {
                for row in recentRows where record(for: row) == nil {
                    await upload(row)
                }
            }
        } catch let error as StravaError {
            setBusy(false)
            if case .server(let status, _) = error, status == 401 || status == 403 {
                statusText = StravaError.readAccessRequired.localizedDescription
            } else {
                statusText = message(for: error)
            }
        } catch {
            setBusy(false)
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

    private static func externalIDMatches(_ value: String, workoutKey: String) -> Bool {
        let expected = externalID(for: workoutKey)
        return value == expected || value == "\(expected).fit"
    }

    private static func externalID(for workoutKey: String) -> String {
        "noop-\(workoutKey.replacingOccurrences(of: "|", with: "-"))"
    }

    private static func remoteActivity(for workoutKey: String,
                                       in activities: [StravaActivitySummary]) -> StravaActivitySummary? {
        activities.first { activity in
            guard let externalID = activity.externalId else { return false }
            return externalIDMatches(externalID, workoutKey: workoutKey)
        }
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
