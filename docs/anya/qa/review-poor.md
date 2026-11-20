# Anya QA review: POOR scenario (Apple on-device model)

Sources: `round3/qa-poor.json` (pages, chat 0-3 and 6-9, food, program, breath, plan, brief) and `chatfix/qa-poor.json` (chat answers for trends 4-5, nutrition 10-11, breathing 12-13, device 14-15). Data = `compactContext` plus each page's `local` text.

Checks: 1 Assistant role, 2 Advice fits, 3 Grounded, 4 On the surface, 5 Manner (metaphor, filler, over cap), 6 Safe, 7 Honest about gaps. "5h" = the page text uses the headings "What I see / What it means / What to do", which the contract forbids ("no headings or labels"); listed separately because it hits all 9 pages and may be a format imposed elsewhere. "n/a" = structured card with no read/advise beat.

Data artefact (not blamed on Anya): the sleep page verdict "Sleep 100% covers what you need" contradicts sleep 5.3h; the Strain `local` text says "23 sessions, Strain 132.7" vs context "last 7 days 103"; the stress `localAdvice` says "You are calm" beside "tenser than your baseline".

Derived figures accepted as grounded (7-day means from the daily table): Recovery 47, strain 14.6, sleep 7.1h, HRV 73.

## Figures not in the data (or wrong)

| Item | Figure | Truth in data |
|---|---|---|
| Sleep page | "sleep 7.2h, recovery 86" | 7.2h is the baseline (last night 5.3h); 86 is 16 Nov (today 18) |
| Stress page | "your 8000 steps goal" | steps are "—"; no goal given |
| HRV page | "keep HRV from falling below 60 by Friday" | invented target; today is Friday |
| Resp page | "reduce the rise by 0.5 /min" | invented target |
| Weight page | "Add 200 steps" | invented |
| Skin page | "lower HRV and RHR ... by 2-3 bpm each", "start at 6 p.m." | HRV is not in bpm; lowering HRV is the wrong direction; 6 p.m. has passed (now 20:22) |
| Chat 1 | "against baseline 82, 54, 77, 62" for five values | 77 is not a baseline; mapping is wrong |
| Chat 4, 5 | "65 baseline" | 30-day Recovery average is 62 |
| Chat 5 | "reduce strain to 9.0 ... Monday" | invented |
| Chat 7 | "7.1h today"; "deep and REM stages were strong"; "yesterday's alcohol" | today 5.3h; deep 0.7h, REM 0.8h, efficiency 70%; no alcohol in context |
| Chat 8 | "finishing in the 5-6 Strain range", "stop by 22:00" | Strain is 19.3 and cannot fall; suggested session is +1-2 |
| Chat 9 | "bring the strain down to a 4-10 level", "finish by 21:30" | Strain cannot fall; 21:30 is under 2h before 23:10 |
| Chat 10 | "bring recovery up to at least 34 by evening", "strength session yesterday" | Recovery is a fixed morning score; the sessions are dated today; it is already evening |
| Chat 12, 13 | "HRV is 26ms under baseline", "RHR up 8bpm" | 26 and 8 are day-over-day changes; vs baseline HRV is -30 and RHR +13 |
| Chat 15 | "resting heart rate 8 bpm" | RHR is 67 |
| Strain page | "bring the Strain back to the 4-10 zone by Friday night" | impossible; Strain only rises |
| Plan | "1.8 g/kg (56 g)" vs JSON `proteinPerKg` 1.1; "-0.25 kg/week" vs JSON -0.1; "Recovery is low (62/100) and strain is high (11.8)" | 1.8 x 74 kg = 133 g; 62 and 11.8 are the 30-day averages, today is 18 and 19.3 |
| Brief | "keep strain under 10" | Strain is already 19.3 |

## Item-by-item grading

| Item | Checks failed | Quote | Note |
|---|---|---|---|
| Page: Recovery | 5h | "**What I see** ... **What it means**" | Reads, explains, one fitted step (bed 23:10, no intense movement). Names no baseline value ("against 30-day average"), never mentions the 5.3h night although the profile says sleep first. "yesterday's workouts": sessions are dated today (yesterday's Strain 18.5 does support the cause). Assistant-like. |
| Page: Strain | 3, 5h | "this will help bring the Strain back to the 4-10 zone by Friday night" | Right direction (stop adding load, early night) but promises a Strain drop that cannot happen tonight. Range is in the headline only. |
| Page: Sleep | 3, 4, 5h | "sleep 7.2h, recovery 86"; "the body handled the night well" | Verdict artefact aside, the figures are misattributed (baseline sleep, a past day's Recovery) and Recovery drifts onto the Sleep page. Text agrees with the verdict but contradicts the data it was given (5.3h, debt 2h 5m). Restates wrong numbers. |
| Page: Stress | 2, 3, 4, 5h, 7 | "heading toward your 8000 steps goal"; "recent movement that wasn't logged" | Invented steps goal while steps are "—". Pushes steps on a day 9 Strain points over the range. Sessions are logged (HIIT, strength) so "wasn't logged" is wrong. Omits baselines for HRV/RHR. |
| Page: HRV | 2, 3, 5h | "aiming to keep HRV from falling below 60 by Friday" | Ignores the obvious cause (5.3h night, 2h 5m debt). "After every effort" walk does not lift HRV. Invented target, and the date is wrong. |
| Page: Resting HR | 1, 5, 5h | "your body is responding more quickly to activity"; "today evening ... do this tomorrow night" | Explanation is meaningless, the step is garbled. Figures are right (67, 54, up 8 from 59). Recheck in 48h is good. |
| Page: Respiratory rate | 3, 5h, 6 | "possibly from minor exertion or anxiety"; "reduce the rise by 0.5 /min" | "Anxiety" is a mood claim; HIIT + strength is not "minor". Profile's clinician line for several off-range nights is missing. "Sleeping position to keep the strap tight" is muddled. Cap 65, text 67 with headline. |
| Page: Weight | 2, 3, 4, 5h | "The slight rise is likely from normal daily activity"; "Add 200 steps ... every morning before breakfast" | Headline "no change", text "slight rise": self-contradiction. No goal, so the profile says ask the aim; instead a generic step that adds load on an over-range day. Pure restatement in "What I see". |
| Page: Skin temp | 2, 3, 5, 5h | "start at 6 p.m. to help lower HRV and RHR ... by 2-3 bpm each"; "late-night activity" | Over cap (75 body words vs 65). "Lower HRV" is backwards. Drops the profile step (ease off, sleep more, watch two nights) and the "early signal, not a diagnosis" line. "Late-night activity" invented. |
| Chat 0 today: why Recovery changed | 1 | "Recovery dipped likely because ... HRV fell, and heart rate rose" | Circular (HRV and RHR are Recovery's inputs). No sleep figure though asked, no comparison with yesterday (35, 78, 59, 6.8h available). Canned NEXT STEP closes it (allowed on Today). |
| Chat 1 today: summarise my day | 1, 3, 7 | "against baseline 82, 54, 77, 62"; "The data does not show stress levels" | Baselines mis-mapped. Stress (SI 24) is in the data. Never mentions HIIT, strength or breathwork, so it is not a summary of the day. Ends on the canned step. |
| Chat 2 health: HRV | 2, 5 | "The signal is weak, so the system is working hard to stay steady"; "walk 10 minutes" | Sleep named as cause but the step (10-minute walk) does not address it. Metaphorical filler. "A late workout": no session times in data. |
| Chat 3 health: fitness age | 1, 4, 7 | "Take a 10-minute walk at a slow pace today" | Does not answer the question at all; a general explanation exists. Re-reads Recovery/HRV and gives an unrelated walk. |
| Chat 4 trends (fix): Recovery over month | 3 | "against a 65 baseline"; "sleep staying at 7.1h" then "sleep didn't keep up" | 65 is not the 62 average. Self-contradiction on sleep. No journal behaviour named though asked. Step is a measurable two-week experiment (good). One block, not short paragraphs. |
| Chat 5 trends (fix): hardest day | 1, 2, 5, 7 | "resting heart rate dash"; "start Monday and Wednesday" | Names no day although the daily table shows it (today 19.3, yesterday 18.5, then Recovery 18). RHR is present (67) but read as "dash". Step is incoherent and generic. |
| Chat 6 sleep: woke several times | 2, 3, 5 | "Sleep is 100% against their own baseline: sleep 5.3h vs 7.2h" | Self-contradiction in the first sentence; third person "their". Ignores the sleep numbers asked for (efficiency 70%, deep 0.7h). Step is generic ("keep the wind-down routine tight", no clock times). |
| Chat 7 sleep: this week vs last | 1, 2, 3, 7 | "with 6.8h logged yesterday and 7.1h today"; "Tonight, keep the same bedtime and quiet routine so sleep holds" | Wrong "today", deep/REM called strong (0.7h/0.8h), alcohol invented. Gives "keep going" on a 5.3h night with a 2h 5m debt. No last-week figure and no admission that it is missing. |
| Chat 8 workouts: best workout | 2, 3 | "finishing in the 5-6 Strain range-start now and stop by 22:00" | At 20:22, Strain 19.3, the day's step is "load is done". "Aim for a 4-10 Strain" is unreachable; 22:00 is 70 minutes before bed. Suggested session says +1-2. |
| Chat 9 workouts: plan the week | 1, 2, 3, 4 | "Today's load is done. Eat, hydrate ..." then "Take a 20-minute walk ... to bring the strain down to a 4-10 level" | No week plan. Copies the NEXT STEP verbatim, then contradicts it with a walk. Strain cannot come down. 96 words, within cap. |
| Chat 10 nutrition (fix): rest of day | 1, 2, 3, 4, 5, 7 | "Sleep dash, HRV dash, resting heart rate dash"; "10-minute walk after lunch to help bring recovery up to at least 34 by evening" | Nothing about food after "0 of 2.250 kcal" (the pack is not in compactContext, so "0 eaten" is unverifiable here). Lunch has passed. Recovery cannot be lifted by evening. Present values read as missing. |
| Chat 11 nutrition (fix): what to eat tonight | 1, 2, 4, 5, 7 | "Sleep dash, HRV dash, resting heart rate dash"; "Log your sleep and heart rate tomorrow morning" | Opens on body vitals, not food. "Small balanced meal with protein and complex carbs": no foods, no amounts, no use of eaten vs target. Tells the user to log what the strap measures. "Tomorrow's steps": invented. |
| Chat 12 breathing (fix): which exercise | 2, 3, 5, 7 | "HRV is 26ms under baseline"; "baseline resilience is dipping"; "4 rounds ... for 2 minutes ... repeating every 10 minutes" | Delta mislabelled as baseline gap. "Baseline numbers don't show if sleep ... are missing": sleep 5.3h is given. 4 rounds of 10s is 40s, not 2 minutes. Ignores stress 24 and today's 20-minute breathwork. Slow, comfortable technique is safe. |
| Chat 13 breathing (fix): how sessions went | 1, 2, 3, 4, 7 | "HRV 26ms under baseline, RHR up 8bpm"; "Do 6 minutes ... repeat ... for 2 minutes" | Does not answer: the data has one Breathwork session (20 min, avg HR 66, max 78) and no per-session HRV; she should say so. Drifts to Recovery. Step lengths are arbitrary. |
| Chat 14 device (fix): why disconnecting | 2 | "Bring the strap closer ... full reconnect-do this now for 2 minutes" | Data says the app "can't use Bluetooth Low Energy": the fitted step is to check Bluetooth/permission, not distance. Gives no general causes (battery, range, other apps). Figures: none (the Recovery drift of round 3 is gone). 85 words, within cap. |
| Chat 15 device (fix): charge and battery | 1, 2, 3, 4, 5, 7 | "resting heart rate 8 bpm"; "Low readiness and weak link to the system"; "will this lift the red signal?" | Does not say how to charge although the profile requires plain general steps. Drifts to Recovery, invents a link between body readiness and the strap, "RHR 8 bpm" wrong, reads raw field labels aloud, "red signal" is a metaphor. 93 words vs cap 90. Correctly refuses to guess the battery time. |
| Food: "2 telur dadar dan 1 piring nasi goreng" | 3 | `"kcal":350` for 60 g C / 15 g P / 15 g F | Macros give about 435 kcal, not 350. Omelette carbs 15 g is implausible (about 1-2 g). Fat 10 g low for two fried eggs. Labelled "An estimate", so no safety issue. Checks 1-2 n/a. |
| Program | 2 | `"Day 1: Upper"` with one exercise; `"restSec":30` on Romanian Deadlift | States "compound lifts first" but Day 1 is a single press with no pull. 30 s rest between 12-20 rep deadlift sets. Ignores Recovery 18 and the 2h 5m debt (no start/ramp advice). Name "Upper / lower" vs a Push-Pull-Legs Day 3. Parsed OK. |
| Breath | 1, 5 | "a gentle sense of ease and quiet comfort"; title "Soft breath, slow and steady" | Filler and poetic framing. No reading of the person (HRV 52, stress, bedtime 23:10), no when to repeat. 5 min at 6s in / 6s out is safe and fits an evening. |
| Plan | 3, 4, 5 | "protein intake of 1.8 g/kg (56 g)"; "Recovery is low (62/100) and strain is high (11.8)"; "slightly above the ideal 4-10 range" | JSON `proteinPerKg` 1.1, text 1.8, 56 g matches neither. Pace -0.25 in text, -0.1 in JSON. Averages mislabelled as today's state, and 19.3 vs 4-10 is far above, not "slightly". 256 words, WHO padding, drifts into sleep and the movement session. |
| Morning brief | 1, 2, 3, 5 | "keep strain under 10"; "the data doesn't show fatigue, just a need to ease into movement"; "notice the breath at bedtime" | No baselines quoted (HRV 52 vs 82 missing). Strain is already 19.3. Three bullets plus a closing step instead of one; "rest more by eating, drinking water" is incoherent. Within 110 words (97). |

## Pass rate per check (N = 30 items; food checks 1-2 n/a so N = 29 there)

| Check | Failed | Pass |
|---|---|---|
| 1 Assistant role | 13 | 16/29 |
| 2 Advice fits | 19 | 10/29 |
| 3 Grounded | 20 | 10/30 |
| 4 On the surface | 10 | 20/30 |
| 5 Manner (excluding page headings) | 12 | 18/30 |
| 5 Manner (headings counted) | 19 | 11/30 |
| 6 Safe | 1 | 29/30 |
| 7 Honest about gaps | 10 | 20/30 |
