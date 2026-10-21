# How PHMN calculates things

Everything here runs on the phone, from the numbers your strap and your own log already hold. The strap protocol, sleep staging and the base
scores (Charge, Effort, Rest) are [NOOP's](NOOP_README.md); this page covers what PHMN **adds on top** and the figures its screens
explain. Each section names the file that holds the code, so you can check the arithmetic yourself.

Everything is an **estimate, not medical advice**. Where a figure needs history to mean anything, PHMN says what it is waiting for instead of
showing a number.

Contents: [Effort](#effort) · [Effort target and plan](#effort-target-and-plan) · [Session reads](#session-reads) ·
[Resting heart rate](#resting-heart-rate) · [Sleep](#sleep) · [Training load](#training-load-and-readiness) ·
[Treadmill distance](#treadmill-distance) · [Fitness age pace](#pace-of-aging) · [Weather and air](#weather-and-air) ·
[Breathing](#breathing) · [Nutrition](#nutrition) · [Lab Book ranges](#lab-book-ranges) · [Ranges and colours](#ranges-and-colours)

---

## Effort

Effort is a logarithm of the day's heart-rate load, on a 0 to 100 axis (you can show it on WHOOP's 0 to 21 scale in Settings):

```
effort = 100 · ln(1 + load) / ln(D)
```

`load` is TRIMP, the training impulse built from your heart rate against your resting and maximum heart rate. `D` is a fixed denominator chosen so
that the theoretical maximum day lands exactly on 100. Because Effort is a logarithm, **loads add up, Effort points do not**: two sessions of Effort 40
are far less than 80. Every calculation below that combines Efforts therefore goes back to load, adds, and maps again.
Code: `StrainScorer` in `Packages/StrandAnalytics`.

### Effort after an activity

The target sheet shows where your day would end if you did a planned activity. It undoes the log map for the day and for the activity, adds the two
loads and maps the total again:

```
trimp(e)  = D^(e/100) − 1
after     = 100 · ln(1 + trimp(day) + trimp(activity)) / ln(D)
```

The higher your Effort already is, the less the same session adds. An input at or below 0 contributes nothing. Code: `StrainScorer.effortAfter`.

### Where the day's Effort came from

To say how much of the day's Effort is workouts and how much is everyday movement, each workout's Effort is turned back into its load, whatever load the
day has beyond the workouts is everyday movement, and each source gets its share. If the workouts' loads add up to more than the day's (their windows overlap
the measurement), they are scaled down so the parts always add up to the day's Effort. Code: `EffortAttribution`.

### Planning estimate for a session

When you set a target, the **Activity effort** is what the session alone would score:

- with a heart-rate zone: `atHour = 3.6 + 2.55 · zone` (Effort of an hour in that zone), stretched or shrunk by length
  `0.35 + 0.65 · ln(1 + minutes/30) / ln(3)`, capped at 20 (on the 0 to 21 scale, so ÷ the scale factor on other scales);
- without a zone: `2.8 + minutes/17`, or `3.6` for a free session;
- the length is the Time target, else the Distance target at an assumed 6 minutes a kilometre, else 45 minutes.

It is a planning figure to compare options, not a promise. Code: `NunaWorkoutGoal.estimatedEffort`.

## Effort target and plan

**Today's Effort target** comes from Charge, the same bands WHOOP uses, on the 0 to 21 scale:

| Charge | Target Effort |
|---|---|
| 67% and above (green) | 14 to 18 |
| 34% to 66% (yellow) | 10 to 14 |
| below 34% (red) | 4 to 10 |

With no Charge (calibrating or unscored) there is no target: no band is guessed. Code: `CoupledView.optimalStrainRange`.

**Anya's suggested session** (`DayPlan`) is worked out only from Charge, yesterday's Effort, the acute-to-chronic load band and your heart-rate zones:

1. Charge below 34, or an excessive load band, means **recovery** (4 + 12 + 4 minutes in zone 1).
2. Charge below 67, a high load band, or yesterday at least 1.5 times your usual Effort means **easy** (Charge under 50) or **steady** (zone 2).
3. Otherwise **quality**: warm-up, 24 minutes in zone 4, cool-down.

The Effort estimate is your **own** median Effort per minute from past sessions, scaled by the kind of session (recovery 0.4, easy 0.7, steady 1.0, quality 1.4) with a
±20% band, and it is left out under three sessions of history. A time target never goes under 30 minutes. Code: `DayPlan`.

## Session reads

**Cardio and muscular split** (gym summary). There is no validated way to turn sets and weights into cardiovascular strain, so this does not try and does not touch
Effort. It answers a relative question: against your usual sessions, how hard was this one on the heart (Effort per minute) and on the muscles (kilograms lifted per
minute)? Each is ranked among your earlier sessions with a mid-rank percentile kept off 0 and 1:

```
rank = (below + ½·equal + ½) / (n + 1)
cardio% = rank_cardio / (rank_cardio + rank_muscular)
```

It needs at least three earlier sessions with both figures, and sessions under five minutes are left out. Code: `SessionLoadSplit`.

**Workout read** (Anya's line on a summary) compares the session with your own last 30 days of the same sport: pace against heart rate, length, Effort and where
the time went. No verdict without at least two other sessions. Code: `WorkoutRead`.

**30-day average pills** on the key statistics compare a figure with the mean of your other sessions of that sport in the 30 days before it (at least two).

## Resting heart rate

On iOS the nightly resting heart rate is the **mean** heart rate of your longest sleep session (valid samples only), not the lowest stretch of the night.
It runs a few bpm above the floor (on one wearer's nights 4 to 13 bpm) and 4 to 7 bpm below a Fitbit worn the same nights. The case for it rests on one participant over
five nights. Known limits: a night the stager splits in two is represented by its longer part, and the minimum-sample check counts samples
rather than time. Code: `PrimarySessionRestingHR`.

## Sleep

**Night end.** A night ends where the strap stopped recording, not where the sleep session closed. A stretch with no recording (off the wrist, not synced) is not wake. It is
found from the movement series: a run of at least 10 minutes of exactly-zero movement on the session's own 30-second grid, starting within 10 minutes of the last sleep, cuts the
night at the last sleep, keeping at most 5 minutes of wake. Awake time the strap did record, and gaps in the middle of a night, are left alone. Code: `SleepTailTrim`.

**Sleep debt.** Each night: `nextDebt = 0.55 · max(0, need + debt − slept)` over the last 14 counted nights, anything under ten minutes clearing to zero. The need is personal
(the upper quartile of your own nights, floored at about 8 hours, so a chronic under-sleeper's debt is not quietly erased) and is the same on every screen that shows debt. Code: `SleepDebt`, `SleepModel.debtNeedMin`.

**What moves your sleep.** A habit you log (alcohol, late caffeine, a late meal) is named as a cause of a night only when your **own** nights show it: at least 3 nights
with it and 3 without, and Rest at least 4 points lower on average after it. The textbook claim alone is never enough. Code: `SleepFactors`.

**Reads on the Rest screens** (`InsightReads`) name which part of the night carried or held back the score, from the four components of Rest (duration against need, time
asleep in bed, deep plus REM share, bedtime regularity), your own usual stage minutes and your HRV and resting heart rate against baseline.

## Training load and readiness

Load balance is the last block against the mean of all blocks (this week against the average of the last six). Under 0.8 is under-loaded, 0.8 to 1.3 optimal, 1.3 to 1.5
high, above that excessive. Form (CTL minus ATL) reads above +2 as fresh, −3 to +2 balanced, −6 to −3 loaded and below −6 overreached. Code: `TrendInsights`.

**Readiness** (the Push / Maintain / Rest chip) is NOOP's `ReadinessEngine`: HRV against your 30-day baseline, resting heart rate drift, respiratory-rate drift, the
acute-to-chronic ratio of your last 7 against your last 28 days, and training monotony. The page behind the chip lists each signal with its figure and flag.

## Treadmill distance

A treadmill gives the strap no GPS and no speed, but it counts steps. Distance = steps × step length, with the step length a share of your height:

- walking: 0.413 of your height;
- running: rising from 0.413 at 110 steps a minute to 0.70 at 180, linearly by cadence.

It needs at least 50 steps, 30 seconds and a height between 120 and 230 cm, and you can replace it with the treadmill's own reading afterwards. Code: `TreadmillDistance`.

## Pace of aging

The fitness age moves by exactly one year per calendar year plus the change in its offset, so the pace is `1 + slope of the offset`. A weekly fitness age is noisy, so the
estimate fits a line through up to 26 weekly readings, measures the noise around the line, and **shrinks the slope towards 1.0×** in proportion to that noise: a short or
jumpy history reads close to normal and only a long, consistent trend moves it far. The result is clamped to −1.0× to 3.0× and needs six weekly readings spanning five weeks.
It is a fitness comparison, not a biological age. Code: `PaceOfAging`.

## Weather and air

Advice is arithmetic over what OpenWeather and IQAir answered for your place (rounded to about a kilometre), for a healthy adult:

- feels-like 38 °C and above, or 33 °C and above, or 30 °C and above with 70% humidity: hot; −10 °C and below, or 5 °C and below: cold;
- US AQI by the EPA bands (good under 51, then moderate, unhealthy for sensitive groups from 101, unhealthy from 151, very unhealthy from 201, hazardous above 300),
  derived from PM2.5 with the EPA breakpoints when only the particle count is known;
- storm, rain, and wind from 12 m/s.

Each factor raises the level from *good* to *adjust* (shorter, easier, or another time) to *indoors*. A cooler hour within the next 12 hours is offered only when it is hot now
and the later hour is at least 3 °C kinder. Code: `Environment` and `EnvironmentClient`.

## Breathing

The breathing advisor is rule-based and on the phone, with no provider. It weighs live heart rate against resting, short-window HRV, the day's stress, how recovered you are,
the time of day and what has worked for you before, then picks a goal (calm, sleep, focus, energise, recover) and one of 15 templates. It never picks a forceful protocol on
its own. Code: `BreathAdvisor`.

## Nutrition

Everything is arithmetic over what you logged and weighed, in `NutritionMath` (pure, with tests). Nothing here is applied for you: the check-in only suggests.

- **Trend weight**: each weigh-in moves the trend by 10% of the way to it for every day since the last one (`1 − 0.9^days`), so water and salt swings do not read as fat. Several weigh-ins on a day count as their mean.
- **What your body spends**: over the last 14 days, the mean intake minus the change of the trend weight at **7,700 kcal per kg**, spread over the days between. It needs food logged on at least 10 of the 14 days and a trend that spans at least 10; until then
  the page uses a rough figure from your profile (Mifflin-St Jeor times 1.4) and says so.
- **Daily target**: what the body spends plus the pace you chose (7,700 kcal per kg, over 7 days), never below **1,200 kcal**.
- **Macros**: protein from your body weight (1.8 g per kg unless you change it), fat as a share of the calories (28% unless you change it), carbohydrate the rest.
- **Weekly check-in**: the trend over the last 7 to 14 days against the pace you planned. It needs 5 days of food in the week and weigh-ins across a week; it suggests a change to the target of at most 250 kcal either way, in steps of 10, and stays quiet under 50 kcal.
- **Anya speaking up**: over the target by more than 5% today (10% for a finished day), behind where the day should be (a quarter of the target by early afternoon, rising to nine tenths late), protein under 60% of its target in the evening,
  nothing logged by noon, or on track. One line at most, and the card has no Add button when the day is already over.
- **Anya's plan** is a suggestion from her, worked out from your profile, weight, food, sleep, recovery, training and, when you share it, the Lab Book. The app clamps every number (1,200 to 4,500 kcal, pace −1 to +0.5 kg a week, protein 0.8 to 2.4 g per kg, fat 20 to 40%) and shows it
  against the WHO references below before you apply it.
- **WHO references used**: healthy adult BMI 18.5 to 24.9; a safe level of protein intake of 0.83 g per kg a day; fat 20 to 35% and carbohydrate 55 to 75% of the energy.

Code: `NutritionMath`, `WhoNutritionReference`, `NunaNutritionView`, `NunaNutritionPlanView`, `NunaAnyaPlanCard`.

## Lab Book ranges

A reading is placed against the range **copied from your own report**; PHMN ships no ranges of its own for blood markers and never judges a value. Two body markers have a reference when your report has none:

- **Weight**: the weight a WHO normal BMI (18.5 up to 25) allows at your profile height, `BMI × height²`.
- **Waist**: below 94 cm for men and 80 cm for women (WHO expert consultation, 2008), by the sex on your profile.

A range from your own report always wins over these. They apply to kg and cm only; a reading in another unit has no reference rather than a converted one. Code: `WhoBodyReference`.

## Ranges and colours

- **Charge**: green from 67, yellow from 34, red below.
- **Effort**: dark blue below 33, blue below 66, light blue above (stored axis).
- **Rest**: excellent 85 to 100, good 70 to 84, fair 50 to 69, low below 50.
- **Heart-rate zones**: from your own maximum and resting heart rate, five zones; the zone buzz repeats at most every 45 seconds while you are outside your target zone, and
  a time or distance target is announced and buzzed once.

Colours come from one place (`NunaScoreStyle`), so the Home Screen widgets and the app cannot disagree.
