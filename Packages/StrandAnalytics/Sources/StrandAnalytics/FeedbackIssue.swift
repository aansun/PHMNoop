import Foundation

/// The GitHub issue a person's feedback or problem report starts. The app opens it in the browser with the title and the outline of the body filled in; the
/// person writes the rest and sends it on GitHub, so nothing leaves the phone from the app itself.
///
/// PURE and unit-tested. Only what is needed to reproduce a problem is added (the version of the app, of iOS, the model of the phone and the language), and
/// never a figure from the person's health data. The text is English because an issue is read by the people who maintain the project.
public enum FeedbackIssue {
    public enum Kind: Equatable, Sendable { case feedback, problem }

    /// What the app says about itself and the phone, added to the end of every issue.
    public struct Details: Equatable, Sendable {
        public var app: String
        public var build: String
        public var os: String
        public var device: String
        public var language: String
        public init(app: String, build: String, os: String, device: String, language: String) {
            self.app = app; self.build = build; self.os = os; self.device = device; self.language = language
        }
    }

    /// The outline of the issue: what to write, then the details.
    public static func body(_ kind: Kind, _ d: Details) -> String {
        let details = """
        ## Details (added by the app)

        - App: PHMN \(d.app) (\(d.build))
        - iOS: \(d.os)
        - Device: \(d.device)
        - Language: \(d.language)
        """
        switch kind {
        case .feedback:
            return """
            ## What would you like to tell us?

            <!-- An idea, a request or a word of thanks. -->


            \(details)
            """
        case .problem:
            return """
            ## What happened?

            <!-- What you did and what you saw. -->


            ## What did you expect?


            ## Steps to reproduce

            1.


            ## Strap log (optional)

            <!-- Device Settings > Advanced > Strap log > the copy icon, then paste here. It holds connection and sync events only, never health data. -->


            \(details)
            """
        }
    }

    /// `https://github.com/<repo>/issues/new` with the title, body and label filled in. A label is applied only when the person may label issues on that
    /// repository (GitHub ignores it otherwise), so it is a hint and never a reason for the page to fail.
    public static func url(repo: String, kind: Kind, details: Details) -> URL? {
        var c = URLComponents()
        c.scheme = "https"; c.host = "github.com"; c.path = "/\(repo)/issues/new"
        c.queryItems = [
            URLQueryItem(name: "title", value: kind == .feedback ? "Feedback: " : "Problem: "),
            URLQueryItem(name: "body", value: body(kind, details)),
            URLQueryItem(name: "labels", value: kind == .feedback ? "feedback" : "bug"),
        ]
        // URLComponents leaves "+" as it is in a value, and GitHub reads a bare "+" as a space.
        guard let query = c.percentEncodedQuery else { return nil }
        c.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }
}
