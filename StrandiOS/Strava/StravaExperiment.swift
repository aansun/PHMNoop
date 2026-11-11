import Foundation

/// Runtime gates for the opt-in Strava integration. Both switches default to OFF: no Strava request is made
/// until the user enables the experiment, connects the account, and chooses manual or automatic upload.
enum StravaExperiment {
    static let enabledKey = "noop.experiment.strava"
    static let automaticUploadKey = "noop.experiment.strava.automaticUpload"
    /// Looking for workouts on Strava that PHMN does not have. On once Strava is connected (connecting is the opt-in); read-only.
    static let autoDetectKey = "noop.experiment.strava.autoDetect"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isAutoDetectEnabled: Bool {
        UserDefaults.standard.object(forKey: autoDetectKey) as? Bool ?? true
    }

    static var isAutomaticUploadEnabled: Bool {
        UserDefaults.standard.bool(forKey: automaticUploadKey)
    }
}
