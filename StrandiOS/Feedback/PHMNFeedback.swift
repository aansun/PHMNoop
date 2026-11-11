#if os(iOS)
import Foundation
import LuciqSDK

/// The one place the app talks to Luciq (feedback and problem reports). Nothing in the app calls the SDK anywhere else.
///
/// What it is for, and what it is not: it is a way for a person to tell the makers something, from the Feedback page in Settings. So the SDK is started with
/// every automatic way in turned off (no shake, no screenshot, no floating button), every collector that would send something on its own turned off (crash
/// reports, performance, session replay, network logs, steps leading to a report), and its surveys, feature requests and chats left out. A report exists
/// only when the person opens the screen from the Feedback page and sends it.
///
/// It is started when the Feedback page opens, not when the app launches: the SDK asks Luciq's servers for its settings the moment it starts (seen in the
/// network log, even with every collector off), and the app tells its users that nothing leaves the iPhone unless they choose it. So the app makes no
/// contact with Luciq until someone opens that page.
///
/// The application token comes from `LUCIQ_APP_TOKEN` in Info.plist (set by the gitignored `Strand/Luciq/LuciqSecrets.xcconfig`). With no token the SDK is never started
/// and the Feedback page says it is not available in this build.
enum PHMNFeedback {
    private(set) static var started = false

    static var token: String {
        (Bundle.main.object(forInfoDictionaryKey: "LUCIQ_APP_TOKEN") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this build has a feedback channel: a token was given when it was built.
    static var isConfigured: Bool { !token.isEmpty }

    /// Starts the SDK the first time it is needed (the Feedback page calls it as it opens, so Luciq is ready by the time a button is tapped). Without a token this does
    /// nothing at all.
    static func start() {
        guard !started, !token.isEmpty else { return }
        // The switches Luciq asks to be set before it starts.
        CrashReporting.enabled = false
        NetworkLogger.disableAutomaticCapturingOfNetworkLogs()
        Luciq.start(withToken: token, invocationEvents: .none)
        APM.enabled = false
        SessionReplay.enabled = false
        Surveys.enabled = false
        FeatureRequests.enabled = false
        Replies.enabled = false
        Luciq.setReproStepsFor(.all, with: .disable)
        // Only the two reports the Feedback page offers, with a picture from the library as the one thing that can be attached: the screen behind a
        // report is the Feedback page, which has nothing to show, and the person chooses anything else they add.
        BugReporting.promptOptionsEnabledReportTypes = [.bug, .feedback]
        BugReporting.enabledAttachmentTypes = [.galleryImage]
        BugReporting.extendedBugReportMode = .disabled
        started = true
    }

    enum Kind { case feedback, problem }

    /// Opens Luciq's screen for a message, an email being optional so nobody has to give one.
    static func show(_ kind: Kind) {
        guard isConfigured else { return }
        let present = { BugReporting.show(with: kind == .feedback ? .feedback : .bug, options: [.emailFieldOptional]) }
        if started { present(); return }
        // Reached without the page having started it: give the SDK a moment before asking it to show anything.
        start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { present() }
    }
}
#endif
