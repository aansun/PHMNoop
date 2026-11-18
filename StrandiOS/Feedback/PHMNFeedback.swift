#if os(iOS)
import Foundation
import UIKit
import StrandAnalytics

/// Where feedback and problem reports go: the project's GitHub Issues. A button on the Feedback page opens a new issue in the browser with the outline already
/// written (see `FeedbackIssue`); the person writes the rest and sends it on GitHub. So the app sends nothing itself, makes no contact with anyone until a
/// button is tapped, and has no service, token or SDK behind it. Writing an issue needs a GitHub account.
enum PHMNFeedback {
    /// The repository the issues go to: the one releases and the update check already use.
    static let repository = "aansun/PHMNoop"

    typealias Kind = FeedbackIssue.Kind

    /// What the app says about itself and the phone: its version and build, iOS, the model of the phone (`iPhone18,3`) and the language.
    static var details: FeedbackIssue.Details {
        var system = utsname()
        uname(&system)
        let model = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        let info = Bundle.main.infoDictionary
        return FeedbackIssue.Details(
            app: (info?["CFBundleShortVersionString"] as? String) ?? "?",
            build: (info?["CFBundleVersion"] as? String) ?? "?",
            os: UIDevice.current.systemVersion, device: model,
            language: Locale.preferredLanguages.first ?? "?")
    }

    /// The new issue for a kind of message, ready to open.
    static func url(_ kind: Kind) -> URL? { FeedbackIssue.url(repo: repository, kind: kind, details: details) }
}
#endif
