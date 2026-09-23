import XCTest

final class AudioCoachingCoreTests: XCTestCase {
    private let target = 135...145

    private func metrics(_ date: Date, hr: Int, distance: Double = 0) -> AudioLiveMetrics {
        AudioLiveMetrics(timestamp: date, heartRate: hr, heartRateSampleAt: date,
                         heartRateZone: 3, distanceMeters: distance, paceSecondsPerKm: nil,
                         state: .active, targetHeartRate: target)
    }

    private func trendMetrics(_ date: Date, hr: Int, pace: Double, cadence: Double = 170) -> AudioLiveMetrics {
        AudioLiveMetrics(timestamp: date, heartRate: hr, heartRateSampleAt: date,
                         heartRateZone: 3, distanceMeters: 1_000, paceSecondsPerKm: pace,
                         state: .active, targetHeartRate: target, cadenceSPM: cadence)
    }

    func testShortHeartRateSpikeDoesNotTrigger() {
        let engine = AudioActivityEngine()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.start(at: start)
        XCTAssertTrue(engine.update(metrics(start, hr: 151)).isEmpty)
        XCTAssertTrue(engine.update(metrics(start.addingTimeInterval(4), hr: 151)).isEmpty)
        XCTAssertTrue(engine.update(metrics(start.addingTimeInterval(4), hr: 145)).isEmpty)
    }

    func testSustainedViolationAndRecoveryUseHysteresis() {
        let engine = AudioActivityEngine()
        let start = Date(timeIntervalSince1970: 2_000)
        _ = engine.start(at: start)
        XCTAssertTrue(engine.update(metrics(start, hr: 151)).isEmpty)
        XCTAssertTrue(engine.update(metrics(start.addingTimeInterval(19), hr: 152)).isEmpty)
        XCTAssertEqual(engine.update(metrics(start.addingTimeInterval(20), hr: 153)),
                       [.heartRateAboveTarget(current: 153, targetMax: 145)])
        XCTAssertTrue(engine.update(metrics(start.addingTimeInterval(25), hr: 148)).isEmpty)
        XCTAssertTrue(engine.update(metrics(start.addingTimeInterval(39), hr: 145)).isEmpty)
        XCTAssertEqual(engine.update(metrics(start.addingTimeInterval(54), hr: 144)),
                       [.heartRateReturnedToTarget])
    }

    func testDistanceMilestonesAreEmittedEveryKilometre() {
        let engine = AudioActivityEngine()
        let start = Date(timeIntervalSince1970: 3_000)
        _ = engine.start(at: start)
        XCTAssertEqual(engine.update(metrics(start, hr: 130, distance: 1_001)),
                       [.distanceMilestone(meters: 1_000)])
        XCTAssertEqual(engine.update(metrics(start.addingTimeInterval(1), hr: 130, distance: 2_100)),
                       [.distanceMilestone(meters: 2_000)])
        XCTAssertEqual(engine.update(metrics(start.addingTimeInterval(2), hr: 130, distance: 3_001)),
                       [.distanceMilestone(meters: 3_000)])
    }

    func testPromptPriorityAndSemanticCooldown() {
        let engine = AudioPromptEngine()
        let now = Date(timeIntervalSince1970: 4_000)
        let context = AudioWorkoutContext(sport: "Running", state: .active, duration: 60,
                                          targetHeartRate: target)
        let policy = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                       distancePrompts: true, frequency: .normal)
        let events: [AudioActivityEvent] = [
            .distanceMilestone(meters: 1_000),
            .activityPaused
        ]
        let prompts = engine.prompts(for: events, context: context, policy: policy, now: now)
        XCTAssertEqual(prompts.map(\.priority), [.workoutTransition, .lap])
        XCTAssertTrue(engine.prompts(for: [.distanceMilestone(meters: 1_000)], context: context,
                                     policy: policy, now: now.addingTimeInterval(1)).isEmpty)
    }

    func testDistancePromptIncludesDistanceZoneAndDuration() {
        let engine = AudioPromptEngine()
        let policy = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                       distancePrompts: true, frequency: .normal)
        let context = AudioWorkoutContext(sport: "Running", state: .active, duration: 125,
                                          targetHeartRate: target, heartRate: 142,
                                          heartRateZone: 3, distanceMeters: 2_000)
        let prompts = engine.prompts(for: [.distanceMilestone(meters: 2_000)], context: context,
                                     policy: policy, now: Date(timeIntervalSince1970: 5_000))
        guard let prompt = prompts.first else {
            XCTFail("Expected a distance milestone prompt")
            return
        }
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(prompt.text.contains("Distance 2 kilometers"))
        XCTAssertTrue(prompt.text.contains("Heart rate zone 3"))
        XCTAssertTrue(prompt.text.contains("Duration 2 minutes 5 seconds"))
    }

    func testDistanceIntervalOnlyAnnouncesConfiguredMultiples() {
        let engine = AudioPromptEngine()
        let context = AudioWorkoutContext(sport: "Running", state: .active, duration: 600,
                                          targetHeartRate: target, heartRate: 142,
                                          heartRateZone: 3, distanceMeters: 5_000)
        let policy = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                       distancePrompts: true, frequency: .normal,
                                       distanceMilestoneKilometers: 5)
        XCTAssertTrue(engine.prompts(for: [.distanceMilestone(meters: 1_000)], context: context,
                                     policy: policy, now: Date(timeIntervalSince1970: 6_000)).isEmpty)
        let prompt = engine.prompts(for: [.distanceMilestone(meters: 5_000)], context: context,
                                    policy: policy, now: Date(timeIntervalSince1970: 6_001)).first
        XCTAssertNotNil(prompt)
    }

    func testDistancePromptCanSpeakOnlySelectedStatistics() {
        let engine = AudioPromptEngine()
        let context = AudioWorkoutContext(sport: "Running", state: .active, duration: 125,
                                          targetHeartRate: target, heartRate: 142,
                                          heartRateZone: 3, distanceMeters: 2_000)
        let policy = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                       distancePrompts: true, frequency: .normal,
                                       distanceIncludesDistance: true,
                                       distanceIncludesDuration: false,
                                       distanceIncludesHeartRate: false)
        let prompt = engine.prompts(for: [.distanceMilestone(meters: 2_000)], context: context,
                                    policy: policy, now: Date(timeIntervalSince1970: 7_000)).first
        XCTAssertEqual(prompt?.text, "Distance 2 kilometers.")
    }

    func testTrendEngineRequiresAStableWindowAndComputesDeltas() {
        let engine = AudioTrendEngine()
        let start = Date(timeIntervalSince1970: 8_000)
        XCTAssertFalse(engine.update(trendMetrics(start, hr: 140, pace: 360)).isReliable)
        _ = engine.update(trendMetrics(start.addingTimeInterval(60), hr: 145, pace: 367, cadence: 165))
        let trends = engine.update(trendMetrics(start.addingTimeInterval(120), hr: 149, pace: 375, cadence: 160))
        XCTAssertTrue(trends.isReliable)
        XCTAssertEqual(trends.heartRateDeltaBPM, 9)
        XCTAssertEqual(trends.paceDeltaSecondsPerKm, 15)
        XCTAssertEqual(trends.cadenceDeltaSPM, -10)
    }

    func testSmartCoachEmitsOnlyForReliableTrendAndDeduplicatesIntent() {
        let trends = AudioMetricTrends(sampleCount: 3, windowDuration: 120,
                                       heartRateDeltaBPM: 9, paceDeltaSecondsPerKm: 5,
                                       cadenceDeltaSPM: 0)
        let engine = AudioCoachingRuleEngine()
        let date = Date(timeIntervalSince1970: 9_000)
        let event = engine.update(metrics: trendMetrics(date, hr: 149, pace: 365), trends: trends)
        XCTAssertEqual(event, [.coachingIntent(.easeOff)])
        XCTAssertTrue(engine.update(metrics: trendMetrics(date.addingTimeInterval(10), hr: 150, pace: 366), trends: trends).isEmpty)
    }

    func testSmartCoachPromptUsesConfiguredToggle() {
        let engine = AudioPromptEngine()
        let context = AudioWorkoutContext(sport: "Running", state: .active, duration: 120,
                                          targetHeartRate: target, heartRate: 149, heartRateZone: 4)
        let disabled = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                         distancePrompts: true, frequency: .normal)
        XCTAssertTrue(engine.prompts(for: [.coachingIntent(.easeOff)], context: context,
                                     policy: disabled, now: Date(timeIntervalSince1970: 10_000)).isEmpty)
        let enabled = AudioPromptPolicy(enabled: true, lifecyclePrompts: true, heartRatePrompts: true,
                                        distancePrompts: true, frequency: .normal, coachingPrompts: true)
        let prompt = engine.prompts(for: [.coachingIntent(.easeOff)], context: context,
                                    policy: enabled, now: Date(timeIntervalSince1970: 10_021)).first
        XCTAssertEqual(prompt?.text, "Heart rate is drifting up. Ease your effort slightly.")
    }
}
