import Foundation

/// Runtime gates for the opt-in Strava integration. Both switches default to OFF: no Strava request is made
/// until the user enables the experiment, connects the account, and chooses manual or automatic upload.
enum StravaExperiment {
    static let enabledKey = "noop.experiment.strava"
    static let automaticUploadKey = "noop.experiment.strava.automaticUpload"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isAutomaticUploadEnabled: Bool {
        UserDefaults.standard.bool(forKey: automaticUploadKey)
    }
}
