#if os(iOS)
import Foundation
import WidgetKit
import StrandAnalytics
import WhoopStore

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
        // Keep the widget aligned with Today: a real current-day strap counter wins over an older
        // Apple Health aggregate. The previous Apple-first order made the widget appear stale when a
        // WHOOP 5/MG offload had already updated Today's Steps tile.
        let steps = todayRow?.steps
            ?? appleRows.last(where: { $0.day == Repository.localDayKey(now) })?.steps
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
        // Keep the widget aligned with Today while the live HR window is still sparse. A live
        // recompute can temporarily under-read a workout that is already reflected in the stored
        // daily score (for example 1 while Today correctly shows 30). Today resolves this through
        // `effectiveEffort`; the widget must use the same floor or it visibly drops behind the app.
        let strain = StrainScorer.effectiveEffort(
            live: liveStrain,
            stored: todayRow?.strain ?? day?.strain
        )
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
            workoutsToday: todayRow?.exerciseCount ?? day?.exerciseCount,
            // The night the vitals describe: today's row once it carries a night, otherwise the carried-over scored day (today's row can
            // exist for steps alone while last night's HRV and resting heart rate still sit on the anchor).
            vitals: Self.vitalReadings(days: days, row: [todayRow, day].compactMap { $0 }.first(where: { $0.avgHrv != nil || $0.restingHr != nil }) ?? day),
            stepGoal: Self.configuredStepGoal
        )
        saveAndReloadIfChanged(snap)
    }

    /// Last night's vital signs for the Vital widget, as finished numbers. In or out of range is the same rule the Health screen
    /// uses (`VitalBands`: the wearer's own baseline once 14 nights are trusted, the typical adult range before that). The marker
    /// position is where the value sits between the lowest and highest of the last 30 nights.
    static func vitalReadings(days: [DailyMetric], row: DailyMetric?) -> [WidgetVital]? {
        guard let row else { return nil }
        let prior = days.filter { $0.day < row.day }.suffix(30)
        func history(_ pick: (DailyMetric) -> Double?) -> [Double?] {
            VitalBands.calendarSeries(prior.map { ($0.day, pick($0)) })
        }
        func position(_ value: Double, _ past: [Double?]) -> Double? {
            let v = past.compactMap { $0 }
            guard v.count >= 7 else { return nil }
            let mean = v.reduce(0, +) / Double(v.count)
            let sd = max((v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)).squareRoot(), 0.0001)
            // The track spans the average plus and minus four spreads; the normal band is the middle half of it.
            return min(max((value - mean) / (8 * sd) + 0.5, 0.03), 0.97)
        }
        var out: [WidgetVital] = []
        func add(_ key: String, _ value: Double?, _ pick: @escaping (DailyMetric) -> Double?, population: ClosedRange<Double>, cfg: MetricCfg?,
                 deltaAgainstAverage: Bool = false, deltaAgainstPrevious: Bool = false) {
            guard let value else { return }
            let past = history(pick)
            let band = VitalBands.band(value: value, history: past, populationRange: population, cfg: cfg)
            var delta: Double?
            var basis: String?
            if deltaAgainstAverage {
                let v = past.compactMap { $0 }
                if v.count >= 7 { delta = value - v.reduce(0, +) / Double(v.count); basis = "average" }
            } else if deltaAgainstPrevious, let last = prior.last.flatMap(pick) {
                delta = value - last; basis = "previous"
            }
            out.append(WidgetVital(key: key, value: value, delta: delta, deltaBasis: basis,
                                   position: position(value, past), outOfRange: band.band == .outOfRange))
        }
        add("hrv", row.avgHrv, { $0.avgHrv }, population: 40...120, cfg: Baselines.hrvCfg, deltaAgainstAverage: true)
        add("rhr", row.restingHr.map(Double.init), { $0.restingHr.map(Double.init) }, population: 40...60, cfg: Baselines.restingHRCfg, deltaAgainstPrevious: true)
        add("spo2", row.spo2Pct, { $0.spo2Pct }, population: 95...100, cfg: nil)
        add("resp", row.respRateBpm, { $0.respRateBpm }, population: 12...20, cfg: Baselines.respCfg)
        if let dev = row.skinTempDevC, !VitalBands.isAbsoluteSkinTemp(dev) {
            add("skin", dev, { $0.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? nil : $0 } }, population: (-0.6)...0.6, cfg: VitalBands.skinTempDeviationCfg)
        }
        return out.isEmpty ? nil : out
    }

    /// The daily step target the wearer set in Me, or 10,000 when none is set.
    static var configuredStepGoal: Int {
        let v = UserDefaults.standard.integer(forKey: "nuna.goal.steps")
        return v > 0 ? v : 10_000
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
        // Steps are a current-day repository value, not a live HR field. Refresh them on this fast path
        // as well so a battery/HR-triggered widget publish cannot carry an older App Group total forward.
        let todayRow = Repository.resolveToday(
            days: model.repo.days,
            logicalKey: Repository.logicalDayKey(now),
            localKey: Repository.localDayKey(now)
        )
        let anchor = Repository.widgetAnchor(days: model.repo.days, now: now)
        let appleRows = await model.repo.appleDailyRows(days: 2)
        if let steps = todayRow?.steps
            ?? appleRows.last(where: { $0.day == Repository.localDayKey(now) })?.steps
            ?? anchor?.steps {
            snap.steps = steps
        }
        snap.stepGoal = Self.configuredStepGoal
        snap.bpm = model.bpm ?? model.live.heartRate
        snap.batteryPct = Self.activeBatteryPct(from: model)
        snap.bonded = model.live.bonded
        if includeEffort {
            let scale = currentEffortScale()
            if let liveStrain = await currentLiveEffort(from: model, now: now) {
                // The fast path already has the last published value. Prefer the current-day
                // repository score when available, then use the snapshot as a final carry-forward;
                // never replace an earned score with a sparse live under-read.
                let storedStrain = todayRow?.strain
                    ?? anchor?.strain
                    ?? snap.effort.map(Double.init)
                let strain = StrainScorer.effectiveEffort(live: liveStrain, stored: storedStrain) ?? liveStrain
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

        var samples = await model.repo.hrSamples(from: start, to: end, limit: 200_000)
        // A manually started workout accumulates its smoothed HR window before the next repository
        // refresh. Include that in the live widget score so Strain does not wait for an offload or a
        // database refresh to reflect the work already visible in the workout screen. De-duplicate by
        // timestamp because the collector may have persisted the same reading already.
        if let activeWorkout = model.activeWorkout, !activeWorkout.samples.isEmpty {
            var byTimestamp = Dictionary(samples.map { ($0.ts, $0) },
                                         uniquingKeysWith: { _, latest in latest })
            for sample in activeWorkout.samples { byTimestamp[sample.ts] = sample }
            samples = byTimestamp.values.sorted { $0.ts < $1.ts }
        }
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
