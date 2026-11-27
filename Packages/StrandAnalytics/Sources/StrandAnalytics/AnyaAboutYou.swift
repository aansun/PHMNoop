import Foundation

/// What the person has told Anya about themselves, or written on the "About you" page: the standing facts a coach keeps in mind. It is theirs
/// to read, change and clear, stays on the phone, and goes to a provider only inside a request to Anya. Pure.
public struct AnyaAboutYou: Codable, Equatable, Sendable {
    public enum Field: String, CaseIterable, Codable, Sendable, Identifiable {
        case goals, schedule, equipment, limits, style

        public var id: String { rawValue }

        /// The heading on the page, in English; the app translates it.
        public var title: String {
            switch self {
            case .goals: return "Goals"
            case .schedule: return "Usual week"
            case .equipment: return "Equipment and places"
            case .limits: return "Injuries and limits"
            case .style: return "How to coach me"
            }
        }
    }

    public static let longest = 400

    private var values: [String: String] = [:]

    public init() {}

    public subscript(_ field: Field) -> String {
        get { values[field.rawValue] ?? "" }
        set {
            let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            values[field.rawValue] = text.isEmpty ? nil : String(text.prefix(Self.longest))
        }
    }

    public var isEmpty: Bool { values.isEmpty }
    public var filled: [Field] { Field.allCases.filter { !self[$0].isEmpty } }

    /// Takes something the person said. It is added to what is there unless it is to replace it; saying the same thing twice changes nothing.
    /// False when there was nothing to take or no room left.
    @discardableResult
    public mutating func note(_ field: Field, _ text: String, replacing: Bool = false) -> Bool {
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return false }
        let old = self[field]
        if replacing || old.isEmpty { self[field] = new; return true }
        if old.localizedCaseInsensitiveContains(new) { return true }
        let joined = old + "; " + new
        guard joined.count <= Self.longest else { return false }
        self[field] = joined
        return true
    }

    /// The part of the instructions that carries it; empty when nothing is known.
    public var promptBlock: String {
        guard !isEmpty else { return "" }
        return "\n\nABOUT THE PERSON (they told you, or wrote it themselves; keep it in mind, do not recite it):\n"
            + filled.map { "- \($0.title): \(self[$0])" }.joined(separator: "\n")
    }

    // MARK: Storage

    public static let defaultsKey = "coach.aboutYou.v1"

    public static func load(_ defaults: UserDefaults = .standard) -> AnyaAboutYou {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(AnyaAboutYou.self, from: $0) } ?? AnyaAboutYou()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if isEmpty { defaults.removeObject(forKey: Self.defaultsKey) }
        else if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
