# Body age

A weekly number you can read at a glance, and the **pace of aging** that follows from it.

## What it is

Body age is a **wellness comparison**, not a biological or clinical age. It answers one question: *"How do my habits and fitness of the last seven days compare with the typical person of my age, expressed in years?"*
Below your real age, you are doing better than typical; above it, worse. It says nothing about how old your body, cells or organs are, and it carries no medical meaning.

It is worked out **on the phone**, from data the app already holds. Nothing is sent anywhere.

## How it is made

PHMN follows the published method that WHOOP's *Healthspan* page also describes, with its own implementation (`VitalityEngine` in `Packages/StrandAnalytics`):

1. Each input is turned into a **log-hazard**: how much more or less likely a person with that value is to die of any cause, against a reference, from large cohorts and meta-analyses.
2. The log-hazards are summed and **shrunk by 0.75**, because the inputs are correlated (fitness, resting heart rate and activity move together) and a plain sum would count the same signal several times.
3. The sum becomes years through the **Gompertz** doubling time: mortality roughly doubles every 8 years, so one unit of `ln(hazard)` is `8 / ln 2` years.

```
years(factor) = lnHazard · 0.75 / (ln 2 / 8)
Body age      = age + Σ years(factor)          (kept between 20 and 90)
```

The years of the nine inputs **add up to the Body age**, so the page can list each one and the list sums to the figure.

### The nine inputs

Each input has a **break-even**: at that value it adds nothing. Better than it takes years away, worse adds years.

| Input | Reads | Break-even | Source and how it is read |
|---|---|---|---|
| **Resting heart rate** | median of the week's nights (bpm) | 60 | about +10.5% all-cause mortality per +10 bpm (UK Biobank, meta-analyses) |
| **VO₂ max** | one you typed, or the estimate worked out with your waist | the median for your age and sex | about 14% per 3.5 ml/kg/min (MET) against the FRIEND registry median (Kaminsky 2015): 48.0 men / 37.6 women at 25 to 24.4 / 18.3 at 75, in a line |
| **Sleep duration** | mean of the nights (hours) | 7.5 h, ±0.5 h free | U-shaped; each hour beyond that band adds about 12% |
| **Sleep regularity** | the stored sleep consistency, else the spread of the nights | 70% | most regular against least regular is about HR 0.70 (UK Biobank sleep regularity) |
| **Steps** | mean of the days (needs three days) | 7,000 | about 12% per 1,000 steps a day up to 7,000, tapering to 11,000 |
| **Heart-rate zones 1 to 3** | minutes in the week | 92 min | Wen et al. 2011: the first 92 min a week of moderate activity lowers all-cause mortality about 14%, each further 92 min about 4% more, flat past 10 h |
| **Heart-rate zones 4 to 5** | minutes in the week | 10 min | a deliberately small reading of Arem 2015 and Stamatakis 2022: up to about 10% by two hours a week |
| **Strength activity** | minutes of strength training in the week | 45 min | Momma et al. 2022: 30 to 60 min a week goes with 10 to 17% lower mortality, no gain past an hour |
| **Lean body mass** | 100 minus the mean body fat of the last 30 days (%) | 78% (rising to a ceiling at 60%) | **Not from a cohort**: read off the colour bar of WHOOP's Healthspan page, one reading's worth of evidence. It treats men and women alike, so for women it reads older |

Heart-rate variability is not one of the nine (the engine can read it, the page does not). The zone minutes are the same ones the Zones pages show, read from the stored heart-rate samples; a week with no samples left leaves the zones out rather than reading zero.

### What is left out, and never guessed

An input with no data (no steps for three days, no VO₂ max you typed or can be worked out without a waist, no body fat reading) is **listed as "No data" with what it needs** and does not count as zero. A Body age needs at least **3 inputs**.
The engine carries a **±5-year band** (`bandYears`) as the honest size of its error; the iOS page shows whole years, with a note under it that this is a wellness estimate.

## The week and the number

- **The latest seven days** make the number the Body age page and the Health tab show; both read it through one function, so they cannot differ.
- **Weekly, on Saturday.** The weekly job stores the week's Body age under that Saturday (`body_age` in `metricSeries`, with `vitality` beside it for the computed source). The trend pages and the pace read those weekly values.
- The week is read by one reader (`VitalityWeekReader`) for the stored number, the page's breakdown and the Health tab, so the number stored, the factors listed and the figure drawn are made from the same week the same way.

## Pace of aging

The Body age moves by one year per calendar year plus the change in its offset, so the pace is `1 + slope of the offset`: **1.0×** is aging at the speed of the calendar, **below 1** slower, **below 0** younger over time. A weekly value is noisy, so a line is fitted through up to 26 weekly readings, the noise around it is measured
and the slope is pulled towards 1.0× in proportion to it. The dial runs from −1.0× to 3.0× and needs six weekly readings spanning five weeks. See [CALCULATIONS.md](CALCULATIONS.md#pace-of-aging). Code: `PaceOfAging`.

## When the model changes

The weeks stored by an older version are on another scale (the first version of this model had six inputs and other break-even points), and a pace fitted across them and new weeks would read the step between them as a change in you. So the stored history carries a mark, `body_age_model`, and the first time a version with a newer model opens:

1. the last **26 completed weeks** are worked out again with the current model, from the days and series the app holds for them;
2. the older `body_age` and `vitality` rows of the computed source are dropped;
3. the mark is written last, so a pass that was cut short runs again.

A week with too little recorded is left out and never filled in, so the history may start later than the old one did, and a week whose heart-rate samples are gone has fewer inputs than a recent one. A restore that replaces the database brings back a database without the mark, which is rebuilt the same way. Code: `BodyAgeHistory` (the pure part) and `IntelligenceEngine.rebuildBodyAgeHistoryIfNeeded`.

## What was before

NOOP's Fitness Age estimated VO₂ max from the Nes 2011 non-exercise model (HUNT3) with resting heart rate and a reconstructed activity index, and read the age at which a reference person would have that VO₂ max. That model (`FitnessAgeEngine`) is still in the repository and the macOS app still uses it; the iOS app no longer shows it, and the Vitality score, which was the Body age on a 0 to 100 scale, is no longer shown either.

## Honesty

- This is a **wellness comparison expressed in years**, not a biological age, a clinical assessment or a diagnosis. It says nothing about disease or longevity.
- The per-input curves are a conservative reading of the cited work, not a re-fit. The sources measure self-reported activity or other populations, while these inputs are minutes in heart-rate zones and a wrist's resting heart rate, so the match is approximate. The zone, strength and lean-mass inputs are the least certain.
- Treat it as a **direction of travel over weeks**, not a precise readout.

## References

Named by author, journal, year and topic, as the code comments cite them:

- Kaminsky LA et al., *Mayo Clin Proc* 2015: reference VO₂ max values by age and sex (FRIEND registry).
- Wen CP et al., *Lancet* 2011: the minimum amount of moderate activity that lowers all-cause mortality.
- Momma H et al., *Br J Sports Med* 2022: muscle-strengthening activity and mortality.
- Arem H et al., *JAMA Intern Med* 2015, and Stamatakis E et al., *Nat Med* 2022: vigorous activity and mortality.
- UK Biobank cohorts on resting heart rate and on sleep regularity, and pooled step-count and mortality meta-analyses.
- Nes BM et al., *Med Sci Sports Exerc* 2011 (HUNT3): the non-exercise VO₂ max model NOOP's Fitness Age uses.
