# WHOOP-Inspired Typography Development Guide

**Document Version:** 1.0  
**Purpose:** Development reference for implementing a WHOOP-inspired health & fitness application  
**Scope:** Typography system, text hierarchy, numeric metrics, accessibility, design tokens, and platform implementation guidance

---

## 1. Purpose

Dokumen ini menjadi panduan implementasi typography untuk aplikasi health & fitness yang terinspirasi dari visual language WHOOP.

Tujuan utamanya:

- menjaga konsistensi UI lintas Android, iOS, dan Web,
- membedakan typography untuk teks dan data numerik,
- mempertahankan karakter visual WHOOP,
- mendukung accessibility tanpa merusak layout,
- menyediakan design tokens yang mudah diterapkan oleh developer,
- membedakan dengan jelas antara nilai yang berasal dari guideline WHOOP dan nilai yang direkonstruksi dari tampilan aplikasi publik.

> **Important:** Tidak semua ukuran font dan spacing aplikasi WHOOP dipublikasikan secara resmi. Karena itu, dokumen ini membedakan antara **Official / Verified** dan **Reconstructed / Recommended**.

---

# 2. Source Classification

Setiap aturan dalam dokumen ini menggunakan salah satu kategori berikut.

## 2.1 Official / Verified

Informasi yang tersedia pada WHOOP Brand & Design Guidelines atau dokumentasi developer WHOOP.

Contoh:

- Proxima Nova digunakan untuk words/text.
- DINPro digunakan untuk numeric data.
- Headline menggunakan Proxima Nova Bold.
- Body menggunakan Proxima Nova Semibold.
- Important headline dapat menggunakan uppercase.
- Headline WHOOP menggunakan increased character spacing.

Official references:

- WHOOP Brand & Design Guidelines  
  https://developer.whoop.com/assets/files/WHOOP%20-%20Brand%20%26%20Design%20Guidelines-bdea3554e94b4ea09e68695b1e8dc8e7.pdf

- WHOOP Developer Design Guidelines  
  https://developer.whoop.com/docs/developing/design-guidelines/

---

## 2.2 Reconstructed / Recommended

Nilai yang tidak dipublikasikan WHOOP secara eksplisit, tetapi direkonstruksi dari:

- screenshot aplikasi WHOOP,
- public product UI,
- current UI patterns,
- reverse-engineering visual hierarchy,
- practical mobile implementation constraints.

Contoh:

- `72sp` untuk hero metric,
- `24sp` untuk section title,
- exact line-height,
- unit-to-number size ratio,
- exact letter-spacing token.

Nilai ini harus diperlakukan sebagai **implementation baseline**, bukan internal WHOOP design token resmi.

---

# 3. Core Typography Principle

WHOOP memiliki dua karakter typography utama:

```text
WORDS / TEXT     → Proxima Nova
NUMERIC METRICS  → DINPro
```

Kontras antara kedua family tersebut merupakan salah satu elemen utama visual identity WHOOP.

Contoh:

```text
RECOVERY
87%
```

Mapping:

```text
RECOVERY → Proxima Nova Bold
87       → DINPro Bold
%        → DINPro / secondary unit styling
```

---

# 4. Font Families

## 4.1 Primary Text Font

```text
Proxima Nova
```

### Recommended usage

- Page title
- Section title
- Card title
- Body
- Navigation
- Buttons
- Labels
- Captions
- Chart axis
- Helper text

### Common weights

```text
500 Medium
600 Semibold
700 Bold
```

---

## 4.2 Numeric Font

```text
DINPro
```

### Recommended usage

- Recovery score
- Strain score
- Sleep score
- Heart rate
- HRV
- Resting HR
- Calories
- Steps
- Duration
- Percentages
- Chart tooltip values
- Statistical values

Recommended weight:

```text
700 Bold
```

---

# 5. Open-Source Font Fallback

Proxima Nova dan DINPro merupakan commercial/licensed fonts.

Untuk project open-source atau distribusi publik, jangan mengambil font binary dari WHOOP application package.

Recommended fallback:

```text
TEXT
Inter

NUMERIC
Inter Tight
```

Alternative:

```text
TEXT
DM Sans / Inter

NUMERIC
Barlow Semi Condensed
```

Recommended default:

```text
Text    = Inter
Numbers = Inter Tight
```

Keuntungan:

- Open-source
- Rendering konsisten
- Android/iOS/Web support baik
- Mudah dibundel
- Character width relatif stabil
- Tetap memberikan visual distinction antara text dan metrics

---

# 6. Font Weight System

Batasi typography ke empat weight:

```text
400 Regular
500 Medium
600 Semibold
700 Bold
```

WHOOP-style UI sebaiknya lebih banyak menggunakan:

```text
500
600
700
```

daripada Regular.

Recommended mapping:

| Element | Weight |
|---|---:|
| Hero Metric | 700 |
| Large Metric | 700 |
| Section Title | 700 |
| Page Title | 700 |
| Card Title | 700 |
| Label | 700 |
| CTA | 700 |
| Body | 600 |
| Caption | 600 |
| Chart Axis | 600 |
| Long Description | 500–600 |

---

# 7. Typography Scale

Recommended implementation scale.

> Status: **Reconstructed / Recommended**

| Token | Family | Size | Weight | Line Height | Tracking | Case |
|---|---|---:|---:|---:|---:|---|
| `metric.hero` | DINPro | 72 | 700 | 76 | -2% | Natural |
| `metric.xl` | DINPro | 56 | 700 | 60 | -1.5% | Natural |
| `metric.lg` | DINPro | 44 | 700 | 48 | -1% | Natural |
| `metric.md` | DINPro | 32 | 700 | 36 | -1% | Natural |
| `metric.sm` | DINPro | 24 | 700 | 28 | 0 | Natural |
| `section.title` | Proxima Nova | 24 | 700 | 28 | -1% | Mixed |
| `page.title` | Proxima Nova | 20 | 700 | 24 | -1% | Mixed |
| `heading` | Proxima Nova | 18 | 700 | 22 | 0 | Mixed |
| `body.large` | Proxima Nova | 17 | 600 | 23 | 0 | Mixed |
| `body.default` | Proxima Nova | 15 | 600 | 20 | 0 | Mixed |
| `body.small` | Proxima Nova | 13 | 600 | 18 | 0 | Mixed |
| `card.title` | Proxima Nova | 12 | 700 | 16 | +6% | UPPERCASE |
| `label` | Proxima Nova | 11 | 700 | 14 | +6% | UPPERCASE |
| `navigation.top` | Proxima Nova | 12 | 700 | 16 | +10% | UPPERCASE |
| `navigation.bottom` | Proxima Nova | 10–11 | 600–700 | 14 | +1% | Mixed |
| `caption` | Proxima Nova | 11 | 600 | 14 | 0 | Mixed |
| `chart.label` | Proxima Nova | 10 | 600 | 12 | +1% | Mixed |
| `button` | Proxima Nova | 12–13 | 700 | 16 | +7% | UPPERCASE |

---

# 8. Metric Typography

Numeric data adalah visual focal point utama aplikasi.

## 8.1 Hero Metric

Example:

```text
RECOVERY

87%
```

Recommended style:

```text
Font Family     DINPro
Font Size       72
Font Weight     700
Line Height     76
Letter Spacing  -2%
```

The unit should not use the same size as the value.

Incorrect:

```text
87%
```

with all characters rendered at `72sp`.

Recommended:

```text
87  %
│   │
│   └── ~29sp
└────── 72sp
```

Recommended formula:

```text
unitSize = metricSize × 0.40
```

Examples:

```text
72 → 29
56 → 22
44 → 18
32 → 13
24 → 10
```

---

# 9. Score Ring Typography

Examples:

```text
84%
SLEEP

87%
RECOVERY

12.8
STRAIN
```

Metric:

```text
DINPro Bold
32sp
36sp line-height
-1% tracking
```

Label:

```text
Proxima Nova Bold
11sp
14sp line-height
UPPERCASE
+6–8% tracking
```

Example:

```text
    87%
 RECOVERY ›
```

---

# 10. Dashboard Metrics

Example:

```text
RESTING HEART RATE

54 BPM
vs 58 bpm 30-day average
```

Label:

```text
Proxima Nova Bold
11–12sp
UPPERCASE
+6% tracking
```

Value:

```text
DINPro Bold
24–28sp
```

Unit:

```text
Proxima Nova Semibold
11–12sp
```

Comparison:

```text
Proxima Nova Semibold
11sp
Secondary Text Color
```

Do not render value and unit as one homogeneous text style.

Preferred component structure:

```text
MetricValue("54")
MetricUnit("BPM")
```

---

# 11. Section Titles

Examples:

```text
My Day
My Dashboard
Sleep
Health
Recovery
```

Recommended:

```text
Proxima Nova
24sp
700
28sp line-height
-1% tracking
Mixed Case
```

Large section titles should generally remain mixed-case.

---

# 12. Page Titles

Examples:

```text
Recovery
Sleep
Health Monitor
Journal
Nutrition
```

Recommended:

```text
Proxima Nova
20sp
700
24sp line-height
-1% tracking
```

---

# 13. Card Titles

Examples:

```text
HEALTH MONITOR
STRESS MONITOR
SLEEP PERFORMANCE
RECOVERY
```

Recommended:

```text
Proxima Nova Bold
12sp
16sp line-height
UPPERCASE
+6% tracking
```

Possible tracking range:

```text
+4% to +8%
```

Default:

```text
+6%
```

---

# 14. Labels

Examples:

```text
RECOVERY
STRAIN
SLEEP
HRV
RESTING HEART RATE
```

Recommended:

```text
Proxima Nova Bold
11sp
14sp line-height
UPPERCASE
+6% tracking
```

---

# 15. Navigation Typography

## 15.1 Top Navigation

Example:

```text
‹    TODAY    ›
```

Recommended:

```text
Proxima Nova Bold
12sp
16sp line-height
UPPERCASE
+10% tracking
```

---

## 15.2 Bottom Navigation

Example:

```text
Home
Health
Coach
More
```

Active:

```text
10–11sp
700
Primary Text
```

Inactive:

```text
10–11sp
600
Tertiary Text
```

Mixed case:

```text
tracking ≈ +1%
```

Uppercase variant:

```text
tracking ≈ +6–10%
```

---

# 16. Body Text

Official WHOOP guidance uses Proxima Nova Semibold for body typography.

Recommended:

```text
Proxima Nova Semibold
15sp
20sp line-height
```

Example:

```text
Your body is signaling it can take on
significant exertion today.
```

Long-form content such as Coach explanations can use:

```text
15–16sp
500–600
21–22sp line-height
```

---

# 17. Caption Typography

Recommended:

```text
Proxima Nova
11sp
600
14sp line-height
```

Use for:

- timestamps,
- small comparison labels,
- supporting metadata,
- chart helper text.

---

# 18. Chart Typography

## Axis

```text
Proxima Nova Semibold
10sp
12sp line-height
Tertiary Text
```

Examples:

```text
MON
TUE
WED

9 PM
12 AM
3 AM
```

---

## Chart Value

```text
DINPro Bold
14–16sp
```

---

## Tooltip Metric

```text
DINPro Bold
20–24sp
```

---

## Tooltip Label

```text
Proxima Nova Bold
10–11sp
UPPERCASE
+6% tracking
```

---

# 19. Sleep Timeline Typography

Stages:

```text
AWAKE
LIGHT
SWS
REM
```

Recommended:

```text
Proxima Nova Bold
10sp
UPPERCASE
+5% tracking
```

Time:

```text
10–11sp
600
```

Duration:

```text
DINPro Bold
14sp
```

---

# 20. CTA and Links

Examples:

```text
SEE TRENDS
VIEW DETAILS
CUSTOMIZE
EXPLORE
```

Recommended:

```text
Proxima Nova Bold
11–12sp
UPPERCASE
+6–8% tracking
```

---

# 21. Buttons

Primary button examples:

```text
START ACTIVITY
CONTINUE
SAVE
DONE
```

Recommended:

```text
Proxima Nova Bold
12–13sp
16sp line-height
UPPERCASE
+7% tracking
```

Compact:

```text
11–12sp
```

Large:

```text
13sp
```

---

# 22. Text Input

For:

- Coach
- Search
- Journal
- Nutrition
- Notes

Entered text:

```text
Proxima Nova
16sp
500
22sp line-height
```

Placeholder:

```text
16sp
500
Tertiary Text
```

Helper label:

```text
11sp
600
Secondary Text
```

---

# 23. Casing Rules

## Use UPPERCASE for

```text
RECOVERY
STRAIN
SLEEP
HEALTH MONITOR
HRV
RESTING HEART RATE
SEE TRENDS
CUSTOMIZE
TODAY
```

---

## Use Mixed Case for

```text
My Day
My Dashboard
Recovery
Health
Your Recovery is...
Coach recommendation...
You slept...
```

Avoid excessive uppercase for long text.

---

# 24. Letter Spacing Tokens

Recommended:

```text
tracking.none    = 0
tracking.tight   = -0.02em
tracking.metric  = -0.015em

tracking.label   = +0.06em
tracking.button  = +0.07em
tracking.nav     = +0.10em
```

Example metric:

```text
87
DINPro Bold
72
-0.02em
```

Example label:

```text
RECOVERY
Proxima Nova Bold
11
+0.06em
```

Example navigation:

```text
TODAY
Proxima Nova Bold
12
+0.10em
```

---

# 25. Text Color Hierarchy

Recommended dark UI hierarchy:

```text
Primary
#FFFFFF

Secondary
#9AA4AC

Tertiary
#6B7177
```

Usage:

Primary:

- metrics,
- titles,
- key labels,
- active navigation.

Secondary:

- comparisons,
- explanations,
- baseline values,
- captions.

Tertiary:

- timestamps,
- inactive tabs,
- chart axis,
- placeholders.

---

# 26. Semantic Color Usage

Typography should generally remain neutral.

Color should communicate status.

Example:

```text
Label = White
Metric = Semantic Color
```

Recovery semantic colors from WHOOP design guidance:

```text
High Recovery
#16EC06

Medium Recovery
#FFDE00

Low Recovery
#FF0026
```

Recommended pattern:

```text
87%        → semantic recovery color
RECOVERY   → white / neutral text
```

Avoid coloring every element on a card.

---

# 27. Numeric Formatting

Enable tabular numeric figures wherever supported.

Recommended CSS:

```css
font-variant-numeric: tabular-nums lining-nums;
```

or:

```css
font-feature-settings:
  "tnum" 1,
  "lnum" 1;
```

Use for:

- HR
- HRV
- Recovery
- Sleep
- Strain
- Steps
- Calories
- Duration
- Chart data
- Timer

Benefits:

- numbers do not shift horizontally,
- graphs and changing values feel more stable,
- UI appears more professional.

---

# 28. Design Tokens

Suggested token system:

```text
font.family.text     = "Proxima Nova"
font.family.metric   = "DINPro"

font.weight.regular  = 400
font.weight.medium   = 500
font.weight.semibold = 600
font.weight.bold     = 700
```

Type tokens:

```text
type.metric.hero = 72 / 76 / 700
type.metric.xl   = 56 / 60 / 700
type.metric.lg   = 44 / 48 / 700
type.metric.md   = 32 / 36 / 700
type.metric.sm   = 24 / 28 / 700

type.title.section = 24 / 28 / 700
type.title.page    = 20 / 24 / 700
type.title.card    = 12 / 16 / 700

type.body.lg = 17 / 23 / 600
type.body.md = 15 / 20 / 600
type.body.sm = 13 / 18 / 600

type.label   = 11 / 14 / 700
type.caption = 11 / 14 / 600
type.chart   = 10 / 12 / 600
type.button  = 12 / 16 / 700
```

Format:

```text
font-size / line-height / font-weight
```

---

# 29. Suggested Figma Text Styles

Recommended naming:

```text
WHOOP / Metric / Hero
WHOOP / Metric / XL
WHOOP / Metric / Large
WHOOP / Metric / Medium
WHOOP / Metric / Small

WHOOP / Heading / Section
WHOOP / Heading / Page
WHOOP / Heading / Card

WHOOP / Body / Large
WHOOP / Body / Default
WHOOP / Body / Small

WHOOP / Label / Default
WHOOP / Label / Chart

WHOOP / Navigation / Top
WHOOP / Navigation / Bottom

WHOOP / Action / Button
WHOOP / Action / Link
```

Avoid generic naming such as:

```text
Font 1
Font 2
Bold 14
Body 12
```

---

# 30. Android Jetpack Compose

Instead of relying only on Material Typography, create additional WHOOP-specific tokens.

Example:

```kotlin
object WhoopType {

    val MetricHero = TextStyle(
        fontFamily = DINPro,
        fontWeight = FontWeight.Bold,
        fontSize = 72.sp,
        lineHeight = 76.sp,
        letterSpacing = (-1.44).sp
    )

    val MetricLarge = TextStyle(
        fontFamily = DINPro,
        fontWeight = FontWeight.Bold,
        fontSize = 44.sp,
        lineHeight = 48.sp,
        letterSpacing = (-0.44).sp
    )

    val SectionTitle = TextStyle(
        fontFamily = ProximaNova,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp,
        lineHeight = 28.sp
    )

    val Body = TextStyle(
        fontFamily = ProximaNova,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        lineHeight = 20.sp
    )

    val Label = TextStyle(
        fontFamily = ProximaNova,
        fontWeight = FontWeight.Bold,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.66.sp
    )
}
```

Recommended usage:

```kotlin
Text(
    text = "87",
    style = WhoopType.MetricHero
)

Text(
    text = "RECOVERY",
    style = WhoopType.Label
)
```

---

# 31. iOS / SwiftUI

Suggested implementation:

```swift
enum WhoopTypography {

    static let metricHero = Font.custom(
        "DINPro-Bold",
        size: 72
    )

    static let metricLarge = Font.custom(
        "DINPro-Bold",
        size: 44
    )

    static let sectionTitle = Font.custom(
        "ProximaNova-Bold",
        size: 24
    )

    static let body = Font.custom(
        "ProximaNova-Semibold",
        size: 15
    )

    static let label = Font.custom(
        "ProximaNova-Bold",
        size: 11
    )
}
```

Example:

```swift
Text("RECOVERY")
    .font(WhoopTypography.label)
    .tracking(0.7)

Text("87")
    .font(WhoopTypography.metricHero)
    .tracking(-1.4)
```

---

# 32. Web / CSS

Suggested variables:

```css
:root {
  --font-text: "Proxima Nova", "Inter", sans-serif;
  --font-metric: "DINPro", "Inter Tight", sans-serif;

  --font-weight-medium: 500;
  --font-weight-semibold: 600;
  --font-weight-bold: 700;

  --type-metric-hero: 72px;
  --type-metric-xl: 56px;
  --type-metric-lg: 44px;
  --type-metric-md: 32px;

  --type-section: 24px;
  --type-page: 20px;
  --type-body: 15px;
  --type-label: 11px;
}
```

Metric:

```css
.metric-value {
  font-family: var(--font-metric);
  font-size: 72px;
  line-height: 76px;
  font-weight: 700;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums lining-nums;
}
```

Label:

```css
.metric-label {
  font-family: var(--font-text);
  font-size: 11px;
  line-height: 14px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
```

---

# 33. Accessibility

Typography must remain scalable without breaking data visualization.

## Body text

Allow:

```text
1.0x → 1.5x
```

---

## Metrics

Large ring metrics should scale more conservatively.

Recommended:

```text
maximum ≈ 1.15x
```

Large uncontrolled scaling may cause:

- ring overflow,
- clipping,
- metric overlap,
- card height changes,
- broken dashboard layouts.

---

## Navigation

Recommended maximum:

```text
1.2x
```

---

## General Accessibility Rules

Avoid:

- fixed-height cards containing dynamic body text,
- clipping important values,
- relying exclusively on color,
- text smaller than ~10sp for essential information.

Allow:

- multiline secondary text,
- adaptive card height,
- screen reader labels,
- semantic descriptions for health metrics.

---

# 34. Metric Component Architecture

Recommended component:

```text
Metric
├── Label
├── Value
├── Unit
├── Comparison
└── Trend Indicator
```

Example:

```text
RESTING HEART RATE

54 BPM
↓ 4 bpm vs 30-day average
```

Internal rendering:

```text
MetricLabel
MetricValue
MetricUnit
MetricComparison
```

Do not combine everything into one Text component.

---

# 35. Number + Unit Baseline

Units should visually support the metric, not compete with it.

Example:

```text
87 %
```

Recommended:

```text
metricSize = 72
unitSize   = 29
```

Align the unit near the lower metric baseline.

For physiological measurements:

```text
54 BPM
38 ms
7h 42m
10,234 steps
```

Use the metric font for the main numeric value and text font for most units.

---

# 36. Responsive Rules

Suggested metric sizes:

```text
Small phone
metric.hero = 64

Normal phone
metric.hero = 72

Large phone
metric.hero = 76–80
```

Do not scale purely based on screen width.

Instead use:

- container size,
- card type,
- content density,
- number of digits.

Example:

```text
87
```

can be larger than:

```text
10,234
```

inside the same width.

---

# 37. Localization Considerations

Uppercase labels can expand substantially in other languages.

Avoid fixed-width text containers for:

```text
RESTING HEART RATE
SLEEP PERFORMANCE
HEALTH MONITOR
```

Localization strategy:

```text
English:
UPPERCASE

Long localized language:
allow smaller tracking or slightly reduced font size
```

Never reduce below accessibility minimum solely to preserve one-line layout.

---

# 38. Typography QA Checklist

Before release, verify:

- [ ] Numeric metrics use numeric font family.
- [ ] Main labels use text font family.
- [ ] Hero metric has negative tracking.
- [ ] Labels have positive tracking.
- [ ] Card titles use uppercase consistently.
- [ ] Section titles remain mixed-case.
- [ ] Units are visually smaller than metric values.
- [ ] Numeric values use tabular figures.
- [ ] Secondary information has lower visual emphasis.
- [ ] Accessibility scaling does not clip content.
- [ ] Long metric values fit correctly.
- [ ] Localization does not break labels.
- [ ] Dynamic numbers do not shift layout noticeably.
- [ ] Font licensing is valid for distributed builds.

---

# 39. Recommended Final Baseline

For development, use:

```text
TEXT FONT
Proxima Nova
Fallback: Inter

NUMBER FONT
DINPro
Fallback: Inter Tight
```

Final scale:

```text
Metric Hero
72 / 76 / Bold / -2%

Metric XL
56 / 60 / Bold / -1.5%

Metric Large
44 / 48 / Bold / -1%

Metric Medium
32 / 36 / Bold / -1%

Metric Small
24 / 28 / Bold

Section
24 / 28 / Bold / -1%

Page Title
20 / 24 / Bold / -1%

Heading
18 / 22 / Bold

Body Large
17 / 23 / Semibold

Body
15 / 20 / Semibold

Body Small
13 / 18 / Semibold

Card Title
12 / 16 / Bold / +6% / UPPERCASE

Label
11 / 14 / Bold / +6% / UPPERCASE

Top Navigation
12 / 16 / Bold / +10% / UPPERCASE

Caption
11 / 14 / Semibold

Chart
10 / 12 / Semibold

CTA
12 / 16 / Bold / +7% / UPPERCASE
```

---

# 40. WHOOP Visual Character Summary

The WHOOP typography feeling is driven by six major rules:

```text
1. Large DIN-style numbers
2. Small uppercase labels
3. Positive tracking on labels
4. Mixed-case section headings
5. Heavy use of Semibold and Bold
6. Strong contrast between primary and secondary information
```

A typical hierarchy:

```text
        87%
     RECOVERY

My Dashboard

RESTING HEART RATE
54 BPM
58 bpm 30-day average
```

If these typography relationships are implemented correctly, the interface will already feel strongly WHOOP-inspired before adding rings, graphs, icons, and other visual elements.

---

# 41. Implementation Decision

For this project, treat this document as:

```text
Typography System v1.0
```

Classification:

```text
Font family behavior:
Official / Verified

Exact point sizes:
Reconstructed / Recommended

Line heights:
Reconstructed / Recommended

Tracking tokens:
Reconstructed / Recommended

Metric unit ratio:
Reconstructed / Recommended
```

This distinction should remain documented to avoid treating reconstructed values as official WHOOP internal design tokens.

---

# 42. References

## WHOOP Official

WHOOP Brand & Design Guidelines  
https://developer.whoop.com/assets/files/WHOOP%20-%20Brand%20%26%20Design%20Guidelines-bdea3554e94b4ea09e68695b1e8dc8e7.pdf

WHOOP Developer Design Guidelines  
https://developer.whoop.com/docs/developing/design-guidelines/

## Additional Visual Reference

WHOOP-inspired / reverse-engineered design language documentation  
https://github.com/ryanbr/noop/blob/main/docs/superpowers/specs/2026-06-22-whoop-design-language.md

---

## Revision History

| Version | Description |
|---|---|
| 1.0 | Initial typography development guideline |
