# iOS Indonesian localization checklist

This is the implementation checklist for the iOS-only Indonesian locale. The app copy is natural and
concise; established health/product terms such as Charge, Effort, Rest, Heart Rate, HRV, RHR, SpO₂,
Zone, Pace, Cadence, Baseline, Apple Health, Strava, GPS, and Live Activity remain unchanged.

- [x] Add the iOS `id` locale and Indonesian permission descriptions.
- [x] Add the compact widget/Live Activity locale table in the extension bundle.
- [ ] Translate the remaining long-tail screens and error states from the shared catalog.
- [x] Add the Indonesian response overlay to the iOS AI Coach while preserving health terms.
- [x] Localize deterministic Audio Coaching prompts and the AI wording instruction.
- [x] Translate the iOS More index plus the primary Settings, Backup & Sync, Data Sources, Power Saving, and NOOP Limitations explanations.
- [ ] Review dynamic strings, accessibility labels, and workout sport names in Indonesian.
- [x] Build and run `NOOPiOS` on Simulator with Indonesian launch arguments; core Today labels render in Indonesian.
- [x] Include Indonesian widget/Live Activity resources in the built iOS bundle and verify the widget extension is present.
- [x] Build and package the unsigned iOS IPA with the Watch app excluded.

The remaining unchecked items are follow-up polish for long-tail copy and dynamic/accessibility text;
they do not block the iOS locale option, the core Today experience, widgets, AI Coach, or Audio Coaching.

The checklist intentionally separates the iOS bundle from macOS and watchOS resources. It can be
continued without changing the project's shared macOS UI or the watch target.
