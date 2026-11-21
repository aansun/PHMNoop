## PHMN 3.1.0

Weather and air on Today, an Anya that writes like a coach and knows the forecast, and steps that no longer lose a walk.

### New / Enhancement
- **Weather and air.** A one-row card on Today, as wide as Daily Outlook: the sky now, the place, the temperature, the air quality and whether it suits time outdoors, on a wash that starts in the colour of the air. It opens a page that reads like a trend view: pick Weather or Air quality, switch between the hours (H) and the days (D), and read the moment on show with the sky beside the temperature, its low and high, and a sentence with the feels-like, wind and humidity that says whether it suits time outdoors. The air is drawn over its bands, with the reading now from IQAir and the hours after it from the OpenWeather forecast. Under the forecast, cards explain why the weather and the air matter and how to tell good air.
- **Weather and air keys.** Under Data and integrations: an OpenWeather key and an IQAir key, each pasted and checked in one step, with a link to get one. Both are needed.
- **Anya knows the forecast.** She is told the coming day by part, the best time to train, the days after and which service measured the air, so “how is the weather tonight?” is answered from data.
- **Anya in plain paragraphs.** On Recovery, Sleep, Strain, Stress and every other page, her note reads as a few full sentences: what the reading is against your own usual, what it most likely means, and one step to take. No titled fragments, no “I see”. Each page has its own instructions.
- **Steps from the better count.** Today and the Steps page show the higher of the strap's count and Apple Health's: each counts only part of a walk, so neither is more than the truth.
- **Naps like Sleep.** The Naps page has the Sleep page's header, a short day name between the arrows (“FRI, 20 NOV”), the night's stage card for the nap and the same Hours vs. needed card. Deleting asks once and shows one Undo.
- **Strap not in use.** While the strap is off, Today hides the battery and says “Strap not in use”; pulling to refresh tells you to wear it. In Device settings, Sync now sits inside the Last sync pill.
- **Charging.** Charging is read from the battery level rising, and while it charges the screen shows the time to full instead of a runtime.

### Bug Fixing
- **A strap listed twice no longer splits its day.** When the same strap was registered twice (the original row left archived), part of the day's heart rate and steps was filed under the old row, so a walk could be missing from the day's steps and Strain. The row in use now stays.
- **Import from Strava** brings back an activity PHMN uploaded when its workout is no longer in the app; it was skipped as “already here”.
- **Charging animation and estimate.** The animation runs while the strap charges, and the time left no longer stays at the figure from the start of the charge (4 d 6 h).
- **Distance during an activity** shows two decimals like the summary after it. The tenth of a kilometre it rounded to could read up to 50 m more.
- **Live Activity clock** shows the whole time (“9:38”) before ten minutes, not “9….”.
- **Add activity:** moving the start later than 45 minutes ago no longer snaps back to the suggestion.
- **“Sleep deleted”** no longer appears three times at once on Sleep and Naps.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
