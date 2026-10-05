#if os(iOS)
import SwiftUI
import StrandAnalytics

/// Anya's pick for the Breathing module: the advisor's goal and template, written out with the figures behind it.
struct NunaBreathSuggestion: Equatable {
    var advice: BreathAdvice
    var headline: String
    var detail: String?
    var read: [String]
    var inputs: BreathAdvisorInput
}

@MainActor
enum NunaBreathAdviceMaker {
    /// Reads what the app already holds (today's numbers, the live strap values the screen mirrors, the session history) and
    /// returns the pick. Nothing leaves the phone.
    static func make(repo: Repository, profile: ProfileStore) async -> NunaBreathSuggestion {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        let live = NunaBreathLive.shared
        let input = BreathAdvisorInput(
            bpm: live.worn ? live.bpm : nil, liveRmssd: live.worn ? live.rmssd : nil,
            restingHr: m.restingHr, hrvDelta: m.hrvDelta, restingHrDelta: m.restingHrDelta,
            charge: m.charge.pct, stress: m.stress,
            hour: Calendar.current.component(.hour, from: Date()), pastEffect: NunaBreathLog.pastEffect())
        return describe(BreathAdvisor.advise(input), input)
    }

    static func describe(_ advice: BreathAdvice, _ input: BreathAdvisorInput) -> NunaBreathSuggestion {
        var lines: [String] = [], read: [String] = []
        for r in advice.reasons {
            switch r {
            case .heartRateHigh(let bpm, let above):
                lines.append(String(localized: "Heart rate \(bpm) bpm, \(above) above your resting rate")); read.append("Heart rate")
            case .liveHrvLow(let ms):
                lines.append(String(localized: "HRV over the last beats is low (\(ms) ms)")); read.append("HRV")
            case .stressHigh(let level):
                lines.append(String(localized: "Stress is \(String(format: "%.1f", locale: AppLanguage.activeLocale, level)) of 3 today")); read.append("Stress")
            case .lateEvening(let h):
                lines.append(String(localized: "It is \(String(format: "%02d:00", h)), close to sleep")); read.append("Time of day")
            case .lowCharge(let pct):
                lines.append(String(localized: "Charge is \(pct)%")); read.append("Charge")
            case .hrvDown(let ms):
                lines.append(String(localized: "HRV is \(ms) ms under your baseline")); read.append("HRV")
            case .restingHrUp(let bpm):
                lines.append(String(localized: "Resting heart rate is up \(bpm) bpm")); read.append("Resting HR")
            case .goodChargeMorning(let pct):
                lines.append(String(localized: "Charge is \(pct)% this morning")); read.append("Charge")
            case .daytime:
                lines.append(String(localized: "Nothing in your numbers calls for more")); read.append("Time of day")
            case .noLiveData:
                lines.append(String(localized: "No live heart rate yet, so this follows the time of day")); read.append("Time of day")
            case .workedBefore(let pct):
                lines.append(String(localized: "It raised your HRV \(pct)% in earlier sessions")); read.append("Your history")
            }
        }
        let t = advice.template
        let head = String(localized: "\(advice.goal.shortTitle): \(t.title), \(t.minutes) min")
        var uniqueRead: [String] = []
        for r in read where !uniqueRead.contains(r) { uniqueRead.append(r) }
        return NunaBreathSuggestion(advice: advice, headline: head,
                                    detail: lines.isEmpty ? nil : lines.joined(separator: ". ") + ".",
                                    read: uniqueRead, inputs: input)
    }
}
#endif
