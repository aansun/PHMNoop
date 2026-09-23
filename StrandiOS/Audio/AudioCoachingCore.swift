import Foundation

/// The normalized state consumed by the activity engine. The engine does not know whether a sample
/// came from WHOOP, GPS, HealthKit, or a replay.
enum AudioActivityState: String, Equatable, Sendable {
    case idle
    case preparing
    case active
    case paused
    case ending
    case completed
}

/// A device-agnostic live sample. `heartRateSampleAt` is separate from `timestamp` so a periodic
/// scheduler can detect a stale HR stream instead of making an old value look fresh.
struct AudioLiveMetrics: Equatable, Sendable {
    let timestamp: Date
    let heartRate: Int?
    let heartRateSampleAt: Date?
    let heartRateZone: Int?
    let distanceMeters: Double?
    let paceSecondsPerKm: Double?
    let state: AudioActivityState
    let targetHeartRate: ClosedRange<Int>?

    init(timestamp: Date = Date(), heartRate: Int?, heartRateSampleAt: Date?, heartRateZone: Int?,
         distanceMeters: Double?, paceSecondsPerKm: Double?, state: AudioActivityState,
         targetHeartRate: ClosedRange<Int>?) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.heartRateSampleAt = heartRateSampleAt
        self.heartRateZone = heartRateZone
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKm = paceSecondsPerKm
        self.state = state
        self.targetHeartRate = targetHeartRate
    }
}

/// Semantic events. These are intentionally not sentences; wording belongs to the prompt layer.
enum AudioActivityEvent: Equatable, Sendable {
    case activityStarted
    case activityPaused
    case activityResumed
    case activityEnded
    case distanceMilestone(meters: Double)
    case heartRateAboveTarget(current: Int, targetMax: Int)
    case heartRateBelowTarget(current: Int, targetMin: Int)
    case heartRateReturnedToTarget

    var priority: AudioPromptPriority {
        switch self {
        case .activityStarted, .activityPaused, .activityResumed, .activityEnded:
            return .workoutTransition
        case .heartRateAboveTarget, .heartRateBelowTarget:
            return .targetAlert
        case .distanceMilestone:
            return .lap
        case .heartRateReturnedToTarget:
            return .information
        }
    }

    /// Stable identity for deduplication. It deliberately excludes the rendered sentence.
    var fingerprint: String {
        switch self {
        case .activityStarted: return "activity_started"
        case .activityPaused: return "activity_paused"
        case .activityResumed: return "activity_resumed"
        case .activityEnded: return "activity_ended"
        case .distanceMilestone(let meters): return "distance_\(Int(meters.rounded()))"
        case .heartRateAboveTarget: return "hr_above_target"
        case .heartRateBelowTarget: return "hr_below_target"
        case .heartRateReturnedToTarget: return "hr_returned_to_target"
        }
    }
}

/// Stable priority ordering: lower values interrupt or precede lower-value work.
enum AudioPromptPriority: Int, Comparable, Sendable {
    case critical = 0
    case workoutTransition = 10
    case targetAlert = 20
    case lap = 30
    case coaching = 40
    case information = 50
    case motivation = 60

    static func < (lhs: AudioPromptPriority, rhs: AudioPromptPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AudioPromptSource: String, Equatable, Sendable {
    case system
    case workout
    case activityRule
}

enum AudioInterruptPolicy: Equatable, Sendable {
    case never
    case lowerPriorityOnly
    case always
}

enum AudioPromptCategory: String, Sendable {
    case lifecycle
    case heartRate
    case distance
}

enum AudioPromptFrequency: String, CaseIterable, Identifiable, Equatable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var minimumInterval: TimeInterval {
        switch self {
        case .low: return 45
        case .normal: return 20
        case .high: return 10
        }
    }

    var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

enum AudioSpeechRate: String, CaseIterable, Identifiable, Equatable, Sendable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    /// Multiplier over AVSpeechUtterance's default rate. The values stay within a
    /// comfortable range for short workout announcements.
    var multiplier: Float {
        switch self {
        case .slow: return 0.75
        case .normal: return 0.92
        case .fast: return 1.15
        }
    }

    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
}

struct AudioPromptPolicy: Equatable, Sendable {
    var enabled: Bool
    var lifecyclePrompts: Bool
    var heartRatePrompts: Bool
    var distancePrompts: Bool
    var frequency: AudioPromptFrequency
    var distanceIncludesDistance: Bool
    var distanceIncludesDuration: Bool
    var distanceIncludesHeartRate: Bool
    var distanceMilestoneKilometers: Int

    init(enabled: Bool, lifecyclePrompts: Bool, heartRatePrompts: Bool, distancePrompts: Bool,
         frequency: AudioPromptFrequency, distanceIncludesDistance: Bool = true,
         distanceIncludesDuration: Bool = true, distanceIncludesHeartRate: Bool = true,
         distanceMilestoneKilometers: Int = 1) {
        self.enabled = enabled
        self.lifecyclePrompts = lifecyclePrompts
        self.heartRatePrompts = heartRatePrompts
        self.distancePrompts = distancePrompts
        self.frequency = frequency
        self.distanceIncludesDistance = distanceIncludesDistance
        self.distanceIncludesDuration = distanceIncludesDuration
        self.distanceIncludesHeartRate = distanceIncludesHeartRate
        self.distanceMilestoneKilometers = min(max(distanceMilestoneKilometers, 1), 10)
    }

    static let `default` = AudioPromptPolicy(
        enabled: false,
        lifecyclePrompts: true,
        heartRatePrompts: true,
        distancePrompts: true,
        frequency: .normal,
        distanceIncludesDistance: true,
        distanceIncludesDuration: true,
        distanceIncludesHeartRate: true,
        distanceMilestoneKilometers: 1)
}

struct AudioPrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let fingerprint: String
    let templateName: String
    let text: String
    let priority: AudioPromptPriority
    let createdAt: Date
    let expiresAt: Date?
    let source: AudioPromptSource
    let interruptPolicy: AudioInterruptPolicy

    init(id: UUID = UUID(), fingerprint: String, templateName: String, text: String,
         priority: AudioPromptPriority, createdAt: Date, expiresAt: Date?, source: AudioPromptSource,
         interruptPolicy: AudioInterruptPolicy = .lowerPriorityOnly) {
        self.id = id
        self.fingerprint = fingerprint
        self.templateName = templateName
        self.text = text
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.source = source
        self.interruptPolicy = interruptPolicy
    }

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return date >= expiresAt
    }
}

/// Explicitly configured target range. V1 does not invent a target from recovery or current HR.
struct AudioWorkoutContext: Sendable {
    let sport: String
    let state: AudioActivityState
    let duration: TimeInterval
    let targetHeartRate: ClosedRange<Int>?
    let heartRate: Int?
    let heartRateZone: Int?
    let distanceMeters: Double?

    init(sport: String, state: AudioActivityState, duration: TimeInterval,
         targetHeartRate: ClosedRange<Int>?, heartRate: Int? = nil,
         heartRateZone: Int? = nil, distanceMeters: Double? = nil) {
        self.sport = sport
        self.state = state
        self.duration = duration
        self.targetHeartRate = targetHeartRate
        self.heartRate = heartRate
        self.heartRateZone = heartRateZone
        self.distanceMeters = distanceMeters
    }
}

/// Deterministic activity state machine with sustained threshold confirmation and hysteresis.
final class AudioActivityEngine {
    struct Configuration: Sendable, Equatable {
        var triggerMarginBPM: Int = 5
        var triggerDuration: TimeInterval = 20
        var recoveryDuration: TimeInterval = 15
        var staleHeartRateAfter: TimeInterval = 15
        var distanceMilestoneStepMeters: Double = 1_000
    }

    private enum Violation {
        case above(startedAt: Date, emitted: Bool)
        case below(startedAt: Date, emitted: Bool)
        case recovering(startedAt: Date, fromAbove: Bool)
    }

    private(set) var state: AudioActivityState = .idle
    private let configuration: Configuration
    private var violation: Violation?
    private var nextMilestoneMeters = 1_000.0

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func start(at date: Date) -> [AudioActivityEvent] {
        state = .active
        violation = nil
        nextMilestoneMeters = max(1, configuration.distanceMilestoneStepMeters)
        return [.activityStarted]
    }

    func pause() -> [AudioActivityEvent] {
        guard state == .active else { return [] }
        state = .paused
        violation = nil
        return [.activityPaused]
    }

    func resume() -> [AudioActivityEvent] {
        guard state == .paused else { return [] }
        state = .active
        violation = nil
        return [.activityResumed]
    }

    func end() -> [AudioActivityEvent] {
        guard state == .active || state == .paused else { return [] }
        state = .completed
        violation = nil
        return [.activityEnded]
    }

    func update(_ metrics: AudioLiveMetrics) -> [AudioActivityEvent] {
        guard state == .active, metrics.state == .active else { return [] }
        var events: [AudioActivityEvent] = []
        if let event = updateHeartRate(metrics) { events.append(event) }
        if let distance = metrics.distanceMeters, distance.isFinite, distance >= 0 {
            let step = max(1, configuration.distanceMilestoneStepMeters)
            while distance >= nextMilestoneMeters {
                events.append(.distanceMilestone(meters: nextMilestoneMeters))
                nextMilestoneMeters += step
            }
        }
        return events
    }

    private func updateHeartRate(_ metrics: AudioLiveMetrics) -> AudioActivityEvent? {
        guard let hr = metrics.heartRate,
              let sampleAt = metrics.heartRateSampleAt,
              metrics.timestamp.timeIntervalSince(sampleAt) <= configuration.staleHeartRateAfter,
              let target = metrics.targetHeartRate else {
            return nil
        }

        let highTrigger = target.upperBound + configuration.triggerMarginBPM
        let lowTrigger = target.lowerBound - configuration.triggerMarginBPM

        switch violation {
        case nil:
            if hr > highTrigger {
                violation = .above(startedAt: metrics.timestamp, emitted: false)
            } else if hr < lowTrigger {
                violation = .below(startedAt: metrics.timestamp, emitted: false)
            }
        case .above(let startedAt, let emitted):
            if hr <= target.upperBound {
                violation = .recovering(startedAt: metrics.timestamp, fromAbove: true)
            } else if !emitted,
                      metrics.timestamp.timeIntervalSince(startedAt) >= configuration.triggerDuration {
                violation = .above(startedAt: startedAt, emitted: true)
                return .heartRateAboveTarget(current: hr, targetMax: target.upperBound)
            }
        case .below(let startedAt, let emitted):
            if hr >= target.lowerBound {
                violation = .recovering(startedAt: metrics.timestamp, fromAbove: false)
            } else if !emitted,
                      metrics.timestamp.timeIntervalSince(startedAt) >= configuration.triggerDuration {
                violation = .below(startedAt: startedAt, emitted: true)
                return .heartRateBelowTarget(current: hr, targetMin: target.lowerBound)
            }
        case .recovering(let startedAt, let fromAbove):
            if fromAbove {
                if hr > highTrigger {
                    violation = .above(startedAt: metrics.timestamp, emitted: true)
                } else if hr <= target.upperBound,
                          metrics.timestamp.timeIntervalSince(startedAt) >= configuration.recoveryDuration {
                    violation = nil
                    return .heartRateReturnedToTarget
                }
            } else if hr < lowTrigger {
                violation = .below(startedAt: metrics.timestamp, emitted: true)
            } else if hr >= target.lowerBound,
                      metrics.timestamp.timeIntervalSince(startedAt) >= configuration.recoveryDuration {
                violation = nil
                return .heartRateReturnedToTarget
            }
        }
        return nil
    }
}

/// Renders short deterministic spoken prompts and owns semantic cooldowns, not audio playback.
final class AudioPromptEngine {
    private var lastEmittedAt: [String: Date] = [:]
    private var lastPromptAt = Date.distantPast

    func reset() {
        lastEmittedAt.removeAll()
        lastPromptAt = .distantPast
    }

    func prompts(for events: [AudioActivityEvent], context: AudioWorkoutContext,
                 policy: AudioPromptPolicy, now: Date) -> [AudioPrompt] {
        guard policy.enabled else { return [] }
        var result: [AudioPrompt] = []
        for event in events.sorted(by: { $0.priority < $1.priority }) {
            guard categoryEnabled(for: event, policy: policy) else { continue }
            let cooldown = cooldown(for: event, policy: policy)
            if let previous = lastEmittedAt[event.fingerprint], now.timeIntervalSince(previous) < cooldown {
                continue
            }
            let bypassFrequency = event.priority <= .workoutTransition || isDistanceMilestone(event)
            if !bypassFrequency, now.timeIntervalSince(lastPromptAt) < policy.frequency.minimumInterval {
                continue
            }
            guard let prompt = render(event: event, context: context, policy: policy, now: now) else { continue }
            lastEmittedAt[event.fingerprint] = now
            lastPromptAt = now
            result.append(prompt)
        }
        return result
    }

    /// Distance milestones are deliberate progress announcements. They must not be dropped by the
    /// global coaching interval, otherwise a fast GPS update crossing two kilometres would only speak
    /// the first one.
    private func isDistanceMilestone(_ event: AudioActivityEvent) -> Bool {
        if case .distanceMilestone = event { return true }
        return false
    }

    private func categoryEnabled(for event: AudioActivityEvent, policy: AudioPromptPolicy) -> Bool {
        switch event {
        case .activityStarted, .activityPaused, .activityResumed, .activityEnded:
            return policy.lifecyclePrompts
        case .heartRateAboveTarget, .heartRateBelowTarget, .heartRateReturnedToTarget:
            return policy.heartRatePrompts
        case .distanceMilestone(let meters):
            return shouldSpeakDistanceMilestone(meters: meters, policy: policy)
        }
    }

    private func shouldSpeakDistanceMilestone(meters: Double, policy: AudioPromptPolicy) -> Bool {
        guard policy.distancePrompts,
              policy.distanceIncludesDistance || policy.distanceIncludesDuration || policy.distanceIncludesHeartRate else {
            return false
        }
        let intervalMeters = Double(policy.distanceMilestoneKilometers * 1_000)
        let multiple = meters / intervalMeters
        return abs(multiple - multiple.rounded()) < 0.0001
    }

    private func cooldown(for event: AudioActivityEvent, policy: AudioPromptPolicy) -> TimeInterval {
        switch event {
        case .heartRateAboveTarget, .heartRateBelowTarget:
            return 120
        case .heartRateReturnedToTarget:
            return 30
        case .distanceMilestone, .activityStarted, .activityPaused, .activityResumed, .activityEnded:
            return 86_400
        }
    }

    private func render(event: AudioActivityEvent, context: AudioWorkoutContext,
                        policy: AudioPromptPolicy, now: Date) -> AudioPrompt? {
        let text: String
        let template: String
        let expires: TimeInterval
        switch event {
        case .activityStarted:
            template = "activity.started"; text = "Workout started."; expires = 8
        case .activityPaused:
            template = "activity.paused"; text = "Workout paused."; expires = 8
        case .activityResumed:
            template = "activity.resumed"; text = "Workout resumed."; expires = 8
        case .activityEnded:
            template = "activity.ended"; text = "Workout complete."; expires = 12
        case .distanceMilestone(let meters):
            template = "distance.milestone"
            text = distanceMilestoneText(meters: meters, context: context, policy: policy)
            expires = 15
        case .heartRateAboveTarget(let current, let targetMax):
            template = "hr.above_target"
            text = "Heart rate \(current). Ease your effort slightly."
            _ = targetMax
            expires = 10
        case .heartRateBelowTarget(let current, let targetMin):
            template = "hr.below_target"
            text = "Heart rate \(current). Increase your effort toward target."
            _ = targetMin
            expires = 10
        case .heartRateReturnedToTarget:
            template = "hr.returned_to_target"; text = "Heart rate back in target."; expires = 12
        }
        return AudioPrompt(fingerprint: event.fingerprint, templateName: template, text: text,
                           priority: event.priority, createdAt: now,
                           expiresAt: now.addingTimeInterval(expires), source: .activityRule)
    }

    private func distanceText(_ meters: Double) -> String {
        if meters < 1_000 { return "Distance \(Int(meters.rounded())) meters." }
        let km = meters / 1_000
        let formatted = km.rounded() == km ? String(Int(km)) : String(format: "%.1f", km)
        return "Distance \(formatted) kilometers."
    }

    private func distanceMilestoneText(meters: Double, context: AudioWorkoutContext,
                                       policy: AudioPromptPolicy) -> String {
        var parts: [String] = []
        if policy.distanceIncludesDistance {
            parts.append(distanceText(meters))
        }
        if policy.distanceIncludesHeartRate {
            if let heartRate = context.heartRate, let zone = context.heartRateZone {
                parts.append("Heart rate \(heartRate) BPM, zone \(zone).")
            } else if let zone = context.heartRateZone {
                parts.append("Heart rate zone \(zone).")
            } else {
                parts.append("Heart rate unavailable.")
            }
        }
        if policy.distanceIncludesDuration {
            parts.append("Duration \(durationText(context.duration)).")
        }
        return parts.joined(separator: " ")
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds) seconds" }
        if seconds == 0 { return "\(minutes) minutes" }
        return "\(minutes) minutes \(seconds) seconds"
    }

    func testPrompt(context: AudioWorkoutContext, policy: AudioPromptPolicy,
                    now: Date = Date()) -> AudioPrompt {
        let text = distanceMilestoneText(
            meters: Double(policy.distanceMilestoneKilometers * 1_000),
            context: context,
            policy: policy)
        return AudioPrompt(
            fingerprint: "audio_coaching_test",
            templateName: "audio.test.distance_milestone",
            text: text,
            priority: .information,
            createdAt: now,
            expiresAt: now.addingTimeInterval(30),
            source: .system)
    }
}

/// UserDefaults boundary for the iOS-only experiment. No audio preference is added to shared/macOS
/// settings, so the original scaffold and desktop behavior remain unchanged.
enum AudioCoachingPreferences {
    static let enabledKey = "noop.audioCoaching.enabled"
    static let lifecycleKey = "noop.audioCoaching.lifecycle"
    static let heartRateKey = "noop.audioCoaching.heartRate"
    static let distanceKey = "noop.audioCoaching.distance"
    static let distanceIncludesDistanceKey = "noop.audioCoaching.distanceIncludesDistance"
    static let distanceIncludesDurationKey = "noop.audioCoaching.distanceIncludesDuration"
    static let distanceIncludesHeartRateKey = "noop.audioCoaching.distanceIncludesHeartRate"
    static let distanceMilestoneKilometersKey = "noop.audioCoaching.distanceMilestoneKilometers"
    static let targetZoneKey = "noop.audioCoaching.targetZone"
    static let frequencyKey = "noop.audioCoaching.frequency"
    static let speechRateKey = "noop.audioCoaching.speechRate"

    static func policy(from defaults: UserDefaults = .standard) -> AudioPromptPolicy {
        let frequency = AudioPromptFrequency(rawValue: defaults.string(forKey: frequencyKey) ?? "") ?? .normal
        let milestoneKilometers = defaults.object(forKey: distanceMilestoneKilometersKey) as? Int ?? 1
        return AudioPromptPolicy(
            enabled: defaults.object(forKey: enabledKey) as? Bool ?? AudioPromptPolicy.default.enabled,
            lifecyclePrompts: defaults.object(forKey: lifecycleKey) as? Bool ?? true,
            heartRatePrompts: defaults.object(forKey: heartRateKey) as? Bool ?? true,
            distancePrompts: defaults.object(forKey: distanceKey) as? Bool ?? true,
            frequency: frequency,
            distanceIncludesDistance: defaults.object(forKey: distanceIncludesDistanceKey) as? Bool ?? true,
            distanceIncludesDuration: defaults.object(forKey: distanceIncludesDurationKey) as? Bool ?? true,
            distanceIncludesHeartRate: defaults.object(forKey: distanceIncludesHeartRateKey) as? Bool ?? true,
            distanceMilestoneKilometers: min(max(milestoneKilometers, 1), 10))
    }

    static var targetZone: Int {
        let raw = UserDefaults.standard.object(forKey: targetZoneKey) as? Int ?? 3
        return min(max(raw, 0), 5)
    }

    static var speechRate: AudioSpeechRate {
        AudioSpeechRate(rawValue: UserDefaults.standard.string(forKey: speechRateKey) ?? "") ?? .normal
    }
}
