#if os(iOS)
import StrandDesign

/// One picture for each thing the app names in more than one place, so the same thing never wears two icons: the Quick menu, the lists, the
/// Settings hub and its search, the tiles on Today and the Breathing pages all read their icon from here.
///
/// The rule behind the choices: a body signal that has a drawn WHOOP picture uses it everywhere (`met:`); breathing is the Breathwork activity
/// picture (`act:`); the heart is the filled heart; anything else keeps one plain SF Symbol. A new place that shows one of these things takes
/// the name from here instead of typing a symbol.
enum NunaIcons {
    // Body signals
    static let heartRate = "heart.fill"
    static let hrv = "met:heart-rate-variability"
    static let restingHr = "met:resting-heart-rate"
    static let avgHr = "met:average-heart-rate"
    static let maxHr = "bolt.heart"
    static let respiratory = "met:respiratory-rate"
    static let steps = "met:steps"
    static let calories = "met:calories"
    static let weight = "met:weight"
    static let stress = "met:total-day-stress"

    // Sleep and breathing
    static let sleep = "moon.zzz.fill"
    static let nap = "moon.zzz.fill"
    static let windDown = "moon.stars"
    static let breathing = "act:breathwork"

    // Body and log
    static let cycle = "drop.fill"
    static let water = "drop.fill"
    static let journal = "book"
    static let notifications = "bell"
    static let earlyWarning = "bell.badge"

    // Settings
    static let appearance = "slider.horizontal.3"
    /// The "adjust this feature" button and row: Breathing, Workout and Anya settings all carry it.
    static let featureSettings = "gearshape"
    static let units = "ruler"
    static let filter = "line.3.horizontal.decrease"
    static let finish = "flag.checkered"
    static let discard = "trash"
    static let ai = NunaGlyph.anya
    static let data = "link"
    static let features = "square.and.pencil"
    static let advanced = "wrench.and.screwdriver"
    static let privacy = "lock.shield.fill"
    static let about = "info.circle"
    static let backup = "externaldrive"
}
#endif
