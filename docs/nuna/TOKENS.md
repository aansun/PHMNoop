# Nuna tokens

Source: `mockups/ui.css`. Swift: `NunaPalette`, `NunaRadius`, `NunaSpacing`, `NunaTypeSize` in `Packages/StrandDesign/Sources/StrandDesign/Nuna/NunaTheme.swift`.

The repository rule "design system is law" still applies: Nuna views use only these tokens (and `StrandFont`), never raw hex values.

## Colour

Dark values follow the "Rekomendasi Palet Warna Health App Dark Mode" guide. Each area has its own neon: Sleep and Rest cyan, Health and Charge green, Trend and Effort yellow, alert pink-red. Colour, font and text size are fixed to the guides and are no longer a user setting (only light or dark, spacing density and the app icon are).

| Token | Dark | Use |
|---|---|---|
| `canvas` | `#000000` | Screen background |
| `card` | `#121214` | Card surface |
| `cardHighlight` | `#1B1B1F` | Anya card, selected card |
| `hairline` / `hairlineSoft` | `#71717A` 25% / 18% | Dividers, grid lines, card borders |
| `textPrimary` | `#FFFFFF` | Primary text |
| `textSecondary` | `#A1A1AA` | Secondary text |
| `textMuted` | `#71717A` | Chart labels, chevrons, placeholders |
| `charge` | `#00FF66` | Health, Charge, ok, active toggles |
| `effort` / `effortText` | `#DFFF00` | Effort, Trend |
| `rest` / `restText` | `#00E5FF` / `#5CEFFF` | Rest, Sleep |
| `restLight` / `restDeep` | `#9BF4FF` / `#0093A8` | REM / deep sleep |
| `warning` | `#FFB020` | Needs attention |
| `alert` / `alertText` | `#FF3366` / `#FF6B8E` | Alert, heart, over-reaching |
| `zoneBase` | `#3F3F46` | Zone 1, awake track |

Charts: a 2 to 3 pt line in the area colour with a fill that fades from 35% of that colour to nothing.

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

SF Pro (system) for text and numbers, from the "Panduan Tipografi dan Jarak UI" guide. Large numbers use -1.5% tracking, small uppercase labels +0.4 pt.

| Role | Size | Weight |
|---|---|---|
| Main stat / score | 44 to 56 | Bold |
| Page header (H1) | 28 | Bold / Heavy |
| H2 | 20 | Heavy |
| Card title (H3) | 17 | Semibold / Bold |
| Body and detail numbers | 14 | Regular to Semibold |
| Chart labels, helper text | 11 to 12 | Regular to Semibold |

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
