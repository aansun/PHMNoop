#if os(iOS)
@preconcurrency import AVFoundation
import Foundation
import OSLog

/// iOS delivery boundary. It knows TTS/audio routing, but never decides whether an activity event exists.
///
/// It behaves like the spoken prompts of a navigation or sports app (Garmin, Apple Maps), not like a music player:
///  - The audio session is brought up only when a cue is about to be spoken and released shortly after the last one, so music is lowered
///    (ducked) for the length of the cue and comes back at full volume, instead of staying quiet through the whole workout.
///  - The mode is "voice prompt", which lowers music and pauses spoken-word audio (a podcast) rather than talking over it.
///  - A short tone comes first, so a cue is noticed over music or wind; it can be switched off.
///  - A plain playback session: the silent switch does not mute it, a Bluetooth headset keeps its normal stereo route (no hands-free
///    profile), and with the app's audio background mode it keeps speaking with the screen locked.
///  - Nothing is assumed to have worked. The scheduler listens for the voice actually starting and finishing, and when it does not start it
///    says so and tries once more with a fresh synthesizer and the system voice.
@MainActor
final class AudioPromptScheduler: NSObject, @preconcurrency AVSpeechSynthesizerDelegate, @preconcurrency AVAudioPlayerDelegate {
    private var synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.phm.noop", category: "AudioCoaching")
    private var queue: [AudioPrompt] = []
    private var current: AudioPrompt?
    private var isSessionActive = false
    private var finishAfterQueue = false
    private var interrupted = false
    private var speechRateMultiplier = AudioSpeechRate.normal.multiplier
    private var routeRecoveryTask: Task<Void, Never>?
    private var routeRecoveryInProgress = false

    /// Whether the voice of the current cue has begun, and whether it already got its one retry.
    private var started = false
    private var retried = false
    private var watchdog: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?
    /// The tone plays once at the start of a burst of cues, not before each of a queue.
    private var chime: AVAudioPlayer?
    private var awaitingChime = false
    private var chimedThisBurst = false
    /// The sound of a finished rest. It shares the session with the cues but is not one: nothing is spoken.
    private var marker: AVAudioPlayer?

    private var speechLanguage: String {
        let preferred = Bundle.main.preferredLocalizations.first?.lowercased() ?? ""
        if preferred.hasPrefix("id") { return "id-ID" }
        if preferred.hasPrefix("en") { return "en-US" }
        return Locale.preferredLanguages.first ?? "en-US"
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: session)
    }

    deinit {
        routeRecoveryTask?.cancel()
        releaseTask?.cancel()
        watchdog?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func setSpeechRate(_ rate: AudioSpeechRate) {
        speechRateMultiplier = rate.multiplier
    }

    /// The last thing that went wrong getting the audio session or the voice going, for the test screen to show. Nil when all is well.
    private(set) var lastError: String?
    var onStatus: ((String?) -> Void)?
    /// What happened, step by step ("Output: iPhone Speaker", "Speech started"), for the test screen.
    var onDetail: ((String) -> Void)?

    private func report(_ message: String?) {
        lastError = message
        onStatus?(message)
    }

    // MARK: Public

    /// A workout begins or the coach is switched on. Nothing is held: the audio session comes up when a cue is spoken.
    func beginSession(resetFinishAfterQueue: Bool = true) {
        if resetFinishAfterQueue { finishAfterQueue = false }
    }

    func enqueue(_ prompts: [AudioPrompt]) {
        guard !prompts.isEmpty else { return }
        recoverIfSpeechStoppedUnexpectedly()
        let now = Date()
        queue.removeAll { $0.isExpired(at: now) }
        for prompt in prompts where !prompt.isExpired(at: now) {
            guard !queue.contains(where: { $0.fingerprint == prompt.fingerprint }) else { continue }
            queue.append(prompt)
        }
        queue.sort { lhs, rhs in
            if lhs.priority == rhs.priority { return lhs.createdAt < rhs.createdAt }
            return lhs.priority < rhs.priority
        }
        speakNextIfPossible()
    }

    func endAfterQueue() {
        finishAfterQueue = true
        if current == nil && queue.isEmpty && !awaitingChime { deactivate() }
    }

    func stopImmediately() {
        routeRecoveryTask?.cancel()
        releaseTask?.cancel()
        watchdog?.cancel()
        chime?.stop(); chime = nil
        awaitingChime = false
        queue.removeAll()
        self.current = nil
        finishAfterQueue = false
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }

    /// A short rising tone to mark something that needs no words (a gym rest period ending). Music is lowered for it and returns.
    /// A cue being spoken already makes sound, so the tone waits for no one and is simply skipped then.
    func playMarker() {
        guard !interrupted, current == nil, !awaitingChime, marker == nil else { return }
        releaseTask?.cancel()
        guard activate(), let player = Self.makeMarker() else { return }
        marker = player
        player.delegate = self
        player.volume = 1
        if player.play() { onDetail?(String(localized: "Rest-end tone played")) }
        else { marker = nil; scheduleRelease() }
    }

    // MARK: Audio session

    /// Bring the session up for a cue. Voice-prompt mode first; if iOS refuses it the plainer modes follow, so the coach is not left silent.
    @discardableResult
    private func activate() -> Bool {
        if isSessionActive { return true }
        let attempts: [(AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.voicePrompt, [.duckOthers, .interruptSpokenAudioAndMixWithOthers]),
            (.spokenAudio, [.duckOthers]),
            (.default, []),
        ]
        var failure: Error?
        for (mode, options) in attempts {
            do {
                try session.setCategory(.playback, mode: mode, options: options)
                try session.setActive(true, options: [])
                isSessionActive = true
                report(nil)
                let route = session.currentRoute.outputs.first?.portName ?? "?"
                let volume = Int((session.outputVolume * 100).rounded())
                onDetail?(String(localized: "Output: \(route) · volume \(volume)%"))
                if volume == 0 { report(String(localized: "The media volume is at zero. Raise it with the volume buttons.")) }
                return true
            } catch {
                failure = error
            }
        }
        let message = failure.map { String(describing: $0) } ?? "unknown"
        report(String(localized: "The audio session would not start: \(message)"))
        logger.error("Unable to activate audio session: \(message, privacy: .public)")
        return false
    }

    private func deactivate() {
        releaseTask?.cancel()
        chimedThisBurst = false
        guard isSessionActive else { return }
        do { try session.setActive(false, options: [.notifyOthersOnDeactivation]) }
        catch { logger.debug("Audio session deactivation skipped: \(String(describing: error), privacy: .public)") }
        isSessionActive = false
    }

    /// Give the session back shortly after the last cue, so the music returns to full volume.
    private func scheduleRelease() {
        if finishAfterQueue { deactivate(); return }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self, self.current == nil, self.queue.isEmpty, !self.awaitingChime else { return }
            self.deactivate()
        }
    }

    // MARK: Speaking

    private func speakNextIfPossible() {
        recoverIfSpeechStoppedUnexpectedly()
        guard !interrupted, !routeRecoveryInProgress, current == nil, !awaitingChime else { return }
        let now = Date()
        queue.removeAll { $0.isExpired(at: now) }
        guard !queue.isEmpty else { scheduleRelease(); return }
        releaseTask?.cancel()
        guard activate() else { return }   // the queue stays; a route change or the next cue tries again
        let prompt = queue.removeFirst()
        current = prompt
        started = false; retried = false

        if !chimedThisBurst, AudioCoachingPreferences.chimeEnabled, let player = Self.makeChime() {
            chimedThisBurst = true
            awaitingChime = true
            chime = player
            player.delegate = self
            player.volume = 1
            if player.play() { onDetail?(String(localized: "Tone played")); return }
            awaitingChime = false
        }
        speak(prompt.text, voiceFallback: false)
    }

    /// The best installed voice for the language: an exact match first, higher quality first, never a novelty voice.
    private func chooseVoice() -> (voice: AVSpeechSynthesisVoice?, note: String) {
        let language = speechLanguage
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !$0.identifier.lowercased().contains("eloquence") && !$0.identifier.contains("synthesis.voice.") }
        func best(_ list: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? { list.max { $0.quality.rawValue < $1.quality.rawValue } }
        if let v = best(voices.filter { $0.language == language }) ?? AVSpeechSynthesisVoice(language: language) {
            return (v, "\(v.name) (\(v.language))")
        }
        let prefix = language.split(separator: "-").first.map(String.init) ?? language
        if let v = best(voices.filter { $0.language.hasPrefix(prefix) }) { return (v, "\(v.name) (\(v.language))") }
        if let v = AVSpeechSynthesisVoice(language: "en-US") {
            return (v, String(localized: "\(v.name) (English: no \(language) voice is installed)"))
        }
        return (nil, String(localized: "the system voice"))
    }

    private func speak(_ text: String, voiceFallback: Bool) {
        let utterance = AVSpeechUtterance(string: text)
        if voiceFallback {
            onDetail?(String(localized: "Voice: the system voice"))
        } else {
            let choice = chooseVoice()
            utterance.voice = choice.voice
            onDetail?(String(localized: "Voice: \(choice.note)"))
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speechRateMultiplier
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        logger.debug("Speaking \(self.current?.templateName ?? "", privacy: .public)")
        synthesizer.speak(utterance)
        armWatchdog(text: text)
    }

    /// A voice that never starts is the usual cause of a silent coach. Say so, and try once more with a fresh synthesizer.
    private func armWatchdog(text: String) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.current != nil, !self.started else { return }
            self.speechDidNotStart(text: text)
        }
    }

    private func speechDidNotStart(text: String) {
        if !retried {
            retried = true
            onDetail?(String(localized: "The voice did not start. Trying again."))
            synthesizer.stopSpeaking(at: .immediate)
            synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            speak(text, voiceFallback: true)
        } else {
            report(String(localized: "The voice did not start. Check Settings › Accessibility › Spoken Content › Voices for a downloaded voice, and that the volume is up."))
            current = nil
            started = false
            speakNextIfPossible()
        }
    }

    /// A speech synthesizer can lose its current utterance during an audio-route change without
    /// delivering `didCancel`. Do not let that stale `current` value permanently block every later
    /// milestone. The next enqueue/tick can safely recover the queue and continue speaking.
    private func recoverIfSpeechStoppedUnexpectedly() {
        // Only a cue that had begun can be lost this way; one that never began is the watchdog's.
        guard let current, !awaitingChime, started, !synthesizer.isSpeaking else { return }
        if !queue.contains(where: { $0.fingerprint == current.fingerprint }) {
            queue.insert(current, at: 0)
        }
        self.current = nil
        started = false
    }

    /// Preserve an in-flight sentence before resetting the audio route. AVSpeechSynthesizer can stop
    /// speaking on a Bluetooth disconnect without delivering didCancel; re-queueing the sentence
    /// makes the next prompt audible through the phone speaker or the replacement headset.
    private func preserveCurrentPrompt() {
        if let current, !queue.contains(where: { $0.fingerprint == current.fingerprint }) {
            queue.insert(current, at: 0)
        }
        current = nil
        started = false
        awaitingChime = false
        chime?.stop(); chime = nil
        watchdog?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: Delegates

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        started = true
        watchdog?.cancel()
        report(nil)
        onDetail?(String(localized: "Speech started"))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onDetail?(String(localized: "Speech finished"))
        current = nil
        started = false
        speakNextIfPossible()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // A cancel we caused while retrying is not the end of the cue.
        guard self.synthesizer === synthesizer else { return }
        current = nil
        started = false
        speakNextIfPossible()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === marker {
            marker = nil
            if current == nil && !awaitingChime { speakNextIfPossible() }   // anything that queued meanwhile, else the session is released
            return
        }
        chime = nil
        awaitingChime = false
        guard let prompt = current else { speakNextIfPossible(); return }
        speak(prompt.text, voiceFallback: false)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interrupted = true
            preserveCurrentPrompt()
            isSessionActive = false
        case .ended:
            interrupted = false
            isSessionActive = false
            // Do not depend on shouldResume: some route/interruption combinations omit it, even though speech must continue.
            speakNextIfPossible()
        @unknown default:
            interrupted = false
            speakNextIfPossible()
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        logger.debug("Audio route changed: \(String(describing: reason), privacy: .public)")
        guard current != nil || !queue.isEmpty else { return }

        // The callback can arrive before the replacement route is ready. Retry after a short
        // delay so headset disconnect → speaker and headset reconnect both resume automatically.
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.recoverAfterRouteChange()
        }
    }

    private func recoverAfterRouteChange() {
        guard !interrupted else { return }
        routeRecoveryInProgress = true
        preserveCurrentPrompt()
        isSessionActive = false
        routeRecoveryInProgress = false
        speakNextIfPossible()
    }

    // MARK: The tone

    private static let rate = 44_100.0

    /// A sine note with a quick attack and a soft release, so it does not click.
    private static func note(_ hz: Double, _ seconds: Double, gain: Double = 0.4) -> [Int16] {
        (0..<Int(rate * seconds)).map { i in
            let t = Double(i) / rate
            let envelope = min(1, t / 0.01) * min(1, (seconds - t) / 0.05)
            return Int16(sin(2 * .pi * hz * t) * envelope * gain * Double(Int16.max))
        }
    }

    private static func silence(_ seconds: Double) -> [Int16] { [Int16](repeating: 0, count: Int(rate * seconds)) }

    /// 16-bit mono PCM as a WAV file in memory.
    private static func wav(_ samples: [Int16]) -> Data {
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; d.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let bytes = samples.count * 2
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        for s in samples { put(s) }
        return d
    }

    /// Two notes, a step up: "a cue is coming".
    private static let chimeData = wav(note(880, 0.12) + silence(0.03) + note(1174.66, 0.16))
    /// Three notes climbing: "rest is over". Longer and brighter than the cue tone, so the two are never confused.
    private static let markerData = wav(note(784, 0.12) + silence(0.02) + note(988, 0.12) + silence(0.02) + note(1318.5, 0.26, gain: 0.5))

    private static func makeMarker() -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: markerData)
        player?.prepareToPlay()
        return player
    }

    private static func makeChime() -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: chimeData)
        player?.prepareToPlay()
        return player
    }
}
#endif
