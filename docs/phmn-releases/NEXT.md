## PHMN 3.1.1

Breathing you can follow by ear, a battery page, and fixes for sleep edits and the weather location.

### New / Enhancement
- **Breathing by ear.** Tones or Anya's voice mark the start, a pause and the end of a session, in every technique including Resonance and Calm me.
- **A breath that ends properly.** When the time is up the session carries on to the end of the out-breath, instead of stopping in the middle of a hold.
- **Anya after breathing.** She reads the session's heart rate, HRV and stress and says what it did for you in a few warm words. When you keep coming back to the same exercise she offers to make it a favourite, one tap in her sheet.
- **Battery page.** A ring with the level, the time left or to full, the average and last charge, and a history chart.
- **Activity names stay in English.** Sports and gym exercises read the same everywhere and can be searched.
- **Walks and other activities on foot.** The log shows the heart-rate zones under the chart and the steps at the top.
- **WHP highlight cards** use the type sizes and greys of the WHOOP card.

### Bug Fixing
- **A shortened night now counts.** After the strap was added again, a night you edited (say from 9 hours to 7) kept its old total on Today and in Anya's reading. Both follow your edit.
- **Weather location** is more exact, and the place name comes from OpenWeather. An IQAir station far from you is left out.
- **Anya does not guess while stress is calibrating.** She says it is still calibrating.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
