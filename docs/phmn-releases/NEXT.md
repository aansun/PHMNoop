## PHMN 3.1.2

Heart rate for Fitbit and Garmin workouts, naps that are found, and no more double activities.

### New / Enhancement
- **Heart rate for workouts from Fitbit and Garmin.** A workout that reaches Apple Health now brings its heart rate: the chart, the average and highest, and the zones. The strap stays first: Apple's heart rate is used only where the strap has none for that time, and it never feeds Strain, Stress or Recovery.
- **One activity, one row.** When the strap, a session logged here, Strava and Apple Health all hold the same workout, PHMN keeps one: the strap or what you logged first, then Strava, then Apple Health. The row you keep takes the heart rate, calories or distance it lacks from the others.
- **Where it came from.** An activity imported from Strava or Apple Health says so on its page, under the figures.
- **Naps found.** Naps of 20 to 90 minutes are now detected, using a clear heart-rate dip and the strap's own sleep reading. Before, only sleeps over an hour and a half were.
- **Suggestions after the workout.** An "Activity detected" suggestion appears once your heart rate has settled for 30 minutes, so it no longer changes while you are still cooling down.
- **Detection learns your habits.** The workout and nap detectors now study your own answers on your phone and are checked against the built-in rules. They change nothing until there is enough of your data to prove they do better. The comparison is in Auto-detect settings, under Detection check.

### Bug Fixing
- **Double activities.** A workout logged here and the same one from Apple Health no longer show side by side when the two name it differently, such as Treadmill walk and Running.
- **Missed naps.** A short daytime nap was never detected, however clear it was on the strap.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
