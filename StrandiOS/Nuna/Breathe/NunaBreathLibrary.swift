#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The techniques the Breathe tab offers beyond the first ten ready exercises: every bundled catalogue protocol that had no ready exercise
/// (Buteyko, Tummo, Qi Gong, Soma, Kapalabhati, Wim Hof, Presence and the rest), and a few well-known gentle ones the catalogue does not carry
/// (pursed-lip, Okinawa belly breath, humming bee, cooling breath, long 4-8 exhale). The new protocols are registered like a kept Anya exercise, so
/// the session, the report and the history treat them like any other.
enum NunaBreathLibrary {
    /// Techniques added here, in the app's own words and gentle timings.
    static let extraProtocols: [BreathProtocol] = [
        BreathProtocol(
            id: "pursed_lip", title: "Pursed-lip breathing", subtitle: "Nose in · lips pursed out",
            edu: "Breathe in gently through your nose, then breathe out slowly through lips shaped as if you were blowing out a candle. The longer, steady exhale helps you slow down and feel less out of breath.",
            caution: nil, sessionHint: "About 5 minutes; ease off if you feel dizzy.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 2_000), BreathStage(type: .exhale, durationMs: 5_000)]),
        BreathProtocol(
            id: "okinawa", title: "Okinawa belly breath", subtitle: "Low belly · slow steady out",
            edu: "A slow, deep belly breath in the spirit of the abdominal breathing taught in Okinawan karate. Breathe in through the nose into the lower belly, rest a moment, then breathe out slowly while gently drawing the lower belly in. The timing here is a gentle pace chosen for this app.",
            caution: nil, sessionHint: "5–10 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 10 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .hold, durationMs: 1_000), BreathStage(type: .exhale, durationMs: 7_000)]),
        BreathProtocol(
            id: "bhramari", title: "Humming bee breath", subtitle: "Nose in · hum out",
            edu: "Breathe in through your nose, then hum softly on the exhale with your lips closed, like a bee. The gentle vibration gives your attention something steady to follow.",
            caution: nil, sessionHint: "About 5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .exhale, durationMs: 8_000)]),
        BreathProtocol(
            id: "sitali", title: "Cooling breath", subtitle: "Curled tongue in · nose out",
            edu: "Roll your tongue into a tube (or rest it behind your lower teeth if it will not curl), breathe in slowly through it, then close your mouth and breathe out through your nose. It feels cool and settling, which is welcome after heat or effort.",
            caution: nil, sessionHint: "3–5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .exhale, durationMs: 6_000)]),
        BreathProtocol(
            id: "extended_4_8", title: "Long exhale 4-8", subtitle: "Exhale twice as long as the inhale",
            edu: "Breathe in through your nose for 4 seconds, then breathe out slowly for 8. An exhale twice as long as the inhale is a simple way to wind down.",
            caution: nil, sessionHint: "5–10 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .exhale, durationMs: 8_000)]),
    ]

    /// The ready exercises added on top of `BreathTemplates.all`. The intense ones are listed for the wearer to choose and never suggested.
    static let extraTemplates: [BreathTemplate] = [
        .init(id: "calm_pursed", goal: .calm, protocolId: "pursed_lip", minutes: 5, advisable: true),
        .init(id: "calm_bhramari", goal: .calm, protocolId: "bhramari", minutes: 5, advisable: true),
        .init(id: "calm_qigong", goal: .calm, protocolId: "qigong", minutes: 10, advisable: true),
        .init(id: "calm_presence", goal: .calm, protocolId: "presence_regular", minutes: 15, advisable: true),
        .init(id: "sleep_48", goal: .sleep, protocolId: "extended_4_8", minutes: 5, advisable: true),
        .init(id: "sleep_buteyko", goal: .sleep, protocolId: "buteyko_reduced", minutes: 10, advisable: true),
        .init(id: "focus_soma", goal: .focus, protocolId: "soma", minutes: 5, advisable: true),
        .init(id: "focus_buteyko", goal: .focus, protocolId: "buteyko", minutes: 5, advisable: true),
        .init(id: "focus_presence", goal: .focus, protocolId: "presence_mid", minutes: 10, advisable: true),
        .init(id: "energize_tummo", goal: .energize, protocolId: "tummo", minutes: 5, advisable: false),
        .init(id: "energize_punching", goal: .energize, protocolId: "presence_punching", minutes: 5, advisable: false),
        .init(id: "energize_kapala", goal: .energize, protocolId: "kapalabhati", minutes: 3, advisable: false),
        .init(id: "energize_wimhof", goal: .energize, protocolId: "wim_hof", minutes: 10, advisable: false),
        .init(id: "energize_holotropic", goal: .energize, protocolId: "holotropic", minutes: 10, advisable: false),
        .init(id: "energize_shamanic", goal: .energize, protocolId: "shamanic", minutes: 10, advisable: false),
        .init(id: "recover_okinawa", goal: .recover, protocolId: "okinawa", minutes: 10, advisable: true),
        .init(id: "recover_sitali", goal: .recover, protocolId: "sitali", minutes: 5, advisable: true),
    ]

    static func registerExtras() {
        for p in extraProtocols { BreathProtocolCatalog.registerCustom(p) }
    }

    static var allTemplates: [BreathTemplate] { BreathTemplates.all + extraTemplates }
    static func templates(for goal: BreathGoal) -> [BreathTemplate] { allTemplates.filter { $0.goal == goal } }
    static func template(id: String) -> BreathTemplate? { allTemplates.first { $0.id == id } }
}

// MARK: Level

/// How demanding a technique is. Shown on its page so nobody starts an intense one by accident.
enum NunaBreathLevel {
    case gentle, moderate, intense
    var title: String {
        switch self { case .gentle: return String(localized: "Gentle"); case .moderate: return String(localized: "Moderate"); case .intense: return String(localized: "Intense") }
    }
    static func of(_ protocolId: String) -> NunaBreathLevel {
        switch protocolId {
        case "tummo", "bhastrika", "kapalabhati", "wim_hof", "holotropic", "shamanic", "presence_punching": return .intense
        case "box_4_4_4_4", "four_seven_eight", "buteyko", "buteyko_reduced", "nadi_shodhana", "ujjayi": return .moderate
        default: return .gentle
        }
    }
}

// MARK: Steps

struct NunaBreathStep: Identifiable {
    let id: Int
    let icon: String
    let text: String
}

/// How to do a technique, a few short cards: sit, then each stage in turn, with the particular touch of the ones that have one (pursed lips,
/// a finger on a nostril, a hum). Techniques without one get their steps from their own stages.
enum NunaBreathGuide {
    private static func s(_ text: String) -> String { String(localized: String.LocalizationValue(text)) }

    private static var sit: (String, String) { ("figure.mind.and.body", String(localized: "Sit upright and comfortable, and relax your neck and shoulders.")) }

    static func steps(for proto: BreathProtocol) -> [NunaBreathStep] {
        let list = custom(proto.id) ?? generic(proto)
        return list.enumerated().map { NunaBreathStep(id: $0.offset, icon: $0.element.0, text: $0.element.1) }
    }

    private static func secs(_ ms: Int) -> String { String(format: "%g", Double(ms) / 1000) }

    private static func generic(_ proto: BreathProtocol) -> [(String, String)] {
        var out = [sit]
        for stage in proto.stages where stage.durationMs > 0 {
            let n = secs(stage.durationMs)
            switch stage.type {
            case .inhale: out.append(("nose", String(localized: "Breathe in slowly through your nose for \(n) seconds.")))
            case .hold, .textOnly: out.append(("pause.circle", String(localized: "Hold gently for \(n) seconds and stay relaxed.")))
            case .exhale: out.append(("wind", String(localized: "Breathe out slowly for \(n) seconds.")))
            }
        }
        out.append(("repeat", String(localized: "Keep this rhythm going. If you lose your place, start again with the next breath.")))
        return out
    }

    private static func custom(_ id: String) -> [(String, String)]? {
        switch id {
        case "pursed_lip": return [sit,
            ("nose", String(localized: "Breathe in slowly through your nose for 2 seconds.")),
            ("mouth", String(localized: "Purse your lips as though you are about to blow out a candle.")),
            ("wind", String(localized: "Breathe out slowly through your pursed lips for four to six counts."))]
        case "okinawa": return [
            ("figure.stand", String(localized: "Sit or stand tall and rest one hand low on your belly.")),
            ("nose", String(localized: "Breathe in through your nose for 4 seconds and let your lower belly rise.")),
            ("pause.circle", String(localized: "Rest for a moment at the top, without any tension.")),
            ("wind", String(localized: "Breathe out slowly for 7 seconds while gently drawing your lower belly in."))]
        case "ujjayi": return [sit,
            ("nose", String(localized: "Breathe in through your nose and narrow the back of your throat a little, as if fogging a mirror with your mouth closed.")),
            ("water.waves", String(localized: "Let the breath sound like soft ocean waves, about 4.5 seconds in and 4.5 seconds out.")),
            ("face.smiling", String(localized: "Keep your face and shoulders loose."))]
        case "nadi_shodhana": return [sit,
            ("hand.point.up.left", String(localized: "Close your right nostril with your thumb and breathe in through the left.")),
            ("hand.raised", String(localized: "Hold briefly, close the left nostril with your ring finger, and breathe out through the right.")),
            ("arrow.left.arrow.right", String(localized: "Breathe in through the right, hold, then out through the left. That is one round."))]
        case "bhramari": return [sit,
            ("nose", String(localized: "Breathe in through your nose for 4 seconds.")),
            ("waveform", String(localized: "Close your lips and hum softly as you breathe out for 8 seconds.")),
            ("face.smiling", String(localized: "Feel the hum in your face and chest, then start the next breath."))]
        case "sitali": return [sit,
            ("mouth", String(localized: "Curl your tongue into a tube and stick it out a little. If it will not curl, rest it behind your lower teeth.")),
            ("wind", String(localized: "Breathe in slowly through your tongue for 4 seconds.")),
            ("nose", String(localized: "Close your mouth and breathe out through your nose for 6 seconds."))]
        case "diaphragmatic_4_2_6": return [
            ("figure.mind.and.body", String(localized: "Sit or lie back comfortably. Place one hand on your chest and one on your belly.")),
            ("nose", String(localized: "Breathe in through your nose for 4 seconds so your belly rises more than your chest.")),
            ("pause.circle", String(localized: "Hold gently for 2 seconds.")),
            ("wind", String(localized: "Breathe out for 6 seconds and let your belly fall."))]
        case "four_seven_eight": return [sit,
            ("mouth", String(localized: "Rest the tip of your tongue behind your upper front teeth.")),
            ("nose", String(localized: "Breathe in quietly through your nose for 4 seconds.")),
            ("pause.circle", String(localized: "Hold for 7 seconds.")),
            ("wind", String(localized: "Breathe out through your mouth with a soft whoosh for 8 seconds."))]
        case "tummo": return [
            ("figure.mind.and.body", String(localized: "Sit steadily. Never do this lying down, in water or while driving.")),
            ("wind", String(localized: "Breathe out forcefully for 1 second.")),
            ("pause.circle", String(localized: "Hold with your lungs empty for 10 seconds.")),
            ("nose", String(localized: "Breathe in slowly for 7 seconds, then hold full for 15.")),
            ("wind", String(localized: "Breathe out slowly for 7 seconds. Stop if you feel strained."))]
        case "bhastrika": return [sit,
            ("nose", String(localized: "Breathe in sharply through your nose for 1 second.")),
            ("wind", String(localized: "Breathe out forcefully for 1 second.")),
            ("pause.circle", String(localized: "Do about 10 breaths, then rest and breathe normally before the next round."))]
        case "kapalabhati": return [
            ("figure.mind.and.body", String(localized: "Sit tall and take one normal breath in.")),
            ("bolt", String(localized: "Snap your lower belly in to push the air out in a short burst. Let the inhale happen by itself.")),
            ("repeat", String(localized: "Do 20 to 30 bursts, then rest. Stop if you feel dizzy."))]
        case "holotropic": return [
            ("person.2", String(localized: "Choose a safe place, ideally with a trained guide beside you.")),
            ("lungs", String(localized: "Breathe deeply and continuously, with no pause between the in-breath and the out-breath.")),
            ("hand.raised", String(localized: "Keep the pace your own, and stop whenever you want."))]
        case "wim_hof": return [
            ("figure.mind.and.body", String(localized: "Sit or lie on a bed, never in water or while driving.")),
            ("lungs", String(localized: "Take about 30 deep breaths: full in, relaxed out.")),
            ("pause.circle", String(localized: "After the last breath out, hold with your lungs empty for as long as it stays comfortable.")),
            ("nose", String(localized: "Breathe in deeply, hold for about 15 seconds, then breathe out. That is one round."))]
        case "shamanic": return [
            ("figure.mind.and.body", String(localized: "Choose a quiet, safe place.")),
            ("lungs", String(localized: "Breathe in a steady rhythm with no pause between breaths.")),
            ("hand.raised", String(localized: "Keep the intensity at a level that feels safe, and ease off whenever you want."))]
        default: return nil
        }
    }
}
#endif
