# Implementation plan

Scope: iOS only (`NOOPiOS`). Android keeps its UI; any new stored data or analytics still has to stay byte-identical across platforms (see `AGENTS.md`). One concern per pull request; keep UI changes separate from schema or protocol changes.

Sizes are rough (S ≈ days, M ≈ 1-2 weeks, L ≈ several weeks).

## Phase 0: foundation (S-M): done

1. Merge `NunaTheme.swift` (tokens, `ExperienceMode`, first components).
2. Add the remaining primitives from `COMPONENTS.md` (button style, icon button, list row, segmented, sheet, tab bar, header, FAB).
3. `NunaRootView`: a new shell with the five tabs. `StrandiOSApp` chooses `RootTabView` or `NunaRootView` from `ExperienceMode`.
4. Experience picker (Saya, Tampilan, Experience) with the confirm sheet.

Acceptance: switching Experience reloads the shell without touching data; Default behaves exactly as before; no raw hex values outside the token file.

Status: implemented and built for the iOS simulator.
- `Packages/StrandDesign/.../Nuna/NunaPrimitives.swift`: button style, icon button, FAB, header, section header, list row, toggle row, segmented control, add card, tab bar, sheet chrome.
- `StrandiOS/Nuna/NunaRootView.swift`: five-tab shell with the floating tab bar. Tab roots still host the existing Today / Health / Trends / Anya views until Phases 1-5 replace them. It handles `NavRouter` requests like `RootTabView`. Not yet ported: Home Screen quick actions, the Lift session bar, and the Anya launcher overlay.
- `StrandiOS/Nuna/NunaMeView.swift`: the "Me" hub; rows open the closest existing screen until Phase 7.
- `StrandiOS/Nuna/NunaAppearanceView.swift` and `ExperienceView.swift`: Experience picker with preview cards and the confirm sheet. Also reachable from the Default shell (Settings, Appearance, Experience).
- `StrandiOSApp.swift` selects the shell from `ExperienceMode`; Default stays the default.
- Indonesian strings for the new screens were added to `Localizable.xcstrings`.
- Known gaps: the Nuna shell forces a dark colour scheme; the Appearance setting is honoured again in Phase 7. The Notifications row opens Automations because the Notifications screen is macOS-only.

## Phase 1: Hari ini (M-L): done

Today with the three-ring card, Anya card, stress card, metrics card, activity card. Date pill and past-day view. Customise (in-place edit mode and the list sheet). Quick actions sheet and the floating "+". Detail screens: Charge, Effort, HRV, RHR, steps, heart rate, all metrics, stress, journal, early warning, notifications. Breathing (with rhythm), water, manual activity.

Acceptance: every card can be hidden, reordered and restored to default; past days are read-only; the "+" sheet reaches every action in `TodayQuick`.

Phase 1 checklist:
- [x] Today screen: header, date pill, three-ring card, Anya card, metrics grid, activity row, stress card, journal row, Start session
- [x] Date sheet and read-only past days
- [x] Quick actions sheet and floating "+"
- [x] Customise via the existing sheet
- [x] In-place edit mode (hide, reorder, restore hidden cards)
- [x] Your Cards, Added Cards and Menstrual Cycle cards
- [x] Early warning card and detail screen
- [x] Nuna metric detail screen (Charge, Effort, HRV, RHR, steps, heart rate, SpO2, respiratory, calories, stress)
- [x] All metrics screen
- [x] Manual activity sheet from the "+" sheet
- [x] Journal, breathing, water and notifications reachable from Today (the screens themselves are re-themed in later phases)
- [x] Indonesian strings, build, simulator check, commit

Status (first slice, built and checked in the iOS simulator):
- `StrandiOS/Nuna/Today/NunaTodayModel.swift`: per-day data (Charge, Effort, Rest, stress, vitals, steps, calories, workouts) with the same resolvers as the Default Today screens; display only.
- `NunaTodayView.swift` and `NunaTodayCards.swift`: header (wearable status chip, updates bell), date pill, three-ring score card, Anya card, key-metrics grid, latest-activity row, stress card, heart-rate row, journal row, Start session. Sections follow the shared `today.sectionOrder` / `today.hiddenSections` / `today.keyMetrics` preferences, so the arrangement carries over from Default.
- `NunaDateSheet.swift`: shortcuts and calendar. A past day is read only: no "+", no Start session, no Anya "today" card.
- `NunaQuickSheet.swift`: the "+" sheet (start workout, add activity, journal, breathing, water when enabled, ask Anya).
- Customise reuses the existing `TodayCustomizationSheet` on the same storage keys.
- Second slice: in-place edit mode (hide, move, reset; "More options" opens the existing sheet for key metrics and cards), Your Cards / Added Cards / Menstrual Cycle as link rows, early warning card and screen, Nuna metric detail (`NunaMetricViews.swift`: 7/30/90 day bars, average / low / high, Anya) used by the rings, tiles, stress card and Your Cards, All metrics list, and the manual activity sheet from "+".
- Known gaps (carried to later phases): Rest still opens the existing Sleep screen (Phase 2); heart rate opens the existing full-day chart; Journal, Breathing, Water and the Customise key-metrics sheet are still the light-themed Default screens; the Anya launcher overlay is not ported.

## Phase 2: Tidur and Kesehatan (M-L): done

Phase 2 checklist:
- [x] Sleep model: night picker, stages, naps, need and debt, vitals (from the cached rows; no new schema)
- [x] Sleep summary (Rest ring, hypnogram, stage comparison, naps, vitals, need and debt, Anya)
- [x] Sleep stages, vitals, performance and nap screens
- [x] Rest ring and Your Cards "Sleep" open the Nuna sleep screen
- [x] Health hub with All / Vital / Body / Sleep tabs
- [x] Health detail: live heart rate, oxygen and breathing, skin temperature, weight, waist (Nuna metric screen)
- [x] Fitness age screen (weekly, plus or minus 5 years, "comparison, not biological age")
- [x] Mood, nutrition, lab book, cycle, permissions, Rhythm (consent gate): reachable from Health
- [x] Nuna Health tab replaces the existing Health tab root
- [x] Indonesian strings, build, simulator check, commit

Sleep summary with movement strip and naps; stage, vitals, performance and nap screens. Health tabs and the detail screens (live HR, oxygen and breathing, skin temperature, fitness age, mood, weight, waist, nutrition, lab book, cycle, permissions, Rhythm with its consent gate).

Needs: nightly movement summary and nap detection (see `DATA_REQUIREMENTS.md`). Fitness age follows `docs/FITNESS_AGE.md`: weekly, ±5-year band, "comparison, not biological age".

Status (built and checked in the iOS simulator with a restored backup):
- `StrandiOS/Nuna/Sleep/`: `NunaSleepModel` (night picker over the same session grouping, main-night and nap rules as `SleepView`; stage timeline and split; need, hours-vs-needed, restorative, consistency and debt use the same rules as `SleepModel`), `NunaSleepParts` (hypnogram strip, stage split bar, legend, stat tile, night picker), `NunaSleepScreens` (summary, stages, overnight vitals, performance with need and debt, naps).
- `StrandiOS/Nuna/Health/NunaHealthView.swift`: Health hub with All / Vital / Body / Sleep tabs and the fitness age screen (weekly value, plus or minus 5 year band against the real age, "comparison, not biological age"). It replaces the Health tab root in `NunaRootView`.
- The Rest ring on Today and the Sleep rows in Your Cards / Added Cards open the Nuna sleep screen. Vitals, oxygen, skin temperature, weight and stress open the shared Nuna metric screen from Phase 1.
- Opened as before (existing screens): live heart rate, Lab Book, Rhythm with its consent gate, Apple Health permissions, cycle tracker, mood check-in, nutrition import. Their look is re-themed in later phases.
- Known gaps: the nightly movement strip (needs the movement summary in `DATA_REQUIREMENTS.md`), the "smart alarm" row, journal notes on the night, adding a nap by hand, Rhythm empty / unsupported states in Nuna style, and the waist tile reads the profile only.

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
