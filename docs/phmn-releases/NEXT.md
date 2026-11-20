## PHMN 3.0.2

Strain on the scale you chose, vital signs that agree on every screen, and a Strain & Recovery chart you can read.

### Bug Fixing
- **Strain target and live ring** follow the Strain scale you chose (0–21 or 0–100). They showed 0–100 beside a 0–21 day.
- **Vital signs agree.** The Today card and tile marked a low respiratory rate or resting heart rate, or a high HRV, as out of range while the detail page called it good news. One rule now.
- **Skin temperature** from imported data no longer reads “+32.5” with no verdict on the Health monitor; every screen shows the rise from your usual.
- **Strain & Recovery chart:** figures no longer land on the day names or on each other. A “−0.0” now reads “0.0”.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
