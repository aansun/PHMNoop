## PHMN 2.0.0

Charge, Effort and Rest follow the day you pick, Effort shows what builds it, and the resting heart rate is the nightly average everywhere; plus a monitor-style heart-rate card, a simpler Compare and a glass strap-sync card.

### New / Enhancement
- **Pick a day, see that day.** Charge, Effort and Rest pages open on the day chosen on Today: the caption, the figures, the activities and the weekly and monthly trend card all follow it.
- **Effort, explained.** The rows under the ring are the Effort's own bands: Heart Rate Zone 1–3 (50–80% of your heart-rate reserve), Heart Rate Zone 4–5 (80–100%), everyday movement (the part of the day no workout explains) and Resting Heart Rate, which opens its own page. Touch a bar of the week to see that day. Heart rate also sits under the ring during a live workout.
- **Resting heart rate is the nightly average, everywhere.** The day's Effort, calories, workout detection and Charge are all scored against the mean of your main sleep, the figure the app shows, and not the lowest value.
- **Heart-rate card as a bedside monitor.** Dark screen, graph paper, a green trace and reading, and a dot that pulses at the pace of your heart. Between two signals it keeps the last trace, dated, until a new one arrives.
- **Compare, simpler.** Add metrics from a menu and remove them as chips. Wide axes, and a touch reads every metric's figure for that day on one row. Charge and Rest lines are grey and blue.
- **Trends.** *Against the previous period* is two rows with thick bars painted in the Today ring colours. Charge and Effort bars are boxes, and capsules only in Flow; touch a day for its figures, and the page still scrolls from the chart.
- **Charts you can touch.** Charge and Rest and Fitness and fatigue read their figures for the day touched, with the date at the right.
- **Strap sync on the Lock Screen** is a small glass card: status at the left, chunks and time at the right.
- **Steps.** The target line and figure follow the daily target you set under Targets, and the weekly Steps widget shows today's steps under the average.
- **Pause first, then end.** End, Discard and Reset appear only while a session or timer is paused, in breathing, the workout card and the interval timer.
- **Flow colours.** Warning and alert colours are clearer in Flow, the three-second countdown is readable on every theme, and the figures that appear when you touch the Charge and Effort chart are readable on every theme.

### Bug Fixing
- **Range and chip agree.** The shaded typical range of a metric is the mean plus and minus one spread, the same line the In range / Above range chip uses.
- **Workout Effort backfill** uses your resting heart rate, not a default of 60.
- **Charts no longer trap a vertical swipe**, so the page scrolls when a finger starts on a chart.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and is not affiliated with WHOOP, Inc., Strava or Hevy.
