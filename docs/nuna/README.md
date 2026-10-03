# Nuna: design handoff

Nuna is the new PHMNOOP "Experience". It is a redesign of the whole iOS app: calmer, restricted palette, WHOOP-referenced, with details revealed on tap (progressive disclosure) and Anya (the AI coach) present in every module. The original NOOP look stays available as the **Default** experience.

This folder is the implementation handoff for the Design Canvas that was produced in the design phase.

## Contents

| File | What it is |
|---|---|
| [`SCREENS.md`](SCREENS.md) / [`screens.json`](screens.json) | Inventory of every screen: group, mockup file, outgoing links, and the existing SwiftUI view to reuse or revise. |
| [`NAVIGATION.md`](NAVIGATION.md) | Tabs, cross-module links, and the key flows. |
| [`TOKENS.md`](TOKENS.md) | Colours, type, radii, spacing, and how they map to `StrandPalette` / `StrandFont`. |
| [`COMPONENTS.md`](COMPONENTS.md) | Component catalogue with the mockup class name and the proposed SwiftUI component. |
| [`DATA_REQUIREMENTS.md`](DATA_REQUIREMENTS.md) | What each area needs from the data layer: reuse, extend, or new. |
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | Phased build order, acceptance criteria, risks. |
| [`PROPOSALS.md`](PROPOSALS.md) | Behaviour that exists only in the mockups and is **not** in the current code. Needs a product decision before it is built. |
| [`mockups/`](mockups) | The Design Canvas sources (`*.dc.html`, `ui.css`, `canvas.json`). |

Code that ships with this handoff:

- [`Packages/StrandDesign/Sources/StrandDesign/Nuna/NunaTheme.swift`](../../Packages/StrandDesign/Sources/StrandDesign/Nuna/NunaTheme.swift): tokens (`NunaPalette`, `NunaRadius`, `NunaSpacing`, `NunaTypeSize`), `ExperienceMode`, and the first components (`NunaCard`, `NunaChip`, `NunaRingGauge`, `NunaZoneBar`).

## How to read the mockups

The `.dc.html` files are Design Canvas artboards. They need the Design Canvas runtime (`support.js`), so open them through the canvas rather than directly in a browser. `ui.css` is the shared stylesheet and the best single reference for exact values. Fonts in the mockups (Plus Jakarta Sans, Sora) are web stand-ins: the app must use `StrandFont` with the WHOOP typography preset.

All UI strings in the mockups are Indonesian. The app is bilingual (Indonesian and English), so every string must go through the existing localization pipeline (`Localizable.xcstrings`, see `docs/IOS_INDONESIAN_LOCALIZATION.md`).

## Design principles

1. **Colour carries meaning.** Green is OK/Charge, blue is Effort, steel is Rest, yellow needs attention, red is alert or heart. White is the primary action. Nothing is coloured for decoration.
2. **Short on the surface, detail on tap.** Each screen shows one headline and a few cards; everything else is one tap away.
3. **One place for each thing.** Quick actions live behind the single "+" button. Anya appears in one card per screen, at a consistent position.
4. **Honest wording.** No diagnosis, no condition names, no alarm colours for experimental features (for example Rhythm). Estimates say they are estimates.
5. **WHOOP first.** Device screens cover WHOOP 4.0, 5.0 and MG only.

## The Experience switch

`ExperienceMode` (`standard` | `nuna`) is stored under `experience.mode`. The app root chooses between the existing shell (`RootTabView`) and the Nuna shell. Switching reloads the app shell; data, scores, settings, widgets and Live Activities are unaffected. Features that exist only in Nuna do not appear in Default.

## Status of the numbers in the mockups

All numbers are sample data. Where a mockup states behaviour (thresholds, durations, trigger rules), it is either taken from the code (noted in the relevant doc) or listed in [`PROPOSALS.md`](PROPOSALS.md).
