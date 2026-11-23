#if os(iOS)
import SwiftUI
import AVFoundation
import StrandAnalytics

/// How a breathing session is cued by ear: not at all, by soft tones, or by Anya's voice saying each step.
enum NunaBreathAudioMode: String, CaseIterable, Identifiable {
    case off, tone, voice
    var id: String { rawValue }

    static let key = "nuna.breath.audioMode"

    var title: LocalizedStringKey {
        switch self { case .off: return "Off"; case .tone: return "Tones"; case .voice: return "Anya's voice" }
    }

    /// The choice made, or the old on/off switch's answer for someone who made none: audio cues on meant tones.
    static var stored: NunaBreathAudioMode {
        if let raw = UserDefaults.standard.string(forKey: key), let m = NunaBreathAudioMode(rawValue: raw) { return m }
        return UserDefaults.standard.bool(forKey: NunaBreathPrefs.audioKey) ? .tone : .off
    }
}

/// Anya's voice for the breath: the step said aloud ("Breathe in", "Hold", "Breathe out") in the language of the app, with the best voice the
/// phone has for it. It is spoken through the playback session, so it is heard with the screen locked, and it lowers other audio for a moment
/// instead of stopping it. Nothing is sent anywhere: the phone's own speech synthesiser speaks.
@MainActor
final class BreathVoice: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var active = false

    func activate() {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: [])
        active = true
    }

    func deactivate() {
        synthesizer.stopSpeaking(at: .immediate)
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        active = false
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    /// With `queued` the words wait for what is being said (the first step after "Let's begin") instead of cutting it off.
    func say(_ text: String, queued: Bool = false) {
        guard active, !text.isEmpty else { return }
        // A step said late is worse than not said: the one in progress is cut off by the next.
        if !queued || !synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice()
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        u.pitchMultiplier = 0.95
        u.volume = 1
        synthesizer.speak(u)
    }

    /// The best installed voice for the app's language, falling back to the phone's default.
    private static func voice() -> AVSpeechSynthesisVoice? {
        let code = AppLanguage.activeLocale.language.languageCode?.identifier ?? "en"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: AppLanguage.activeLocale.identifier)
    }
}

/// The audio side of a breathing session: tones or voice, chosen in Settings and changeable from the speaker button, one cue for each step.
@MainActor
final class NunaBreathCue: ObservableObject {
    private let tones = BreathTonePlayer()
    private let voice = BreathVoice()
    @Published private(set) var mode: NunaBreathAudioMode = .off

    /// Brings the chosen audio up and the other down; holds the audio session only while one is wanted.
    func apply(_ new: NunaBreathAudioMode) {
        mode = new
        switch new {
        case .off: tones.deactivate(); voice.deactivate()
        case .tone: voice.deactivate(); tones.activate()
        case .voice: tones.deactivate(); voice.activate()
        }
    }

    func deactivate() { guard !releasing else { return }; apply(.off) }

    /// The cue for the step that begins now. `previous` tells a hold after the inhale (lungs full) from one after the exhale (lungs empty).
    func cue(_ phase: BreathPhase, previous: BreathPhase?, label: String?, queued: Bool = false) {
        switch mode {
        case .off: break
        case .tone:
            switch phase {
            case .inhale: tones.play(.inhale, queued: queued)
            case .exhale: tones.play(.exhale, queued: queued)
            case .hold: tones.play(previous == .exhale ? .holdEmpty : .holdFull, queued: queued)
            case .textOnly: break
            }
        case .voice:
            switch phase {
            case .inhale: voice.say(String(localized: "Breathe in"), queued: queued)
            case .exhale: voice.say(String(localized: "Breathe out"), queued: queued)
            case .hold: voice.say(String(localized: "Hold"), queued: queued)
            case .textOnly: if let l = label, !l.isEmpty { voice.say(String(localized: String.LocalizationValue(l)), queued: queued) }
            }
        }
    }

    /// The marks of the session itself, which the wearer hears whichever way the steps are cued: the start, a pause, a carry-on and the end.
    func started() {
        switch mode {
        case .off: break
        case .tone: tones.play(.begin)
        case .voice: voice.say(String(localized: "Let's begin. Get comfortable and breathe with me."))
        }
    }

    func paused() {
        switch mode {
        case .off: break
        case .tone: tones.play(.pause)
        case .voice: voice.say(String(localized: "Paused."))
        }
    }

    func resumed() {
        switch mode {
        case .off: break
        case .tone: tones.play(.begin)
        case .voice: voice.say(String(localized: "Continuing."))
        }
    }

    /// Said (or sounded) once the last breath is out.
    func finished() {
        switch mode {
        case .off: break
        case .tone: tones.play(.complete)
        case .voice: voice.say(String(localized: "The exercise is complete. Well done. Now breathe normally."))
        }
    }

    func silence() { voice.stop() }

    /// Set while the closing words are still being spoken: the screen that ends under them must not cut them off.
    private var releasing = false

    /// Lets the closing words finish before the audio session is released, also after the screen that began them is gone.
    func releaseAfterFinishing() {
        guard mode != .off else { deactivate(); return }
        releasing = true
        finished()
        let wait: UInt64 = mode == .voice ? 6_000_000_000 : 3_200_000_000
        Task { try? await Task.sleep(nanoseconds: wait); releasing = false; deactivate() }
    }
}
#endif
