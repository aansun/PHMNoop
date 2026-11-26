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
    /// The voice picked when the session's audio came up. Looking through the installed voices takes long enough to be heard, so it is not done at every step.
    private var chosen: AVSpeechSynthesisVoice?
    /// Called once, when the words it was asked with begin to sound.
    private var onStart: (id: ObjectIdentifier, call: () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func activate() {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: [])
        chosen = Self.voice()
        active = true
    }

    func deactivate() {
        synthesizer.stopSpeaking(at: .immediate)
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        active = false
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    /// With `queued` the words wait for what is being said instead of cutting it off. `started` is called when they begin to sound.
    func say(_ text: String, queued: Bool = false, started: (() -> Void)? = nil) {
        guard active, !text.isEmpty else { started?(); return }
        // A step said late is worse than not said: the one in progress is cut off by the next.
        if !queued || !synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = chosen
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        u.pitchMultiplier = 0.95
        u.volume = 1
        onStart = started.map { (ObjectIdentifier(u), $0) }
        synthesizer.speak(u)
    }

    /// The best installed voice for the app's language, falling back to the phone's default.
    private static func voice() -> AVSpeechSynthesisVoice? {
        let code = AppLanguage.activeLocale.language.languageCode?.identifier ?? "en"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: AppLanguage.activeLocale.identifier)
    }
}

extension BreathVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.began(id) }
    }

    /// Words asked for earlier may only now be starting; only the ones waited for are answered.
    private func began(_ id: ObjectIdentifier) {
        guard let waiting = onStart, waiting.id == id else { return }
        onStart = nil
        waiting.call()
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
        epoch += 1
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

    /// One number of the countdown, said or ticked. Returns when it can be heard, so the number on screen is timed from the sound and not from the
    /// request: the phone takes a moment to find its voice the first time. It never waits longer than `patience`.
    func count(_ n: Int) async {
        switch mode {
        case .off: return
        case .tone: tones.play(.count)
        case .voice:
            let patience: UInt64 = 1_200_000_000
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var waiting: CheckedContinuation<Void, Never>? = done
                let resume: @MainActor () -> Void = { waiting?.resume(); waiting = nil }
                voice.say("\(n)", started: resume)
                Task { @MainActor in try? await Task.sleep(nanoseconds: patience); resume() }
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
    /// Bumped whenever the audio is set up again (a new session starts), so a release scheduled by the last one does not take it down.
    private var epoch = 0

    /// Lets the closing words finish before the audio session is released, also after the screen that began them is gone.
    func releaseAfterFinishing() {
        guard mode != .off else { deactivate(); return }
        releasing = true
        finished()
        let wait: UInt64 = mode == .voice ? 6_000_000_000 : 3_200_000_000
        let mine = epoch
        Task {
            try? await Task.sleep(nanoseconds: wait)
            releasing = false
            if epoch == mine { deactivate() }
        }
    }
}
/// 3, 2, 1 before a breathing session, drawn as before an activity. Each number appears when its sound (Anya's voice or the tick) is heard, not when it
/// is asked for, and is held for a second from there.
struct NunaBreathCountdown: View {
    let cue: NunaBreathCue
    let onDone: () -> Void
    let onCancel: () -> Void
    /// Nil for the moment before the first number can be heard.
    @State private var count: Int?

    var body: some View {
        NunaCountdownOverlay(count: count) { cue.silence(); onCancel() }
            .task {
                for n in stride(from: 3, through: 1, by: -1) {
                    await cue.count(n)
                    if Task.isCancelled { return }
                    count = n
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
                onDone()
            }
    }
}
#endif
