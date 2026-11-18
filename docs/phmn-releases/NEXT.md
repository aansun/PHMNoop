## PHMN 3.0.0

Your day in WHOOP's words, redrawn: Recovery, Strain and Sleep, a Body age built from nine habits, and a strap that tells you what it is doing.

### New / Enhancement
- **Recovery, Strain, Sleep.** Three scores, three names you already know, and a page behind every number that shows how it is made.
- **Body age.** Nine habits, each shown as the years it gives or takes, with a pace of aging on top. Which one costs you most? It replaces Fitness age and Vitality, and your history is rebuilt the first time you open it.
- **A Health tab.** Fitness age, Health monitor, Stress monitor and Lab Book: the slow things in one place.
- **Stress, 0 to 3.** Heart rate and HRV against your own baseline, split into total, outside activity and asleep. It switches on after 14 nights.
- **Fairer Strain.** Light and intermittent work finally shows, and a desk day nets almost nothing.
- **Home, rebuilt.** Highlights, a Day In Review, tonight's sleep, your journal, your plan and a dashboard that is yours.
- **My Plan.** Boost Fitness, Feel Better, Sleep Deeper, your own, or a GLP-1 Companion built from a few questions.
- **Journal.** Full screen, Smart log with Anya, and **Use previous answers**, so yesterday does the typing.
- **Strength Trainer.** Progress, programs, a photo grid of workouts and a muscle map of what is ready.
- **Breathing.** A tab of its own: step-by-step techniques, a breath line to follow and a report after every session.
- **Workouts.** Cleaner logs, a zone ring while you move, End and Discard that ask first, and workouts found on Strava offered in Today's activities.
- **Lab Book.** Every marker on a ring by status, a page for each, and a step-by-step way to add a result.
- **Your strap, in the open.** Battery with a charging animation, **Broadcast heart rate**, a **Strap log** to copy or share, Restart and Test vibration, in one pinned Device Settings page.
- **5.0 / MG alarm.** One switch under Experiments, and Home says *Strap not armed* when it is not.
- **Off-body reminder.** Ten minutes without the strap on your wrist, and your phone tells you.
- **One type scale.** Default, WHP and Flow share the same sizes, and Anya speaks at 16 pt everywhere.
- **Anya.** A redesigned sheet, and charts, programs, workouts and breathing exercises come back as cards even when a model names them loosely.
- **Widgets.** Four glance widgets and the new PHMN logo family.
- **Indonesian.** About 950 more strings, in a casual "kamu".
- **First run.** The terms and a four-page welcome. Strain starts on 0 to 21, with continuous overnight HRV and workout detection on.
- **Feedback on GitHub.** *Share feedback* and *Report a problem* open a new issue with the details filled in. The app sends nothing itself.

### Bug Fixing
- **Workout detection** no longer offers walks that never reached zone 1, and a deleted suggestion stays deleted.
- **Lab Book** counts of 10 or more are no longer cut to an ellipsis.
- **Anya** replies that named a block loosely no longer show raw JSON or a stray `>`.
- **The alarm card** no longer says *Alarm on* for a 5.0 / MG that was never given the alarm.
- **The low-battery banner** keeps its close button, and saving a Strength session no longer leaves a "No session running" screen.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
