## PHMN 3.1.3

Effort and climb for the activities that come from Apple Health.

### New / Enhancement
- **Effort for activities from Apple Health.** An activity from Fitbit, Garmin or another app in Apple Health now shows an Effort worked out by PHMN from your heart rate, the strap's first. Apple's own figure is never used.
- **Elevation gain for activities from Apple Health.** The climb comes from the figure the device wrote with the activity when there is one, otherwise from the altitudes of its route, smoothed so a flat walk does not climb.

### Bug Fixing
- **Empty figures.** An activity imported from Apple Health no longer shows an empty Activity strain or Elev. gain.
- **"Imported from" line.** It now sits in line with the figures above it.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
