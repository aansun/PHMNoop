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
