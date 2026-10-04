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

Follow-up: the Customise chip next to the date pill was removed (the dashed "Add or arrange cards" card at the bottom does the same). Key metrics show the change against the previous night for HRV, resting HR, blood oxygen and respiratory; a value carried from the last scored night is compared with the night before it. Key metrics can be shown as two-column cards or one long list (toggle in the section title, stored in `nuna.keyMetricsLayout`).

Icon colour rule (requested): every symbol is neutral (white, grey or black). `NunaIconTile` ignores its `tint`, chip and quick-action icons are white, and the add-card plus is white. Colour stays on scores, rings, chart marks, chips' text and status.

Charts (requested): every trend chart now shows day and month on its axis and the real value of each reading. Lines use NOOP's own Line2 chart (`TrendChart` with point values and month-over-day axis labels) for metric history, stress 7D / 30D, sleep trends and fitness age. Bars (Charge, Effort, steps) write the value above each bar for 7 to 14 days, or the highest and latest for longer ranges, with the date under each bar (start, middle and end for 30D / 90D). Days without a reading are left out of lines and drawn as a faint stub in bars; nothing is filled in. The body-clock rhythm curve is the only drawn shape that is an estimate, and its card says "Estimated shape".

Health re-check against Health, HealthVital, HealthBody and HealthSleep: All has the normal-range card (HRV and resting HR on a bar with the 30-day average), the Anya card, vital tiles with captions, body tiles, an Apple Health card (steps read + write, weight and waist read) and the strap card with battery and last sync. Vital has live heart rate, an HRV hero with 14 / 30 / 90 day Line2 chart, vitals tiles, stress, fitness age and early warning cards. Body has the weight hero with 30D / 90D / 1Y Line2 chart, body composition (fat and lean only when Apple Health has them), nutrition, water (when enabled), Lab Book, cycle, mood. Sleep has the last 7 nights, need vs actual, bedtime consistency, average stages against your usual, naps this week. Not built because the app has no such data or setting: caffeine tracker, smart alarm and bedtime reminder rows, manual weight entry, "write steps to Health" switch, the HealthLive zones screen, HealthOxygen, HealthSkin and HealthVO2 detail layouts (they open the shared metric screen).

Design pass (against docs/nuna/mockups, compared one screen at a time in the browser pane):
- Today now follows Main: strap chip with battery, bell with unread dot, date pill plus "Customise" chip, score card with `%` units and the ready chip, Anya card with a white "Start" button, stress card, "Key metrics" with "Edit" and "All", "Activity" with "All workouts", quick-log chips (water, journal, mood), dashed "Add or arrange cards". Default order and metrics follow the mockup until the person arranges their own (shared keys; Your Cards hidden by default).
- Stress uses NOOP's own intraday curve (`StressDayCurve` and `DaytimeLoadLine`, the same drawing as Default Today and the widget), in a Nuna card.
- Edit mode matches TodayEdit: dashed frames with a grip, X to hide, drag to reorder (accessibility actions move up and down), "Add a card here" for hidden cards, Card settings, Restore defaults.
- Date sheet matches TodayDate: month grid with Charge-coloured dots, recorded-days count, quick jumps, a Charge / Effort / Rest summary of the selected day.
- Quick actions matches TodayQuick: six shortcuts, Ask Anya, water row (when water tracking is on).
- Detail screens match TodayCharge, TodayEffort, TodayHRV / RHR / Steps (shared metric screen with band line or capsule columns), TodayStress and TodayAllMetrics.

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

Body clock (added after the first design pass): two new mockups, `SleepBodyClock` (lowest point, 24 h dial of last night against the ideal window, lowest / peak / schedule tiles, 24 h rhythm curve, confidence, how it is calculated) and `SleepBodyClockPlan` (trip or shift planner with the daily light and sleep plan). `Sleep` links to it with a Body clock card, and Health, Sleep tab lists it. Implemented in `StrandiOS/Nuna/Sleep/NunaBodyClock.swift` on the existing `CircadianEngine` (estimate, chronotype, ideal window, `planShift`); nothing is computed differently from Default. It needs at least 7 days of heart-rate data, otherwise it shows the honest "hard to read" state with the planner still available.

Status (built and checked in the iOS simulator with a restored backup):
- `StrandiOS/Nuna/Sleep/`: `NunaSleepModel` (night picker over the same session grouping, main-night and nap rules as `SleepView`; stage timeline and split; need, hours-vs-needed, restorative, consistency and debt use the same rules as `SleepModel`), `NunaSleepParts` (hypnogram strip, stage split bar, legend, stat tile, night picker), `NunaSleepScreens` (summary, stages, overnight vitals, performance with need and debt, naps).
- Health › Vital, revised on request: the live card is "Beats per minute" with the same data as Default Today (rolling live samples while the strap streams, otherwise today's 5-minute averages since midnight with gaps left as gaps, min / avg / max) in `NunaLiveHeart.swift`; tapping it opens `NunaDeepTimelineView`, the Nuna look for Default's Deep Timeline (metric chips, day stepper, `OverviewHRChart` with pinch zoom and scrub, sleep and workout bands, min / avg / max tiles). Stress monitor uses a half-circle gauge and a "Breathe 5 min" button (BreathingView); fitness age shows the ±5 chip, years younger / older chip, actual age, an age slider and "Updated <weekday> · 4-week trend" from the weekly `fitness_age` series; early warning has the shield header, Safe chip and a 2 x 2 grid of check chips (a chip flags when its signal is among the fired signals). Health › All vital rows compare with the night before again (`NunaTodayModel` deltas), not a 14-day average. Parts live in `NunaVitalParts.swift`.
- Health › Vital tiles, Body and Sleep re-checked against the current mockups: the vital tiles (SpO₂, Respiratory, Skin temp, Max HR) carry visible status chips (Normal / Above or Below range / Small or Larger deviation) and Resting HR is a hero card with the change from yesterday; Body has the composition bar with fat / lean / BMI tiles, a Waist card with a manual measurement sheet (writes the profile value), nutrition with macro bars, and no Apple Health permissions or mood rows (mood opens from the stress card); Sleep has bedtime-to-wake bars on one clock, naps with icons, and the two new rows below. Smart strap alarm and Bedtime reminder rows toggle in place and open Nuna detail screens (`NunaAlarms.swift`) built on the existing `BehaviorStore`, `AppModel.applySmartAlarm()` and `WindDownNudge`: countdown and next-buzz stamp, wake time, repeat days, strap honesty notes and the "check what the strap stored" action; reminder time, usual wake time, per-day overrides, and the notifications-denied alert. `TrendChart` gained `pointValueStride` so dense Line2 charts label every Nth point (newest always).
- Health detail screens built from the mockups (`NunaHealthDetails.swift`, `NunaFitnessAge.swift`): Live heart rate (HealthLive: live or banked bpm with trace, 5 min / 1 hour / Today min-avg-max, today's time in zones from the profile zone set, Dynamic Island switch, broadcast switch on WHOOP 5/MG, links to the deep timeline and to starting a session), Oxygen and breathing (HealthOxygen: SpO₂ tab with last night, 7-night columns and min / avg / max; Breathing tab with the 14-night Line2 chart and your range), Skin temperature (HealthSkin: last-night deviation, 14 nights as bars around the baseline, deviation scale, what affects it) and Fitness age (HealthVO2: hero with the age slider, 4-week direction, the two inputs rebuilt from the last 7 days with their years, data coverage, weekly history, VO₂max with the waist unlock, how to lower it). `spo2`, `resp_rate`, `skin_temp` and `fitness_age` metrics now open these instead of the shared metric screen. Not shown because the app has no such data: room temperature value and a logged-alcohol state on the skin screen (rows are explanatory), the high-resting-heart-rate alert toggle.
- Mood, body and data screens (`NunaMood.swift`, `NunaBodyDetails.swift`, `NunaAppleHealth.swift`): Mood check-in (five faces saved to the existing mood store, factors, energy, note kept per day on this phone, today's stress, this week, and the correlation lines once there are 7 check-ins); Weight (latest with target and distance, 30D / 90D / 1Y Line2 chart, fat / lean / BMI tiles, BMI scale, add a measurement stored under its own `noop-manual` source and also written to the profile, weight target); Waist (profile value, waist-to-height scale, manual entry, link to VO₂max); Nutrition (kcal ring against energy out, macros, CSV import card, active caffeine from the caffeine log); Lab Book (cards with the user's own typed range and a "within / outside your range" chip, reusing the existing editor and detail sheets in dark); Menstrual cycle (phase ring, week strip, log a period start, tracking switch, history). Apple Health permissions moved to Me › Apple Health: connection state and last sync, what is read, what is written, Sync now / Enable, open the Health app; iOS grants access as one set, so there are no per-type switches. Removed from Health › Body: the Apple Health permissions row. Not built: the meals-of-the-day list (the app stores no meals), a weight reminder, a monthly waist reminder, the waist history chart (only the latest value is stored), and the cycle week's fertile-window shading.
- Rhythm (HealthRhythm, HealthRhythmConsent, HealthRhythmEmpty, HealthRhythmUnsupported) in `NunaRhythm.swift`, opened from the Vital tab row. It shares the Default consent record (`RhythmConsent`), so accepting in either experience counts for both, and it runs the same `RhythmScreener` windowing and stillness gate over the last banked night. Consent screen with the five numbered points, the "I understand" switch and Turn on / Not now; main screen with the last-night summary (confidence and regularity chips, variation and extra-or-skipped bars), the Poincaré scatter with its SD1 / SD2 ellipse (evenly sampled for legibility), reading windows (neighbouring readable 5-minute windows joined into time spans), the six numbers, how it is measured, the standing disclaimer, the on/off switch and "read the consent again"; empty and unsupported states choose their copy from the same empty-reason classifier as Default. The neutral CSV share row is kept.
- `StrandiOS/Nuna/Health/NunaHealthView.swift`: Health hub with All / Vital / Body / Sleep tabs and the fitness age screen (weekly value, plus or minus 5 year band against the real age, "comparison, not biological age"). It replaces the Health tab root in `NunaRootView`.
- The Rest ring on Today and the Sleep rows in Your Cards / Added Cards open the Nuna sleep screen. Vitals, oxygen, skin temperature, weight and stress open the shared Nuna metric screen from Phase 1.
- Opened as before (existing screens): live heart rate, Lab Book, Rhythm with its consent gate, Apple Health permissions, cycle tracker, mood check-in, nutrition import. Their look is re-themed in later phases.
- Movement strip (added later): the Sleep summary and Sleep stages screens draw the stored 30-second movement under the hypnogram, with Movement, Position changes and Restlessness. Counts are derived on the fly from `sessionMotions` (a movement is a burst above 0.3, a position change a burst peaking above 6, restlessness is movements per hour: under 6 low, under 12 medium). Magnitudes are uncalibrated, so the counts are relative to the strap and the screen says so. No stored summary was needed.
- Naps (matches `SleepNap`): the hero with stage lanes and the movement strip, Light / Deep / REM / Movement tiles, the effect on tonight's need, nap history with Manual / Auto, and an "Add a nap by hand" sheet (`Repository.addManualNap`). Manual naps are marked from the stored `userEdited` flag. The Detected-automatically toggle and "Hitung ke kebutuhan" toggle in the mockup are not wired: the app always counts naps toward need.
- Stress detail (matches `TodayStress`, then revised on request): the Day average is a ring gauge (0 to 3) beside the baseline note, HRV and Resting HR tiles with the change from the night before, Today / 7D / 30D, a line chart (NOOP's own `DaytimeLoadLine` for today, a smooth band line for 7D / 30D), stress zones with minutes and share, the two highest peaks, 2-minute breathing, Anya, and a switch that shows or hides the Stress card on Today. Stress monitoring itself lives in Today (the card), not in Health. Not wired: the "remind me when high for a long time" toggle, because no such setting exists in the app yet.
- Known gaps: the "smart alarm" row, journal notes on the night, adding a nap by hand, Rhythm empty / unsupported states in Nuna style, and the waist tile reads the profile only.

## Phase 3: Tren (M): done

Built in `StrandiOS/Nuna/Trends/` and mounted as the Trends tab (`NunaTrendsView`). Everything is computed from the stored daily series (`repo.exploreSeries`); no figure is typed in. The pure helpers live in `Packages/StrandAnalytics/.../TrendInsights.swift` with unit tests (zone counts, weekday and weekly patterns, next-day buckets, strength label, longest streak).

- [x] Root (Trends.dc): range 7D / 30D / 90D / 1Y, summary sentence and three rings with the change from the previous period, best and lowest day, Charge-and-Effort and Charge-and-Rest cards with real correlation and "after a hard day" figures, daily signals (HRV, resting HR, stress, steps) with change and sparkline, 12-week Charge heat map, against-the-previous-period bars, Anya line from the data, Explore / Compare / Insights links, PDF export (existing report sheet).
- [x] Charge, Effort and Rest (TrendsCharge / TrendsEffort / TrendsRest): ring hero with the period change, 7D bars or Line2 chart with dates, zones with day counts, weekly pattern, highest and lowest with dates, drivers (Charge), load per week (Effort), what shapes Rest from the nights themselves (duration against need, consistency, efficiency, debt). Effort follows the chosen scale.
- [x] Charge and Effort (TrendsChargeEffort): bars and line on one day axis with touch-to-read, Charge tomorrow by Effort band, scatter with the fitted line, days that stand out.
- [x] Charge and Rest (TrendsChargeRest): two lines, Charge by Rest band, scatter, what shapes Rest.
- [x] Heat map (TrendsHeatmap): 3 / 6 / 12 months, green / yellow / red counts, weekly pattern, by month, best green streak.
- [x] Insights (TrendsInsights): data sufficiency, behaviour effects from journal answers (with and without days, confidence), cost of activity (`ActivityCostEngine`), links between metrics, tracked behaviours.
- [x] Compare (TrendsCompare): pick 2 to 4 metrics, normalised lines, correlation per pair, previous-period overlay, saved comparisons kept on this phone.
- [x] Explore (TrendsExplore): search, filters, favourites kept on this phone, every signal that has data with sparkline and latest value; opens the metric screen.

Not built: the "Pilih periode" custom date picker, and Insights rows for caffeine / hydration / late workouts that need their own journal entries (they appear only once those answers exist). Dummy-data note: the 90-day dummy Rest is almost always above 86%, so the low-Rest bucket on Charge and Rest is empty there; the screen shows a dash rather than inventing a value.

## Phase 4: Latihan (L): built, with gaps

Built in `StrandiOS/Nuna/Workouts/`. The Workouts destination (Today's "All workouts", Effort's session rows, the Quick sheet's Start session) now opens `NunaWorkoutsView`; the Default screens are untouched. Everything reads saved workouts (`repo.workoutRows`), daily Effort, lifting sessions and sets, and the stored heart rate.

- [x] Hub (Workouts.dc): last 7 days of Effort against the usual week with cardio and strength columns, sessions / duration / calories, training-load card with the acute-to-chronic ratio, 5-week calendar, auto-detect suggestion card with Save / Not a workout, start grid, history, banner for a running session.
- [x] Start (WorkoutStart.dc): sport picker over the existing catalogue, Free / Time / Distance / Zone target, readiness line from today's Charge, GPS and strap-buzz options, 3-second countdown, then `AppModel.startWorkout` (GPS arming and persistence are the existing ones).
- [x] Live session: elapsed time, heart rate, zone, Effort building, average and peak, GPS distance and pace when a route is recorded, progress to the target, a strap buzz when the target is reached or the zone is left, pause, resume, end and discard. Uses `AppModel.activeWorkout`, the same state the Default screen uses, so a session can be resumed from either.
- [x] Summary (WorkoutSummary.dc): distance, time, pace for on-foot sports, route trace when one was recorded, Effort added with the day's total, time per heart-rate zone, heart-rate curve, delete.
- [x] History (WorkoutHistory.dc): search, filters, totals, grouped by week, newest or oldest first.
- [x] Calendar (WorkoutCalendar.dc): 7 weeks of days coloured cardio / strength / both, tap a day for its sessions, active and rest days, streak, longest gap, weekday pattern.
- [x] Training load (TrainingLoad, Cardio, Muscle): summary with the load balance scale and 6 weeks of cardio and strength; cardio with form, fitness and fatigue from the existing `TrainingLoadEngine`, daily form, form states, load sources, time per zone; strength with weekly volume, volume by muscle group and personal records from the Lift Log tables.
- [x] Auto-detect (WorkoutAutoDetect / Off): the switch, the fixed rules read from `AutoWorkoutDetector`, the latest suggestion.
- [x] Pure helpers with tests: `TrendInsights.loadRatio`, `loadBand`, `formState`.

Not built, and why:
- Lock-screen Live Activity and Dynamic Island for a running session, voice coach, Strava push, GPS and non-GPS live templates (LiveWalk, LiveCycle, LiveHIIT, LiveIndoor, LiveIsland, LiveZone): the Default live activity, Strava and voice code stay as they are. The Nuna live screen does not yet drive them.
- Gym programs, import and "save as program" (WorkoutGym, WorkoutProgram, WorkoutProgramImport, WorkoutProgramItem, WorkoutSaveProgram, WorkoutLift, WorkoutSummaryGym) are reached through the existing Lift Log; their Nuna redesign is the next slice.
- A map under the route trace (only the line is drawn), per-kilometre splits, and the Write-to-Health and Strava switches on the summary (the sync handles Health; Strava is not wired here).
- Dummy data: the 90-day dummy now has four lifting sessions with sets so Strength can be checked; its run and walk rows have no GPS route, so the route trace and splits could not be seen.

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
