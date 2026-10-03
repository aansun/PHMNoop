# Nuna tokens

Source: `mockups/ui.css`. Swift: `NunaPalette`, `NunaRadius`, `NunaSpacing`, `NunaTypeSize` in `Packages/StrandDesign/Sources/StrandDesign/Nuna/NunaTheme.swift`.

The repository rule "design system is law" still applies: Nuna views use only these tokens (and `StrandFont`), never raw hex values.

## Colour

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#0A0D10` | Screen background |
| `card` | `#14181D` | Card surface |
| `cardHighlight` | `#191F25` | Anya card, selected card (plus a 26% white border) |
| `glass` / `glassStrong` | white 5% / 9% | Segmented control track, icon buttons, neutral chips |
| `hairline` / `hairlineSoft` | white 10% / 8% | Dividers, card borders |
| `textPrimary` | `#FFFFFF` | Primary text |
| `textSecondary` | `#9AA4AC` | Secondary text, captions |
| `textMuted` | `#6B7177` | Chevrons, placeholders |
| `charge` | `#16EC06` | OK, Charge, active toggle, zone 2 |
| `effort` / `effortText` | `#0093E7` / `#38AEF5` | Effort (fill / readable text) |
| `rest` / `restText` | `#7BA1BB` / `#9DBBD0` | Rest, sleep |
| `restLight` | `#B8CCE0` | REM |
| `restDeep` | `#4A7090` | Deep sleep |
| `warning` | `#FFDE00` | Needs attention, zone 3-4 |
| `alert` / `alertText` | `#FF0026` / `#FF5468` | Heart, alert, zone 5 |
| `zoneBase` | `#3B4258` | Zone 1, awake track |

Chip backgrounds are the meaning colour at 12-16% opacity with a 30-40% border.

### Mapping to the existing palette

Reuse existing tokens when a Nuna token has an equal in `StrandPalette`; only add Nuna tokens where the value differs. Suggested mapping, to be confirmed against `Palette.swift`:

| Nuna | Existing |
|---|---|
| `charge` | `StrandPalette.chargeColor` |
| `effort` | `StrandPalette.effortColor` |
| `rest` | `StrandPalette.restColor` |
| `textPrimary/Secondary` | `StrandPalette.textPrimary/textSecondary` |
| `canvas` | `StrandPalette.surfaceBase` (differs: Nuna is near-black, not navy) |

## Type

Mockups use two faces: a text face (labels) and a numeric face (scores). In the app both come from `StrandFont` with the WHOOP preset (`Typography.swift`).

| Role | Size | Weight | Notes |
|---|---|---|---|
| H1 | 34 | 800 | Screen title, tracking -3.5% |
| H2 | 22 | 800 | Section title |
| H3 | 17 | 700 | Row title |
| Sub | 14 | 600 | Secondary text |
| Caption | 11.5 | 800 | Uppercase, tracking 10% |
| Number XL / L / M / S | 68 / 44 / 30 / 21 | 700 | Tabular figures, tracking -4% |
| Unit | 40% of the number | 700 | Secondary colour, 4 pt leading |

## Shape and spacing

| Token | Value |
|---|---|
| Card radius | 28 (small cards 24) |
| Chip | height 30, radius 15 |
| Button | height 48, radius 24 (primary actions 54-60, radius = half) |
| Icon button | 44 x 44, radius 22 |
| Icon tile | 40 x 40, radius 14 |
| Tab bar | height 72, radius 36, inset 14, 24 from the bottom |
| Sheet | top radius 34, 44 x 5 handle, scrim black 62% |
| Floating "+" | 58 x 58, white, 104 above the bottom |
| Toggle | 52 x 32 |
| Screen padding | 20 horizontal, 16 between sections |

## Motion

The mockups are static. Reuse `StrandMotion` / `NoopMotion` (calm easing, ~240 ms crossfade between tab roots). Rings animate from zero on first appearance only.
