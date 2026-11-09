#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The techniques the Breathe tab offers beyond the first ten ready exercises: every bundled catalogue protocol that had no ready exercise
/// (Buteyko, Tummo, Qi Gong, Soma, Kapalabhati, Wim Hof, Presence and the rest) and the Japanese techniques of the two guides (Misogi, Torifune, Kiko, Nogare, Okinaga, Ibuki, Kiai, Kokyuho), and a few well-known gentle ones the catalogue does not carry
/// (pursed-lip, humming bee, cooling breath, long 4-8 exhale). The new protocols are registered like a kept Anya exercise, so
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
            id: "misogi_kokyuho", title: "Misogi Kokyuho", subtitle: "Slow in · strong “Haa” out",
            edu: "A purifying breath from Shinto practice and Aikido. Breathe in slowly through the nose, picturing energy gathering at the tanden (the centre of the belly), then breathe out firmly through the mouth with a “Haa” or “Ou” sound, picturing tension leaving. A strong exhale empties the lungs and invites a fresh, oxygen-rich breath.",
            caution: "Stop if you feel dizzy.", sessionHint: "About 5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 5_000), BreathStage(type: .exhale, durationMs: 4_000)]),
        BreathProtocol(
            id: "torifune_kokyuho", title: "Torifune Kokyuho", subtitle: "Rowing-boat breath · lean and pull back",
            edu: "A practice from the Misogi tradition, also used in budo. Stand in a wide stance and rock your body forward and back as if rowing a boat. Breathe out sharply as you lean forward and breathe in deeply toward the tanden as you pull back. Pairing rhythmic movement with the breath trains the two to move together and can wake you up quickly.",
            caution: "Keep your knees soft. Stop if you feel dizzy, or if you have back, balance or blood-pressure concerns.", sessionHint: "2–5 minutes.",
            mode: .playable, category: .ans, recommendedDurationMs: 3 * 60_000,
            stages: [BreathStage(type: .exhale, durationMs: 2_000, label: "Lean forward · out"), BreathStage(type: .inhale, durationMs: 4_000, label: "Pull back · in")]),
        BreathProtocol(
            id: "kiko_kokyuho", title: "Kiko Kokyuho", subtitle: "Hands on the belly · slow in · soft hold",
            edu: "The Japanese take on Qigong, used for inner health. Rest both hands below the navel (the tanden), breathe in very slowly through the nose and let the belly swell like a balloon, hold softly for three to five seconds, then breathe out gently.",
            caution: nil, sessionHint: "5–10 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 8 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 6_000), BreathStage(type: .hold, durationMs: 4_000), BreathStage(type: .exhale, durationMs: 6_000)]),
        BreathProtocol(
            id: "nogare", title: "Nogare", subtitle: "Recovery breath · deep in · silent out",
            edu: "A recovery breath from traditional karate and from the discipline of stealth training (shinobi). Breathe in deeply and gently through the nose, pause for a moment low in the belly, then breathe out slowly through an open mouth without any sound, controlling the whole exhale with your diaphragm. It is used to bring the heart rate down after hard effort or a scare.",
            caution: nil, sessionHint: "3–5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .hold, durationMs: 1_000), BreathStage(type: .exhale, durationMs: 8_000)]),
        BreathProtocol(
            id: "okinaga", title: "Okinaga", subtitle: "Long breath · silent in · barely audible out",
            edu: "Okinaga means “long breath” and is a core technique of the shinobi, used to stay focused and quiet while watching. Breathe in very slowly and silently through the nose, hold gently low in the belly without strain, then breathe out extremely slowly and evenly until the sound disappears. Think of exhaling so softly that a feather in front of your nose would not stir.",
            caution: "Keep every phase comfortable and never strain on the hold.", sessionHint: "3–5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 6_000), BreathStage(type: .hold, durationMs: 3_000), BreathStage(type: .exhale, durationMs: 10_000)]),
        BreathProtocol(
            id: "ibuki", title: "Ibuki", subtitle: "Full in · hissing forceful out",
            edu: "A hard-breathing practice from budo and karate (Goju-ryu, Kyokushin). Take a full breath in, then breathe out forcefully through narrowed lips with a sharp hiss while tightening your whole core. It firms the body at once and prepares it to absorb a blow.",
            caution: "Intense. Skip with high blood pressure, pregnancy or a hernia, and stop if you feel dizzy. Not for beginners without guidance.", sessionHint: "A few breaths at a time, with rests in between.",
            mode: .playable, category: .ans, recommendedDurationMs: 3 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 3_000), BreathStage(type: .exhale, durationMs: 4_000)]),
        BreathProtocol(
            id: "kiai", title: "Kiai", subtitle: "Guided · sharp breath out with a shout",
            edu: "The instant release of energy in martial arts. Breathe in quickly as you prepare, then breathe out sharply with a strong shout from the diaphragm as you strike or push, tightening your core. It locks the body steady at the point of effort. This entry is guided: it times the session and shows reminders without pacing the shouts.",
            caution: "Practise where a loud shout is fine. Skip if you are pregnant or have high blood pressure, and stop if you feel dizzy.", sessionHint: "A few short rounds.",
            mode: .guided, category: .ans, recommendedDurationMs: 3 * 60_000, stages: []),
        BreathProtocol(
            id: "kokyuho", title: "Kokyuho", subtitle: "Breath that moves with the spine",
            edu: "The foundation of breathing in Aikido and jujutsu: let the breath drive the movement instead of muscle. Breathe out as you fold or round your back, emptying the air, and breathe in as you open your chest and lengthen your spine.",
            caution: nil, sessionHint: "About 5 minutes.", mode: .playable, category: .ans, recommendedDurationMs: 5 * 60_000,
            stages: [BreathStage(type: .inhale, durationMs: 4_000, label: "Open chest · in"), BreathStage(type: .exhale, durationMs: 5_000, label: "Round back · out")]),
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
        .init(id: "recover_kiko", goal: .recover, protocolId: "kiko_kokyuho", minutes: 8, advisable: true),
        .init(id: "recover_nogare", goal: .recover, protocolId: "nogare", minutes: 5, advisable: true),
        .init(id: "focus_okinaga", goal: .focus, protocolId: "okinaga", minutes: 5, advisable: true),
        .init(id: "focus_kokyuho", goal: .focus, protocolId: "kokyuho", minutes: 5, advisable: true),
        .init(id: "energize_misogi", goal: .energize, protocolId: "misogi_kokyuho", minutes: 5, advisable: true),
        .init(id: "energize_torifune", goal: .energize, protocolId: "torifune_kokyuho", minutes: 3, advisable: true),
        .init(id: "energize_ibuki", goal: .energize, protocolId: "ibuki", minutes: 3, advisable: false),
        .init(id: "energize_kiai", goal: .energize, protocolId: "kiai", minutes: 3, advisable: false),
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
        case "tummo", "bhastrika", "kapalabhati", "wim_hof", "holotropic", "shamanic", "presence_punching", "ibuki", "kiai": return .intense
        case "box_4_4_4_4", "four_seven_eight", "buteyko", "buteyko_reduced", "nadi_shodhana", "ujjayi", "misogi_kokyuho", "torifune_kokyuho", "kiko_kokyuho", "okinaga": return .moderate
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
        case "misogi_kokyuho": return [
            ("figure.mind.and.body", String(localized: "Sit upright, on a cushion or on your heels, with your back tall.")),
            ("nose", String(localized: "Breathe in slowly through your nose and picture energy gathering in the centre of your belly.")),
            ("mouth", String(localized: "Breathe out firmly through your mouth with a “Haa” or “Ou” sound.")),
            ("sparkles", String(localized: "Picture tension and stale air leaving with the sound, then take the next fresh breath."))]
        case "torifune_kokyuho": return [
            ("figure.stand", String(localized: "Stand with your feet wide and your knees soft, like a horse stance.")),
            ("arrow.forward", String(localized: "Rock forward like rowing a boat and breathe out sharply as you lean.")),
            ("arrow.backward", String(localized: "Pull back and breathe in deeply toward the centre of your belly.")),
            ("repeat", String(localized: "Keep the rocking rhythmic, and stop if you feel dizzy."))]
        case "kiko_kokyuho": return [
            ("hand.raised", String(localized: "Rest both hands below your navel, over the centre of your belly.")),
            ("nose", String(localized: "Breathe in very slowly through your nose and let your belly swell like a balloon.")),
            ("pause.circle", String(localized: "Hold softly for 3 to 5 seconds, as if locking the energy in.")),
            ("wind", String(localized: "Breathe out gently and let the belly settle."))]
        case "nogare": return [
            ("figure.mind.and.body", String(localized: "Stand or sit tall and let your shoulders drop.")),
            ("nose", String(localized: "Breathe in deeply and gently through your nose.")),
            ("pause.circle", String(localized: "Pause for a moment low in your belly.")),
            ("wind", String(localized: "Breathe out slowly through an open mouth without any sound, controlling it with your diaphragm."))]
        case "okinaga": return [
            ("figure.mind.and.body", String(localized: "Sit upright and quiet, and relax your face and shoulders.")),
            ("nose", String(localized: "Breathe in very slowly and silently through your nose.")),
            ("pause.circle", String(localized: "Hold gently low in your belly, without any strain.")),
            ("leaf", String(localized: "Breathe out so slowly and softly that a feather in front of your nose would not move."))]
        case "ibuki": return [
            ("figure.stand", String(localized: "Stand with your feet apart and your core ready to tighten.")),
            ("nose", String(localized: "Take a full breath in.")),
            ("wind", String(localized: "Breathe out forcefully through narrowed lips with a sharp hiss while you tighten your whole core.")),
            ("pause.circle", String(localized: "Rest and breathe normally between rounds. Stop if you feel dizzy."))]
        case "kiai": return [
            ("figure.martial.arts", String(localized: "Stand in your stance somewhere a loud shout is fine.")),
            ("nose", String(localized: "Breathe in quickly as you prepare your movement.")),
            ("megaphone", String(localized: "Breathe out sharply with a strong shout from your diaphragm as you strike or push, and tighten your core.")),
            ("pause.circle", String(localized: "Rest between rounds and breathe normally."))]
        case "kokyuho": return [
            ("figure.flexibility", String(localized: "Sit or stand with your spine long and your hands relaxed.")),
            ("arrow.up.left.and.arrow.down.right", String(localized: "Breathe in as you open your chest and lengthen your spine.")),
            ("arrow.down.right.and.arrow.up.left", String(localized: "Breathe out as you fold or round your back, emptying the air.")),
            ("repeat", String(localized: "Let the breath move you, not your muscles."))]
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

// MARK: Groups

/// One thing in the Explore grid: a ready exercise, or Resonance / Calm me.
enum NunaBreathItem: Identifiable, Equatable {
    case template(BreathTemplate)
    case tool(NunaBreathTool)
    var id: String {
        switch self { case .template(let t): return "t-" + t.id; case .tool(let t): return "k-" + t.rawValue }
    }
    var title: String { switch self { case .template(let t): return t.title; case .tool(let t): return t.title } }
    var icon: String { switch self { case .template(let t): return NunaBreathIcon.name(for: t); case .tool(let t): return t.glyph } }
    var levelTitle: String {
        switch self { case .template(let t): return NunaBreathLevel.of(t.protocolId).title; case .tool: return NunaBreathLevel.gentle.title }
    }
    var level: NunaBreathLevel {
        switch self { case .template(let t): return NunaBreathLevel.of(t.protocolId); case .tool: return .gentle }
    }
    var blurb: String { switch self { case .template(let t): return t.blurb; case .tool(let t): return t.subtitle } }
    func minutesText(lengthPref: Int) -> String {
        switch self {
        case .template(let t): return "\(lengthPref > 0 ? lengthPref : t.minutes)"
        case .tool(let t): return t.duration
        }
    }
}

/// The cards of "What is it for?": what a breath is for, and the kind of breathing, so no group has a long list. The first five follow the goals the
/// advisor knows; the others group the techniques by where they come from.
enum NunaBreathGroup: String, CaseIterable, Identifiable {
    case calm, sleep, focus, energize, recover, budoCalm, budoPower, intense, mindful, biofeedback
    var id: String { rawValue }

    private var goal: BreathGoal? {
        switch self { case .calm: return .calm; case .sleep: return .sleep; case .focus: return .focus; case .energize: return .energize; case .recover: return .recover; default: return nil }
    }
    static func of(_ goal: BreathGoal) -> NunaBreathGroup {
        switch goal { case .calm: return .calm; case .sleep: return .sleep; case .focus: return .focus; case .energize: return .energize; case .recover: return .recover }
    }

    var title: String {
        if let goal { return goal.shortTitle }
        switch self {
        case .budoCalm: return String(localized: "Japanese calm")
        case .budoPower: return String(localized: "Japanese power")
        case .intense: return String(localized: "Intense breathwork")
        case .mindful: return String(localized: "Mindful rhythm")
        default: return String(localized: "Biofeedback")
        }
    }
    var blurb: String {
        if let goal { return goal.blurbText }
        switch self {
        case .budoCalm: return String(localized: "Long, silent breaths")
        case .budoPower: return String(localized: "Sharp, strong breaths")
        case .intense: return String(localized: "For the experienced")
        case .mindful: return String(localized: "Slow and present")
        default: return String(localized: "Guided by your heart")
        }
    }
    /// The picture of the group, from the activity set.
    var icon: String {
        switch self {
        case .calm: return "Meditation"; case .sleep: return "Sleep"; case .focus: return "Breathwork"; case .energize: return "HIIT"; case .recover: return "Restorative Yoga"
        case .budoCalm: return "Tai Chi"; case .budoPower: return "Martial Arts"; case .intense: return "Ice Bath"; case .mindful: return "QiGong"; case .biofeedback: return "Non-sleep, deep rest"
        }
    }
    /// The photograph behind its page.
    var background: String { "breath-bg-" + rawValue }

    var about: String {
        if let goal { return goal.about }
        switch self {
        case .budoCalm: return String(localized: "Quiet techniques from karate, aikido and the shinobi tradition. They breathe long and silent, with the belly doing the work, to settle the heart and sharpen attention.")
        case .budoPower: return String(localized: "Forceful techniques from budo: sharp exhales, a tight core and a rhythm that goes with movement. They wake the body fast and are meant for short rounds.")
        case .intense: return String(localized: "Powerful breathwork with fast or held breaths. They are for people who already know them: short, seated, and never in water or while driving.")
        case .mindful: return String(localized: "Slow, steady rhythms to pair with presence: Qi Gong pacing and the Presence tempos. Good for longer, quieter sessions.")
        default: return String(localized: "Let your strap guide you. Resonance finds the slow pace that suits your body, and Calm me buzzes just under your heart rate and eases it down.")
        }
    }
    var benefits: [String] {
        if let goal { return goal.benefits }
        switch self {
        case .budoCalm: return [String(localized: "Settles the heart with long, silent breaths"), String(localized: "Trains steady attention and a quiet body"), String(localized: "Brings the heart rate down after effort or a scare")]
        case .budoPower: return [String(localized: "Wakes the body and firms the core"), String(localized: "Pairs breath with movement"), String(localized: "Quick and short, with no equipment")]
        case .intense: return [String(localized: "Strong effects in a few minutes"), String(localized: "Trains control of the breath"), String(localized: "Needs care: follow every caution on the page")]
        case .mindful: return [String(localized: "A slow rhythm that is easy to hold"), String(localized: "Works for longer sessions"), String(localized: "Pairs well with sitting still and paying attention")]
        default: return [String(localized: "Finds the pace that suits your body"), String(localized: "Gives a restless mind a steady beat to follow"), String(localized: "Uses your strap's heart reading and buzz")]
        }
    }

    private var templateIds: [String] {
        switch self {
        case .calm: return ["calm_slow", "calm_coherence", "calm_deep", "calm_pursed", "calm_bhramari"]
        case .sleep: return ["sleep_478", "sleep_exhale", "sleep_belly", "sleep_48", "sleep_buteyko"]
        case .focus: return ["focus_box", "focus_alternate", "focus_66", "focus_soma", "focus_buteyko"]
        case .energize: return ["energize_ocean", "energize_box", "energize_bhastrika", "energize_kapala"]
        case .recover: return ["recover_66", "recover_belly", "recover_coherence", "recover_sitali"]
        case .budoCalm: return ["focus_okinaga", "recover_nogare", "recover_kiko", "focus_kokyuho"]
        case .budoPower: return ["energize_misogi", "energize_torifune", "energize_ibuki", "energize_kiai"]
        case .intense: return ["energize_tummo", "energize_wimhof", "energize_holotropic", "energize_shamanic", "energize_punching"]
        case .mindful: return ["calm_qigong", "calm_presence", "focus_presence"]
        case .biofeedback: return []
        }
    }
    private var tools: [NunaBreathTool] { self == .biofeedback ? [.calmMe, .resonance] : [] }

    /// The group a ready exercise belongs to (the first that lists it).
    static func containing(templateId: String) -> NunaBreathGroup {
        allCases.first { $0.templateIds.contains(templateId) } ?? .calm
    }

    var firstTemplate: BreathTemplate? {
        for i in items { if case .template(let t) = i { return t } }
        return nil
    }

    var items: [NunaBreathItem] {
        templateIds.compactMap { NunaBreathLibrary.template(id: $0) }.map(NunaBreathItem.template) + tools.map(NunaBreathItem.tool)
    }

    /// The most demanding technique in it, as the group's level.
    var level: NunaBreathLevel {
        let all = items.map(\.level)
        return all.contains(.intense) ? .intense : (all.contains(.moderate) ? .moderate : .gentle)
    }
}
#endif
