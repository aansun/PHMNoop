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
    /// How long after the last push iOS may keep showing the activity as fresh. The activity is
    /// refreshed every ~2 s while streaming, so this never bites a live session; it auto-greys a
    /// frozen activity if the app is suspended/killed without an explicit end (a missed-tick safety net
    /// on top of the connected-driven end below).
    private static let staleAfter: TimeInterval = 120

    /// Whether the current activity was started for a workout. This is kept separately from the
    /// content state so the transition from workout → ordinary live HR can end cleanly when the
    /// workout finishes without relying on a final HR sample.
    private var workoutIsActive = false

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
                workoutActive: Bool = false) {
        guard activitiesEnabled else { return }

        // Re-adopt an activity that outlived a previous app session. ActivityKit keeps Live Activities
        // alive across launches/relaunches, but a fresh controller starts with `activity == nil`, so
        // without recovering the handle here we can neither update nor END an already-showing activity
        // — which made the #336 opt-out a no-op (#341: toggle off, heart stays) and risked spawning a
        // duplicate on the start path below. Done on the HR tick rather than in `init` because
        // `Activity.activities` isn't reliably hydrated at the instant of process launch.
        if activity == nil { activity = Activity<NOOPActivityAttributes>.activities.first }

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

        // End the ordinary live-HR activity when the live link drops. A workout deliberately stays up
        // through that disconnect so the user can finish the session and its timer remains visible.
        if !connected && !workoutActive {
            Task { await end() }
            return
        }
        guard workoutActive || bpm != nil else { return }

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
            speed: speed)
        let staleDate = Date().addingTimeInterval(Self.staleAfter)
        // Track the lifecycle even when the content update is throttled. A workout can start within
        // two seconds of the previous live-HR tick, and its later end must still be able to close the
        // activity without waiting for another HR sample.
        workoutIsActive = workoutActive

        if let activity {
            guard Date().timeIntervalSince(lastPush) > 2 else { return }
            lastPush = Date()
            Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
        } else {
            // Set the start gate SYNCHRONOUSLY before any await so a second `update` arriving on the
            // main actor while `Activity.request` is still in flight bails here instead of issuing a
            // second request. The 2-second throttle above only guards the update path.
            guard !isStarting else { return }
            isStarting = true
            do {
                activity = try Activity.request(
                    attributes: NOOPActivityAttributes(title: String(localized: "Live HR")),
                    content: ActivityContent(state: state, staleDate: staleDate),
                    pushType: nil
                )
                lastPush = Date()
            } catch {
                activity = nil
                logger.error("Live HR activity request refused: \(String(describing: error), privacy: .public)")
            }
            isStarting = false
        }
    }

    func end() async {
        // End every NOOP Live Activity, not just our cached handle — covers a straggler from a prior
        // session we never re-adopted (#341) and any rare duplicate. Iterating the live list is the
        // only way to reach activities this controller instance never started.
        for act in Activity<NOOPActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        self.workoutIsActive = false
    }
}
#endif
