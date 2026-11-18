## PHMN 3.0.0

A redesign in WHOOP's own words: Recovery, Strain and Sleep, a Health tab, and a Body age from nine inputs; plus weekly plans, a Strength Trainer, a new Breathing tab, and a strap you can see and tell more about.

### New / Enhancement
- **Recovery, Strain and Sleep.** The three scores take WHOOP's names, with Strain on its 0 to 21 scale by default. Each has trend pages, grouped in a drop-down (Strain, Recovery, Sleep, Health, Other), with cards that explain how a figure is calculated and what affects it.
- **A Health tab.** Fitness age, the Health monitor, the Stress monitor and the Lab Book sit together. The tab bar is Home, Health, Breathing and More, with Anya as the round button beside it.
- **Body age.** Fitness age is now a weekly Body age from nine inputs: resting heart rate, VO₂ max, sleep duration and regularity, steps, time in heart-rate zones 1 to 3 and 4 to 5, strength time and lean body mass. Each shows the years it adds or takes away, an input with no data says so, and the pace of aging reads these weeks. The Vitality score is gone. The first time this version opens, up to 26 earlier weeks are worked out again with the new model.
- **Stress, after WHOOP's description.** A 0 to 3 reading from heart rate and HRV against your own baseline, in three parts (total, outside activity, asleep). It appears after 14 nights.
- **Strain, scored with Banister.** The day's Strain counts effort at every intensity and subtracts the cost of being awake, calibrated against WHOOP's Day Strain, so light and intermittent work shows. A switch under Advanced goes back to the zone-based score.
- **Home.** Your avatar and day streak at the top, Highlights for what stands out, a Day In Review from the late afternoon, Today's activities, Tonight's sleep, My Journal, My Plan and a My Dashboard you customize.
- **My Plan.** Weekly plans with activities and behaviors: Boost Fitness, Feel Better, Sleep Deeper, a Custom plan, and a GLP-1 Companion built from a few questions.
- **Journal.** A full-screen page after WHOOP's, with follow-up questions, Smart log with Anya, behavior insights and **Use previous answers**, which fills a day's unanswered questions from the day before.
- **Strength Trainer.** The gym module, renamed, with Progress, My Program and Explore tabs, a photo grid of ready-made workouts, groups for your programs and a muscle map.
- **Breathing.** A tab laid out like the Strength Trainer: Progress, Breathe and Explore, techniques with step-by-step pages, a scrolling breath line and a report for every session.
- **Workouts.** Logs drawn after WHOOP's, a live heart-rate tab with a zone ring, WHOOP-style End and Discard questions, a Banner Live Activity card, and workouts found on Strava offered in Today's activities.
- **Lab Book.** A ring of your markers by status, a card and a detail page for each, a history of tests and a step-by-step way to add a result.
- **Device Settings.** A Status tab with the battery and its charging animation and **Broadcast heart rate**, and an Advanced tab with Add a device, Reconnect, Test vibration, Restart strap, the **Strap log** to copy or share, and Remove and Delete data. The strap and its tabs stay pinned as the page scrolls.
- **WHOOP 5.0 / MG alarm.** The wake alarm is sent to a 5.0 / MG while its switch under Experiments is on, and the Home card says *Strap not armed* when it is not.
- **Off-body reminder.** A phone notification when the strap has been off your wrist for ten minutes; it takes itself back when you put the strap on or charge it.
- **Settings after WHOOP's.** Account and settings, Support, one card for each setting, drop-downs for choices, and questions that ask in a centred WHOOP-style box.
- **Three looks, one set of sizes.** Default, WHP and Flow all set their text at WHP's sizes. Anya's words are 16 pt, the size of the Daily Outlook, wherever she speaks.
- **Anya.** A new sheet design for every card and menu, and a chart, program, workout or breathing exercise she makes comes back as a card even when a model names the block loosely.
- **Widgets.** Four new glance widgets (the three scores, the Sleep ring, the Recovery and Strain rings, and the rings with HRV and Calories), and the PHMN logo family across the app, widgets and Live Activities.
- **Indonesian.** About 950 more strings translated, in a casual "kamu" register.
- **First run.** The terms page and a four-page welcome in the new look. Defaults follow WHOOP's app: Strain on 0 to 21, continuous overnight HRV and workout detection on.
- **Feedback through GitHub.** *Share feedback* and *Report a problem* open a new issue on the repository with its outline started; the app adds only its version, your iOS version, the model of your iPhone and the language. The Luciq SDK is removed.

### Bug Fixing
- **Workout detection** offered walks whose heart rate never reached the first zone, and a deleted suggestion came back up to three times. A suggestion now needs two minutes in zone 1, and a deletion stays even when the next scan sees the session a few minutes off.
- **Lab Book counts** of two digits or more were cut to an ellipsis; they are never cut now.
- **Anya's replies** that named a block `json` showed raw JSON and a stray `>`; they become cards and clean text.
- **The alarm card** said *Alarm on* for a 5.0 / MG that was never sent the alarm.
- **The low-battery banner** kept its close button when the figure moved, and a saved Strength session no longer leaves a "No session running" screen.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and is not affiliated with WHOOP, Inc., Strava or Hevy.
