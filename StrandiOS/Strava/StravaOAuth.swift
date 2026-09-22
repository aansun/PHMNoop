import Foundation

/// The user's own Strava OAuth application credentials. Values are injected into the iOS Info.plist
/// from the ignored `Config/BundleIdSecrets.xcconfig`; the client secret never belongs in source control.
struct StravaCredentials: Equatable {
    let clientId: String
    let clientSecret: String
    let redirectURI: String

    static func from(_ info: [String: Any]) -> StravaCredentials? {
        func nonBlank(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("$("), !value.hasPrefix("your_") else { return nil }
            return value
        }
        guard let id = nonBlank("STRAVA_CLIENT_ID"),
              let secret = nonBlank("STRAVA_CLIENT_SECRET"),
              let redirect = nonBlank("STRAVA_REDIRECT_URI") else { return nil }
        return StravaCredentials(clientId: id, clientSecret: secret, redirectURI: redirect)
    }

    static var fromBundle: StravaCredentials? {
        from(Bundle.main.infoDictionary ?? [:])
    }
}

struct StravaTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let athleteId: Int?
    let athleteName: String?
    let scope: String

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

enum StravaError: LocalizedError {
    case notConfigured
    case notConnected
    case cancelled
    case authentication(String)
    case tokenExchange(String)
    case network(String)
    case server(status: Int, detail: String)
    case noRoute
    case invalidUpload

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Strava API credentials are not configured for this build.")
        case .notConnected:
            return String(localized: "Connect Strava before uploading an activity.")
        case .cancelled:
            return String(localized: "Strava sign-in was cancelled.")
        case .authentication(let message), .tokenExchange(let message), .network(let message):
            return message
        case .server(let status, let detail):
            if detail.isEmpty { return "Strava returned HTTP \(status)." }
            return "Strava returned HTTP \(status): \(detail)"
        case .noRoute:
            return String(localized: "This workout has no GPS route. Strava upload requires a route file.")
        case .invalidUpload:
            return String(localized: "Strava did not return a valid upload identifier.")
        }
    }
}

enum StravaOAuth {
    static let authorizeEndpoint = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    static let tokenEndpoint = URL(string: "https://www.strava.com/oauth/token")!
    static let deauthorizeEndpoint = URL(string: "https://www.strava.com/oauth/deauthorize")!
    static let apiBase = URL(string: "https://www.strava.com/api/v3")!
    static let scopes = ["activity:write"]

    static func authorizeURL(credentials: StravaCredentials, state: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: credentials.clientId),
            .init(name: "redirect_uri", value: credentials.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: scopes.joined(separator: ",")),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    static func tokenExchangeRequest(credentials: StravaCredentials, code: String) -> URLRequest {
        formRequest(tokenEndpoint, fields: [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ])
    }

    static func refreshRequest(credentials: StravaCredentials, refreshToken: String) -> URLRequest {
        formRequest(tokenEndpoint, fields: [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    static func deauthorizeRequest(accessToken: String) -> URLRequest {
        formRequest(deauthorizeEndpoint, fields: ["access_token": accessToken])
    }

    static func parseTokenResponse(_ data: Data, now: Date = Date()) throws -> StravaTokens {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = object["refresh_token"] as? String, !refresh.isEmpty else {
            throw StravaError.tokenExchange(String(data: data, encoding: .utf8) ?? "Invalid token response")
        }

        let expiresAt: Date
        if let epoch = object["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = object["expires_at"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(epoch))
        } else if let seconds = object["expires_in"] as? Double {
            expiresAt = now.addingTimeInterval(seconds)
        } else {
            expiresAt = now
        }

        let athlete = object["athlete"] as? [String: Any]
        let athleteId = (athlete?["id"] as? Int) ?? (athlete?["id"] as? NSNumber)?.intValue
        let first = athlete?["firstname"] as? String
        let last = athlete?["lastname"] as? String
        let name = [first, last].compactMap { $0 }.joined(separator: " ")
        let scope = object["scope"] as? String ?? ""
        return StravaTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                            athleteId: athleteId, athleteName: name.isEmpty ? nil : name, scope: scope)
    }

    private static func formRequest(_ url: URL, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        request.httpBody = fields.map { field in "\(encode(field.key))=\(encode(field.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}
