import Foundation

/// A conversation Anya opens herself, when the person taps one of her notifications. Nothing is written in advance and nothing is sent until
/// that tap: the opening line is asked for then, from the data as it is at that moment.
enum AnyaCheckIn: String {
    case evening
    case afterWorkout

    /// The identifier of the repeating evening notification, here so the AI master switch can take it down.
    static let eveningRequestId = "anya-evening-checkin"

    var instruction: String {
        switch self {
        case .evening:
            return "(From the app, not typed by the person: they opened your evening check-in. Open the conversation yourself: one or two warm sentences on "
                + "how their day looks, only what matters, then one short question about how it went. No plan yet.)"
        case .afterWorkout:
            return "(From the app, not typed by the person: they opened the summary of the workout they just finished. Open the conversation yourself: one or "
                + "two sentences on that session from its own figures, looking it up if you need to, then one short question about how it felt.)"
        }
    }
}
