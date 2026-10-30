import Foundation

/// Whether the strap's wake alarm is, as far as the app can tell, buzzing right now: the moment a double tap on the strap turns it off.
///
/// The strap fires the alarm on its own, even with the phone asleep, and tells the app only afterwards and not always (the fire event is not
/// reliably observed). So two things count as "ringing", whichever the app knows:
/// - the strap reported the alarm fired (`firedAt`), or
/// - the time the alarm was armed for (`armedFor`) has come.
/// Either holds for `window` seconds, which is longer than the buzz itself (30 s) so a tap a little late still lands. A tap that already turned this
/// ring off (`dismissedAt`) ends it, so the next double tap goes back to doing what the person set it to do.
public enum AlarmRinging {
    /// How long after the alarm time a double tap still turns it off, in seconds.
    public static let window: Double = 120

    public static func isRinging(now: Double, armedFor: Double?, firedAt: Double?, dismissedAt: Double?) -> Bool {
        func within(_ start: Double?) -> Double? {
            guard let start, now >= start, now - start <= window else { return nil }
            return start
        }
        guard let began = [within(armedFor), within(firedAt)].compactMap({ $0 }).min() else { return false }
        if let dismissedAt, dismissedAt >= began { return false }
        return true
    }
}
