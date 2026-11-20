# Anya QA review: POOR scenario, round 4 (Apple on-device model)

Source: `round4/qa-poor.json` (9 pages, 16 chat, food, program, breath, plan, morning brief). Data = `compactContext` plus each page's `local` text. Compared against `review-poor.md` (round 3 + chatfix).

Checks: 1 Assistant role, 2 Advice fits, 3 Grounded, 4 On the surface, 5 Manner (metaphor, filler, garbled, over cap), 6 Safe, 7 Honest about gaps. "5h" = the page text still uses the headings "What I see / What it means / What to do", which the contract forbids; counted separately, as last round. "n/a" = food, checks 1-2.

Ground truth used (compactContext, 20 Nov, 20:50): Recovery 18 (yesterday 35, 30-day 62); HRV 52 (yesterday 78, 30-day 81, baseline 82); RHR 67 (yesterday 59, 30-day 55, baseline 54); sleep 5.3h (need about 8h, debt 2h 5m, efficiency 70%, deep 0.7, REM 0.8, light 3.8); Strain 19.3 (yesterday 18.5, range 4-10, usual 14.3, last 7 days 103); stress index 25; sessions today: strength 58 min (7.6), HIIT 45 min (4.0), breathwork 20 min; suggested session: easy movement, 20 min, zone 1, +1; asleep by 23:10. Derived 7-day means accepted: Recovery 47, strain 14.6, sleep 7.1h, HRV 73. Last-week values are not in the table (trends/sleep pack may hold them: marked unverifiable).

Data artefacts (not blamed on Anya): sleep verdict "100%" beside 5.3h; Recovery page `local` "was 82%" vs context 35 yesterday; Strain `local` "131.4 this week" vs context 103; stress page `local` "calm" beside HRV 52 / RHR 67.

Good news first: the word "dash" no longer appears anywhere; no invented bpm/ms/steps targets on pages; no promise to lower Strain; no "keep strain under 10".

## Item-by-item grading

| Item | Fails | Quote | Note |
|---|---|---|---|
| Page: Recovery | 2, 3, 5h | "likely from the Strength Training session"; "keep the same easy movement routine for 20 minutes before bed to help restore baseline readiness" | Figures right (18/62, 52/81, 67/55) but not labelled as 30-day. The session is dated today, after this morning's score, so it cannot explain it; yesterday's Strain 18.5 would. Ignores the 5.3h night (the profile's first lever) and the earlier bed; "keep the same routine" invents a routine; "restore baseline" over-promises. |
| Page: Strain | 2, 5h | "keep the easy movement habit going - do 20 minutes of zone 1 work ... and avoid adding more effort" | Fixed: no promise to bring Strain down. Still contradicts its own headline "stop adding load" by adding a session; no food, water or early night (the profile's step). "Habit" invented. Body gives no range or comparison figure (range is in the headline). |
| Page: Sleep | 2, 3, 5, 5h | "sleep 7.1h against 8.2h, efficiency 91%%, deep 1.3h, REM 1.7h, not available"; "showing strong resilience" | Every figure is from an older night (7.1h/91%/1.3/1.7 = 18 Nov; 8.2h = 14 Nov). Last night: 5.3h, 70%, 0.7, 0.8. The profile says quote the hours when verdict and hours disagree; she quoted wrong ones. Text agrees with the "good" verdict but contradicts the data given. "%%" typo, dangling "not available", "resilience" filler. Maintain step on a 5.3h night with 2h 5m debt. |
| Page: Stress | 3, 5h | "The most likely cause is a regular bedtime that kept the day steady and quiet" | Contract: never name a cause for a good reading; nothing in the data shows a regular bedtime, and "steady and quiet" sits beside HIIT, strength, Strain 19.3, HRV 52. Steps goal and "not logged" claims are gone (fixed). Lists HRV 52/RHR 67 with no baseline or comment. |
| Page: HRV | 2, 5, 5h | "Start a gentle walk for 10 minutes tonight to help the system reset ... since the reading is slipping and no strong recovery signal is visible" | Figures right (52, 82/81, down 26 from 78). Invented target gone (fixed). Cause "increased strain over the past week" is supported (14.6 vs 11.8) but the 5.3h night and 2h 5m debt are ignored; a 10-minute walk is not the habit that lifts HRV in 2-3 days. Echoes the prompt ("since the reading is slipping"), "system reset" filler. 76 words vs cap 75 (at limit). |
| Page: Resting HR | - (5h) | "suggests recent stress or increased activity, even if not logged" | Figures right (67, 54, up 8 from 59); step (rest day tomorrow, walking only) fits. Weak: sessions are logged, "for 24 hours" is filler, no recheck time. Passes. Round 3's garbled step is gone. |
| Page: Respiratory rate | 6, 5h | "Adjust strap fit tonight if it feels tight, to reduce pressure and help the reading stabilize by tomorrow morning" | Figures right (17.2 vs 14.5). Verdict is attention, 2.4 above yesterday, but the clinician line (profile: always add it for a reading that stays off) is missing, though the page's own `localAdvice` has it. Cause "slight strain from daily activity" understates HIIT plus strength. "Anxiety" is gone (fixed). |
| Page: Weight | 2, 3, 5h | "The slight dip suggests a recent shift in intake or activity balance"; "Add 5 minutes of walk after each meal today" | Headline "stable", body "slight dip": inconsistent. Cause (intake/activity) not shown by any figure (no food logged). No goal, so the profile says state the trend and ask the aim, give no training change; instead a load step, after meals that have passed. "Add 200 steps" became "5 minutes of walk": same defect. Figures right (73.6/74.2). |
| Page: Skin temp | 2, 5, 5h | "The drop in heart rate timing and rising skin signal likely point to increased stress or fatigue"; "rest more tonight - do this tonight for 15 minutes" | Invented bpm and 6 p.m. are gone (fixed). The explanation is nonsense (heart rate rose), the step ("rest 15 minutes") is meaningless, and the profile's "watch the next two nights" and "early signal, not a diagnosis" are missing. Reads "1,1 °C against yesterday" (a change) with the 0,9 rise only in the headline. 75 words vs cap 60. |
| Chat 0 today: why Recovery changed | 3 | "down from 82 yesterday" | Yesterday was 35 (82 is the HRV baseline, and the artefact "was 82%"). Sleep-stage cause is correct and grounded (deep 0.7 vs 1.4, REM 0.8 vs 1.8, light 3.8 vs 3.6); "I cannot tell why sleep quality dipped" ignores 5.3h vs 8h need. "Decline in resilience" filler. Canned NEXT STEP closes it (allowed on Today). |
| Chat 1 today: summarise day | 3 | "well below the 34-66 range that supports maintenance" | 34-66 is not in the data. HRV "down from 82" and RHR vs 54 are labelled. Cause (strength + HIIT stacking) is supported. Breathwork omitted. Canned step closes. |
| Chat 2 health: HRV | 2 | "skip the strength Training session and focus on gentle movement ... starting tomorrow evening" | Fixed: cause is now the short night (5.3h below need). Step is contradictory ("Today ... starting tomorrow evening"), asks to skip a session already done today, and does not address sleep. "You cannot tell if" is garbled. |
| Chat 3 health: fitness age | 4 | "Right now, Recovery 18, HRV 52ms against 82ms baseline ... likely from the Strength Training session" | Partly fixed: she now says it is not visible and gives a (vague) general explanation instead of only an unrelated walk. Then drifts to Recovery/HRV/RHR for most of the answer and closes with an unrelated mobility step. |
| Chat 4 trends: Recovery over month | 2, 3 | "18 points lower than the 30-day average of 62"; "shorter sleep periods ... sleep holding at 7.1h"; "add a 15-minute walk ... to ease the load without adding more strain" | 47 vs 62 is 15 points (18 is today's Recovery). "66 the week before" unverifiable. Sleep both "shorter" and "holding", and a stated cause then "I cannot tell why". No journal behaviour named. A walk adds load; not a measurable two-week experiment. Baseline 62 is now right (fixed). |
| Chat 5 trends: hardest day | 1, 2, 3, 7 | "HRV 73ms, resting heart rate not available, against 30-day average 62" | No day named, though the table shows it (strain 18.5 on 19 Nov, Recovery 18 after). HRV 73 is the 7-day mean labelled as today's; RHR 67 is present but called "not available" (the "dash" defect re-worded). Step "keep the same rhythm" is generic. |
| Chat 6 sleep: woke several times | 2 | "Stick to the same bedtime and wind-down routine from yesterday evening to keep the pattern steady" | Opens correctly on 5.3h vs 7.2h (self-contradiction with "100%" is gone; fixed). Ignores efficiency 70% and deep 0.7h, the numbers that answer the question. Mechanism "debt pulled you out of deeper stages" is invented physiology. "Keep the pattern" on a poor night; no clock times. |
| Chat 7 sleep: this week vs last | 1, 2, 3, 7 | "5.3h, 6.8h, 7.1h, 7.9h, 7.0h, 8.2h - against 7.2h, 7.2h, 7.2h, not available, not available ..."; "a small deficit in the latest night" | Series drops a night (7.1 listed once of two); the "against" row is the baseline repeated plus "not available" four times, not last week. 5.3 vs 7.2 is 1.9h, not "small"; debt 2h 5m. "Late wind-down" is invented. Never says plainly that last week is not in the data. Keep-going step on a poor night. Alcohol and "strong deep/REM" are gone (fixed). |
| Chat 8 workouts: best workout | 2, 3 | "aim to add 45 minutes of quiet movement after bedtime ... starting at 22:00" | At 20:50 with Strain 19.3 the step should be "load is done". "45 minutes" is the sleep-extension cap misapplied; "after bedtime" vs a 23:10 bed; contradicts the suggested session (20 min, zone 1) and the "finish 2h before bed" rule; no "day is done" line. Same defect as round 3 ("stop by 22:00"). |
| Chat 9 workouts: plan the week | 1, 5 | "Your Strain this week is 131.4, which is 51% above your usual weekly level"; "finish by 23:10 tonight" | Fixed: no promise of a lower Strain, "no new hard session" is right, 20 min zone 1 matches the suggestion. But no week plan (asked), 142 words vs cap 120, "finish by 23:10" muddles session and bedtime, "low recovery ... explain the elevated strain" has cause backwards. 131.4 and 51% unverifiable (context says 103; the 131.4 is from the page artefact). |
| Chat 10 nutrition: rest of day | 2, 3 | "The low activity and empty intake may explain the drop in readiness"; "Start with a small meal today - something to bring intake closer" | "0 of 2.250 kcal", "no food logged in 14 days": unverifiable, plausible (matches the plan). "Low activity" is false (HIIT, strength, Strain 19.3). Step names no foods or amounts. Fixed: no "dash", no "lift recovery by evening", no body-vitals opener. |
| Chat 11 nutrition: what to eat tonight | 2, 3, 4, 5, 7 | "sleep not available, HRV not available, resting heart rate not available"; "light and simple - by 7 p.m." | Opens on vitals not food, and all three "not available" are present (5.3h, 52, 67). 7 p.m. is 2h in the past (20:50). No foods. "Easy energy" repeated filler. 111 words vs cap 110. Honest that nothing was logged. "dash" re-worded, same fault. |
| Chat 12 breathing: which exercise | 3, 7 | "Your HRV is 26ms below your baseline, and resting heart rate is up 8bpm" | Delta vs yesterday labelled as baseline gap (baseline gap is 30 ms and +13 bpm). Round 3 defect, unchanged. Ignores stress 25 and earlier sessions; never says per-session HRV is not in the data. "Recovery coherence practice" name unverifiable (module pack). Step is slow and comfortable (safe); "twice" at 10 min each is long for 20:50 but fits. |
| Chat 13 breathing: how sessions went | 1, 3, 5, 7 | "HRV 26ms today, against 81ms today, against 73ms today, and RHR 67bpm today, against 51bpm today"; "pulling more energy from the system" | HRV 26 is a delta, not today's value (52); "today" repeated for the 30-day, 7-day mean and a 15 Nov value (51). Does not answer (one 20-min breathwork session, no per-session HRV; not said). "Stress is building" unsupported, "system" metaphor. Repeat hourly twice to 22:50 is arbitrary. |
| Chat 14 device: why disconnecting | 2, 5 | "last sync problem: This device can't use Bluetooth Low Energy, today against yesterday, not available"; "reconnect, today for two minutes" | Reads the field label and a template phrase aloud. Data says the phone cannot use BLE, so the fitted step is to check Bluetooth and permission; she moves the strap closer and only offers the Bluetooth check as a question. No general disconnection causes (battery, range, other apps). Round 3 defect, still there; the Recovery drift is gone. |
| Chat 15 device: charge and battery | 1, 2, 3, 4, 5, 7 | "which explains the low Readiness and the rising effort level"; "last sync is none since the app opened" | Does not say how to charge (profile requires plain general steps) and does not say battery time is unavailable. Drifts to Recovery and invents a strap-to-readiness link; reads raw labels aloud. "RHR 8 bpm" is gone (fixed). 84 words, within cap. |
| Food: "2 telur dadar dan 1 piring nasi goreng" | 3 | `"kcal":350` for 60 g C / 10 g P / 15 g F | Rice macros give about 415 kcal, not 350 (round 3 was 435). Eggs: 160 kcal vs 170 from macros, fine, but carbs 8 g for an omelette is high. Labelled "An estimate", so no safety issue. 1-2 n/a. |
| Program | 2 | "Day 2 (Back and Shoulders)"; "Day 3 (Legs and Core)"; name "Upper / lower, 3 days" | Fixed: rest 30 s is gone (60/90 s). Each day is still one exercise, so "Back and Shoulders" has no shoulder work and "Legs and Core" no core; the name contradicts the split. No reading of Recovery 18 or the debt (no ramp or start-date advice). Parsed OK. |
| Breath | 1, 5 | "like a soft lullaby for your body"; "peaceful and ready for rest" | Title is now plain (fixed); the intro still has a metaphor and filler. No reading of the person (HRV 52, stress 25, bed 23:10) and no when to repeat. 5 min at 6 s in / 6 s out is safe and fits the evening. |
| Plan | 3, 4, 5 | "pace of -0.25 kg/week ... so maintenance (pace 0) is appropriate"; "Protein at 1.8 g/kg (56 g for a 74 kg male)"; "Sleep of 7.2h and low recovery (18)" | Three paces in one plan (-0.25 text, 0 in the sentence, -0.2 JSON) with "no goal weight"; 1.8 x 74 = 133 g, not 56; "-0.27 kg over 14 days" vs "-0.27 kg/week"; sleep 7.2h is the baseline, last night 5.3h. Fixed: 62/11.8 are no longer called today's state; protein per kg now matches the text. Drifts into sleep and movement; WHO padding, garbled "carb-protein-sugar distribution is implied". Cautions send the user to "a professional" for Strain and for not logging food (over-escalation, not unsafe). |
| Morning brief | 5 | "the quiet hours before 23:10 are the anchor"; "The body feels a bit under pressure" | Fixed: no "keep strain under 10", one clear step set, within the cap (76 words), all figures right. Still quotes no baselines ("against the 30-day average" without the values), does not name the session (type, minutes, zone), and ends on a metaphor that repeats the bedtime line. |

## Pass rate per check (N = 30; food checks 1-2 n/a so N = 29)

| Check | Failed | Round 4 | Round 3 |
|---|---|---|---|
| 1 Assistant role | 6 (C5, C7, C9, C13, C15, Breath) | 23/29 | 16/29 |
| 2 Advice fits | 17 | 12/29 | 10/29 |
| 3 Grounded | 17 | 13/30 | 10/30 |
| 4 On the surface | 4 (C3, C11, C15, Plan) | 26/30 | 20/30 |
| 5 Manner (excluding headings) | 11 | 19/30 | 18/30 |
| 5 Manner (headings counted, 6 more pages) | 17 | 13/30 | 11/30 |
| 6 Safe | 1 (Resp page) | 29/30 | 29/30 |
| 7 Honest about gaps | 6 (C5, C7, C11, C12, C13, C15) | 24/30 | 20/30 |

## Earlier defects (review-poor.md): fixed or not

| Round 3 defect | Status |
|---|---|
| Sleep page "7.2h, recovery 86" | STILL THERE in a new form (older nights' 7.1h/91%/8.2h); the Recovery drift is gone |
| Stress page "8000 steps goal", "not logged" | FIXED |
| HRV page invented "below 60 by Friday" | FIXED (walk step and ignored sleep cause remain) |
| Resp page "reduce the rise by 0.5", "anxiety" | FIXED; clinician line STILL missing |
| Weight page "Add 200 steps" | PARTLY (now "5 minutes of walk after each meal"; still a load step without a goal, and a dip against a "stable" headline) |
| Skin page bpm/HRV backwards, "6 p.m." | PARTLY (figures gone; new nonsense wording, over cap, profile steps still missing) |
| Strain page "back to 4-10 by Friday night" | FIXED |
| Page headings "What I see / What it means / What to do" | STILL THERE (9/9) |
| Chat 1 baselines mis-mapped | PARTLY (HRV/RHR right; new invented "34-66") |
| Chat 4, 5 "65 baseline" | FIXED (62) |
| Chat 4 sleep self-contradiction | STILL THERE ("shorter" vs "holding at 7.1h") |
| Chat 5 "reduce strain to 9.0 by Monday" | FIXED |
| Chat 5 "resting heart rate dash" | STILL THERE ("not available" while 67 is given), plus HRV 73 shown as today's |
| Chat 7 "7.1h today", alcohol, "deep and REM strong" | PARTLY (alcohol and "strong" gone; garbled series; still "keep the routine" on a 5.3h night) |
| Chat 8 "finishing in 5-6 Strain, stop by 22:00" | STILL THERE ("45 minutes ... after bedtime ... starting at 22:00") |
| Chat 9 "bring the strain down to 4-10", NEXT STEP contradicted | FIXED (week plan still missing; over cap now) |
| Chat 10 "recovery up to at least 34", "dash" | FIXED (new "low activity" error; generic meal step) |
| Chat 11 "dash", not about food | STILL THERE ("not available"; opens on vitals; "by 7 p.m." in the past) |
| Chat 12, 13 "HRV 26ms under baseline" | STILL THERE |
| Chat 14 wrong fitted step | STILL THERE (and field label read aloud) |
| Chat 15 "RHR 8 bpm" | FIXED; no charge steps, Recovery drift, label reading STILL THERE |
| Plan 1.8 g/kg vs 56 g; pace mismatch; averages as today's state | PARTLY (averages fixed, JSON protein now matches; 56 g and three paces STILL) |
| Brief "keep strain under 10", no baselines | PARTLY (strain line fixed; baseline values still missing) |
| Food kcal vs macros | PARTLY (350 vs 415, was 435) |
| Program restSec 30, single exercise per day | PARTLY (rest fixed; one exercise per day and no state reading STILL) |
| Breath poetic framing | PARTLY (title fixed; "soft lullaby" intro STILL) |
| The word "dash" in answers | FIXED (but replaced by a false "not available") |
