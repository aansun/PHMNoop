#if os(iOS)
import Combine
import Foundation
import OSLog
import SwiftUI

/// iOS adapter from the existing AppModel publishers into the device-agnostic audio engines.
/// It owns no BLE lifecycle and remains alive at the app root while the workout UI is dismissed or the
/// phone is backgrounded.
@MainActor
final class AudioCoachingCoordinator: ObservableObject {
    @Published private(set) var lastPromptText: String?
    @Published private(set) var lastDecision: String?
    @Published private(set) var promptHistory: [AudioPrompt] = []

    private let activityEngine = AudioActivityEngine()
    private let trendEngine = AudioTrendEngine()
    private let coachingRuleEngine = AudioCoachingRuleEngine()
    private let aiCoachingProvider = AudioAICoachingProvider()
    private let promptEngine = AudioPromptEngine()
    private let scheduler = AudioPromptScheduler()
    private let logger = Logger(subsystem: "com.phm.noop", category: "AudioCoaching")
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private weak var model: AppModel?
    private var workout: AppModel.ActiveWorkout?
    private var latestHeartRate: Int?
    private var latestHeartRateAt: Date?
    private var latestDistance: Double?
    private var latestPace: Double?
    private var latestCadence: Double?
    private var latestTrends = AudioMetricTrends(sampleCount: 0, windowDuration: 0,
                                                 heartRateDeltaBPM: nil,
                                                 paceDeltaSecondsPerKm: nil,
                                                 cadenceDeltaSPM: nil)

    deinit { timer?.invalidate() }

    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        AudioAICoachingProvider.bootstrapDefaults()
        scheduler.setSpeechRate(AudioCoachingPreferences.speechRate)
        model.$activeWorkout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workout in self?.handleWorkoutChange(workout) }
            .store(in: &cancellables)
        model.$bpm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in self?.handleHeartRate(bpm) }
            .store(in: &cancellables)
        model.gpsRecorder.$distanceM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] distance in
                self?.latestDistance = distance
                self?.ingestCurrentMetrics()
            }
            .store(in: &cancellables)
        model.gpsRecorder.$paceSecPerKm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pace in
                self?.latestPace = pace
                self?.ingestCurrentMetrics()
            }
            .store(in: &cancellables)
        model.live.$sensorCadence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cadence in
                self?.latestCadence = cadence
                self?.ingestCurrentMetrics()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.preferencesChanged() }
            .store(in: &cancellables)

        if let active = model.activeWorkout { handleWorkoutChange(active) }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        guard workout != nil else { return }
        if phase == .active, AudioCoachingPreferences.policy().enabled {
            scheduler.beginSession()
        }
    }

    /// Plays a deterministic sample without requiring an active workout. This is intentionally an
    /// explicit user action so it remains available while the experiment toggle is off.
    func testAudio() {
        let storedPolicy = AudioCoachingPreferences.policy()
        guard storedPolicy.distancePrompts else {
            lastDecision = "Distance milestones are disabled"
            return
        }
        guard storedPolicy.distanceIncludesDistance || storedPolicy.distanceIncludesDuration || storedPolicy.distanceIncludesHeartRate else {
            lastDecision = "Enable at least one milestone detail"
            return
        }
        let policy = AudioPromptPolicy(
            enabled: true,
            lifecyclePrompts: storedPolicy.lifecyclePrompts,
            heartRatePrompts: storedPolicy.heartRatePrompts,
            distancePrompts: storedPolicy.distancePrompts,
            frequency: storedPolicy.frequency,
            coachingPrompts: storedPolicy.coachingPrompts,
            coachingFrequency: storedPolicy.coachingFrequency,
            distanceIncludesDistance: storedPolicy.distanceIncludesDistance,
            distanceIncludesDuration: storedPolicy.distanceIncludesDuration,
            distanceIncludesHeartRate: storedPolicy.distanceIncludesHeartRate,
            distanceMilestoneKilometers: storedPolicy.distanceMilestoneKilometers)
        let kilometre = Double(policy.distanceMilestoneKilometers)
        let context = AudioWorkoutContext(
            sport: "Test",
            state: .active,
            duration: kilometre * 360,
            targetHeartRate: nil,
            heartRate: 142,
            heartRateZone: 3,
            distanceMeters: kilometre * 1_000)
        scheduler.setSpeechRate(AudioCoachingPreferences.speechRate)
        let prompt = promptEngine.testPrompt(context: context, policy: policy)
        lastPromptText = prompt.text
        promptHistory = Array(([prompt] + promptHistory).prefix(10))
        lastDecision = "Test audio queued using current settings"
        scheduler.enqueue([prompt])
        logger.debug("Queued audio coaching test prompt")
    }

    private func handleWorkoutChange(_ next: AppModel.ActiveWorkout?) {
        let previous = workout
        workout = next
        switch (previous, next) {
        case (nil, .some(let next)):
            start(next)
        case (.some(let previous), .some(let next)) where previous.start != next.start:
            finish(previous)
            start(next)
        case (.some(let previous), .some(let next)):
            if previous.isPaused != next.isPaused {
                trendEngine.reset()
                coachingRuleEngine.reset()
                let events = next.isPaused ? activityEngine.pause() : activityEngine.resume()
                emit(events, for: next)
            }
            ingestCurrentMetrics()
        case (.some(let previous), nil):
            finish(previous)
        case (nil, nil):
            break
        }
    }

    private func start(_ workout: AppModel.ActiveWorkout) {
        timer?.invalidate()
        _ = activityEngine.start(at: workout.start)
        trendEngine.reset()
        coachingRuleEngine.reset()
        latestTrends = AudioMetricTrends(sampleCount: 0, windowDuration: 0,
                                         heartRateDeltaBPM: nil, paceDeltaSecondsPerKm: nil,
                                         cadenceDeltaSPM: nil)
        promptEngine.reset()
        promptHistory.removeAll()
        scheduler.setSpeechRate(AudioCoachingPreferences.speechRate)
        if AudioCoachingPreferences.policy().enabled { scheduler.beginSession() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ingestCurrentMetrics() }
        }
        emit([.activityStarted], for: workout)
        logger.debug("Audio coaching activity started")
    }

    private func finish(_ workout: AppModel.ActiveWorkout) {
        timer?.invalidate()
        timer = nil
        let events = activityEngine.end()
        emit(events, for: workout)
        if AudioCoachingPreferences.policy().enabled {
            scheduler.endAfterQueue()
        } else {
            scheduler.stopImmediately()
        }
        latestHeartRate = nil
        latestHeartRateAt = nil
        latestDistance = nil
        latestPace = nil
        latestCadence = nil
        trendEngine.reset()
        coachingRuleEngine.reset()
        latestTrends = AudioMetricTrends(sampleCount: 0, windowDuration: 0,
                                         heartRateDeltaBPM: nil, paceDeltaSecondsPerKm: nil,
                                         cadenceDeltaSPM: nil)
        logger.debug("Audio coaching activity ended")
    }

    private func handleHeartRate(_ bpm: Int?) {
        guard let bpm, (30...220).contains(bpm) else {
            latestHeartRate = nil
            latestHeartRateAt = nil
            ingestCurrentMetrics()
            return
        }
        latestHeartRate = bpm
        latestHeartRateAt = Date()
        ingestCurrentMetrics()
    }

    private func ingestCurrentMetrics() {
        guard let workout, !workout.isPaused else { return }
        let now = Date()
        let metrics = AudioLiveMetrics(
            timestamp: now,
            heartRate: latestHeartRate,
            heartRateSampleAt: latestHeartRateAt,
            heartRateZone: currentHeartRateZone(),
            distanceMeters: latestDistance,
            paceSecondsPerKm: latestPace,
            state: .active,
            targetHeartRate: targetHeartRate(),
            cadenceSPM: latestCadence)
        let trends = trendEngine.update(metrics)
        latestTrends = trends
        let events = activityEngine.update(metrics) + coachingRuleEngine.update(metrics: metrics, trends: trends)
        emit(events, for: workout, now: now)
    }

    private func targetHeartRate() -> ClosedRange<Int>? {
        let zone = AudioCoachingPreferences.targetZone
        guard zone > 0, let band = model?.profile.hrZoneSet.zones.first(where: { $0.number == zone }) else {
            return nil
        }
        let lower = Int(ceil(band.lower))
        let upper = Int(floor(band.upper))
        guard lower <= upper else { return nil }
        return lower...upper
    }

    private func currentHeartRateZone() -> Int? {
        guard let heartRate = latestHeartRate, let model else { return nil }
        let zone = model.profile.hrZoneSet.zoneNumber(forBPM: Double(heartRate))
        return zone > 0 ? zone : nil
    }

    private func emit(_ events: [AudioActivityEvent], for workout: AppModel.ActiveWorkout, now: Date = Date()) {
        guard !events.isEmpty else { return }
        let policy = AudioCoachingPreferences.policy()
        guard policy.enabled else {
            lastDecision = "Audio coaching is disabled"
            return
        }
        let context = AudioWorkoutContext(
            sport: workout.sport,
            state: workout.isPaused ? .paused : .active,
            duration: workout.elapsed(at: now),
            targetHeartRate: targetHeartRate(),
            heartRate: latestHeartRate,
            heartRateZone: currentHeartRateZone(),
            distanceMeters: latestDistance)
        let prompts = promptEngine.prompts(for: events, context: context, policy: policy, now: now)
        lastDecision = prompts.isEmpty ? "Event suppressed by policy or cooldown" : "\(prompts.count) prompt queued"
        guard !prompts.isEmpty else { return }
        let aiEnabled = UserDefaults.standard.object(forKey: AudioCoachingPreferences.aiWordingKey) as? Bool ?? false
        let aiPrompts = aiEnabled ? prompts.filter { $0.priority == .coaching } : []
        let immediatePrompts = prompts.filter { !aiPrompts.contains($0) }
        if !immediatePrompts.isEmpty {
            lastPromptText = immediatePrompts.last?.text
            promptHistory = Array((immediatePrompts + promptHistory).prefix(10))
            scheduler.enqueue(immediatePrompts)
        }
        if !aiPrompts.isEmpty, aiCoachingProvider.isConfigured, model?.coach.dataConsent == true {
            for prompt in aiPrompts {
                guard let intent = events.compactMap({ event -> AudioCoachingIntent? in
                    if case .coachingIntent(let intent) = event { return intent }
                    return nil
                }).first else { continue }
                let aiContext = AudioAICoachingContext(
                    sport: workout.sport,
                    duration: workout.elapsed(at: now),
                    heartRate: latestHeartRate,
                    heartRateZone: currentHeartRateZone(),
                    heartRateDelta: latestTrends.heartRateDeltaBPM,
                    paceDelta: latestTrends.paceDeltaSecondsPerKm,
                    cadenceDelta: latestTrends.cadenceDeltaSPM)
                let workoutStart = workout.start
                Task { [weak self] in
                    let rewritten = await self?.aiCoachingProvider.rewrite(intent: intent, context: aiContext)
                    self?.deliverAIPrompt(rewritten, fallback: prompt, workoutStart: workoutStart)
                }
            }
        } else if !aiPrompts.isEmpty {
            lastPromptText = aiPrompts.last?.text
            promptHistory = Array((aiPrompts + promptHistory).prefix(10))
            scheduler.enqueue(aiPrompts)
        }
        logger.debug("Queued \(prompts.count) audio coaching prompt(s)")
    }

    private func deliverAIPrompt(_ rewritten: String?, fallback: AudioPrompt, workoutStart: Date) {
        guard workout?.start == workoutStart else { return }
        let prompt = rewritten.map {
            AudioPrompt(id: fallback.id, fingerprint: fallback.fingerprint, templateName: "coaching.ai",
                        text: $0, priority: fallback.priority, createdAt: fallback.createdAt,
                        expiresAt: fallback.expiresAt, source: .activityRule)
        } ?? fallback
        lastPromptText = prompt.text
        promptHistory = Array(([prompt] + promptHistory).prefix(10))
        scheduler.enqueue([prompt])
    }

    private func preferencesChanged() {
        scheduler.setSpeechRate(AudioCoachingPreferences.speechRate)
        coachingRuleEngine.reset()
        guard workout != nil else { return }
        if AudioCoachingPreferences.policy().enabled {
            scheduler.beginSession()
        } else {
            scheduler.stopImmediately()
        }
    }
}
#endif
