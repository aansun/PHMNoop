#if os(iOS)
import Foundation

/// What changed in PHMN itself, newest first. NOOP's own release notes stay in `AppChangelog` and are shown under "NOOP history".
enum PHMNChangelog {
    struct Release: Identifiable {
        let version: String
        let title: String
        let date: String
        /// New and enhanced: a new feature or a change to an existing one.
        let items: [String]
        /// Bug fixes.
        var fixes: [String] = []
        var id: String { version }
    }

    struct Expectation: Identifiable {
        let icon: String
        let title: String
        let body: String
        var id: String { title }
    }

    static let releases: [Release] = [
        Release(
            version: "2.0.0",
            title: "Charge, Effort and Rest follow the day you pick, Effort shows what builds it, and the resting heart rate is the nightly average everywhere; plus a monitor-style heart-rate card, a simpler Compare and a glass strap-sync card.",
            date: "October 2026",
            items: [
                "**Pick a day, see that day.** Charge, Effort and Rest pages open on the day chosen on Today: the caption, the figures, the activities and the weekly and monthly trend card all follow it.",
                "**Effort, explained.** The rows under the ring are the Effort's own bands: Heart Rate Zone 1–3 (50–80% of your heart-rate reserve), Heart Rate Zone 4–5 (80–100%), everyday movement (the part of the day no workout explains) and Resting Heart Rate, which opens its own page. Touch a bar of the week to see that day. Heart rate also sits under the ring during a live workout.",
                "**Resting heart rate is the nightly average, everywhere.** The day's Effort, calories, workout detection and Charge are all scored against the mean of your main sleep, the figure the app shows, and not the lowest value.",
                "**Heart-rate card as a bedside monitor.** Dark screen, graph paper, a green trace and reading, and a dot that pulses at the pace of your heart. Between two signals it keeps the last trace, dated, until a new one arrives.",
                "**Compare, simpler.** Add metrics from a menu and remove them as chips. Wide axes, and a touch reads every metric's figure for that day on one row. Charge and Rest lines are grey and blue.",
                "**Trends.** *Against the previous period* is two rows with thick bars painted in the Today ring colours. Charge and Effort bars are boxes, and capsules only in Flow; touch a day for its figures, and the page still scrolls from the chart.",
                "**Charts you can touch.** Charge and Rest and Fitness and fatigue read their figures for the day touched, with the date at the right.",
                "**Strap sync on the Lock Screen** is a small glass card: status at the left, chunks and time at the right.",
                "**Steps.** The target line and figure follow the daily target you set under Targets, and the weekly Steps widget shows today's steps under the average.",
                "**Pause first, then end.** End, Discard and Reset appear only while a session or timer is paused, in breathing, the workout card and the interval timer.",
                "**Flow colours.** Warning and alert colours are clearer in Flow, the three-second countdown is readable on every theme, and the figures that appear when you touch the Charge and Effort chart are readable on every theme.",
            ],
            fixes: [
                "**Range and chip agree.** The shaded typical range of a metric is the mean plus and minus one spread, the same line the In range / Above range chip uses.",
                "**Workout Effort backfill** uses your resting heart rate, not a default of 60.",
                "**Charts no longer trap a vertical swipe**, so the page scrolls when a finger starts on a chart.",
            ]
        ),
        Release(
            version: "1.2.0",
            title: "The Flow look, capsule charts for Charge and Effort, a Banner design for the workout Live Activity, a gym session you can change as you go, and gym sessions on Strava with their sets.",
            date: "October 2026",
            items: [
                "**Flow look.** A third style beside Default and WHP: a warm cream-and-berry palette with rounded shapes, Fraunces figures and Plus Jakarta Sans text, following Light, Dark or Automatic.",
                "**Charge and Effort as capsules.** Today and Trends show Charge as capsules and Effort as a line; touch a bar for its figure in any range. The card opens the Charge and Effort page.",
                "**Banner Live Activity.** A second Lock Screen design: the clock, the PHMN mark and the heart rate above; the five zones and two figures below (distance and pace on a route, otherwise steps or calories). Pick it in Optional features, with a preview.",
                "**Gym, as you go.** Preview a program's exercises, replace one for next time or for this session only, start from any exercise, continue on its own after the rest, add custom exercises, and keep the screen on. A session comes back after the app is closed.",
                "**Anya builds a gym program** from a target and your instructions, and **makes custom breathing exercises**.",
                "**Breathing audio.** Off, soft tones, or Anya's voice saying each step; the timer follows the clock.",
                "**Strava for gym.** A gym session goes up as a strength activity with its sets, calories and heart rate; if that is refused, it goes as an activity with the sets in the description.",
                "**Post-workout gym.** Anya's line comes before the photos; Strava and Apple Health are in the three-dots menu.",
                "**Quick actions.** The food button reads *+Catat* (*+Log*), as wide as *+250*; the meal pill has a clear fill.",
            ],
            fixes: [
                "**Light stays light.** Switching to Light in the Nuna look is no longer undone.",
                "**Score rings** keep a full track in every style and theme, and the Fitness age orb reads on light themes.",
                "**Scrolling** on Today and Trends is smoother, and the tab bar shows only on the main page of a tab.",
                "**The live workout** shows End only while paused, and switches between Effort and Heart rate at once.",
            ]
        ),
        Release(
            version: "1.1.0",
            title: "Nutrition rebuilt around a daily budget and a diary you can fill by telling Anya, a Lab Book in the Nuna style that Anya can fill from a report, a Weight page, and exercise videos.",
            date: "October 2026",
            items: [
                "**Nutrition, rebuilt.** A ring shows what is left to eat today, with eaten and active burn beside it; protein, carbs and fat sit against your targets, and the day's food is listed by meal. Step back through earlier days. The gear holds Strategy, Import CSV and a switch for Anya speaking up.",
                "**Add food.** Tell Anya what you ate in words or with a photo and she estimates each item; type the numbers yourself (calories can be worked out from the macros); or pick from saved and recent foods. Whatever Anya estimates can be edited, item by item, before it is added. A photo goes to the provider you chose only if it can look at pictures; otherwise the iPhone reads food names from it and sends nothing.",
                "**Strategy and the weekly check-in.** Choose a goal weight and a pace and get a daily target and macros from what your body spends, worked out from your food and weight once there are two weeks of both. Once a week the page compares your trend with your pace and suggests a change to the target, which you apply or keep. Anya can also suggest a whole plan from your profile, weight, food, sleep, recovery, training and, if you share it, the Lab Book, shown against the WHO references; nothing changes until you apply it, and you can discard it.",
                "**Anya speaks up on Nutrition** when the day runs over or short of your target, or protein lags; when you are already over there is no Add button to mislead.",
                "**Quick add on Today.** The + sheet shows today's food against the target with an Add food button, and *Log food* is a quick action you can choose.",
                "**Lab Book in the Nuna style.** A summary ring of the markers inside their range, the ones outside it, then a card per marker with the date, status, change and a bar that shows the reading against the range from your own report. Each marker has its own page with a gauge, the readings over time with their numbers, what the numbers say in words, a comparison with a wearable signal, and a dropdown in the header to move between markers. Weight and waist use the WHO reference when your report gives no range.",
                "**Add a result.** One sheet to type a result or import a file: a CSV template you can download and fill in (with range and note), any date, marker, value, unit CSV, a WHOOP biomarker export, or a FHIR file from a lab.",
                "**Anya can fill the Lab Book.** Tell her your results or attach a report (PDF, CSV or FHIR) and they come back as a card to check; CSV and FHIR files are read on the phone without being sent anywhere.",
                "**Weight page and card.** Weight is a card in Your cards and in Key metrics, and opens a page with the trend, BMI and waist, and body composition when Apple Health has it.",
                "**Gym exercise demos.** An exercise with an animation has a small switch to a video of it; one with no animation opens straight to the video, and only the player is shown. The GIF option is gone.",
                "**Gym tab** has Anya at the top, programs grouped in one card with a group dropdown, a muscle map with a link to more details, sets per muscle with body thumbnails, and a history that starts the week on Monday.",
                "**State chips** are their own section on Today, and chips for important information have a tinted background.",
            ],
            fixes: [
                "**The live workout** opens its summary after End, shows distance and pace on the treadmill and for GPS runs, keeps its session bar on every tab, and the heart beats in the colour of the zone.",
                "**The Effort ring moves during a live workout.** It used to stay still until the session ended.",
                "**Indonesian translations** were completed across the screens added in this release and the ones before it.",
            ]
        ),
        Release(
            version: "1.0.0",
            title: "Gym summary redesigned, tappable explanations on Today, a Trends header that pages through your history, and fixes for workouts that lost their targets when the app was away",
            date: "October 2026",
            items: [
                "**Gym summary, redesigned.** The page opens with the date and program, the Activity Effort with its 30-day average and the cardio and muscular share beside it, then key statistics for lifting (volume, sets, reps, duration, heart rate, calories). Two tabs below: **Exercises**, where each exercise opens to its sets, its record and its demo, and **Heart rate zones**, with the curve and the zones. Save as program, Edit sets and Delete are in the three dots.",
                "**The chips under the rings explain themselves.** Tap Solid, Last night, Calibrating or No data to see why Charge is in that state, what to do, and what the green, yellow, red and grey dot mean. Tap Push, Maintain or Rest to see the signals behind your readiness, each with its figure and flag.",
                "**Trends pages through your history.** Week, month, six months and year now sit beside the title with a date stepper under them, the same controls as every metric card, and the arrows move to earlier periods.",
                "**Key metrics tiles** use the vital signs design: icon and label, the value, and the change as a chip beneath. With trend lines on, every tile is the same height.",
                "**Early warning** no longer takes a card on Today. It arrives in the notifications bell once a day per level, Anya adds one short line, and the full page is still in quick actions.",
                "**What's new** follows the latest GitHub release by itself, and shows each release in two groups, New / Enhancement and Bug Fixing.",
                "**More room in the target sheet**, between the effort figures, the bar and Anya's line.",
                "**Demo data** includes a finished gym session, so the gym screens can be looked at without logging one.",
            ],
            fixes: [
                "**Targets survive the app being away.** After a few minutes in another app, iOS can end PHMN; the workout was restored but its time, distance and zone targets were lost, so the strap stopped buzzing and the audio coach went quiet. The targets are now saved with the workout and come back with it.",
                "**\"Start workout\" is not said twice.** A workout picked up after the app was reopened no longer announces its start again, and a time target already passed is not announced a second time.",
                "**The screen stays on during a live workout** after you lock the phone or visit another app. The setting is asked for again every time the app comes back, and a finished Strava or Oura task no longer releases it.",
                "**The summary opens at once** after End and save, instead of waiting on a *Saving activity* page.",
                "**Metric tiles no longer shift** when one has no history yet, and the figures of the Effort rows (such as Strength training time) line up with the rest.",
            ]
        ),
        Release(
            version: "0.1.3",
            title: "A new Effort target for an activity, a heart rate that beats in its zone colour, treadmill on Strava, and a clearer night.",
            date: "October 2026",
            items: [
                "**Effort target, redone.** Choose Time or Distance (one of them, or neither) and, with either or alone, a heart-rate zone. The sheet shows Effort now, the target and the day after it, against the range that suits today. Time starts at 30 minutes; distance has 3, 5, 10, 15, half marathon and marathon. Anya's session for today is the default and sits in one line at the bottom.",
                "**Heart rate as a beating disc** in the colour of the zone, on the start screen and on the live Heart rate tab. The zone bar dims the zones you are not in.",
                "**Workout summary in a new order**: date, Effort and duration, the map, the key statistics, the heart-rate curve and the zones. Tap a zone and its stretches light up on the curve, at their time and length. Photos and how it felt come last.",
                "**Treadmill on Strava** goes up as a Run or a Walk marked indoor, not as a Virtual Run, and the file says treadmill. With no distance measured, one is estimated from steps and height. **Edit activity** on a saved session lets you set the distance, the time and more after the fact.",
                "**Rest**: the wake-ups card is folded into Efficiency as *Brief awakenings*.",
                "**Activity settings** on the start screen has a shortcut to the audio coach.",
                "**Weather and air** (OpenWeather and IQAir, your own keys, off by default). Anya reads them on Today, in her suggestion for a session and after you train; the daily brief takes them into account too. Only your place, rounded to about a kilometre, is ever sent.",
                "**Steps this week widget**: the week's total, a bar per day, and dashed lines for your average and your target.",
                "**The Anya sheet** shows the headline and the detail as one paragraph, with a little colour for good and bad news, and has Read and Ask tabs; each sheet keeps its own conversation. The Anya tab is tidier.",
                "Anya reads the day with the time of day, the session the Plan card suggests and the journal factors behind a poor night.",
            ],
            fixes: [
                "**Rest**: the sleep need now adds your sleep debt when no stored need exists (it showed 0 before).",
                "**The daily Anya brief** no longer waits for the Anya tab: it is armed when the app opens and made when its time has passed.",
            ]
        ),
        Release(
            version: "0.1.2",
            title: "Gym becomes a module of its own, with an audio coach, Hevy and Strava, and a Today that lists the day.",
            date: "October 2026",
            items: [
                "**Gym is its own tab** in Workouts (Workout, Gym, Insight). Programs, which you can group into folders; a full-screen session in the style of Hevy with sets, weight, reps, RPE, a rest timer and a tone when the rest ends; and a library of 876 exercises with photos and the muscles each one works. A body map shows which muscles are trained and which are still tired. Every way into Gym opens that tab.",
                "**A program has its own page**: the whole name, the exercises and what they add up to, **Start** at the bottom and a menu to edit or delete. The session reads *Program gym*, or *Gym* when it has no program.",
                "**Audio coach** in the workout settings: spoken cues for heart-rate zones and distance, with a test button that says what the phone did.",
                "**Hevy, read only.** Import your workouts and routines with your own API key. Nothing is ever written to Hevy; the Hevy API is part of Hevy Pro.",
                "**Gym on Strava.** A gym session you log in PHMN can go to Strava (by hand, or automatically). Sessions that came from Hevy or Apple Health never do. Bring your own Strava key; it needs a Strava premium account.",
                "**Today lists the day.** One card with the night's sleep and every workout in the order they happened, each opening its own detail. Anya stays on Today after a workout instead of disappearing for an hour. Key Metrics and Your cards keep their title and buttons inside the card, and *Detailed tiles* now draws the trend lines.",
                "**Health › Body has a Training section** with the last seven days, the load balance and a way into Workouts. Mood check-in is left to Today and the journal.",
                "**Water, in the same look as Steps**: a W / M / 6M trend with the goal as a dashed line. The amount the water button adds is set in Customize quick actions.",
                "**Cleaner tabs and controls.** Page tabs are underlined, and settings and edit controls are plain icons.",
            ],
            fixes: [
                "Starting a gym session from a sheet opens it at once.",
                "Finishing or discarding no longer leaves a *No session running* screen, and the Live Activity ends with the session.",
                "The Effort of a gym session is the same on Today and in its detail.",
                "A gym start no longer disappears when it is begun from Quick actions.",
            ]
        ),
        Release(
            version: "0.1.1",
            title: "Workout detail, rebuilt around the session",
            date: "October 2026",
            items: [
                "**One layout for every sport.** A saved session reads the same way: when it ran and the Effort it added, Anya's line, the map when a route was recorded, a summary that fits the sport, the heart-rate curve, the zones, photos, how it felt, and Strava. Runs, rides and swims lead with distance and pace or speed; classes and court sports with time, calories and heart rate; gym sessions with volume, sets and each exercise.",
                "**Zones you can read.** Each zone has its bpm range, minutes, share and a bar sized against your longest zone.",
                "**Review a session.** Slide to say how it felt, add photos as a carousel, and see where it stands with Strava (the logo, ticked when uploads are automatic). Photos and answers stay on the phone.",
                "**Pin up to 8 workouts** to Start a workout. Tap Edit to choose, or press and hold any workout.",
                "**Anya cards open on their own line.** Tapping a card with a figure in it opens the sheet about that figure, not a general read. The explain button no longer carries an icon.",
                "**Today's Anya card with an action** puts the words across the full width and a small translucent button under them.",
            ]
        ),
        Release(
            version: "0.1.0",
            title: "The first PHMN: NOOP's engine, rebuilt around reading your day",
            date: "October 2026",
            items: [
                "**Nuna design.** Today, Health, Trends, Anya and Me are redrawn, in two styles (Default and WHP). Charge, Effort and Rest stay pinned as rings at the top of Today, and every metric opens one card with a W / M / 6M switch.",
                "**Anya follows your day.** The card on Today shows the morning plan with today's Effort target, the session while it runs, what a finished session earned against the target, a rest note once the target is met, and a journal prompt after 20:00.",
                "**Deep timeline.** A signal dropdown, your sleep and workouts marked on the day, and the latest reading at the right edge. Pinch to zoom, hold and drag to read.",
                "**Stress.** Today shows the last hour's average, an arrow against your own baseline, the day's high-stress time and the curve with the latest reading on it. The all-day chart carries the peak, the lowest and the latest, and hold-and-drag reads any hour.",
                "**Journal.** A week strip, check or cross answers, steppers, your own questions, an evening reminder and a link to the Mood check-in.",
                "**Me.** Settings are grouped, search reaches the individual setting (try \"live activity\"), and the ones you opened last are listed.",
                "**Widgets and Live Activities.** Score, Vital sign, Heart rate, Stress, Anya, Steps and Rings, and Live Activities for workouts, lift sessions and strap sync.",
                "**Anya on a metric screen** reads that metric: the latest reading, against the day before and against your own average, with questions about it.",
                "**Footnotes.** \"What affects it\" and \"How it's calculated\" are quiet notes at the foot of a detail screen.",
            ]
        ),
    ]

    static let expectations: [Expectation] = [
        Expectation(
            icon: "person",
            title: "A personal project",
            body: "PHMN is built around how I read my own day. It may not fit yours, and nothing here is a promise."),
        Expectation(
            icon: "checkmark.seal",
            title: "On NOOP's engine",
            body: "Strap protocol, storage, sleep staging and scoring are NOOP's, unchanged. WHOOP 4.0 is the tested path; 5.0 and MG are newer."),
        Expectation(
            icon: "hourglass",
            title: "Scores build over a few nights",
            body: "Live heart rate is instant. Charge, Effort and Rest sharpen as PHMN learns your baseline over your first nights of wear."),
        Expectation(
            icon: "lock.shield",
            title: "Everything stays on this iPhone",
            body: "No account, no cloud. Everything shown is an estimate, not medical advice, and PHMN is not affiliated with WHOOP."),
    ]
}
#endif
