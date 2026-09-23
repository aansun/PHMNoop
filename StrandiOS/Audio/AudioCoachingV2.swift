import Foundation

/// A short, local trend snapshot. A delta is nil when there is not enough recent data to make a
/// useful comparison; the coach never fills missing sensor data with an estimate.
struct AudioMetricTrends: Equatable, Sendable {
    let sampleCount: Int
    let windowDuration: TimeInterval
    let heartRateDeltaBPM: Int?
    let paceDeltaSecondsPerKm: Double?
    let cadenceDeltaSPM: Double?

    var isReliable: Bool { sampleCount >= 3 && windowDuration >= 90 }
}

/// Keeps only the most recent two minutes of live workout samples. This is intentionally pure so
/// it can be replayed in tests without a device, HealthKit, GPS, or a network provider.
final class AudioTrendEngine {
    struct Configuration: Equatable, Sendable {
        var window: TimeInterval = 120
        var minimumSampleSpacing: TimeInterval = 3
        var maximumSamples = 60
    }

    private struct Sample: Equatable {
        let timestamp: Date
        let heartRate: Int?
        let pace: Double?
        let cadence: Double?
    }

    private let configuration: Configuration
    private var samples: [Sample] = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func reset() { samples.removeAll(keepingCapacity: true) }

    @discardableResult
    func update(_ metrics: AudioLiveMetrics) -> AudioMetricTrends {
        guard metrics.state == .active else { return snapshot() }
        guard !samples.contains(where: { $0.timestamp == metrics.timestamp }) else { return snapshot() }
        if let last = samples.last, metrics.timestamp.timeIntervalSince(last.timestamp) < configuration.minimumSampleSpacing {
            return snapshot()
        }

        let sample = Sample(timestamp: metrics.timestamp,
                            heartRate: freshHeartRate(from: metrics),
                            pace: valid(metrics.paceSecondsPerKm),
                            cadence: valid(metrics.cadenceSPM))
        guard sample.heartRate != nil || sample.pace != nil || sample.cadence != nil else {
            return snapshot()
        }
        samples.append(sample)
        let cutoff = metrics.timestamp.addingTimeInterval(-configuration.window)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > configuration.maximumSamples {
            samples.removeFirst(samples.count - configuration.maximumSamples)
        }
        return snapshot()
    }

    private func snapshot() -> AudioMetricTrends {
        guard let first = samples.first, let last = samples.last else {
            return AudioMetricTrends(sampleCount: 0, windowDuration: 0,
                                     heartRateDeltaBPM: nil, paceDeltaSecondsPerKm: nil,
                                     cadenceDeltaSPM: nil)
        }
        return AudioMetricTrends(
            sampleCount: samples.count,
            windowDuration: max(0, last.timestamp.timeIntervalSince(first.timestamp)),
            heartRateDeltaBPM: delta(first.heartRate, last.heartRate),
            paceDeltaSecondsPerKm: delta(first.pace, last.pace),
            cadenceDeltaSPM: delta(first.cadence, last.cadence))
    }

    private func freshHeartRate(from metrics: AudioLiveMetrics) -> Int? {
        guard let heartRate = metrics.heartRate,
              let sampleAt = metrics.heartRateSampleAt,
              metrics.timestamp.timeIntervalSince(sampleAt) <= 15,
              (30...220).contains(heartRate) else { return nil }
        return heartRate
    }

    private func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func delta(_ first: Int?, _ last: Int?) -> Int? {
        guard let first, let last else { return nil }
        return last - first
    }

    private func delta(_ first: Double?, _ last: Double?) -> Double? {
        guard let first, let last else { return nil }
        return last - first
    }
}

enum AudioCoachingIntent: String, Equatable, Sendable {
    case easeOff
    case stabilizePace
    case maintainRhythm

    var fingerprint: String { "coaching_\(rawValue)" }
}

/// Deterministic V2 coaching rules. It emits only after a reliable two-minute trend and only once
/// per intent until the trend returns to neutral. The prompt layer owns the user-configured cooldown.
final class AudioCoachingRuleEngine {
    struct Configuration: Equatable, Sendable {
        var heartRateDriftBPM = 8
        var stablePaceToleranceSeconds = 15.0
        var paceSlowdownSeconds = 20.0
        var cadenceDropSPM = 8.0
    }

    private let configuration: Configuration
    private var activeIntent: AudioCoachingIntent?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func reset() { activeIntent = nil }

    func update(metrics: AudioLiveMetrics, trends: AudioMetricTrends) -> [AudioActivityEvent] {
        guard metrics.state == .active, trends.isReliable else { return [] }
        let intent: AudioCoachingIntent?
        if let heartRateDelta = trends.heartRateDeltaBPM,
           heartRateDelta >= configuration.heartRateDriftBPM,
           let paceDelta = trends.paceDeltaSecondsPerKm,
           abs(paceDelta) <= configuration.stablePaceToleranceSeconds {
            intent = .easeOff
        } else if let paceDelta = trends.paceDeltaSecondsPerKm,
                  paceDelta >= configuration.paceSlowdownSeconds,
                  (trends.heartRateDeltaBPM ?? 0) < configuration.heartRateDriftBPM {
            intent = .stabilizePace
        } else if let cadenceDelta = trends.cadenceDeltaSPM,
                  cadenceDelta <= -configuration.cadenceDropSPM {
            intent = .maintainRhythm
        } else {
            intent = nil
        }

        guard let intent, intent != activeIntent else {
            if intent == nil { activeIntent = nil }
            return []
        }
        activeIntent = intent
        return [.coachingIntent(intent)]
    }
}
