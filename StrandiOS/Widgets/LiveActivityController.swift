#if os(iOS)
import Foundation
import ActivityKit
import OSLog

/// Starts, updates, and ends the Live Activity. A workout owns the activity lifecycle: it starts as
/// soon as the workout starts, even before the first HR sample or when the optional Live HR setting is
/// off, and remains visible until the workout ends. Outside a workout it falls back to the optional
/// connected-and-streaming live-HR activity.
@MainActor
final class LiveActivityController {
    private var activity: Activity<NOOPActivityAttributes>?
    private var lastPush: Date = .distantPast
    /// Activity permission is read for each update. Users can change Live Activities in Settings
    /// while NOOP remains alive; caching this bridge made the Lock Screen stay disabled until the
    /// process was relaunched.
    private var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    private let logger = Logger(subsystem: "com.phm.noop", category: "LiveActivity")
    /// Synchronous gate against concurrent `Activity.request` calls. The `else` branch below is
    /// re-entered while the first request is still in flight (it hasn't assigned `self.activity`
    /// yet), so without this guard two close-together HR samples could both fire `Activity.request`
    /// and create duplicate Live Activities.
    private var isStarting = false
    /// Retained so a workout heartbeat can refresh the activity even when no new HR/GPS sample arrives.
    private var lastWorkoutState: NOOPActivityAttributes.ContentState?
    private var workoutKeepAliveTask: Task<Void, Never>?
    /// How long after the last push iOS may keep showing the activity as fresh. The activity is
    /// refreshed every ~2 s while streaming, so this never bites a live session; it auto-greys a
    /// frozen activity if the app is suspended/killed without an explicit end (a missed-tick safety net
    /// on top of the connected-driven end below).
    private static let staleAfter: TimeInterval = 600
    private static let staleAfterDisconnected: TimeInterval = 3 * 3600

    /// Whether the current activity was started for a workout. This is kept separately from the
    /// content state so the transition from workout → ordinary live HR can end cleanly when the
    /// workout finishes without relying on a final HR sample.
    private var workoutIsActive = false
    /// When the current banner was requested, for the eight-hour limit.
    private var bannerRequestedAt: Date?
    /// A banner is replaced after this long, well inside the system's eight hours.
    private static let rolloverAfter: TimeInterval = 7.5 * 3600

    deinit { workoutKeepAliveTask?.cancel() }

    /// Drive the activity from the latest live values. A workout starts immediately and is allowed to
    /// continue through a strap disconnect; the Lock Screen then shows the last known/empty HR while
    /// the workout clock and sport remain live. Outside a workout, the legacy connected + HR policy
    /// remains in place. Throttled to ~once every 2 s so we stay well under the Live Activity budget.
    func update(bpm: Int?, recovery: Int?, connected: Bool, batteryPct: Int? = nil,
                effort: Int? = nil,
                heartRateZone: Int? = nil, activityName: String? = nil,
                activityStartedAt: Date? = nil,
                averageBPM: Int? = nil, peakBPM: Int? = nil,
                distance: String? = nil, pace: String? = nil, speed: String? = nil,
                calories: Int? = nil, subtitle: String? = nil, progress: Double? = nil, targetZone: Int? = nil,
                zonePosition: Double? = nil, zoneSeconds: Int? = nil, pausedAt: Date? = nil, effortLabel: String? = nil,
                workoutActive: Bool = false) {
        guard activitiesEnabled else { return }

        // Re-adopt an activity that outlived a previous app session. ActivityKit keeps Live Activities
        // alive across launches/relaunches, but a fresh controller starts with `activity == nil`, so
        // without recovering the handle here we can neither update nor END an already-showing activity
        // — which made the #336 opt-out a no-op (#341: toggle off, heart stays) and risked spawning a
        // duplicate on the start path below. Done on the HR tick rather than in `init` because
        // `Activity.activities` isn't reliably hydrated at the instant of process launch.
        // Only an activity that is still showing counts: one that was just ended lingers in the list for a moment, and updating
        // it does nothing, so a session started right after another was discarded would never get its own banner.
        if let current = activity, current.activityState != .active { activity = nil }
        if activity == nil { activity = Activity<NOOPActivityAttributes>.activities.first { $0.activityState == .active } }

        // A workout is a first-class Live Activity, not a variation of the optional live-HR setting.
        // Users may turn off the latter while still expecting a started workout to remain visible.
        if !workoutActive && workoutIsActive {
            workoutIsActive = false
            // If there is no ordinary live-HR activity to fall back to, remove the workout banner
            // immediately. If HR is available and the setting is on, the existing activity below is
            // converted to the normal live-HR presentation instead of briefly disappearing.
            if !UnitPrefs.liveActivityEnabled() || !connected || bpm == nil {
                Task { await end() }
                return
            }
        }

        // User opt-out (#336) applies only to ordinary live HR. A running workout bypasses this app
        // preference; the system-level Live Activities permission above remains authoritative.
        guard workoutActive || UnitPrefs.liveActivityEnabled() else {
            if activity != nil { Task { await end() } }
            return
        }

        // The banner outlives the strap link. It used to end when the link dropped, but iOS only lets an app START a Live Activity while it is
        // in the foreground: once ended in the background (a locked phone, a strap that reconnects on its own) there was no way to bring it back
        // until the app was opened again, which is why it seemed to vanish after a few minutes. It now stays, says it is reconnecting, and
        // carries on when the heart rate returns. It is ended only by the user (the setting) or by the system's eight-hour limit.
        if !connected && !workoutActive && activity == nil { return }
        guard workoutActive || bpm != nil || activity != nil else { return }

        let state = NOOPActivityAttributes.ContentState(
            bpm: bpm,
            recovery: recovery,
            bonded: connected,
            batteryPct: batteryPct,
            effort: effort,
            heartRateZone: heartRateZone,
            activityName: activityName,
            activityStartedAt: activityStartedAt,
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            distance: distance,
            pace: pace,
            speed: speed,
            calories: calories,
            subtitle: subtitle,
            progress: progress,
            targetZone: targetZone,
            zonePosition: zonePosition,
            zoneSeconds: zoneSeconds,
            pausedAt: pausedAt,
            effortLabel: effortLabel)
        // A workout owns this activity until End/Discard. Do not let a temporary strap disconnect or
        // quiet GPS stream make the Lock Screen activity stale while the workout clock is still live.
        // Ordinary live-HR activity keeps the shorter freshness date as a safety net.
        // A long window: the number is frozen while the app is suspended, and the "Reconnecting" line, not a dimmed banner, tells the truth.
        let staleDate: Date? = workoutActive ? nil : Date().addingTimeInterval(connected ? Self.staleAfter : Self.staleAfterDisconnected)
        // Track the lifecycle even when the content update is throttled. A workout can start within
        // two seconds of the previous live-HR tick, and its later end must still be able to close the
        // activity without waiting for another HR sample.
        workoutIsActive = workoutActive
        lastWorkoutState = workoutActive ? state : nil
        if workoutActive {
            beginWorkoutKeepAliveIfNeeded()
        } else {
            workoutKeepAliveTask?.cancel()
            workoutKeepAliveTask = nil
        }

        if let activity {
            guard Date().timeIntervalSince(lastPush) > 2 else { return }
            lastPush = Date()
            Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
        } else {
            startActivity(state, staleDate: staleDate)
        }
    }

    /// Ask iOS for a new banner. The start gate is set SYNCHRONOUSLY, before anything can suspend, so a second `update` arriving on the
    /// main actor while `Activity.request` is in flight bails out instead of issuing a second request. The 2-second throttle on the
    /// update path does not guard this one.
    private func startActivity(_ state: NOOPActivityAttributes.ContentState, staleDate: Date?) {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            activity = try Activity.request(
                attributes: NOOPActivityAttributes(title: String(localized: "Live HR")),
                content: ActivityContent(state: state, staleDate: staleDate),
                pushType: nil
            )
            bannerRequestedAt = Date()
            lastPush = Date()
        } catch {
            // Refused in the background or while the system is busy; the workout heartbeat and the next foreground try again.
            activity = nil
            logger.error("Live HR activity request refused: \(String(describing: error), privacy: .public)")
        }
    }

    /// iOS ends any Live Activity after eight hours. A workout that long gets a fresh banner before that happens.
    private func rolloverIfNeeded() async {
        guard let started = bannerRequestedAt, Date().timeIntervalSince(started) > Self.rolloverAfter else { return }
        let old = activity
        activity = nil
        bannerRequestedAt = nil
        await old?.end(nil, dismissalPolicy: .immediate)
    }

    func end() async {
        workoutKeepAliveTask?.cancel()
        workoutKeepAliveTask = nil
        // End every NOOP Live Activity, not just our cached handle — covers a straggler from a prior
        // session we never re-adopted (#341) and any rare duplicate. Iterating the live list is the
        // only way to reach activities this controller instance never started.
        for act in Activity<NOOPActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        self.bannerRequestedAt = nil
        self.workoutIsActive = false
        self.lastWorkoutState = nil
        self.lastPush = .distantPast
    }

    private func beginWorkoutKeepAliveIfNeeded() {
        guard workoutKeepAliveTask == nil else { return }
        workoutKeepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshWorkoutActivity()
            }
        }
    }

    /// The workout heartbeat: keeps the banner fresh and, for as long as the workout runs, brings it back if it is gone (swiped away,
    /// ended by the system, past the eight-hour limit) rather than waiting for the next heart-rate tick.
    private func refreshWorkoutActivity() async {
        guard workoutIsActive, let state = lastWorkoutState else { return }
        await rolloverIfNeeded()
        if let current = activity, current.activityState != .active { activity = nil }
        if activity == nil { activity = Activity<NOOPActivityAttributes>.activities.first { $0.activityState == .active } }
        guard let activity else {
            startActivity(state, staleDate: nil)
            return
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        lastPush = Date()
    }
}
#endif
