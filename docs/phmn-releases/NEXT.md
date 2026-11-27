## PHMN 3.2.0

Blood pressure, a new Beat rhythm page, a fuller sleep planner, and pages that open complete.

### New / Enhancement
- **Blood pressure.** A page for the readings your cuff saves to Apple Health or that you type in: the latest pair on a gauge, a week and month chart, and what the ranges mean. It is also on Health, in Health monitor, in the quick actions and on My Dashboard. The strap does not measure blood pressure.
- **Blood pressure reminder and your data.** A gear on the page sets a morning and evening reminder and Apple Health. "Your readings and your data" puts a week of pressure beside your sleep, strain, weight, journal and breathing.
- **Beat rhythm.** A new page in the style of Sleep, with Anya, a card under Body clock and a quick action. Anya describes the figures and never names a condition.
- **Sleep planner.** My Schedule sets an alarm, mode and goal for each weekday. An experimental early wake, off by default, can buzz the strap in the hour before your wake time.
- **Body clock.** Redesigned like the Sleep pages, with the 24-hour dial first and a rhythm card that is easier to read.
- **Breathing.** A countdown in step with Anya, a sideways full screen, and tabs you can slide between.
- **Live activity.** The dial names your heart rate and shows the zone large, you can swipe between Strain and Heart Rate from anywhere, and a reached target reads Completed.
- **Treadmill.** Distance and pace appear after the session, and the live screen says when the distance is still being calculated.
- **Smoother pages.** Today, Health and the detail pages come in whole and fade in, instead of filling in card by card.
- **Support on Ko-fi.** The Ko-fi cup beside search on More opens the support page in your browser.

### Bug Fixing
- **Strava treadmill upload.** An indoor session without a route is now accepted by Strava.
- **Cards that appeared and vanished.** Opening the app after it was closed no longer shows empty cards or calibration notices before your data is read.
- **Strap notice.** "Strap not in use" waits longer for the first connection after the app starts.
- **Live Activity on a Mac.** The words no longer show as boxes when the iPhone is mirrored.
- **Lab Book.** Chart figures no longer run into each other, and a typed blood pressure reading is named correctly.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
