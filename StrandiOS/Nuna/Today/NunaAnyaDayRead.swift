#if os(iOS)
import Foundation

/// What Anya reads from the day to decide how it should end: whether the body is still wound up and breathing before bed is worth the
/// five minutes, whether to go straight to sleep, or whether sleep should come early. Every sentence cites the figures behind it, and the
/// decision is made on this iPhone from numbers the app already holds. No model is involved.
struct NunaAnyaDayInputs {
    var hour: Int
    var minutesSinceWorkout: Int?
    /// Live heart rate while the strap is on and connected.
    var bpm: Int?
    var restingHr: Double?
    /// Latest stress reading (0 to 3) and the minutes of the day already spent in the high band.
    var stressNow: Double?
    var stressHighMin: Int?
    var sleepMin: Double?
    var sleepNeedMin: Double
    var effort: Double?
    var targetLow: Double?
    var targetHigh: Double?
    var hrvDelta: Double?
    var restingHrDelta: Double?
}

enum NunaAnyaDayAction: Equatable { case breathe, windDown, none }

struct NunaAnyaDayVerdict: Equatable {
    var title: String
    var detail: String
    var action: NunaAnyaDayAction
}

enum NunaAnyaDayRead {
    /// Nil only when there is nothing at all to base a read on.
    static func evening(_ i: NunaAnyaDayInputs, effortShown: (Double) -> String) -> NunaAnyaDayVerdict? {
        func f1(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }

        // What the body is doing now.
        let above: Int? = (i.bpm != nil && i.restingHr != nil) ? Int((Double(i.bpm!) - i.restingHr!).rounded()) : nil
        let cooling = (i.minutesSinceWorkout ?? Int.max) < 90
        let activated = (above ?? 0) >= 15
        let stressHigh = (i.stressNow ?? 0) >= 1.8 || ((i.stressHighMin ?? 0) >= 180 && (i.stressNow ?? 0) >= 1.3)
        // What the night before and the day cost.
        let need = i.sleepNeedMin
        let shortBy = i.sleepMin.map { need - $0 } ?? 0
        let sleepShort = shortBy >= 45
        let overshoot = (i.effort != nil && i.targetHigh != nil) ? i.effort! > i.targetHigh! * 1.15 : false
        let strained = (i.hrvDelta ?? 0) <= -8 || (i.restingHrDelta ?? 0) >= 4

        var facts: [String] = []
        if let bpm = i.bpm, let above { facts.append(String(localized: "heart rate \(bpm), \(above) over your resting rate")) }
        if let s = i.stressNow { facts.append(String(localized: "stress \(f1(min(max(s, 0), 3))) of 3")) }

        // 1. Just trained and still up: let it settle, then breathe.
        if cooling && activated, let m = i.minutesSinceWorkout {
            return .init(title: String(localized: "Let your body settle first"),
                         detail: sentence([String(localized: "Your session ended \(m) min ago")] + facts)
                            + " " + String(localized: "Water and a shower now, then five minutes of breathing before bed."),
                         action: .breathe)
        }
        // 2. Wound up or stressed late in the day: breathing is worth it.
        if activated || stressHigh {
            var why = facts
            if (i.stressHighMin ?? 0) >= 60 { why.append(String(localized: "\(StressTrace.clock(minutes: i.stressHighMin ?? 0)) hours of high stress today")) }
            return .init(title: String(localized: "Five minutes of breathing before bed is worth it"),
                         detail: sentence(why) + " " + String(localized: "A slow breath out lowers it, and sleep starts easier."),
                         action: .breathe)
        }
        // 3. Calm, but the night or the day asks for more sleep.
        if sleepShort || overshoot || strained {
            var why: [String] = []
            if sleepShort, let s = i.sleepMin { why.append(String(localized: "last night was \(hm(s)) against the \(hm(need)) you need")) }
            if overshoot, let e = i.effort, let hi = i.targetHigh { why.append(String(localized: "Effort \(effortShown(e)) is above today's band (up to \(effortShown(hi)))")) }
            if strained {
                if let d = i.hrvDelta, d <= -8 { why.append(String(localized: "HRV is \(Int(abs(d).rounded())) ms under your baseline")) }
                else if let d = i.restingHrDelta, d >= 4 { why.append(String(localized: "resting heart rate is up \(Int(d.rounded())) bpm")) }
            }
            return .init(title: String(localized: "No breathing needed, but go to bed early"),
                         detail: sentence(facts.prefix(1).map { $0 } + why) + " " + String(localized: "Sleep is what puts it back."),
                         action: .windDown)
        }
        // 4. Calm and rested: straight to sleep.
        if facts.isEmpty && i.effort == nil { return nil }
        var calm = facts
        if let e = i.effort, let lo = i.targetLow, let hi = i.targetHigh, e >= lo { calm.append(String(localized: "Effort \(effortShown(e)) is in today's band")) }
        return .init(title: String(localized: "You can go straight to sleep"),
                     detail: sentence(calm) + " " + String(localized: "Nothing in your numbers asks for more."),
                     action: .none)
    }

    /// The same read in the middle of the day, once the Effort target is reached: what to do with the rest of it.
    static func targetReached(_ i: NunaAnyaDayInputs, effortShown: (Double) -> String, band: String) -> NunaAnyaDayVerdict? {
        guard let e = i.effort, let hi = i.targetHigh else { return nil }
        if e > hi * 1.15 {
            return .init(title: String(localized: "That is more than enough for today"),
                         detail: String(localized: "Effort \(effortShown(e)) is above the \(band) band. More training now costs tomorrow's Charge: drink, eat well and sleep early."),
                         action: .windDown)
        }
        if let d = i.hrvDelta, d <= -8 {
            return .init(title: String(localized: "Target reached, so stop here"),
                         detail: String(localized: "Effort \(effortShown(e)) is in the \(band) band, and HRV is \(Int(abs(d).rounded())) ms under your baseline. Keep the rest of the day easy."),
                         action: .none)
        }
        return .init(title: String(localized: "Target reached, you are done for today"),
                     detail: String(localized: "Effort \(effortShown(e)) is in the \(band) band. The rest of the day is for eating, drinking and an early night."),
                     action: .none)
    }

    private static func sentence(_ parts: [String]) -> String {
        guard !parts.isEmpty else { return "" }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60)h \(m % 60)m"
    }
}
#endif
