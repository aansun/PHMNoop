#if os(iOS)
@preconcurrency import AVFoundation
import Foundation
import OSLog

/// iOS delivery boundary. It knows TTS/audio routing, but never decides whether an activity event exists.
@MainActor
final class AudioPromptScheduler: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
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
        NotificationCenter.default.removeObserver(self)
    }

    func setSpeechRate(_ rate: AudioSpeechRate) {
        speechRateMultiplier = rate.multiplier
    }

    func beginSession(resetFinishAfterQueue: Bool = true) {
        if resetFinishAfterQueue { finishAfterQueue = false }
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
            isSessionActive = true
        } catch {
            // A Bluetooth route can disappear while the old session still looks active. Keep the
            // queue intact and mark it inactive so the next route callback can retry activation.
            isSessionActive = false
            logger.error("Unable to activate audio session: \(String(describing: error), privacy: .public)")
        }
    }

    func enqueue(_ prompts: [AudioPrompt]) {
        guard !prompts.isEmpty else { return }
        beginSession()
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
        if current == nil && queue.isEmpty { deactivate() }
    }

    func stopImmediately() {
        routeRecoveryTask?.cancel()
        queue.removeAll()
        self.current = nil
        finishAfterQueue = false
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }

    private func speakNextIfPossible() {
        recoverIfSpeechStoppedUnexpectedly()
        guard !interrupted, !routeRecoveryInProgress, isSessionActive, current == nil else { return }
        let now = Date()
        queue.removeAll { $0.isExpired(at: now) }
        guard !queue.isEmpty else {
            if finishAfterQueue { deactivate() }
            return
        }
        let prompt = queue.removeFirst()
        current = prompt
        let utterance = AVSpeechUtterance(string: prompt.text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLanguage)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speechRateMultiplier
        utterance.pitchMultiplier = 1.0
        logger.debug("Speaking \(prompt.templateName, privacy: .public)")
        synthesizer.speak(utterance)
    }

    /// A speech synthesizer can lose its current utterance during an audio-route change without
    /// delivering `didCancel`. Do not let that stale `current` value permanently block every later
    /// milestone. The next enqueue/tick can safely recover the queue and continue speaking.
    private func recoverIfSpeechStoppedUnexpectedly() {
        guard let current, !synthesizer.isSpeaking else { return }
        if !queue.contains(where: { $0.fingerprint == current.fingerprint }) {
            queue.insert(current, at: 0)
        }
        self.current = nil
    }

    /// Preserve an in-flight sentence before resetting the audio route. AVSpeechSynthesizer can stop
    /// speaking on a Bluetooth disconnect without delivering didCancel; re-queueing the sentence
    /// makes the next prompt audible through the phone speaker or the replacement headset.
    private func preserveCurrentPrompt() {
        if let current, !queue.contains(where: { $0.fingerprint == current.fingerprint }) {
            queue.insert(current, at: 0)
        }
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func deactivate() {
        guard isSessionActive else { return }
        do { try session.setActive(false, options: [.notifyOthersOnDeactivation]) }
        catch { logger.debug("Audio session deactivation skipped: \(String(describing: error), privacy: .public)") }
        isSessionActive = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        current = nil
        speakNextIfPossible()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        current = nil
        speakNextIfPossible()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interrupted = true
            if let current { queue.insert(current, at: 0); self.current = nil }
            synthesizer.stopSpeaking(at: .immediate)
        case .ended:
            interrupted = false
            if !queue.isEmpty || current != nil || isSessionActive {
                // Do not depend on shouldResume: some route/interruption combinations omit it,
                // even though speech must continue after the interruption ends.
                beginSession(resetFinishAfterQueue: false)
            }
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
        guard isSessionActive || current != nil || !queue.isEmpty else { return }

        // The callback can arrive before the replacement route is ready. Reactivate after a short
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
        beginSession(resetFinishAfterQueue: false)
        routeRecoveryInProgress = false
        speakNextIfPossible()
    }
}
#endif
