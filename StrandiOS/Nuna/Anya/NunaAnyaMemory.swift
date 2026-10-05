#if os(iOS)
import Foundation
import StrandAnalytics

/// What Anya remembers inside one module (`AnyaNoteStore` in StrandAnalytics holds the logic and is tested there). Each module
/// reads and writes only its own notes, and each can forget its own. Notes live in this phone's defaults; they reach a provider
/// only inside a question the wearer asks in that module, and only with data access on.
enum NunaAnyaMemory {
    private static let store = AnyaNoteStore()

    static func entries(_ module: NunaAnyaModule) -> [AnyaNote] { store.notes(module.rawValue) }
    static func remember(_ module: NunaAnyaModule, _ text: String) { store.remember(module.rawValue, text) }
    static func clear(_ module: NunaAnyaModule) { store.clear(module.rawValue) }
    static func summary(_ module: NunaAnyaModule, limit: Int = 8) -> String? { store.summary(module.rawValue, limit: limit) }

    /// How each remembered figure is named and written, per figure key.
    private static let figures: [String: (name: String, unit: String, decimals: Int)] = [
        "charge": ("Charge", "%", 0), "effort": ("Effort", "", 0), "rest": ("Rest", "%", 0),
        "hrv": ("HRV", " ms", 0), "rhr": ("Resting heart rate", " bpm", 0), "spo2": ("SpO₂", "%", 0), "resp": ("Breathing", "/min", 1),
        "sleepMin": ("Sleep", " min", 0), "efficiency": ("Sleep efficiency", "%", 0), "deepMin": ("Deep sleep", " min", 0),
        "week": ("Charge this week", "%", 0), "before": ("Charge before that", "%", 0),
        "sessions": ("Sessions in 7 days", "", 0), "minutes": ("Training minutes", " min", 0), "weekEffort": ("Effort this week", "", 0),
    ]

    /// Records today's figures for a module (one snapshot per day, replaced as the day goes on) and returns a sentence on what
    /// moved since the last day it noted, or nil when there is nothing earlier to compare with.
    @discardableResult
    static func snapshot(_ module: NunaAnyaModule, headline: String, values: [String: Double]) -> String? {
        let m = module.rawValue
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let tag = "day:" + f.string(from: Date())
        let previous = store.previousSnapshot(m, excluding: tag)
        store.remember(m, headline, tag: tag, values: values)
        guard let previous, let before = previous.values else { return nil }
        let moves = AnyaNoteMath.changes(previous: before, current: values, minAbsolute: 1)
        guard !moves.isEmpty else { return nil }
        let days = AnyaNoteMath.daysBetween(previous.ts, Int(Date().timeIntervalSince1970))
        let when = days <= 0 ? String(localized: "earlier") : (days == 1 ? String(localized: "yesterday") : String(localized: "\(days) days ago"))
        let bits = moves.compactMap { c -> String? in
            guard let fig = figures[c.key] else { return nil }
            func s(_ v: Double) -> String { String(format: "%.\(fig.decimals)f", locale: AppLanguage.activeLocale, v) + fig.unit }
            return "\(String(localized: String.LocalizationValue(fig.name))) \(s(c.now)) (\(String(localized: "was")) \(s(c.was)))"
        }
        guard !bits.isEmpty else { return nil }
        return String(localized: "Compared with my note \(when): ") + bits.joined(separator: ", ") + "."
    }
}
#endif
