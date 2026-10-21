## PHMN 1.1.0

Nutrition rebuilt around a daily budget and a diary you can fill by telling Anya, a Lab Book in the Nuna style that Anya can fill from a report, a Weight page, and exercise videos.

### New / Enhancement
- **Nutrition, rebuilt.** A ring shows what is left to eat today, with eaten and active burn beside it; protein, carbs and fat sit against your targets, and the day's food is listed by meal. Step back through earlier days. The gear holds Strategy, Import CSV and a switch for Anya speaking up.
- **Add food.** Tell Anya what you ate in words or with a photo and she estimates each item; type the numbers yourself (calories can be worked out from the macros); or pick from saved and recent foods. Whatever Anya estimates can be edited, item by item, before it is added. A photo goes to the provider you chose only if it can look at pictures; otherwise the iPhone reads food names from it and sends nothing.
- **Strategy and the weekly check-in.** Choose a goal weight and a pace and get a daily target and macros from what your body spends, worked out from your food and weight once there are two weeks of both. Once a week the page compares your trend with your pace and suggests a change to the target, which you apply or keep. Anya can also suggest a whole plan from your profile, weight, food, sleep, recovery, training and, if you share it, the Lab Book, shown against the WHO references; nothing changes until you apply it, and you can discard it.
- **Anya speaks up on Nutrition** when the day runs over or short of your target, or protein lags; when you are already over there is no Add button to mislead.
- **Quick add on Today.** The + sheet shows today's food against the target with an Add food button, and *Log food* is a quick action you can choose.
- **Lab Book in the Nuna style.** A summary ring of the markers inside their range, the ones outside it, then a card per marker with the date, status, change and a bar that shows the reading against the range from your own report. Each marker has its own page with a gauge, the readings over time with their numbers, what the numbers say in words, a comparison with a wearable signal, and a dropdown in the header to move between markers. Weight and waist use the WHO reference when your report gives no range.
- **Add a result.** One sheet to type a result or import a file: a CSV template you can download and fill in (with range and note), any date, marker, value, unit CSV, a WHOOP biomarker export, or a FHIR file from a lab.
- **Anya can fill the Lab Book.** Tell her your results or attach a report (PDF, CSV or FHIR) and they come back as a card to check; CSV and FHIR files are read on the phone without being sent anywhere.
- **Weight page and card.** Weight is a card in Your cards and in Key metrics, and opens a page with the trend, BMI and waist, and body composition when Apple Health has it.
- **Gym exercise demos.** An exercise with an animation has a small switch to a video of it; one with no animation opens straight to the video, and only the player is shown. The GIF option is gone.
- **Gym tab** has Anya at the top, programs grouped in one card with a group dropdown, a muscle map with a link to more details, sets per muscle with body thumbnails, and a history that starts the week on Monday.
- **State chips** are their own section on Today, and chips for important information have a tinted background.

### Bug Fixing
- **The live workout** opens its summary after End, shows distance and pace on the treadmill and for GPS runs, keeps its session bar on every tab, and the heart beats in the colour of the zone.
- **The Effort ring moves during a live workout.** It used to stay still until the session ended.
- **Indonesian translations** were completed across the screens added in this release and the ones before it.

### Install
`PHMN-ios-unsigned.ipa` is **unsigned** and has no Apple Watch app. Sign it with a sideloader (AltStore or SideStore), or yourself: see [docs/SIGNING.md](https://github.com/aansun/PHMNoop/blob/phm/docs/SIGNING.md).
With a free Apple ID, HealthKit is not available to a sideloaded build.

Everything the app shows is an estimate, not medical advice. PHMN is a fork of NOOP and is not affiliated with WHOOP, Inc., Strava or Hevy.
