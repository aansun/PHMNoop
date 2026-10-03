# Mockup behaviour that is not in the current code

The mockups were derived from the existing code wherever it was read. The items below were added by design and have **no counterpart in the repository today**. Each needs a product decision before implementation. Numbers shown in mockups are sample data.

## Today
- Floating "+" button and the **Quick actions** sheet (add activity, start session, journal, breathing, nap, weight, water, ask Anya).
- Date pill with a calendar picker and a read-only **past-day** view.
- In-place **edit mode** for cards (the list-based customisation sheet exists).
- Stress card with a day timeline on the main screen.
- Metrics card with a chosen set of 2-6 metrics.

## Sleep
- Movement summary (count, position changes, per-hour) and the movement strip.
- Nap card, nap detail, manual nap, and nap effect on sleep need.

## Health
- Mood check screen, fitness-age detail with the 4-week change.
- Dedicated nutrition, weight, waist, cycle and oxygen/breathing screens (the data exists; the screens are new).

## Trends
- Charge-vs-Effort and Charge-vs-Rest comparison, bucket tables, scatter.
- Per-metric trend screens, heat map detail, compare and explore pages.

## Workouts
- Workout calendar and "all sessions" filters.
- Muscular load index and per-muscle recovery status.
- **Save a gym session as a program.**
- Zone alerts on the live screen: yellow/red states, hold time (10 s), haptic pattern (1 short for yellow, 3 strong for red), repeat intervals (30 s / 20 s). Thresholds are placeholders.
- HIIT start/live screens.
- Optional auto-detect extras shown in the mockup ("check on every sync", "write to Apple Health").

## Anya
- Contextual card and header button in every module, with the trigger table in `AnyaPattern`.
- Day plan screen (warm-up, main, cool-down).
- Provider onboarding screens (the settings exist; the flow is new).

## Devices
- Battery temperature and cycle count, "ping strap", reminder to charge in the evening, sync history list.
- Pairing-reset help flow (the error exists; the guided flow is new).

## Live surfaces
- Effort chip in the Live Activity header, GPS/no-GPS card layouts, all Dynamic Island states.
- Vital sign widget, "hide health numbers on the lock screen", "show status word".

## Settings
- Experience switch (Default / Nuna) and its confirm sheet.
- In-app **language** picker (Indonesian / English).
- Persona goals screen, quiet hours for notifications, "sync failed" reminder.
- Privacy overview screen.
- Hub regrouping of Settings.

## Not designed
Apple Watch (glance, breathe, complications), Intelligence and Fused record in Trends, chart-style options, card transparency, sleep chart style and staging settings, floating Anya button. See the feature map board (`MapOverview`).
