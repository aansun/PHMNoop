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

    deinit { NotificationCenter.default.removeObserver(self) }

    func beginSession() {
        finishAfterQueue = false
        guard !isSessionActive else { return }
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
            isSessionActive = true
        } catch {
            logger.error("Unable to activate audio session: \(String(describing: error), privacy: .public)")
        }
    }

    func enqueue(_ prompts: [AudioPrompt]) {
        guard !prompts.isEmpty else { return }
        beginSession()
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
        queue.removeAll()
        current = nil
        finishAfterQueue = false
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }

    private func speakNextIfPossible() {
        guard !interrupted, current == nil else { return }
        let now = Date()
        queue.removeAll { $0.isExpired(at: now) }
        guard !queue.isEmpty else {
            if finishAfterQueue { deactivate() }
            return
        }
        let prompt = queue.removeFirst()
        current = prompt
        let utterance = AVSpeechUtterance(string: prompt.text)
        let language = Locale.preferredLanguages.first ?? "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        logger.debug("Speaking \(prompt.templateName, privacy: .public)")
        synthesizer.speak(utterance)
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
            if let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                beginSession()
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
    }
}
#endif
