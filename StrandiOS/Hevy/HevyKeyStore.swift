#if os(iOS)
import Foundation
import Security

/// The Hevy API key, in this iPhone's Keychain only (generic password, this device, after first unlock). It is never written to
/// UserDefaults, a plist, a backup or a log, and it is sent to exactly one place: api.hevyapp.com, as the `api-key` header.
enum HevyKeyStore {
    private static let service = "com.noop.hevy"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// Store (or replace) the key. False when the Keychain refused it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { clear(); return trimmed.isEmpty }
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func clear() { SecItemDelete(baseQuery as CFDictionary) }

    static var hasKey: Bool { read() != nil }
}

/// Hevy is off until it is turned on, and while it is off no request is made to it.
enum HevyExperiment {
    static let enabledKey = "noop.experiment.hevy"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}
#endif
