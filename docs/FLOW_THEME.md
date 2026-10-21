# Flow style

Flow is the third Appearance style, after Default and WHP. It is adapted from the "Bloom" design system for women's health: a warm, calm look with
rounded shapes. It is a **skin**: the same screens and components, restyled through `NunaThemePrefs.Skin.flow` in
`Packages/StrandDesign/Sources/StrandDesign/Nuna/NunaTheme.swift`. Unlike WHP it supports Light, Dark and Automatic.

## What Flow changes

| Area | Light | Dark |
|---|---|---|
| Canvas | `#FBF6F2` | `#1A1217` |
| Card | `#FFFFFF` | `#241A20` |
| Raised / field | `#F3E9E3` | `#2E2228` / `#120C10` |
| Hairline | `#E6D6CE` | `#3D2D36` |
| Text (primary / secondary / muted) | `#2A1B24` / `#6B5562` / `#9C8590` | `#F5EBEF` / `#C4B0BA` / `#8A7380` |
| Accent (berry) | `#8A2F5C`, label `#FFFFFF` | `#EB9BBD`, label `#2A0F1C` |
| Warning | `#8A5A00` | `#F0C060` |
| Alert | `#B42318` | `#FF8A7A` |

- **Shape**: cards 16 pt, small cards 12 pt, chips, pills, buttons and icon tiles fully round, tab bar 28 pt, sheets 24 pt.
- **Elevation**: a soft shadow under cards in Light, a hairline border in Dark.
- **Type**: Fraunces (variable, weight 600, optical size follows the point size, SOFT 50) for figures and headings of 24 pt and up; Plus Jakarta Sans
  (400 to 700) everywhere else. Both ship as variable fonts in `StrandiOS/Resources/Fonts/` under the SIL Open Font License; the system rounded font is
  the fallback if a file is missing.

## What Flow leaves alone

- The metric meaning colours (Charge, Effort, Rest, scores) keep their Default values, so a colour means the same thing in every style.
- The universal parts of the design system: spacing scale, accessibility rules, UX writing and icons.
- The cycle-phase colour tokens, which belong to a feature PHMN does not have.
