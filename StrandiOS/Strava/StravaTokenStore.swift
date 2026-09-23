import Foundation
import Security

/// Keychain storage for Strava OAuth tokens. Tokens never go into UserDefaults or the activity ledger.
enum StravaTokenStore {
    private static let service = "com.noop.strava"
    private static let account = "oauth-tokens"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ tokens: StravaTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> StravaTokens? {
        var request = query
        request[kSecReturnData as String] = kCFBooleanTrue
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StravaTokens.self, from: data)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }

    static var isConnected: Bool { load() != nil }
}

struct StravaUploadRecord: Codable, Equatable, Identifiable {
    let workoutKey: String
    let startTs: Int
    let sport: String
    var uploadId: Int?
    var activityId: Int?
    var status: String
    var message: String?
    var updatedAt: Date

    var id: String { workoutKey }
    var isComplete: Bool { activityId != nil }
}

enum StravaActivityStore {
    private static let defaultsKey = "noop.experiment.strava.uploads.v1"

    static func load() -> [StravaUploadRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([StravaUploadRecord].self, from: data) else { return [] }
        return records.sorted { $0.startTs > $1.startTs }
    }

    static func record(for workoutKey: String) -> StravaUploadRecord? {
        load().first { $0.workoutKey == workoutKey }
    }

    static func save(_ record: StravaUploadRecord) {
        var records = load().filter { $0.workoutKey != record.workoutKey }
        records.append(record)
        records.sort { $0.startTs > $1.startTs }
        if records.count > 200 { records = Array(records.prefix(200)) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func remove(workoutKeys: Set<String>) {
        guard !workoutKeys.isEmpty else { return }
        let records = load().filter { !workoutKeys.contains($0.workoutKey) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
