## PHMN 3.2.1

Anya converses and looks up your own data, learns your food figures, and the nutrition and gym pages are redrawn.

### New / Enhancement
- **Anya converses.** She answers what you said, asks when something is missing, and the length follows your message.
- **Anya looks up your data.** With the Anthropic provider and data access on, she fetches your days, nights, workouts, body trends, food diary and profile to answer, and the journal, blood pressure and lab results only if you also share patterns and Lab Book. The line under a reply names what was looked up. Claude Haiku 5.5 is the default for a new install.
- **About you.** A page for your goals, usual week, equipment, limits and coaching style, which you can edit or clear. Anya can add to it from a conversation and says so.
- **Check-ins.** An optional evening reminder, off until you switch it on. It and the workout summary notification open Anya, who writes from your data at that moment.
- **Anya on Home.** Her button lists Recovery, sleep, Strain, the suggested session and tonight's bedtime, each with its day, and greets you in a few words that you can switch off.
- **Nutrition plan.** The app works out the pace, calories and macros by rule and Anya explains them. It opens in Anya's sheet, where you can ask about it before you apply it.
- **Your food figures.** Change the figures on an estimate and they are used the next time for the same food and unit. Nutrition settings lists them, with a way to forget each one.
- **Redrawn pages.** Strategy and the gym program pages look like the other detail pages, and pages with a plain title have it centred.
- **Strap certificate.** Device Settings shows what the strap last reported about its stored certificate. Only the "valid" wording has been seen on a strap so far.
- **Body age.** The new design calls it Body age everywhere.
- **Smaller photos.** Meal photos and attachments are sent as JPEG.

### Bug Fixing
- **Energy burned.** Nutrition shows the chosen day's own figure, never one carried from another day, and labels the strap's figure as the whole day's burn.
- **One body weight.** A nutrition plan no longer shows two different protein figures.
- **Gym programs.** A program shows one duration, opens from Applications, lists its first day on top, wraps long names and can be saved again after a change. An exercise is no longer swapped for one that needs other equipment, and Superman and similar moves count in reps.
- **No double entries.** A food, program or lab card in a kept conversation remembers it was used.
- **Meal photos.** Removing a photo clears its estimate, a photo with no food is not sent twice, and figures printed on a label or menu are copied.
- **Anya's memory.** Ordinary questions are no longer kept as goals and events; those saved that way wait for you to keep or delete them.
- **Water.** The page no longer runs off the screen.
- **Indonesian.** Anya says "kamu", calories read "kkal", and her plan uses the same decimal mark as its card.

### Install
`PHMN-v3.2.1-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
