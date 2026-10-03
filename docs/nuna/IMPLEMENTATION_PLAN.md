# Implementation plan

Scope: iOS only (`NOOPiOS`). Android keeps its UI; any new stored data or analytics still has to stay byte-identical across platforms (see `AGENTS.md`). One concern per pull request; keep UI changes separate from schema or protocol changes.

Sizes are rough (S ≈ days, M ≈ 1-2 weeks, L ≈ several weeks).

## Phase 0: foundation (S-M)

1. Merge `NunaTheme.swift` (tokens, `ExperienceMode`, first components).
2. Add the remaining primitives from `COMPONENTS.md` (button style, icon button, list row, segmented, sheet, tab bar, header, FAB).
3. `NunaRootView`: a new shell with the five tabs. `StrandiOSApp` chooses `RootTabView` or `NunaRootView` from `ExperienceMode`.
4. Experience picker (Saya, Tampilan, Experience) with the confirm sheet.

Acceptance: switching Experience reloads the shell without touching data; Default behaves exactly as before; no raw hex values outside the token file.

## Phase 1: Hari ini (M-L)

Today with the three-ring card, Anya card, stress card, metrics card, activity card. Date pill and past-day view. Customise (in-place edit mode and the list sheet). Quick actions sheet and the floating "+". Detail screens: Charge, Effort, HRV, RHR, steps, heart rate, all metrics, stress, journal, early warning, notifications. Breathing (with rhythm), water, manual activity.

Acceptance: every card can be hidden, reordered and restored to default; past days are read-only; the "+" sheet reaches every action in `TodayQuick`.

## Phase 2: Tidur and Kesehatan (M-L)

Sleep summary with movement strip and naps; stage, vitals, performance and nap screens. Health tabs and the detail screens (live HR, oxygen and breathing, skin temperature, fitness age, mood, weight, waist, nutrition, lab book, cycle, permissions, Rhythm with its consent gate).

Needs: nightly movement summary and nap detection (see `DATA_REQUIREMENTS.md`). Fitness age follows `docs/FITNESS_AGE.md`: weekly, ±5-year band, "comparison, not biological age".

## Phase 3: Tren (M)

Summary with ring gauges, Charge-vs-Effort and Charge-vs-Rest comparisons, per-metric trend screens, heat map, insights, compare, explore.

Needs: a correlation/bucket analytics function with unit tests. Keep each Trends sub-view in its own file; `TrendsView` is already near the type-check budget.

## Phase 4: Latihan (L)

Hub, start, summary. Gym programs (templates), import, session summary, "save as program". Training load (summary, cardio, muscular), calendar, history. Auto-detect on/off. Live sessions for GPS (run, walk, cycle) and non-GPS (HIIT, indoor), lock-screen Live Activity, Dynamic Island, zone alerts.

Acceptance: GPS sessions always show distance, time and pace (speed for cycling) on the session screen, lock screen and Island; non-GPS sessions never show distance or pace; the lock screen has no Pause/End buttons.

## Phase 5: Anya everywhere (M)

Contextual card and header button per module; extend `CoachLauncherSheet` contexts; day-plan response; provider setup screens (Apple Intelligence, ChatGPT, API key, custom server); memory, history, attachments, voice input, morning brief, voice coach.

Acceptance: one card per screen, always cites figures, hideable; "Connect Anya" row when no provider; consent off means no data leaves the device.

## Phase 6: Perangkat (M)

Device manager and detail, battery, sync history, add-WHOOP flow, help and re-pair flow, model comparison, log, restart, sync Live Activity. WHOOP 4.0, 5.0 and MG only; keep the BLE safety contract in `docs/CONTRIBUTING.md`.

## Phase 7: Saya (M)

Hub, persona (profile, zones, goals), appearance, units, language, notifications, optional features, automations (double-tap, presence, haptic coaching, sedentary, alerts, shortcuts), data hub, backup, Strava, privacy, advanced, experiments, test centre, about.

Most screens re-skin existing settings; the new work is the hub, persona goals, language and privacy.

## Phase 8: Widgets (M)

Revise existing widgets to Nuna tokens; add the Vital sign widget (small, medium, large, lock screen) and its configuration; add the new optional fields to `WidgetSnapshot`.

## Phase 9: Onboarding (M)

The 19-screen flow: welcome, privacy, terms gate, value pages, device choice, Bluetooth, wear, scan help, profile, Health, import, Anya, preferences, done, what's new.

## Cross-cutting

- **Localization:** every new string in `Localizable.xcstrings` (English and Indonesian); run `Tools/i18n_audit.py`.
- **Accessibility:** rings and charts need accessibility labels and values (the mockups include them); targets 44 pt; Dynamic Type.
- **Tests:** analytics additions get unit tests; view models for new screens get snapshot or logic tests.
- **Rollout:** ship Nuna behind `ExperienceMode` defaulting to Default until Phase 7 is complete, then flip the default for PHMNOOP builds.

## Known risks

- Type-checker budget in large SwiftUI views (`TrendsView`, `SettingsView`): split into small views.
- The Default look and Nuna differ in navigation; deep links (`NavRouter`) must resolve in both shells.
- Dynamic Island and lock-screen layouts are constrained by ActivityKit; the mockups are the intent, not pixel-exact.
- Some mockup behaviour is a proposal (see `PROPOSALS.md`); do not build it without a decision.
