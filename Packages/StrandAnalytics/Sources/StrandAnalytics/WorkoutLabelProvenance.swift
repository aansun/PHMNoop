import Foundation
import WhoopStore

// WorkoutLabelProvenance.swift — whose label is a saved workout's sport?
//
// A saved workout row has a sport name, but that name is not always the PERSON'S word. The auto-detector offers a window with a sport, and one tap on
// "Save it" writes that same name as an ordinary `manual` row (`Repository.saveDetectedWorkout`). A model that learned from those rows would be learning
// from its own guesses, and the more it was right the more it would believe itself. So every saved row is given an ORIGIN, and only some origins are
// a label in the person's own words.
//
// The origin comes from three facts: where the row came from, whether the suggestion log (`workoutSuggestion`, v48) shows that window was offered and
// saved, and whether the log existed yet when the row was made. Pure: no I/O, no clock.
//
// Origins and whether they count as the person's label:
//   typedByPerson          a manual row with no matching saved suggestion               label
//   editedAfterSuggestion  saved under another name than offered, or renamed later      label (the change is a correction, the strongest kind)
//   imported               Apple Health, a Hevy/Liftosaur session, a GPX/TCX/FIT file    label (named by another app or by the person there)
//   manualBeforeLog        a manual row made before the log began                        label WITH A CAVEAT: some may be saved suggestions
//   savedFromSuggestion    saved from a suggestion and left as offered                   NOT a label (it is the detector's own guess)
//   strapOwn               a workout the WHOOP strap or its app named                    NOT a label (not the person's word, and not independent)
//   legacyDetected         an old NOOP-detected bout                                     NOT a label

/// Where a saved workout row came from, in the terms this file needs. The app maps its own `WorkoutSource` onto this.
public enum WorkoutLabelSource: String, Sendable, CaseIterable {
    case manual, whoop, apple, detected, lifting, activityFile
}

/// Whose label a saved workout's sport is. See the file header for what each means.
public enum WorkoutLabelOrigin: String, Sendable, CaseIterable {
    case typedByPerson
    case editedAfterSuggestion
    case imported
    case manualBeforeLog
    case savedFromSuggestion
    case strapOwn
    case legacyDetected

    /// True when the sport is the person's own word (or another app's), so it may be used as ground truth.
    /// `manualBeforeLog` is included only when the caller says it accepts the caveat.
    public func isLabel(includeBeforeLog: Bool) -> Bool {
        switch self {
        case .typedByPerson, .editedAfterSuggestion, .imported: return true
        case .manualBeforeLog: return includeBeforeLog
        case .savedFromSuggestion, .strapOwn, .legacyDetected: return false
        }
    }
}

public enum WorkoutLabelProvenance {

    /// A saved row's start may sit a little off its suggestion's start (the app rounds the duration to whole minutes), so a saved
    /// suggestion matches a row whose start is within this many seconds.
    public static let startToleranceSec = 120

    /// - Parameters:
    ///   - source: where the row came from.
    ///   - sport: the row's sport name.
    ///   - startTs: the row's start, unix seconds.
    ///   - suggestions: the logged suggestions for the same device (any outcome; only `saved` ones matter here).
    ///   - logStartedAt: when the suggestion log began on this device (unix seconds), or nil if it has not. A manual row that starts before it
    ///     cannot be told apart from a saved suggestion, so it is `manualBeforeLog`.
    public static func origin(source: WorkoutLabelSource, sport: String, startTs: Int,
                              suggestions: [WorkoutSuggestionRow], logStartedAt: Int?) -> WorkoutLabelOrigin {
        switch source {
        case .detected: return .legacyDetected
        case .whoop: return .strapOwn
        case .apple, .lifting, .activityFile: return .imported
        case .manual:
            guard let logStartedAt, startTs >= logStartedAt else { return .manualBeforeLog }
            let match = suggestions
                .filter { $0.outcome == WorkoutSuggestionOutcome.saved.rawValue && abs($0.startSec - startTs) <= startToleranceSec }
                .min { abs($0.startSec - startTs) < abs($1.startSec - startTs) }
            guard let match else { return .typedByPerson }
            func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let offered = norm(match.predictedSport)
            let saved = norm(match.savedSport ?? match.predictedSport)
            // Saved under a different name than the card offered: the person picked another sport from the alternatives. That is their word.
            if saved != offered { return .editedAfterSuggestion }
            // Saved as offered, and still that name: the detector's own guess. Renamed since: a correction.
            return norm(sport) == saved ? .savedFromSuggestion : .editedAfterSuggestion
        }
    }
}
