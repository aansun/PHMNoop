#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// One finished breathing session, as it is kept in the history and shown in the report. Every figure is measured during the
/// session; a number the strap did not give (no heart rate, too few beats for HRV) is nil, never filled in.
struct NunaBreathRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var startTs: Int
    var seconds: Int
    var goal: String
    var templateId: String?
    var protocolId: String
    var breaths: Int
    var hrStart: Double?
    var hrEnd: Double?
    var hrAvg: Double?
    var rmssdStart: Double?
    var rmssdAvg: Double?
    var rmssdPeak: Double?
    var hrSeries: [Double]
    var rmssdSeries: [Double]
    var haptics: Bool
    /// Seconds between the points of the two series.
    var step: Int = 10

    var rmssdChangePct: Double? {
        guard let a = rmssdStart, a > 0, let b = rmssdAvg else { return nil }
        return (b - a) / a * 100
    }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(startTs)) }
    /// "8 min" or, for a short session, "32 s".
    var durationText: String { seconds >= 60 ? String(localized: "\(seconds / 60) min") : String(localized: "\(seconds) s") }
}

enum NunaBreathLog {
    static let key = "nuna.breath.history"
    static let maxCount = 300

    static func all() -> [NunaBreathRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([NunaBreathRecord].self, from: data) else { return [] }
        return list.sorted { $0.startTs > $1.startTs }
    }

    static func append(_ r: NunaBreathRecord) {
        var list = all(); list.insert(r, at: 0)
        if list.count > maxCount { list.removeLast(list.count - maxCount) }
        save(list)
    }

    static func delete(_ id: UUID) { save(all().filter { $0.id != id }) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    private static func save(_ list: [NunaBreathRecord]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// For the advisor: how each template has moved HRV for this wearer.
    static func pastEffect() -> [String: Double] {
        BreathAdvisor.pastEffect(all().compactMap { r in r.templateId.map { ($0, r.rmssdStart, r.rmssdAvg) } })
    }
}

/// The live numbers the Breathing module reads (heart rate from the strap and HRV over the last beats). The Breathing screen
/// keeps it current while it is open; Anya's sheet for this module reads it, so what it says matches what is on screen.
@MainActor
final class NunaBreathLive: ObservableObject {
    static let shared = NunaBreathLive()
    @Published var bpm: Int?
    @Published var rmssd: Double?
    @Published var worn = false
}

enum NunaBreathPrefs {
    static let countdownKey = "nuna.breath.countdown"
    static let lengthKey = "nuna.breath.length"          // 0 = the template's own length
    static let anyaKey = "nuna.breath.anya"
    static let audioKey = "breathe.audioCues"
    static let hapticsKey = HapticPrefs.breathing
}

/// Short wording for goals and templates, kept with the data so every screen says the same thing.
extension BreathGoal {
    var title: LocalizedStringKey {
        switch self {
        case .calm: return "Calm down"; case .sleep: return "Wind down for sleep"; case .focus: return "Focus"
        case .energize: return "Energise"; case .recover: return "Recover"
        }
    }
    var shortTitle: String {
        switch self {
        case .calm: return String(localized: "Calm down"); case .sleep: return String(localized: "Sleep"); case .focus: return String(localized: "Focus")
        case .energize: return String(localized: "Energise"); case .recover: return String(localized: "Recover")
        }
    }
    var blurb: LocalizedStringKey {
        switch self {
        case .calm: return "Slow a racing heart"; case .sleep: return "Ease into the night"; case .focus: return "Steady and clear"
        case .energize: return "A gentle lift"; case .recover: return "After effort or a poor night"
        }
    }
    var icon: String {
        switch self {
        case .calm: return "leaf"; case .sleep: return "moon.zzz"; case .focus: return "scope"
        case .energize: return "bolt"; case .recover: return "heart.circle"
        }
    }
    var tint: Color {
        switch self {
        case .calm: return NunaPalette.rest; case .sleep: return NunaPalette.restLight; case .focus: return NunaPalette.charge
        case .energize: return NunaPalette.effort; case .recover: return NunaPalette.charge
        }
    }
}

extension BreathTemplate {
    var title: String {
        switch id {
        case "calm_slow": return String(localized: "Slow down")
        case "calm_coherence": return String(localized: "Steady coherence")
        case "calm_deep": return String(localized: "Deep breaths")
        case "sleep_478": return String(localized: "4-7-8 wind-down")
        case "sleep_exhale": return String(localized: "Long exhale")
        case "sleep_belly": return String(localized: "Belly breathing")
        case "focus_box": return String(localized: "Box breathing")
        case "focus_alternate": return String(localized: "Alternate nostril")
        case "focus_66": return String(localized: "Even 6-6")
        case "energize_ocean": return String(localized: "Ocean breath")
        case "energize_box": return String(localized: "Quick box")
        case "energize_bhastrika": return String(localized: "Bellows breath")
        case "recover_66": return String(localized: "Recovery 6-6")
        case "recover_belly": return String(localized: "Belly reset")
        case "recover_coherence": return String(localized: "Recovery coherence")
        default: return protocolTitle
        }
    }
    var protocolTitle: String {
        BreathProtocolCatalog.protocolById(protocolId).map { String(localized: String.LocalizationValue($0.title)) } ?? protocolId
    }
    var blurb: String {
        BreathProtocolCatalog.protocolById(protocolId).map { String(localized: String.LocalizationValue($0.subtitle)) } ?? ""
    }
}
#endif
