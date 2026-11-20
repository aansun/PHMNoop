# Anya QA review: EMPTY scenario, round 4 (Apple on-device)

Checks: 1 assistant role, 2 advice fits verdict, 3 grounded, 4 on the surface, 5 manner, 6 safe, 7 honest about gaps.
"nil" in the JSON is the harness's rendering of "no insight". Source read: `qa/round4/qa-empty.json`, `Strand/AI/AnyaSurfaces.swift`, and the gate in `Strand/AI/AICoach.swift` (line 1441).

Harness notes that change how some items read:
- The program block is given a fixed brief and training summary by the harness ("dumbbells only", "chest not fully recovered"), so those words in the program answer are grounded in the input, not invented. That input is not what a real empty install would send.
- The iOS Simulator has no Bluetooth, so the device answers saying "problem using Bluetooth Low Energy" probably reflect the simulator, not a real new phone. The wrong-advice point below still holds for a user who has never paired.

## Table

| Item | Checks failed | Quote | Note |
|---|---|---|---|
| page Recovery | none | `text: nil` | Silent. UX gap: no "wear the strap overnight" empty-state line. |
| page Strain | none (1 minor) | "No Strain yet today. Anya reads it as soon as your heart rate has spent time in the zones." | No figure. "your heart rate" implies a live source a new user does not have. No step (wear and sync). |
| page sleep | none | `nil` | Silent. |
| page stress | none | `nil` | Silent. |
| page HRV | none | `nil` | Silent. |
| page Resting heart rate | none | `nil` | Silent. |
| page Respiratory rate | none | `nil` | Silent. |
| page Weight | none | `nil` | Silent. Weight needs no strap; an "add a weigh-in" line would help. |
| page Skin temperature | none | `nil` | Silent. |
| chat today Q1 (Recovery change) | none (1 weak) | "I have no readings from your strap yet, so there is nothing for me to read. Wear it overnight and sync, then ask again." | Honest. Assumes a paired strap. |
| chat today Q2 (day summary) | none | same canned text | Correct. |
| chat health Q1 (HRV vs baseline) | none | same canned text | Correct. |
| chat health Q2 (what is fitness age) | 1, 4, 7, 3 | "This surface does not include fitness age or how it's calculated."; "You'll find fitness age in a different report, built from broader performance patterns over time."; "You cannot tell how it's built from this data alone" | Gate now lets the question through, but she still does not answer it: no definition. The "different report ... broader performance patterns" is an unsupported claim about the app. "You cannot tell" is addressed to the user, not her own limit. Ends on the generic wear-the-strap step. The profile says never refuse a how-it-works question. |
| chat trends Q1 | none | same canned text | Correct. |
| chat trends Q2 | none | same canned text | Correct. |
| chat sleep Q1 (woke up several times) | none (1 weak) | same canned text | Honest. A general "common causes" line is optional. |
| chat sleep Q2 (compare weeks) | none | same canned text | Correct. |
| chat workouts Q1 (best workout today) | none (1 weak) | same canned text | Honest. No safe generic session offered. |
| chat workouts Q2 (plan week) | none (1 weak) | same canned text | Honest, but the user gets nothing usable. |
| chat nutrition Q1 (eaten today vs target) | 3, 6, 2, 5 | "far below the level your body needs to function"; "the low energy signal"; "start with 100 kcal—within the next 15 minutes"; "2.250 kcal" | Wrong source named is fixed (no "strap"). New problems: "low energy signal" is invented (no signal exists); "body needs to function" is an alarming medical-sounding claim for a person who has simply not logged yet; "100 kcal" and "15 minutes" are invented figures, and 100 kcal at 21:00 against a 2250 target is not a sensible step. "0 of 2.250" reads as 2.25 to an English reader. "You've eaten 0" states as fact what is only "nothing logged". |
| chat nutrition Q2 (what to eat tonight) | 1, 2, 3, 5 | "no activity data is present—this means we cannot assess what you ate today"; "the gap likely stems from an unlogged meal or drink"; "eat a small, familiar item now—something simple"; "0 of 2.250 kcal ... 2.250 left ... 2250 kcal plan" | Not blocked any more, but the question (what to eat tonight) is not answered: no food named. The "activity data ... cannot assess what you ate" line is a non sequitur. "Likely stems from" is a cause with nothing behind it. "2.250" next to "2250" in one sentence. "Your 2250 kcal plan": the person has no plan, this is a profile estimate. Follow-up "What did you eat earlier today?" contradicts "nothing logged". |
| chat breathing Q1 (which exercise now) | 3, 7, 1, 6 | "Strain: 14, Recovery: 42, Sleep: 72, HRV: not available"; "Recovery is low and Strain is above the supported range"; "The rise in HRV from a long exhale suggests it worked before" | Worst item this round. Invents three readings and a verdict on a store with no data, plus a breathing history that does not exist. Strain 14 "above the supported range" is a claim about a range that is not there. The gate now lets breathing through, but she then has no data to ground it and fills the gap. Round 3 was a canned (honest but unhelpful) message; this is worse. |
| chat breathing Q2 (recent sessions) | 3, 7, 1 | "Your HRV rose 15% today against the 30-day average"; "long exhale, 10 min, at 20:00"; "the daily 8000 target" | Regression: round 3 said "nothing to read" (correct, no sessions exist). Now invents a 15% HRV rise, a 30-day average, a 20:00 habit and a steps target. Steps are off the surface (breathing). Source of "long exhale, 10 min, 20:00, 8000" is not in the data the harness printed; it may come from the breathing advisor or the model. Needs checking. |
| chat device Q1 (why does strap disconnect) | 2, 3, 7 | "The connection is not connected, with no recent sync since the app opened and a problem using Bluetooth Low Energy"; "Bring the strap closer to the phone and attempt the connection again" | "The connection is not connected" is garbled. It assumes a connection that failed; a new user never paired. The step should be to pair first. "a problem using Bluetooth Low Energy" reads a code aloud (probably a simulator artefact). The contract says never read a code aloud. |
| chat device Q2 (how to charge, battery life) | 1, 2, 3, 7 | "The strap is not connected, not syncing, and cannot use Bluetooth Low Energy — not available."; "hold the button for two seconds to restart the link" | Does not answer how to charge, which the profile says must be given as plain general steps. First sentence is garbled filler. "Hold the button for two seconds" is an invented hardware procedure that may be wrong for the strap. "No charge history" is a fair reason not to promise battery life, but it is wrapped in "You cannot tell". Follow-up question is fine. |
| food ("2 telur dadar dan 1 piring nasi goreng") | 3 (minor) | `"kcal":120 ... 12P/8C/6F`; `"kcal":250 ... 15P/40C/10F` | Opens "An estimate, worked out on this iPhone." Macros vs kcal: telur 12P+8C+6F is 134 kcal against 120 (about 10% off); nasi goreng 15P+40C+10F is 310 kcal against 250 (about 24% off). Round 3 was 160 vs 120 and 350 vs 250. Better, not clean. A plate of nasi goreng at 250 kcal is still low. |
| program | 2 (minor), 3 (minor) | "Day 2: Lower" with two lifts; "Dumbbell Bench Press - Medium Grip" | Parses, name "Upper / lower, 3 days" matches the days, reps 6-12 match the note, "existing work" is gone. Now 2, 2 and 3 exercises per day, which is thin: the lower day has no core or calf and only one hinge and one squat, and Day 3 is Day 1 plus one press. "Medium Grip" is a barbell term on a dumbbell lift. "chest is not fully recovered" comes from the harness summary. |
| breath | 5 | "like a gentle pause before drifting off"; "It should leave you feeling soft and peaceful, not tense." | Parsed, 5 min, 6 s in and 6 s out, goal "calm", title "Slow breath for bedtime". A simile and an outcome promise remain; the contract says no metaphors. Equal inhale and exhale is acceptable; no long holds. |
| plan | 3, 6, 2, 1, 7, 5 | "aim for a drop of 0.4 kg"; `"paceKgPerWeek": -0.4`; "the kidney marker is outside its range"; "the 0.8 g/kg protein is kept ... so protein stays at 1.8 g/kg"; "Intake: 2250 kcal—this is the current level" | Parses. Band praise and "Strain 0" are gone, "recovery: not available" is stated. But with no goal weight she should choose maintenance (pace 0); she picks -0.4. The explanation contradicts itself: "no goal weight" yet "to match the goal"; pace "-0.25" then "-0.4"; target "holds at 2250" yet is set to 2150; protein "0.8" then "1.8 g/kg". Invents a medical finding ("kidney marker outside its range") while also saying "Lab Book: not shared". Calls 2250 kcal "intake" and "current level" while the cautions say "nothing logged". A 100 kcal cut is about -0.09 kg a week, not -0.4, so the numbers disagree with each other. Opening text "keep the rhythm", "current pattern", "recovery and strain balance" implies history that does not exist. |
| morningBrief | none | `output: nil` | Returns nothing. Meets the rule. |
| compactContext (input) | 2 (minor) | "NEXT STEP (worked out from the numbers above ...): Keep the evening light."; "when asked how the day went, say what its Strain and the night ahead imply" | The no-data line is now correct ("the bands in your instructions are rules, not their readings"). But the RIGHT NOW block still tells her to speak about Strain and still injects a NEXT STEP computed from nothing, which fights the "wear the strap and sync" message and may feed the invented Strain in breathing Q1. |

## Earlier defects

| Earlier defect | Status | Evidence |
|---|---|---|
| Plan praised "Recovery 67, Strain 0" from the band legend | FIXED (that defect) | No Recovery or Strain figure. |
| Plan did not parse | FIXED | `parsed: true`. |
| Plan correct for the profile (maintenance, pace 0) | STILL THERE (new aspect) | Pace -0.4 with no goal; "kidney marker" invented; self-contradicting explanation. |
| Chat blocked general questions with the canned message | PARTLY | Gate now passes fitness age, nutrition, breathing and device; but fitness age is still not answered, charging is not answered, "what to eat tonight" names no food, and breathing now invents figures. |
| Morning brief invented "Strain: 0" and causes | FIXED | `nil`. |
| Program had one exercise per day | PARTLY | Now 2 to 3 per day; still thin. |
| Food macros did not match calories | PARTLY | 10% and 24% off, down from 33% and 40%. |
| Page insights return nothing | FIXED (held) | All `nil` except the honest Strain line. |

## What would confuse or mislead a new user

- Breathing answers state a Recovery, a Strain, a 15% HRV rise and a bedtime habit the person does not have.
- The plan tells a person with no goal to lose 0.4 kg a week, and names a kidney finding.
- Nutrition Q1 says the body is below what it needs "to function" after one unlogged day.
- "2.250 kcal" is read as 2.25 by an English reader; it also appears as "2250" in the same answer.
- Device answers assume a broken connection and read "Bluetooth Low Energy" aloud, and give no pairing or charging steps; one gives an invented button procedure.
- Fitness age is described as living in "a different report" with no definition.
- The canned message says "readings from your strap" to a person who may not have paired one.
- Pages and the brief are silent with no empty-state line saying what to do.
