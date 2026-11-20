## PHMN 3.0.2

Trend views that tell you if you are doing better, Strain on the scale you chose, and vital signs that agree on every screen.

### New / Enhancement
- **Change against the period before.** Under the average of every Trend view: “5% vs. prior week”, month or six months, following the W / M / 6M switch. Green when it moved the better way for that reading, grey when it did not or stayed the same.
- **Skin temperature as the rise.** Every screen shows how far you are from your usual (+0.3), not the wrist temperature, with your range beside it.
- **Start activity.** One name for it everywhere. Anya's pick on the Strain target reads like her pick on Breathing.

### Bug Fixing
- **Strain target and live ring** follow the Strain scale you chose (0–21 or 0–100). They showed 0–100 beside a 0–21 day.
- **Vital signs agree.** The Today card and tile marked a low respiratory rate or resting heart rate, or a high HRV, as out of range while the detail page called it good news. One rule now.
- **Skin temperature** from imported data no longer reads “+32.5” with no verdict on the Health monitor.
- **Strain & Recovery chart:** figures no longer land on the day names or on each other. A “−0.0” now reads “0.0”.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and independent of every brand it works with.
