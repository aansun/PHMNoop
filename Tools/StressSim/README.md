# StressSim

Lays two stress readings side by side on invented data whose true stress is known:

- **legacy**: the app's existing reading, untouched (`DaytimeStress` for the waking day, the nightly proxy for sleep).
- **WHOOP-ver**: `WhoopStress`, an experimental reading that follows WHOOP's public description of the Stress Monitor
  (heart rate and HRV against a 14-night baseline, motion limiting the effect of exercise, and Total day / Non-activity / Sleep).

The scenario is three days and nights: a calm day, a stressful day with a workout, and a day after a poor night.

```bash
cd Tools/StressSim
swift build -c release --scratch-path /tmp/stresssim-build   # outside iCloud Drive, or the bundle signing step fails
/tmp/stresssim-build/release/stresssim --out /tmp/stresssim-out   # writes series.json for plotting
```

## What to trust

It shows how each method **behaves**: how it handles noisy R-R, exercise, the three categories and a mistuned offset.
It does **not** show how accurate either is on a person, because the generator is this tool's own model, and several
`WhoopStress.Tuning` constants (`wakeHROffsetBPM`, `wakeHRVRatio`, `sleepRawShift`) were set in the neighbourhood of that
model. The calibration sweep in the output shows how much the result depends on them. Calibrate on real nights before
believing a number.

`WhoopStress` is not wired to any screen and has no Kotlin twin. Add one before it is shown to anyone.
