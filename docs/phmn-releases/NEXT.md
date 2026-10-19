## PHMN <version>

Gym summary redesigned, tappable explanations on Today, a Trends header that pages through your history, and fixes for workouts that lost their targets when the app was away.

### New / Enhancement
- **Gym summary, redesigned.** The page opens with the date and program, the Activity Effort with its 30-day average and the cardio and muscular share beside it, then key statistics for lifting
  (volume, sets, reps, duration, heart rate, calories). Two tabs below: **Exercises**, where each exercise opens to its sets, its record and its demo, and **Heart rate zones**, with the curve and the zones.
  Save as program, Edit sets and Delete are in the three dots.
- **The chips under the rings explain themselves.** Tap Solid, Last night, Calibrating or No data to see why Charge is in that state, what to do, and what the green, yellow, red and grey dot mean.
  Tap Push, Maintain or Rest to see the signals behind your readiness, each with its figure and flag.
- **Trends pages through your history.** Week, month, six months and year now sit beside the title with a date stepper under them, the same controls as every metric card, and the arrows move to earlier periods.
- **Key metrics tiles** use the vital signs design: icon and label, the value, and the change as a chip beneath. With trend lines on, every tile is the same height.
- **Early warning** no longer takes a card on Today. It arrives in the notifications bell once a day per level, Anya adds one short line, and the full page is still in quick actions.
- **What's new** follows the latest GitHub release by itself, and shows each release in two groups, New / Enhancement and Bug Fixing.
- **More room in the target sheet**, between the effort figures, the bar and Anya's line.
- **Demo data** includes a finished gym session, so the gym screens can be looked at without logging one.

### Bug Fixing
- **Targets survive the app being away.** After a few minutes in another app, iOS can end PHMN; the workout was restored but its time, distance and zone targets were lost, so the strap stopped buzzing and
  the audio coach went quiet. The targets are now saved with the workout and come back with it.
- **"Start workout" is not said twice.** A workout picked up after the app was reopened no longer announces its start again, and a time target already passed is not announced a second time.
- **The screen stays on during a live workout** after you lock the phone or visit another app. The setting is asked for again every time the app comes back, and a finished Strava or Oura task no longer releases it.
- **The summary opens at once** after End and save, instead of waiting on a *Saving activity* page.
- **Metric tiles no longer shift** when one has no history yet, and the figures of the Effort rows (such as Strength training time) line up with the rest.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and is not affiliated with WHOOP, Inc., Strava or Hevy.
