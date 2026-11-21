## PHMN 3.0.3

Anya that writes like a coach, a Naps page built like Sleep, and a battery that knows when the strap is charging.

### New / Enhancement
- **Anya in plain paragraphs.** On Recovery, Sleep, Strain, Stress and every other page, her note reads as a few full sentences: what the reading is against your own usual, what it most likely means, and one step to take (to improve a poor reading, to keep a good one). No titled fragments, no “I see”. Each page has its own instructions, so the note fits the page it is on.
- **Naps like Sleep.** The Naps page has the Sleep page's header, a short day name between the arrows (“FRI, 20 NOV”), the night's stage card for the nap and the same Hours vs. needed card, with the nap counted in the day. Deleting asks once and shows one Undo.
- **Strap not in use.** While the strap is off, Today hides the battery and says “Strap not in use”; pulling to refresh tells you to wear it. In Device settings, Sync now sits inside the Last sync pill.
- **Weather and air on Today.** A one-row card, as wide as the Daily Outlook one, with the sky now, the temperature, the air quality and whether it suits time outdoors (“Outdoors, with care”), and a page behind it with the whole day. The page behind it reads like a trend view: pick Weather or Air quality, switch between the hours (H) and the days (D), and read the moment on show (now, until you touch a point) with the sky beside the temperature, its low and high, and a sentence with the feels-like, wind and humidity that says whether it suits time outdoors. The air is drawn over its bands, with the reading now measured by IQAir and the hours after it from the OpenWeather forecast. Needs Weather and air to be on, with an OpenWeather key and an IQAir key (each is pasted, saved and checked in one step); the page also explains why the weather and the air matter and how to tell good air.
- **Charging.** Charging is read from the battery level rising, and while it charges the screen shows the time to full instead of a runtime.

### Bug Fixing
- **Charging animation and estimate.** The animation runs while the strap charges, and the time left no longer stays at the figure from the start of the charge (4 d 6 h).
- **Distance during an activity** shows two decimals like the summary after it. The tenth of a kilometre it rounded to could read up to 50 m more.
- **Live Activity clock** shows the whole time (“9:38”) before ten minutes, not “9….”.
- **Add activity:** moving the start later than 45 minutes ago no longer snaps back to the suggestion.
- **“Sleep deleted”** no longer appears three times at once on Sleep and Naps.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
