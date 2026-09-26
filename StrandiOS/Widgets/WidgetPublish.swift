#if os(iOS)
import Foundation
import WidgetKit
import StrandAnalytics

extension WidgetSnapshot {
    /// The ACTIVE device's charge for the widget (#2075).
    ///
    /// `LiveState.batteryPct` is the WHOOP's, and `LiveState` is one object every live source writes
    /// into, so publishing it unconditionally put the strap's charge on the widget while a ring was the
    /// active device. Same rule as the Live Console, through the same seam.
    ///
    /// `@MainActor` like both publishers that call it: `AppModel.deviceRegistry` and `LiveState` are
    /// main-actor isolated, so a nonisolated helper cannot read them.
    @MainActor
    static func activeBatteryPct(from model: AppModel) -> Int? {
        LiveConsoleReadout.batteryPercent(
            activeIsWhoop: LiveConsoleReadout.activeIsWhoop(
                devices: model.deviceRegistry?.devices ?? [],
                activeId: model.deviceRegistry?.activeDeviceId,
            ),
            whoopPct: model.live.batteryPct,
            ringPct: model.live.ouraBatteryPct,
        )
    }

    /// Build a glance snapshot from the live app state and publish it to the shared App Group, then
    /// ask WidgetKit to refresh. Called when the app becomes active and after a Health sync.
    ///
    /// `async` because the Rest score (#446) lives in a computed metric series, not a `DailyMetric`
    /// column, so it needs an `exploreSeries` read. The sole caller already runs inside a `Task`, so it
    /// just gains an `await`. Charge stays on the recovery anchor, while Effort / Rest / HRV / Resting HR
    /// follow the same current-day resolution as Today. This keeps the widget useful during the rollover
    /// window, when today's live metrics exist before today's Charge has been scored.
    ///
    /// #911: the anchor is resolved the way Today resolves it (the current LOGICAL local day, `Date()`
    /// read here so the day rolls live as the extension republishes), NOT "the most recent day with any
    /// recovery score". The old anchor drifted around the day rollover: the new logical day exists but
    /// isn't scored yet, so `days.last(where: recovery != nil)` still pointed at yesterday's scored row
    /// and the widget showed the older day while Today had already moved on. We now anchor on today's
    /// row and, only when today isn't scored yet, carry over the last STRICTLY-PRIOR scored day for the
    /// recovery-derived fields (the same carry-over Today does), so the widget never blanks right after
    /// the rollover yet always describes today.
    @MainActor
    static func publish(from model: AppModel) async {
        await refreshWidgetPresence()
        let days = model.repo.days
        let now = Date()
        // The recovery-derived anchor: today's row when it's scored, else the freshest STRICTLY-PRIOR
        // scored day carried over. Resolved through the SHARED `Repository.widgetAnchor`, the ONE selector
        // the watch snapshot and the iOS Live Activity now also use, so all four surfaces describe the same
        // day (the #911 fix; see `Repository.widgetAnchor` for the rollover-drift rationale, the #304
        // pre-04:00 carve-out and the #547 future-day guard it folds in). The `$0.day < carriedKey` bound
        // inside the helper (matching `TodayView.selectedDayKey`) means a stale scored row can never
        // re-surface AS today.
        let day = Repository.widgetAnchor(days: days, now: now)
        // Today can have live Rest/Effort/vitals while Charge still carries the last scored day. Resolve
        // the current row independently from the recovery anchor so the widget cannot mix yesterday's
        // Rest with today's live values. This mirrors TodayView's fresh-rest rule, including its
        // freshness guard for the tail fallback.
        let todayRow = Repository.resolveToday(
            days: days,
            logicalKey: Repository.logicalDayKey(now),
            localKey: Repository.localDayKey(now)
        )
        let todayKey = todayRow?.day ?? Repository.logicalDayKey(now)
        // Steps are a calendar-day HealthKit total, so resolve the current local day explicitly rather
        // than borrowing an arbitrary historical `DailyMetric` row. The strap row remains the fallback
        // for users who have not enabled Apple Health, while the Rings widget stays honest when neither
        // source has published a value yet.
        let appleRows = await model.repo.appleDailyRows(days: 2)
        let steps = appleRows.last(where: { $0.day == Repository.localDayKey(now) })?.steps
            ?? todayRow?.steps
            ?? day?.steps
        let caloriesKcal = appleRows.last(where: { $0.day == Repository.localDayKey(now) })?.activeKcal.map { Int($0.rounded()) }
            ?? todayRow?.activeKcalEst.map { Int($0.rounded()) }
            ?? day?.activeKcalEst.map { Int($0.rounded()) }
        var restScore: Double?
        let restSeries = await model.repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        restScore = Self.freshRestScore(
            todayValue: restByDay[todayKey],
            lastDay: restSeries.last?.day,
            lastValue: restSeries.last?.value,
            todayKey: todayKey
        )
        // #313: honour the user's Effort scale at publish time. The widget extension cannot read the
        // app's plain `@AppStorage(UnitPrefs.effortScaleKey)` (it is not in the App Group), so we
        // pre-format the display string here and keep the 0–100 int for the ring fill (the fill
        // fraction is scale-independent: 38/100 == 8.0/21).
        let effortScale = currentEffortScale()
        // Today uses the in-progress HR window for today's Effort. Reading only `day.strain` here made
        // the widget lag behind the app until the next heavy scoring pass (and could even show the
        // previous day's Effort after the logical-day rollover). Keep Charge on the shared recovery
        // anchor, but resolve Effort from today's row/live HR exactly as Today does.
        let liveStrain = await currentLiveEffort(from: model, now: now)
        let strain = liveStrain ?? todayRow?.strain ?? day?.strain
        let effortDisplay: String? = strain.map { Self.effortDisplay($0, scale: effortScale) }
        // #2040: today's stress curve. Self-gating on a cheap heart-rate fingerprint, so a publish that
        // changed nothing costs one indexed COUNT and no rows. Only the FULL path scores it; the live
        // fast path below reuses the previous snapshot and so carries the curve forward untouched.
        let stress = await StressDayCurve.today(repo: model.repo)
        // The widget's own point type is built HERE, at the one place that needs it: `StressPoint`
        // lives in the iOS/widget shared sources, and the producer is now also read by the Today card,
        // which is compiled for macOS too.
        let stressPoints: [StressPoint]? = stress.map { scored in
            scored.result.timeline.map {
                // `startTs` is the wall-clock bucket start with the local shift already undone, so it
                // is a true instant and formats correctly against the device's zone.
                StressPoint(ts: Int64($0.startTs), level: $0.level, moving: $0.maskedForActivity)
            }
        }
        // Loaded ONCE for the carry-forward below. Reaching for `load()` in each of the two arguments
        // would decode the App Group blob twice on any publish that could not score, and this file
        // already went to the trouble of removing one such decode from the live path.
        let storedStress: WidgetSnapshot? = stress == nil ? load() : nil
        let recoveryValue = day?.recovery.map { Int($0.rounded()) }
        let bpmValue = model.bpm ?? model.live.heartRate
        let batteryValue = activeBatteryPct(from: model)
        let effortValue = strain.map { Int($0.rounded()) }
        let restValue = restScore.map { Int($0.rounded()) }
        let hrvValue = (todayRow?.avgHrv ?? day?.avgHrv).map { Int($0.rounded()) }
        let restingHRValue = todayRow?.restingHr ?? day?.restingHr
        let stressSeriesValue = stressPoints ?? storedStress?.stressSeries
        let stressDayValue = stress?.day ?? storedStress?.stressDay
        let snap = WidgetSnapshot(
            recovery: recoveryValue,
            bpm: bpmValue,
            batteryPct: batteryValue,
            bonded: model.live.bonded,
            updated: Date(),
            // Stored 0–100 axis for ring fill; display string carries the #313 scale.
            effort: effortValue,
            rest: restValue,
            hrv: hrvValue,
            restingHr: restingHRValue,
            effortDisplay: effortDisplay,
            effortWhoop: effortScale == .whoop,
            // nil when the curve could not be scored at all, which must not blank a widget that already
            // has one: carry the stored values forward instead of publishing an absence.
            stressSeries: stressSeriesValue,
            stressDay: stressDayValue,
            steps: steps,
            caloriesKcal: caloriesKcal,
            workoutsToday: todayRow?.exerciseCount ?? day?.exerciseCount
        )
        saveAndReloadIfChanged(snap)
    }

    /// Rest resolution shared in behavior with TodayView: today's value wins, otherwise the latest
    /// scored night is carried only while it is still fresh. The widget always represents today.
    private static func freshRestScore(todayValue: Double?, lastDay: String?, lastValue: Double?,
                                       todayKey: String) -> Double? {
        if let todayValue { return todayValue }
        guard let lastDay, let lastValue,
              !isCarryStale(priorDayKey: lastDay, todayKey: todayKey) else { return nil }
        return lastValue
    }

    private static func isCarryStale(priorDayKey: String, todayKey: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let prior = formatter.date(from: priorDayKey),
              let today = formatter.date(from: todayKey) else { return false }
        let days = Calendar.current.dateComponents([.day], from: prior, to: today).day ?? 0
        return days > 2
    }

    /// Publish fields that come directly from the live BLE state without re-reading the Rest metric
    /// series. HR is admitted once a minute and battery arrives about every eight minutes; routing those
    /// hooks through the full `publish` path used to query up to 4,000 days of Rest history every time even
    /// though none of the score fields could have changed. Reusing the last full snapshot keeps every score
    /// byte-identical and changes only the three live fields. A cold start with no snapshot falls back to a
    /// full build so this fast path can never publish an incomplete first glance. The first live update
    /// after a local-day rollover also takes the full path so the score anchor advances with Today.
    @MainActor
    static func publishLive(from model: AppModel, includeEffort: Bool = false) async {
        let now = Date()
        guard var snap = load(), !liveUpdateRequiresFullBuild(previous: snap, now: now) else {
            await publish(from: model)
            return
        }
        // The loaded value IS the current on-disk state (this runs on the main actor, so nothing else
        // rewrote it between here and the save); hand it to the dedup so the live path reads the App Group
        // ONCE per tick instead of loading it again inside saveAndReloadIfChanged.
        let previous = snap
        snap.bpm = model.bpm ?? model.live.heartRate
        snap.batteryPct = Self.activeBatteryPct(from: model)
        snap.bonded = model.live.bonded
        if includeEffort {
            let scale = currentEffortScale()
            if let strain = await currentLiveEffort(from: model, now: now) {
                snap.effort = Int(strain.rounded())
                snap.effortDisplay = effortDisplay(strain, scale: scale)
                snap.effortWhoop = scale == .whoop
            }
        }
        snap.updated = now
        saveAndReloadIfChanged(snap, previous: previous)
    }

    /// Optional live score used by the widget while the app is accumulating today's HR. This mirrors
    /// TodayView's live Effort path without changing the shared/core scoring implementation.
    @MainActor
    private static func currentLiveEffort(from model: AppModel, now: Date) async -> Double? {
        let end = Int(now.timeIntervalSince1970)
        var start = Int(Repository.logicalDayStart(now).timeIntervalSince1970)

        // Today can use sleep-onset as the start of the effort window. Keep that same preference here
        // so the widget does not disagree with the ring when the user has enabled it.
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        if mode == .sleepOnset {
            let key = Repository.logicalDayKey(now)
            let onset = await model.repo.exploreSeries(
                key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop"
            ).last(where: { $0.day <= key }).map { Int($0.value.rounded()) }
            if let onset { start = onset }
        }
        guard end > start else { return nil }

        let samples = await model.repo.hrSamples(from: start, to: end, limit: 200_000)
        let maxHR = model.profile.age > 0
            ? StrainScorer.tanakaHRmax(age: Double(model.profile.age)) : nil
        let restingHR = model.repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        return StrainScorer.strain(
            samples,
            maxHR: maxHR,
            restingHR: restingHR,
            method: PuffinExperiment.effortMethod,
            sex: model.profile.sex
        )
    }

    @MainActor
    private static func currentEffortScale() -> EffortScale {
        UnitPrefs.resolveEffortScale(
            UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? ""
        )
    }

    private static func effortDisplay(_ strain: Double, scale: EffortScale) -> String {
        if scale == .whoop {
            return String(format: "%.1f", locale: AppLanguage.activeLocale,
                          UnitFormatter.effortValue(strain, scale: .whoop))
        }
        return "\(Int(strain.rounded()))"
    }

    /// Persist and ask WidgetKit for a new timeline only when a rendered field changed. The snapshot's
    /// timestamp is metadata only (no widget family displays it), so an otherwise-identical publish is a
    /// true no-op rather than an App-Group write plus an extension reload.
    /// `previous` lets the live fast path pass the snapshot it already loaded (it runs on the main actor,
    /// so that value is still current); the full publish path omits it and this loads once for the dedup.
    @MainActor
    private static func saveAndReloadIfChanged(_ snap: WidgetSnapshot, previous: WidgetSnapshot? = nil) {
        let previous = previous ?? load()
        if renderedContentChanged(from: previous, to: snap) {
            snap.save(previousSeries: previous?.hrSeries ?? [])
            WidgetCenter.shared.reloadAllTimelines()
            // Android skips the update entirely when no widget is placed; WidgetKit offers no
            // synchronous way to know, so the reload still goes out and is instead recorded honestly.
            // Counting it as a reload would make a widget-removed export read exactly like a
            // widget-installed one, which is half the comparison the counters exist for.
            if WidgetTelemetry.widgetsInstalled {
                WidgetTelemetry.noteReloaded()
            } else {
                WidgetTelemetry.noteNoWidget()
            }
        } else if WidgetSnapshot.traceNeedsPoint(previous: previous, bpm: snap.bpm, now: snap.updated) {
            // A steady heart changes nothing the header renders, so the branch above declines — but the
            // TRACE still wants this minute's point, or it stops advancing at rest and prunes to empty
            // (#1957). Persist without a reload: the point is for the next timeline WidgetKit builds,
            // and spending a reload a minute is exactly what the dedup above exists to avoid.
            snap.save(previousSeries: previous?.hrSeries ?? [])
            WidgetTelemetry.noteDeclined()
        } else if liveUpdateRequiresFullBuild(previous: previous, now: snap.updated) {
            // The rollover's visible values can legitimately match yesterday's. Persist the fresh day
            // stamp once without spending a redundant WidgetKit reload, so later live ticks stay fast.
            snap.save(previousSeries: previous?.hrSeries ?? [])
            WidgetTelemetry.noteDeclined()
        } else {
            // Nothing at all to do. Counted rather than left as a silent fall-through: an outcome that
            // records nothing is exactly how the Android counters came to report publishes that never
            // went anywhere as if they had.
            WidgetTelemetry.noteDeclined()
        }
    }

    /// Ask WidgetKit whether any widget is actually installed, and remember the answer.
    ///
    /// Only on the full publish path: it is already `async`, and the once-a-minute live path has no
    /// `await` to spend on an XPC round trip it does not need. The answer changes when a user adds or
    /// removes a widget, which is exactly when the app is being foregrounded anyway, so a value from
    /// the last full publish is fresh enough for a diagnostic.
    ///
    /// A failure leaves the previous answer in place rather than guessing, and "never asked" counts as
    /// installed — over-reporting reloads is the safe direction for a figure meant to show a cost.
    @MainActor
    private static func refreshWidgetPresence() async {
        let installed: Bool? = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets): continuation.resume(returning: !widgets.isEmpty)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
        if let installed { WidgetTelemetry.noteWidgetsInstalled(installed) }
    }

    /// #114/#169: HR is the ONE high-frequency widget-publish trigger — `model.bpm` moves every few
    /// seconds during activity, unlike battery (~8 min) or connection flips (rare). Left ungated, the
    /// `model.$bpm` hook rewrote the shared snapshot + called `reloadAllTimelines()` on every tick (and,
    /// before the live-only fast path, also re-read the full Rest series). This caps HR-DRIVEN publishes
    /// to one per `interval`, mirroring Android's `PushGate` 60 s `HR_REFRESH_MS` cadence. Only the bpm
    /// hook consults it; the low-frequency score/battery/connection/scenePhase publish sites stay ungated,
    /// exactly as before. `@MainActor` (the hook already runs there), so the timestamp needs no locking.
    @MainActor
    enum HRPublishThrottle {
        static let interval: TimeInterval = 60
        private static var lastPublishedAt: Date = .distantPast
        /// True (and stamps `now`) when at least `interval` has elapsed since the last HR-driven publish;
        /// false to skip this HR change. The first call always admits (`.distantPast`).
        static func admit(now: Date = Date()) -> Bool {
            guard now.timeIntervalSince(lastPublishedAt) >= interval else {
                WidgetTelemetry.noteGated(now: now)
                return false
            }
            lastPublishedAt = now
            WidgetTelemetry.noteAdmitted(now: now)
            return true
        }
    }
}
#endif
