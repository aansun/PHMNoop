#if os(iOS)
import Foundation
import Security

/// The OpenWeather and IQAir API keys, in this iPhone's Keychain only (generic password, this device, after first unlock). Neither is
/// written to UserDefaults, a plist, a backup or a log; each is sent to exactly one place, its own service.
enum EnvironmentKeyStore {
    enum Account: String { case openWeather = "openweather", iqAir = "iqair" }
    private static let service = "com.noop.environment"

    private static func baseQuery(_ a: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: a.rawValue]
    }

    @discardableResult
    static func save(_ key: String, for a: Account) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { clear(a); return trimmed.isEmpty }
        SecItemDelete(baseQuery(a) as CFDictionary)
        var attrs = baseQuery(a)
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ a: Account) -> String? {
        var query = baseQuery(a)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func clear(_ a: Account) { SecItemDelete(baseQuery(a) as CFDictionary) }
    static func has(_ a: Account) -> Bool { read(a) != nil }
    static var hasAny: Bool { has(.openWeather) || has(.iqAir) }
}

/// Weather and air are off until they are turned on, and while they are off no request is made to either service.
enum EnvironmentExperiment {
    static let enabledKey = "noop.experiment.environment"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}
#endif
