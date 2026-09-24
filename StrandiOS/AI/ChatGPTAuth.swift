#if os(iOS)
import Foundation
import Combine
import Security
import SwiftUI
import UIKit
import StrandDesign

/// Tokens returned by the ChatGPT device-auth flow.
///
/// This is deliberately separate from `AIKeyStore`: an OAuth refresh token is not an API key and
/// must never be sent to an arbitrary provider selected in the Coach picker.
struct ChatGPTTokens: Codable, Sendable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let accountID: String?
}

struct ChatGPTDeviceCode: Sendable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval
    let verificationURL: URL
}

enum ChatGPTAuthError: LocalizedError {
    case network(String)
    case server(Int, String)
    case invalidResponse
    case pendingTimeout
    case cancelled
    case notConnected
    case refreshRejected
    case keychain
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .network(let detail):
            return "ChatGPT tidak dapat dihubungi. Periksa koneksi internet dan coba lagi.\(detail.isEmpty ? "" : " (\(detail))")"
        case .server(let status, let detail):
            return detail.isEmpty
                ? "Login ChatGPT gagal (HTTP \(status)). Coba lagi."
                : "Login ChatGPT gagal: \(detail)"
        case .invalidResponse:
            return "Respons login ChatGPT tidak valid. Coba mulai login lagi."
        case .pendingTimeout:
            return "Persetujuan login belum diterima. Buka halaman device lalu coba lagi."
        case .cancelled:
            return "Login ChatGPT dibatalkan."
        case .notConnected:
            return "Hubungkan ChatGPT terlebih dahulu."
        case .refreshRejected:
            return "Sesi ChatGPT kedaluwarsa. Hubungkan kembali untuk melanjutkan."
        case .keychain:
            return "Token ChatGPT tidak dapat disimpan di Keychain perangkat."
        case .missingRefreshToken:
            return "Sesi ChatGPT tidak memiliki refresh token. Hubungkan kembali."
        }
    }
}

/// Local-only Keychain storage for the ChatGPT OAuth session.
enum ChatGPTAuthStore {
    private static let service = "com.noop.chatgpt-auth"
    private static let account = "oauth-tokens"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static var isConnected: Bool { load() != nil }

    static func load() -> ChatGPTTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ChatGPTTokens.self, from: data)
    }

    @discardableResult
    static func save(_ tokens: ChatGPTTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return true }
        guard status == errSecDuplicateItem else { return false }

        let update = [kSecValueData as String: data]
        return SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Authenticates the iOS Coach against the ChatGPT/Codex device-auth flow.
///
/// The client id is public application metadata; no client secret is embedded in the app. The
/// refresh token is never exposed to SwiftUI and is only read by this actor when an access token
/// needs refreshing.
actor ChatGPTAuthService {
    static let shared = ChatGPTAuthService()

    private let issuer = URL(string: "https://auth.openai.com")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    private let redirectURI = "https://auth.openai.com/deviceauth/callback"

    private var userCodeEndpoint: URL { issuer.appendingPathComponent("api/accounts/deviceauth/usercode") }
    private var tokenPollEndpoint: URL { issuer.appendingPathComponent("api/accounts/deviceauth/token") }
    private var tokenExchangeEndpoint: URL { issuer.appendingPathComponent("oauth/token") }

    func beginDeviceLogin() async throws -> ChatGPTDeviceCode {
        var request = URLRequest(url: userCodeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])

        let (data, response) = try await requestData(request)
        try validate(response: response, data: data)
        guard let object = try? jsonObject(data),
              let deviceAuthID = string(in: object, keys: ["device_auth_id", "deviceAuthId"]),
              let userCode = string(in: object, keys: ["user_code", "usercode", "userCode"]) else {
            throw ChatGPTAuthError.invalidResponse
        }

        let rawInterval = string(in: object, keys: ["interval", "poll_interval", "pollInterval"])
        let interval = max(5, TimeInterval(rawInterval ?? "5") ?? 5)
        return ChatGPTDeviceCode(deviceAuthID: deviceAuthID,
                                 userCode: userCode,
                                 interval: interval,
                                 verificationURL: verificationURL)
    }

    func pollAndExchange(_ device: ChatGPTDeviceCode) async throws -> ChatGPTTokens {
        let deadline = Date().addingTimeInterval(15 * 60)

        while Date() < deadline {
            try Task.checkCancellation()

            var request = URLRequest(url: tokenPollEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": device.deviceAuthID,
                "user_code": device.userCode
            ])

            let (data, response) = try await requestData(request)
            guard let http = response as? HTTPURLResponse else {
                throw ChatGPTAuthError.invalidResponse
            }

            if http.statusCode == 403 || http.statusCode == 404 {
                try await Task.sleep(for: .seconds(device.interval))
                continue
            }
            if http.statusCode == 410 {
                throw ChatGPTAuthError.server(http.statusCode, "Kode device sudah kedaluwarsa.")
            }
            try validate(response: response, data: data)

            guard let object = try? jsonObject(data),
                  let authorizationCode = string(in: object, keys: ["authorization_code", "authorizationCode"]),
                  let codeVerifier = string(in: object, keys: ["code_verifier", "codeVerifier"]) else {
                throw ChatGPTAuthError.invalidResponse
            }
            return try await exchangeAuthorizationCode(authorizationCode, codeVerifier: codeVerifier)
        }

        throw ChatGPTAuthError.pendingTimeout
    }

    func validAuthorization() async throws -> ChatGPTTokens {
        guard let stored = ChatGPTAuthStore.load() else { throw ChatGPTAuthError.notConnected }
        guard stored.expiresAt.timeIntervalSinceNow <= 60 else { return stored }
        guard !stored.refreshToken.isEmpty else { throw ChatGPTAuthError.missingRefreshToken }

        do {
            var request = URLRequest(url: tokenExchangeEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncoded([
                "grant_type": "refresh_token",
                "client_id": clientID,
                "refresh_token": stored.refreshToken
            ])

            let (data, response) = try await requestData(request)
            try validate(response: response, data: data)
            let refreshed = try decodeTokens(jsonObject(data), fallbackRefreshToken: stored.refreshToken)
            guard ChatGPTAuthStore.save(refreshed) else { throw ChatGPTAuthError.keychain }
            return refreshed
        } catch is CancellationError {
            throw ChatGPTAuthError.cancelled
        } catch let error as ChatGPTAuthError {
            if case .server = error { throw ChatGPTAuthError.refreshRejected }
            throw error
        } catch {
            throw ChatGPTAuthError.refreshRejected
        }
    }

    func logout() {
        // Deliberately local-only. This flow has no revoke call in the product contract.
        ChatGPTAuthStore.clear()
    }

    private func exchangeAuthorizationCode(_ code: String, codeVerifier: String) async throws -> ChatGPTTokens {
        var request = URLRequest(url: tokenExchangeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await requestData(request)
        try validate(response: response, data: data)
        let tokens = try decodeTokens(jsonObject(data), fallbackRefreshToken: nil)
        guard ChatGPTAuthStore.save(tokens) else { throw ChatGPTAuthError.keychain }
        return tokens
    }

    private func requestData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw ChatGPTAuthError.cancelled
        } catch {
            throw ChatGPTAuthError.network(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatGPTAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ChatGPTAuthError.server(http.statusCode, providerMessage(data))
        }
    }

    private func decodeTokens(_ object: [String: Any], fallbackRefreshToken: String?) throws -> ChatGPTTokens {
        guard let idToken = string(in: object, keys: ["id_token", "idToken"]),
              let accessToken = string(in: object, keys: ["access_token", "accessToken"]) else {
            throw ChatGPTAuthError.invalidResponse
        }
        let refreshToken = string(in: object, keys: ["refresh_token", "refreshToken"]) ?? fallbackRefreshToken ?? ""
        guard !refreshToken.isEmpty else { throw ChatGPTAuthError.missingRefreshToken }

        let expiresIn = number(in: object, keys: ["expires_in", "expiresIn"])
        let jwtExpiry = jwtExpiry(accessToken) ?? jwtExpiry(idToken)
        let fallbackLifetime = max(0, jwtExpiry?.timeIntervalSinceNow ?? 3600)
        let expiresAt = Date(timeIntervalSinceNow: expiresIn.map { max(0, $0) } ?? fallbackLifetime)
        let accountID = jwtAccountID(accessToken) ?? jwtAccountID(idToken)
        return ChatGPTTokens(idToken: idToken,
                             accessToken: accessToken,
                             refreshToken: refreshToken,
                             expiresAt: expiresAt,
                             accountID: accountID)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatGPTAuthError.invalidResponse
        }
        return object
    }

    private func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private func number(in object: [String: Any], keys: [String]) -> TimeInterval? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private func formEncoded(_ values: [String: String]) -> Data {
        let body = values.map { key, value in
            "\(formEscape(key))=\(formEscape(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func providerMessage(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return ""
    }

    private func jwtPayload(_ token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".")
        guard pieces.count >= 2 else { return nil }
        var base64 = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return payload
    }

    private func jwtExpiry(_ token: String) -> Date? {
        guard let exp = jwtPayload(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    private func jwtAccountID(_ token: String) -> String? {
        guard let payload = jwtPayload(token) else { return nil }
        if let account = payload["chatgpt_account_id"] as? String { return account }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
           let account = auth["chatgpt_account_id"] as? String { return account }
        return nil
    }
}

@MainActor
final class ChatGPTAuthModel: ObservableObject {
    static let shared = ChatGPTAuthModel()

    @Published private(set) var isConnected = ChatGPTAuthStore.isConnected
    @Published private(set) var isBusy = false
    @Published private(set) var deviceCode: ChatGPTDeviceCode?
    @Published private(set) var errorMessage: String?

    private var loginTask: Task<Void, Never>?

    var verificationURL: URL? { deviceCode?.verificationURL }

    func startLogin() {
        guard !isBusy else { return }
        errorMessage = nil
        deviceCode = nil
        isBusy = true
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            do {
                let device = try await ChatGPTAuthService.shared.beginDeviceLogin()
                guard !Task.isCancelled else { throw ChatGPTAuthError.cancelled }
                self?.deviceCode = device
                let _ = try await ChatGPTAuthService.shared.pollAndExchange(device)
                guard let self, !Task.isCancelled else { return }
                self.isConnected = true
                self.isBusy = false
                self.deviceCode = nil
            } catch is CancellationError {
                self?.isBusy = false
            } catch let error as ChatGPTAuthError {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isBusy = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = ChatGPTAuthError.network(error.localizedDescription).localizedDescription
                self.isBusy = false
            }
        }
    }

    func openVerificationPage() {
        guard let url = verificationURL else { return }
        UIApplication.shared.open(url)
    }

    func logout() {
        loginTask?.cancel()
        loginTask = nil
        Task {
            await ChatGPTAuthService.shared.logout()
            isConnected = false
            deviceCode = nil
            errorMessage = nil
            isBusy = false
        }
    }

    func refreshConnection() {
        isConnected = ChatGPTAuthStore.isConnected
    }
}

struct ChatGPTAuthCard: View {
    @StateObject private var auth = ChatGPTAuthModel.shared
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: auth.isConnected ? "checkmark.seal.fill" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(StrandPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.isConnected ? "ChatGPT connected" : "Sign in with ChatGPT")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(auth.isConnected
                         ? "Token tersimpan aman di Apple Keychain."
                         : "Gunakan akun ChatGPT tanpa menempelkan API key.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if auth.isConnected {
                Button("Log out ChatGPT") { auth.logout() }
                    .buttonStyle(NoopButtonStyle(.secondary))
            } else if let code = auth.deviceCode {
                Text("Kode perangkat")
                    .strandOverline()
                Text(code.userCode)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .tracking(1.5)
                HStack(spacing: 10) {
                    Button("Buka halaman login") { auth.openVerificationPage() }
                        .buttonStyle(NoopButtonStyle(.primary))
                    if auth.isBusy { ProgressView().controlSize(.small) }
                }
                Text("Masukkan kode di auth.openai.com/codex/device. NOOP akan menunggu persetujuan secara otomatis.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Sign in with ChatGPT") { auth.startLogin() }
                    .buttonStyle(NoopButtonStyle(.primary))
                    .disabled(auth.isBusy)
            }

            if let error = auth.errorMessage, !error.isEmpty {
                Text(error)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 0 : 2)
        .task { auth.refreshConnection() }
    }
}
#endif
