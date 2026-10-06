#if os(iOS)
import Foundation

/// What changed in PHMN itself, newest first. NOOP's own release notes stay in `AppChangelog` and are shown under "NOOP history".
enum PHMNChangelog {
    struct Release: Identifiable {
        let version: String
        let title: String
        let date: String
        let items: [String]
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
