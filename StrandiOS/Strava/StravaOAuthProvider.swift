import Foundation
import AuthenticationServices
import UIKit

/// iOS-only interactive OAuth provider for Strava. The user remains in control: this is called only by
/// the explicit Connect action in the experimental settings screen.
@MainActor
final class StravaOAuthProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let credentials: StravaCredentials
    private let session: URLSession
    private var presentation: ASPresentationAnchor?
    private var webSession: ASWebAuthenticationSession?

    init(credentials: StravaCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func authorize(presentationAnchor: ASPresentationAnchor) async throws -> StravaTokens {
        presentation = presentationAnchor
        let state = UUID().uuidString
        let scheme = URL(string: credentials.redirectURI)?.scheme ?? "noop"
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(
                url: StravaOAuth.authorizeURL(credentials: credentials, state: state),
                callbackURLScheme: scheme) { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else if let error, (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: StravaError.cancelled)
                    } else {
                        continuation.resume(throwing: StravaError.authentication(error?.localizedDescription ?? "Authentication failed"))
                    }
                }
            webSession = auth
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            if !auth.start() {
                continuation.resume(throwing: StravaError.authentication("Could not start Strava sign-in"))
            }
        }
        webSession = nil

        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw StravaError.authentication("Invalid Strava callback")
        }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard query["state"] == state else { throw StravaError.authentication("Strava state mismatch") }
        guard let code = query["code"], !code.isEmpty else {
            throw StravaError.authentication(query["error"] ?? "Strava did not return an authorization code")
        }

        let request = StravaOAuth.tokenExchangeRequest(credentials: credentials, code: code)
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, data: data)
            let tokens = try StravaOAuth.parseTokenResponse(data)
            guard StravaTokenStore.save(tokens) else { throw StravaError.tokenExchange("Could not save Strava tokens to Keychain") }
            return tokens
        } catch let error as StravaError {
            throw error
        } catch {
            throw StravaError.network(error.localizedDescription)
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentation ?? ASPresentationAnchor()
    }

    nonisolated static func validate(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw StravaError.server(status: status, detail: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

@MainActor
func stravaPresentationAnchor() -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
}
