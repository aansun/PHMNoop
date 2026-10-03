# Nuna components

Mockup class names come from `mockups/ui.css`. "Status" says whether the SwiftUI component already exists in `NunaTheme.swift` (✅), reuses an existing StrandDesign view (♻️), or still has to be written (🆕).

## Primitives

| Mockup | Purpose | SwiftUI | Status |
|---|---|---|---|
| `.gc` / `.gc.s` / `.gc.hl` | Card, small card, highlighted card | `NunaCard(small:highlight:)` | ✅ |
| `.chip` (`.a` `.w` `.v` `.d`) | Status pill: ok, effort, rest, alert | `NunaChip(_:systemImage:color:)` | ✅ |
| `.btn` / `.btn.g` / `.btn.r` | Primary (white), ghost, destructive | `NunaButtonStyle` (extend `NoopButton`) | 🆕 |
| `.ib` | 44 pt icon button | `NunaIconButton` | 🆕 |
| `.tg` | Toggle (green when on) | `Toggle` with `.tint(NunaPalette.charge)` | ♻️ |
| `.sg` | Segmented control | `Picker(.segmented)` styled, or `NunaSegmented` | 🆕 |
| `.li` / `.ic` | List row with icon tile | `NunaListRow` | 🆕 |
| `.pb` | Progress bar | `NunaProgressBar` | 🆕 |
| `.cap`, `.h1`..`.h3`, `.n*` | Type roles | `StrandFont` roles | ♻️ |

## Data display

| Mockup | Purpose | SwiftUI | Status |
|---|---|---|---|
| Ring (`rcol`, `ringw`) | Charge / Effort / Rest, Trends gauges, widgets | `NunaRingGauge` | ✅ |
| Zone bar | Heart-rate zones with marker | `NunaZoneBar` | ✅ |
| Hypnogram + movement strip | Sleep stages and movement | existing `Hypnogram`; add movement strip | ♻️🆕 |
| Stress bars | Stress timeline (0-3, colour by level) | `NunaStressStrip` | 🆕 |
| Line / bar charts | Trends, weight, battery | Swift Charts with Nuna tokens (`TrendChart`, `Sparkline`) | ♻️ |
| Scatter + regression line | Charge vs Effort / Rest | Swift Charts `PointMark` + `LineMark` | 🆕 |
| Heat map grid | Charge by day | existing `YearHeatStrip` | ♻️ |
| Calendar dots | Workout calendar (cardio blue, muscular white, both split) | `NunaWorkoutCalendar` | 🆕 |
| Age scale | Fitness age: age marker, ±5 band | `NunaAgeScale` | 🆕 |
| Score bars (pace/zone/range) | Typical-range markers | existing `TypicalRangeBar` | ♻️ |

## Structure and navigation

| Mockup | Purpose | SwiftUI | Status |
|---|---|---|---|
| `.tabbar` | Floating tab bar, 5 tabs | `NunaTabBar` | 🆕 |
| Bottom sheet | Quick actions, Anya, attach, confirmations | `NunaSheet` (detents, 34 pt radius, scrim) | 🆕 |
| Floating "+" | Opens Quick actions on Today | `NunaFAB` | 🆕 |
| Date pill | Opens the date picker | `NunaDatePill` | 🆕 |
| Back header | Title with back and optional trailing control | `NunaHeader` | 🆕 |
| Dashed add card | "Add card", "Add WHOOP" | `NunaAddCard` | 🆕 |

## Anya

| Mockup | Purpose | SwiftUI | Status |
|---|---|---|---|
| Contextual card | One insight with figures, opens a sheet | `AnyaContextCard(context:)` backed by `CoachLauncherSheet` | 🆕 |
| Header Anya button | White icon button in detail headers | `NunaHeader(trailing: .anya(context))` | 🆕 |
| Context sheet | Insight, question chips, mini composer | extend `CoachLauncherSheet` with the contexts: today, health, trends, sleep, workout, nutrition, device | ♻️ |
| Chat bubbles, "Read:" chips | Conversation | extend `CoachView` | ♻️ |

Placement rules are in `mockups/AnyaPattern.dc.html`: one card per screen, same position, always cites the figures it used, hideable, and degrades to a small "Connect Anya" row when no provider is set.

## Live surfaces (WidgetKit / ActivityKit)

| Mockup | Purpose | Status |
|---|---|---|
| Lock screen Live Activity | Header (sport + Effort chip), HR + zone, zone bar, divider, three metrics. **No Pause/End buttons.** | revise `NOOPLiveActivity` |
| Dynamic Island | Minimal / compact / expanded for GPS and non-GPS sports, plus pause, zone alert, GPS weak, rest timer, HIIT phase and done states | revise `NOOPLiveActivity`, `LiftLiveActivity` |
| Sync Live Activity | Connecting / syncing (packets, elapsed) / done | revise `SyncLiveActivity` |
| Home widgets | Score S/M/L, Heart rate, Stress, Anya brief, Steps | revise existing widgets |
| Vital sign widget | 5 metrics S/M/L + lock screen | 🆕 `VitalWidget` |

GPS sports (run, walk, cycle) always show **distance, time and pace** (speed for cycling). Non-GPS sports show time, heart rate, zone and the sport-specific measure (sets and volume for gym, round and phase for HIIT, calories for yoga).
