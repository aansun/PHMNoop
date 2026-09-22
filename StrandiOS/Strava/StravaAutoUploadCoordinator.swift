import WhoopStore

/// Coordinates the optional post-workout upload without adding a background sync loop. It is called only
/// from the iOS app's finished-workout event, and it remains silent when the experiment or automatic mode
/// is disabled. The in-flight key guard also protects against duplicate `lastWorkout` publisher events.
@MainActor
enum StravaAutoUploadCoordinator {
    private static var inFlightKeys = Set<String>()

    static func uploadIfNeeded(_ row: WorkoutRow) async {
        guard StravaExperiment.isEnabled,
              StravaExperiment.isAutomaticUploadEnabled,
              StravaTokenStore.isConnected,
              StravaCredentials.fromBundle != nil else { return }

        let key = StravaSettingsModel.workoutKey(for: row)
        guard StravaActivityStore.record(for: key) == nil,
              inFlightKeys.insert(key).inserted else { return }
        defer { inFlightKeys.remove(key) }

        // Reuse the same validation, FIT rendering, token refresh, upload ledger, and deduplication path as
        // the manual button. Automatic mode changes only who initiates the upload.
        let model = StravaSettingsModel()
        await model.upload(row)
    }
}
