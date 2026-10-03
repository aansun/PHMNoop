# Data requirements

What each Nuna area needs from the data layer. "Reuse" means the data is already produced; "Extend" means a small addition; "New" means new storage or computation. Remember the parity contract in `AGENTS.md`: analytics and stored data must stay byte-identical across Swift and Kotlin, and Room/GRDB migrations must agree.

## Today

| Need | Status | Notes |
|---|---|---|
| Charge, Effort, Rest, HRV, RHR, steps | Reuse | `Repository.days`, scores already feed `TodayView` |
| Stress timeline and average (0-3) | Reuse | `stressSeries` in `WidgetSnapshot`, `StressTodayCard` |
| Card order and visibility | Reuse | `TodayCustomizationMetadata`, `TodayCustomizationSheet` |
| Chosen metrics for the metrics card | Extend | Store 2-6 metric keys in preferences |
| Past-day view | Extend | Parameterise `TodayView` by day (`DayNavBar` exists) |
| Quick actions list | Extend | Order and visibility in preferences |

## Sleep

| Need | Status | Notes |
|---|---|---|
| Stages, vitals, performance, debt | Reuse | `SleepView` cards |
| Nightly movement (count, position changes, per-hour) | New/Extend | Aggregate the motion stream per night; needs an analytics function and a stored summary |
| Nap list | Extend | Detect and store nap segments; include them in total sleep and the sleep need |

## Health

| Need | Status | Notes |
|---|---|---|
| Vitals (HRV, RHR, SpO2, breathing, skin temp) | Reuse | `VitalSignsSummary`, `SkinTempCardsView` |
| Fitness age and VO2max | Reuse | `fitness_age`, `vo2max_est` weekly series; the 4-week change needs the last 4 weekly values |
| Fitness age inputs breakdown (RHR, activity index) | Extend | Expose the two terms of the Nes model |
| Weight, waist | Reuse | HealthKit bridge (read) |
| Nutrition summary | Reuse | CSV import totals |
| Lab Book, Rhythm, cycle | Reuse | Existing views and stores |

## Trends

| Need | Status | Notes |
|---|---|---|
| Averages, previous-period deltas, best/worst day | Extend | Derived from `Repository.days` |
| Correlations (Charge vs next-day Effort, Rest) and bucket averages | New | Pure analytics function with tests; keep in `StrandAnalytics` |
| Behaviour effects, activity cost | Reuse | Insights correlation engine, `ActivityCostEngine` |
| Year heat map | Reuse | `ActivityHeatmap`, `YearHeatStrip` |

## Workouts

| Need | Status | Notes |
|---|---|---|
| Sessions, zones, GPS | Reuse | Workout tables |
| Training load: CTL / ATL / form | Reuse | `TrainingLoadEngine` |
| Muscular load: weekly volume, per-muscle sets, recovery | Extend | Lift log already has volume and direct/indirect sets; add per-muscle last-trained time |
| Workout calendar (active/rest days, cardio/muscular) | Extend | Derived from workouts; no new storage |
| Programs (templates) | Reuse | Lift programs; "Save session as program" is a new write path (see PROPOSALS) |
| Auto-detect setting | Reuse | `PuffinExperiment.autoDetectWorkoutsKey` |
| Zone alert state (hold 10 s, repeat interval) | New | Live-session logic (see PROPOSALS) |

## Devices

| Need | Status | Notes |
|---|---|---|
| Battery %, firmware, signal, last sync | Reuse | `LiveState`, `DevicesView` |
| Battery history and runtime estimate | Extend | Predictive-battery spec exists (`docs/superpowers/specs/2026-07-10-predictive-battery-alert-design.md`) |
| Sync history (last N syncs) | New | Small log of sync results |
| Pairing reset detection | Reuse | Existing error path in `DevicesView` |

## Anya

| Need | Status | Notes |
|---|---|---|
| Providers, key storage, consent, memory, history | Reuse | `AICoach`, providers, `CoachMemory` |
| Contextual brief per module | Extend | `generateContextualBrief(pageContext:)`: add contexts health, nutrition, device, workout |
| Day plan (warm-up, main, cool-down) | New | Prompt + structured response; reuse the existing workout-plan prompts |

## Widgets and Live Activities

| Need | Status | Notes |
|---|---|---|
| Snapshot fields for score, HR, stress, steps | Reuse | `WidgetSnapshot` |
| **Vital sign widget**: SpO2, breathing rate, skin temperature deviation | **New fields** | Add optional, defaulted fields to `WidgetSnapshot` (older snapshots must still decode) |
| Effort for the Live Activity chip | Extend | Live session already tracks session Effort |

## Settings

| Need | Status | Notes |
|---|---|---|
| Profile, units, appearance | Reuse | `SettingsView` sections |
| Experience mode | New | `experience.mode` preference (`ExperienceMode`) |
| App language | New | In-app picker in front of the iOS per-app language setting |
| Goals (Effort, sleep, steps, water, weight) | Extend | Only some exist; unify under one goals store |
| Notification preferences, quiet hours | Extend | `NotificationSettingsView`; quiet hours is a proposal |
| Strava | Reuse | `StravaSettingsView` (state: enabled, credentials, connection, auto-upload) |
