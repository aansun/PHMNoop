# Anya QA review: GOOD scenario, Apple on-device model, round 9

Source: `round9/qa-good.json` (9 pages, 16 chat, food, program, breath, plan, morning brief; N = 30). Compared with `review-good-round4.md`. Same rules as round 4: an item fails a check on any single slip; check 2 = the step/remedy (a fix for a green reading, "take it easy", generic or incoherent step); an ungrounded cause or a mislabelled figure goes under check 3; a cause named for a good reading is also counted under check 3.

Ground truth (compactContext): today Recovery 91 (yesterday 49, 30-day 63), sleep 8.0 h (yesterday 6.8, 30-day 7.2, need about 8 h, debt 0h 37m), eff 94%, HRV 100 (yesterday 78, 30-day 82), RHR 50 (yesterday 59, 30-day 54), Strain so far 10.9 (yesterday 16.1, 30-day 11.2, supported 14-18, usual day 13.4, 7-day 92), SpO2 98.0, resp 14.2 (14.8 / 14.5), skin +0.1 (30-day -0.1), stress SI 25. Sessions today: Strength 58 min (7.6), Breathwork 20 min, Rowing 61 min (7.2). No HIIT this round. Clock 22:20 (night, review part of the day), asleep by 23:10, suggested Tempo 42 min zone 4, NEXT STEP "Wind down now ... be asleep by 23:10". Weekly averages (trends pack): recovery 67/63/66/60, daily strain 12.1/9.4/11.3/13.1, sleep 7.2/7.0/7.3/7.5.

Artefacts not scored against Anya: "Recovery was 82%", "1h 0m past what you need", Stress "1,7 of 3", "68 such night(s)", "24 sessions, Strain 145.2", Strain 11.3 on the page (known) against 10.9 in the context (both accepted), the simulator that "can't use Bluetooth Low Energy", "0 of 2.250 kcal", "It is 22:00" in the breathing pack. Chat 14 and 15 are answered on the phone: graded, marked LOCAL.

Word counts: body without the app's section titles (headline counted separately). Caps: Recovery/Sleep/Strain 80, Stress/Weight 70, HRV/RHR 75, Vitals 65, Skin 60; chat today/health/trends/sleep/nutrition 110, workouts 120, breathing/device 90, brief 110. Over cap: Stress page (body 98, with headline 105 against 70) and Skin page (body 63, with headline 70 against 60). Chat: none over cap (largest: chat 1, 96 of 110). Brief 83.

| Item | Checks failed | Quote | Note |
|---|---|---|---|
| Page: Recovery | 3 | "RHR 50 bpm against yesterday 49, yesterday 59 bpm"; "likely from the breathwork and light movement done today" | Figures are right but pasted as one run: "against yesterday 49" is Recovery, not RHR. Cause is invented and false: today holds Strength 58 min plus Rowing 61 min, not "light movement", and breathwork does not explain a score. Step "Keep the breathwork habit tonight" is a keep, not a fix, and not the NEXT STEP pasted. 80 words, at the cap. Round 4's +22/-9-as-baseline error is gone on this page. |
| Page: Strain | 2, 3 | "The low strain likely comes from a lighter day before"; "Finish the day with an easy session tonight before bed" | Figures right on the page's own scale (11.3 vs 16.1 and 11.2). Yesterday was Strain 16.1, the opposite of "lighter". At 22:20 the day is done: an "easy session tonight" is a new activity at night, not the profile's "finish the day easy". Under-range verdict and the 14-18 range are in the headline (improved). |
| Page: Sleep | 2, 3, 5 | "sleep: today 8.0 h, against need 7.2 h"; "likely because you kept a regular bedtime and didn't push hard yesterday evening"; "go to bed before bed tonight" | 7.2 h is the 30-day average, need is about 8 h. Cause is invented (yesterday was Strain 16.1, a 6.8 h night). The step is garbled ("go to bed before bed"), has no bedtime or wake time, so it is generic. Round 4's "HRV not available" and the 23:10 "wake time" are gone. |
| Page: Stress | 2, 3, 5 | "The rising HRV and heart rate while staying below the usual baseline suggest a lingering stress pattern ... likely tied to the hard session"; "to help reset the system" | HRV rose above baseline and heart rate fell: both clauses are false, and a "lingering stress pattern" is a problem named on a green day. Never quotes the page's own stress figure. Step "reset the system" is a fix. Body 98 words against a cap of 70. Short night / alcohol / illness of round 4 are gone, as is "keep today easy". |
| Page: HRV | 2, 3 | "keep things easy"; "Start tonight before bed with a short walk of 10 minutes" | Figures right (100 / 78 / 82). The headline "keep things easy" is "take it easy" on a green reading. A new habit with a number ("10 minutes") that is in no data, where the profile wants a habit to keep (8.0 h sleep). The "routine behind it is working" line is acceptable. |
| Page: Resting heart rate | 3 | "likely because you stayed asleep longer than needed yesterday evening" | Figures right (50 / 59 / 54). Cause is the "1h past need" artefact (8.0 h against a need of about 8 h) and "yesterday evening" is the wrong time (it was last night). Step "Keep the full night you had" is a keep and fits (round 4's "sleep 1 hour more every night" is gone). |
| Page: Respiratory rate | none | "Your usual range holds. Keep the strap snug and worn overnight" | Figures right (14,2 / 14,8 / 14,5), labels right, step is the profile's maintain step. Minor: "better side of your own baseline" sits beside the headline "in line with usual". 56 words with headline. Cleanest page. |
| Page: Weight | 2, 3, 4, 5 | "pattern needs quiet attention"; "The slight rise may follow a hard block, as the pairing of low HRV and high resting heart rate often does"; "Keep today easy ... do not add load tonight" | Regression to round 3 drift. Weight is "Up 0,0" so there is no rise; HRV is high and RHR low; the profile bans HRV/RHR and training on this page. "Take it easy" on a green day. No goal, and she does not ask what the person is aiming for. Figures in What I see are right. |
| Page: Skin temperature | 1, 3, 5 | "The most likely cause is a consistent nightly rhythm, as the sleep increase and HRV lift follow a steady pattern" | The skin figure (+0,1, up 0,3 from -0,2) is never read; What I see lists HRV and sleep only. "Steady pattern" is false (6.8 h to 8.0 h in one night). Step "Keep the 8.0 h sleep tonight so it holds" is good and fits. Body 63 words against a cap of 60. The baseline-as-today error of round 4 is gone. |
| Chat 0: today, Recovery vs yesterday | 3 | "HRV increased by 22 ms against the 82 ms baseline, and resting heart rate dropped 9 bpm against the 54 bpm baseline"; "likely from consistent rest and reduced strain" | Yesterday's 49 and the 30-day 63 are given (fixed). +22 and -9 are versus yesterday; against the 30-day baseline they are +18 and -4. "Consistent rest" is false (6.8 h yesterday); cause named on a good reading. Step is the NEXT STEP and fits 22:20. 65 words. |
| Chat 1: today, summarise | 3, 5 | "Recovery is 91, well above the threshold for pushing"; "HRV rose 22 ms and resting heart rate dropped 9 bpm against your baseline"; "The consistent effort without spikes likely explains"; "let this quiet recovery carry into your rest" | No threshold exists; 22 and 9 are mislabelled again; "without spikes" is false (16.1 yesterday). The day's sessions (Strength 58, Rowing 61, Breathwork) are not named. Closing line is figurative. 96 words (cap 110). |
| Chat 2: health, HRV | 3, 5 | "against 82 ms yesterday and 82 ms 30-day average"; "with 8 hours tonight"; "Keep the easy day before so this holds. Tonight, keep the bedtime routine steady" | Yesterday was 78, not 82. 8.0 h was last night, not tonight. "Easy day before" is false (Strain 16.1). Two steps in a row. The eight-values-all-"today" garble of round 4 is gone. 60 words. |
| Chat 3: health, fitness age | 1, 3, 4, 7 | "Your fitness age is not available, as this surface only shows vital signs"; "Recovery 91, HRV 100 ms, RHR 50 bpm against 30-day average"; "Keep the breathwork routine tonight" | Still does not say what fitness age is or how the app works it out (profile: never refuse a how-it-works question). "The app estimates age using wearable trends" is a vague claim. Then recites Recovery, HRV and RHR (drift), names a cause, and ends on a "breathwork routine" from one session. Same defect as round 4. 83 words. |
| Chat 4: trends, why Recovery moved | 2, 3 | "Recovery: today 60, yesterday 63, 30-day average 65."; "strain rose above the maintenance range several times"; "go to bed at the same time as on recent quiet days" | The opening line is invented: today is 91 and yesterday 49; 60 and 65 are the weekly and prior-month averages from `known`, not today or the 30-day average. "Maintenance range" appears nowhere. No two-week experiment, a generic step built on "quiet days" that do not exist. Cause (higher-strain week: 13.1 vs 11.3) is partly supported. "You cannot tell" voice is gone. 71 words. |
| Chat 5: trends, hardest day | 2, 3, 5 | the three labelled lines pasted back as the opening; "The hardest day was yesterday ... this likely followed a heavy load without enough recovery"; "so the recovery can climb" | Lists are copied back verbatim (contract: do not). Hardest day of the week by `known` is 14 Nov (Recovery 28) or 15 Nov (Strain 16.4); yesterday was 16.1 and Recovery 49. What followed yesterday is Recovery 91, which contradicts "without enough recovery". "Recovery can climb" for a 91. 85 words. |
| Chat 6: sleep, woke several times | 3, 5, 7 | "the small deficit tonight may have pulled you into lighter cycles"; "the slight drop in total time could have left you briefly alert" | Sleep rose 6.8 to 8.0 h, so there is no deficit and no drop; invents a problem for a 94% night. There is no awakening count in the data and she does not say so. Label line pasted at the start. Step (NEXT STEP) fits. 81 words. |
| Chat 7: sleep, this week vs last | 1, 3, 5, 7 | "Sleep: today 8.0 h, yesterday 6.8 h, 30-day average 7.2 h."; "a solid increase in hours over the week"; "a consistent bedtime and quiet evening, as shown in the data" | Asks week against last week; she compares today against yesterday and never says last week is not in the data (round 4 did). "As shown in the data" is not shown. Label list copied. Step (NEXT STEP) fits. 58 words. Regression. |
| Chat 8: workouts, best workout | 1, 3 | "tonight the sleep is 8.0 hours"; "another with 7.2, both low enough to let the body settle"; "quiet movement tonight before bed" | Right on Strain 10.9 against the supported range and ends correctly with no added load at 22:20. Misses: the suggested Tempo session is never named or placed ("not tonight"); Strength 7.6 and a 61 min Rowing (Z3 36%, 565 kcal) are called "low"; 8.0 h was last night. 69 words. |
| Chat 9: workouts, plan the week | 1, 3, 7 | "the drop from yesterday's 49 points shows strong recovery"; "likely from consistent rest and good sleep" | 49 to 91 is a rise, not a "drop"; the week verdict "Strain 64% above usual" is ignored. No week plan, and she does not say that a week plan needs daily data (profile). Step (keep 8.0 h) is fine. The 137.7 error of round 4 is gone. 62 words. |
| Chat 10: nutrition, eaten vs target | 2, 3, 7 | "the lack of fuel may be limiting performance"; "to close the gap"; "a balanced meal ... protein and complex carbs" | Honest that nothing is logged, and "down 1,2 kg over four weeks" is in `known`. Then asserts a lack of fuel from an empty diary, invents a gap, names no food, and never gives the 2.250 target. "Not logged, not available" is a stutter. "Skipping meals" of round 4 is gone. 60 words. |
| Chat 11: nutrition, tonight | 2, 3, 7 | "Your energy is holding strong today"; "the breathwork and strength sessions are contributing to a steady baseline"; "a balanced dinner tonight with lean protein and complex carbs" | Round 4's best chat has regressed: it no longer says that no food is logged, gives no 2.250 target, no named foods, and "dinner" at 22:20 is late. "Energy holding strong" has no data. Closing question to log tomorrow is fine. 87 words. |
| Chat 12: breathing, which exercise | 3, 5 | "The rise in HRV likely came from the long exhale, 10 min, done at 22:00"; "That habit explains the lift"; "now before bed" then "keep the 10-minute exhale at 22:00 tonight" | The pack says the exercise raised HRV 15% in earlier sessions; she says it explains today's rise, as if already done at 22:00. Two steps, "now" and "22:00", that disagree. "That habit explains the lift" is the prompt wording leaking. The 15% itself is not quoted. Today's figures right. 82 words. |
| Chat 13: breathing, recent sessions | 1, 3, 5, 7 | "likely because the long exhale helped your system reset"; "The rhythm of that breath seems to be the quiet force behind the shift" | Still no session-by-session answer (the pack only has one aggregate, 15%), and she does not say so; today's HRV and RHR are offered as the result of the sessions. "Quiet force" is a metaphor. Step (keep the long exhale tonight) fits. "Longer hold" of round 4 is gone. 84 words (cap 90). |
| Chat 14: device, why disconnecting (LOCAL) | none | "keep it within a few metres of the phone, check that Bluetooth is on ... use Reconnect in Device Settings" | Correct from the strap lines (not connected, no sync). Plain general steps in order. It does not mention that this device cannot use BLE (a simulator artefact). 51 words. |
| Chat 15: device, charge and battery (LOCAL) | none | "put the strap on its charger ... The estimate of how long a charge lasts comes back after you take it off the charger" | Answers the question: charging steps given, and the battery time is honestly not available. Fixes round 4's worst chat. 56 words. |
| Food | none | "kcal":240 (2 eggs), "kcal":420 (fried rice) | Macros give 210 and 463 kcal: within about 14% and 9%. "An estimate, worked out on this iPhone" is honest. Parsed. Round 4's 21% gap is closed. |
| Program | 2 | `"Plank"` with `"repsLow":1,"repsHigh":1`; "Day 3 – Full body balance" | Day titles now match their exercises (round 4 had a push move on Pull day). Plank given as 1 rep, Day 3 is two exercises that are not "full body", and Day 2 has no core work despite "Lower body and core". Prose says "Upper / lower" in the name for three days. Parsed. No data claims. |
| Breath | none | `inhale 6 s, exhale 12 s, 5 min, goal sleep` | The simile is gone ("ease and quiet stillness" is mild). Exercise is slow and comfortable, suits the evening. There is still no "when to repeat". Parsed. |
| Plan | 2, 3, 4 | "Protein is set at 1.8 g/kg (59 g total)"; "target of 2250 kcal" against `"targetKcal":2390`; "maintenance pace (0) with -0.25 kg/week" | 1.8 g/kg at 74 kg is about 133 g, not 59. The text calls the target 2250 while the field is 2390; the pace is 0 and -0.25 in the same line; 55-75% carbs is quoted as 1100-1650 kcal (about 2000 kcal base); "adjusted to meet the minimum of 1200 kcal" is meaningless. Cautions: "The strain of 10.9 is relatively low — ensure rest rather than overexertion" and "monitor for signs of fatigue" are fixes on a green day. Recovery 91 and Strain are dragged into a nutrition plan. Maintenance without a goal weight is correct (improved), and "No food logged" is honest. |
| Morning brief | 2, 3, 5 | "Keep Tempo work indoors and shorten the effort to 14-18 Strain, since the current load leans heavy—no added push"; "Let the night's quiet finish" | Strain 10.9 is under the 14-18 range, so "load leans heavy" is false and the range is used as a cap. Contradicts the suggested Tempo 42 min zone 4 with no reason from the person; "indoors" is invented; "no added push" for a green day. "The night's quiet finish" is figurative. Labels and cause lines of round 4 are gone, comparisons are labelled, the last bullet (keep 8.0 h) is a good keep. 83 words. |

## Tally (N = 30)

| Check | Fails | Pass rate now | Round 4 |
|---|---|---|---|
| 1 Assistant role | 6 (Skin page; chat 3, 7, 8, 9, 13) | 24/30 | 21/30 |
| 2 Advice fits verdict | 12 (Strain, Sleep, Stress, HRV, Weight pages; chat 4, 5, 10, 11; Program, Plan, Brief) | 18/30 | 12/30 |
| 3 Grounded | 24 | 6/30 (Resp page, chat 14, 15, Food, Program, Breath) | 4/30 |
| 4 On the surface | 3 (Weight page, chat 3, Plan) | 27/30 | 25/30 |
| 5 Manner | 12 (Sleep, Stress, Weight, Skin pages; chat 1, 2, 5, 6, 7, 12, 13; Brief) | 18/30 | 18/30 |
| 6 Safe | 0 | 30/30 | 30/30 |
| 7 Honest about gaps | 7 (chat 3, 6, 7, 9, 10, 11, 13) | 23/30 | 25/30 |

Pages alone (9): check 1 8/9 (was 7/9), check 2 4/9 (was 3/9), check 3 1/9 (was 0/9), check 4 8/9, check 5 5/9 (was 8/9), check 7 9/9 (was 8/9).
Chat alone (16): check 1 11/16 (was 9/16), check 2 12/16 (was 7/16), check 3 2/16 (chat 14, 15; was 2/16), check 4 15/16 (was 13/16), check 5 9/16 (was 7/16), check 7 9/16 (was 12/16).
Items passing all seven: Respiratory rate page, chat 14 (local), chat 15 (local), Food, Breath (round 4: none).

Cause or problem named on a good reading: 21 of the 24 non-local pages/chat/brief items (Recovery, Strain, Sleep, Stress, RHR, Skin, Weight pages; chat 0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13; brief), the same as round 4 (21 of 25). Only HRV and Resp pages, chat 8, and the food/program/breath items stay clear.

## Status of each worst defect in review-good-round4.md

| Round 4 defect | Status | Evidence now |
|---|---|---|
| Recovery page: +22/-9 labelled against baseline | FIXED on the page, STILL THERE in chat | page list is correct; chat 0 and 1: "22 ms against the 82 ms baseline" |
| Recovery page: invented cause | STILL THERE | "likely from the breathwork and light movement" (step fixed) |
| Strain page: "no heavy effort", range not quoted | PARTLY | range now in headline; new false cause "lighter day before" |
| Sleep page: "HRV not available", wake time 23:10, third person | FIXED | replaced by garbled "go to bed before bed", 7.2 h as need |
| Stress page: short night/alcohol/illness, "keep today easy" | PARTLY | words gone, but "lingering stress pattern ... hard session" with false HRV claim; 98 words |
| HRV page: new walk habit | STILL THERE | "short walk of 10 minutes" |
| RHR page: "1 hour past need every night" | FIXED (advice) | cause "longer than needed" remains |
| Resp page: cause "calm day", "clears" | FIXED | |
| Weight page: no goal, no question | STILL THERE (and the HRV/RHR drift returned) | "low HRV and high resting heart rate" |
| Skin page: baseline read as today's | FIXED | figure now absent, word cap STILL (63 vs 60) |
| Chat 0: yesterday's Recovery never given | FIXED | 49 and 63 given; labels on HRV/RHR still wrong |
| Chat 1: ignores the day's sessions | STILL THERE | |
| Chat 2: eight values all "today" | FIXED | new "82 ms yesterday" |
| Chat 3: no fitness-age explanation | STILL THERE | |
| Chat 4: cause then "cannot tell" | FIXED | new invented "today 60, yesterday 63" |
| Chat 5: wrong day, rest-days scolding | PARTLY | scolding gone; wrong hardest day, copied list |
| Chat 6: invented physiology | STILL THERE | "small deficit tonight" |
| Chat 7: honest that last week is missing | REGRESSED | compares today with yesterday as a week |
| Chat 8: no session named, "light" | STILL THERE | Tempo not named, 7.6 and 7.2 "low" |
| Chat 9: Strain 137.7 read as current | FIXED | but no week plan STILL THERE |
| Chat 10: "0 of 2.250", skipping meals | FIXED | new "lack of fuel" |
| Chat 11: light activity | FIXED | but now no mention of an empty diary, no foods (regression) |
| Chat 12: "67-100", "Strain above range" | FIXED | new "done at 22:00", two clashing steps |
| Chat 13: no per-session walk-through, "longer hold" | PARTLY | "longer hold" gone; per-session STILL; "quiet force" |
| Chat 14 / 15: raw status, no charging steps (LOCAL) | FIXED | plain steps, honest battery answer |
| Food: kcal against macros | FIXED | within about 14% |
| Program: push move on Pull day | FIXED (titles), PARTLY overall | plank 1 rep |
| Breath: simile | FIXED | |
| Plan: numeric contradictions, Recovery/Strain in reasons | STILL THERE | 59 g vs 1.8 g/kg; 2250 vs 2390; pace 0 vs -0.25 |
| Brief: Tempo contradicted, labels, cause | PARTLY | labels and cause gone; Tempo still shortened, "load leans heavy" new |
| System: "You cannot tell" voice | FIXED | none left |
| System: "keep today easy ... clears" on green | PARTLY | HRV headline, Weight page, Plan caution |
| System: artefact strings as advice | FIXED | only "longer than needed" in RHR/Sleep |

## Systemic patterns

- The cause beat is still treated as mandatory on a good reading (21 of 24 items). The new vague form is "likely from consistent rest/rhythm" next to a claim the data contradicts (yesterday was 6.8 h and Strain 16.1, not consistent or easy).
- Mislabelled comparators moved from the pages (now right) to the chat: +22/-9 "against baseline" (chat 0, 1), "82 yesterday" (chat 2), "tonight" for last night's 8.0 h (chat 2, 8), and trend figures given as today's (chat 4).
- Label lines copied back as the opening (chat 5, 6, 7, 13), which the contract forbids.
- Clock is now 22:20 and Anya mostly respects it (chat 8, Strain page end at bedtime), but the Strain page still suggests an "easy session tonight" and chat 11 a "dinner".
- Profile bleed: canned phrases cross pages (the "low HRV and high resting heart rate" sentence on the Weight page, "routine behind it is working" on HRV and Resp).
- Local answers (chat 14, 15, local page texts) are the strongest part of the set.
