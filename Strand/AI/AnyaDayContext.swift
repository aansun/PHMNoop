import Foundation

/// The "right now" block of Anya's context: what time of day it is, the session the Plan card suggests, the Effort already
/// banked today and this week, and tonight's sleep need with a bedtime that follows from it.
///
/// Before this block Anya did not know the time, so it answered "Have I done enough today?" at 08:00 and at 21:00 the same
/// way, and it could not tell a morning planning question from an evening review. It also worked its own training direction
/// out of the Charge band, which could differ from the session the Plan card shows. Everything here is derived from numbers
/// the phone already holds and goes out as plain sentences, never raw readings.
///
/// Pure (Foundation only) so it is unit-testable with no store, strap or network. The data is gathered by the Nuna builder.
enum AnyaDayContext {

    struct Input {
        var now: Date
        var calendar: Calendar = .current
        /// Today's Charge, 0-100.
        var chargePct: Double?
        /// The Plan card's session, in the same words as the card.
        var sessionTitle: String?
        /// The session kind the plan chose: "recovery", "easy", "steady" or "quality".
        var sessionKind: String?
        var sessionMainZone: Int?
        /// Estimated Effort the session adds, on the stored 0-100 axis (nil under three sessions of history).
        var sessionEffortLow: Double?
        var sessionEffortHigh: Double?
        /// Effort banked so far today, stored 0-100 axis.
        var todayEffort: Double?
        /// The band of daily Effort worth aiming for at today's Charge (the one the Today card judges by), stored axis.
        var effortTargetLow: Double?
        var effortTargetHigh: Double?
        /// The wearer's typical daily Effort (a median of recent scored days).
        var usualEffort: Double?
        /// Effort summed over the last seven days including today.
        var weekEffort: Double?
        var weeklyEffortGoal: Double?
        /// Personal sleep need and the recency-weighted debt, minutes.
        var sleepNeedMin: Double?
        var sleepDebtMin: Double?
        /// Habitual midsleep as local seconds since midnight.
        var habitualMidsleepSec: Int?
        /// How the last few sessions felt, in the person's own rating, newest first ("Running, Challenging").
        var sessionFeelings: [String] = []
        /// The weather and air where the wearer is, as plain sentences, and what they mean for training: "good", "adjust" or "indoors".
        /// nil when the wearer has not turned weather and air on, or the reading is old.
        var outdoorLine: String?
        var outdoorLevel: String?
    }

    // MARK: Parts of the day

    enum Part: String, Equatable { case morning, midday, afternoon, evening, night }

    static func part(hour: Int) -> Part {
        switch hour {
        case 4..<11: return .morning
        case 11..<14: return .midday
        case 14..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }

    /// Clock time "HH:mm" for seconds after local midnight, wrapping around the day.
    static func clock(seconds: Int) -> String {
        let s = ((seconds % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// When to be asleep so the night is centred on the habitual midsleep and lasts `needMin`.
    static func asleepBySec(midsleepSec: Int, needMin: Double) -> Int {
        midsleepSec - Int((needMin * 60 / 2).rounded())
    }

    // MARK: Block

    /// The clock line is always present; each further line is added only when its numbers exist.
    static func block(_ i: Input) -> String {
        let cal = i.calendar
        let hour = cal.component(.hour, from: i.now)
        let minute = cal.component(.minute, from: i.now)
        let part = part(hour: hour)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEEE d MMMM"
        var lines: [String] = []

        var clockLine = "RIGHT NOW: \(fmt.string(from: i.now)), \(String(format: "%02d:%02d", hour, minute)) (\(part.rawValue))."
        switch part {
        case .morning, .midday:
            clockLine += " This is the planning part of the day: when asked what to do today, anchor on the suggested session below and the Effort already banked."
        case .afternoon:
            clockLine += " The day is half done: judge a training question by the Effort already banked and by how much daylight and energy are left."
        case .evening, .night:
            clockLine += " This is the review part of the day: when asked how the day went, say what its Effort and the night ahead imply and point to bedtime, not to a new hard session."
        }
        lines.append(clockLine)

        // Effort so far, against what is usual and against the week.
        var effort: [String] = []
        if let t = i.todayEffort, t > 0 {
            var s = "Effort so far today \(oneDecimal(t))"
            if let u = i.usualEffort, u > 0 { s += " (a usual day is about \(oneDecimal(u)))" }
            effort.append(s)
        } else if i.todayEffort != nil {
            effort.append("no Effort banked yet today")
        }
        if let lo = i.effortTargetLow, let hi = i.effortTargetHigh {
            effort.append("the Effort worth aiming for at today's Charge is \(Int(lo.rounded()))-\(Int(hi.rounded()))")
        }
        if let w = i.weekEffort, w > 0 {
            var s = "last 7 days \(Int(w.rounded()))"
            if let g = i.weeklyEffortGoal, g > 0 { s += " of the weekly target \(Int(g.rounded()))" }
            effort.append(s)
        }
        if !effort.isEmpty { lines.append("EFFORT (0-100 axis): " + effort.joined(separator: "; ") + ".") }

        // The Plan card's session. Anya must not contradict it unless the person gives a reason to change it.
        if let title = i.sessionTitle {
            var s = "TODAY'S SUGGESTED SESSION (the same one the Plan card shows; do not contradict it unless the person gives a reason): \(title)"
            if let z = i.sessionMainZone { s += ", main work in zone \(z)" }
            if let lo = i.sessionEffortLow, let hi = i.sessionEffortHigh {
                s += ", about +\(Int(lo.rounded()))-\(Int(hi.rounded())) Effort"
            }
            s += "."
            if let c = i.chargePct { s += " It was chosen from a Charge of \(Int(c.rounded()))."}
            lines.append(s)
        }

        // The person's own rating of recent sessions: the one signal the strap cannot measure.
        if !i.sessionFeelings.isEmpty {
            lines.append("HOW RECENT SESSIONS FELT (the person's own rating, newest first): " + i.sessionFeelings.prefix(3).joined(separator: "; ") + ".")
        }

        // Tonight: need, debt, and the bedtime that follows.
        if let need = i.sleepNeedMin, need > 0 {
            var s = "SLEEP TONIGHT: personal need about \(hours(need))"
            if let d = i.sleepDebtMin, d >= 10 { s += ", with a recent debt of about \(hours(d))" }
            else if i.sleepDebtMin != nil { s += ", no meaningful debt" }
            if let mid = i.habitualMidsleepSec {
                s += "; centred on the usual midsleep \(clock(seconds: mid)), being asleep by about \(clock(seconds: asleepBySec(midsleepSec: mid, needMin: need)))"
            }
            s += ". Debt is repaid over several nights: never ask for more than about 45 minutes of extra sleep in one night."
            lines.append(s)
        }
        // The weather and air, read a moment ago: a reason to shorten, move or shift a session, never a forecast for later in the week.
        if let o = i.outdoorLine {
            lines.append("OUTDOORS (read recently, treat as now): \(o) When the person asks what to do today, or how a session went, let these conditions shape the answer: heat and bad air raise heart rate for the same pace, so judge by effort, and move the session indoors or to a kinder hour when the level says so.")
        }
        if let step = nextStep(i) {
            lines.append("NEXT STEP (worked out from the numbers above, for this moment; close the answer with it unless the question points elsewhere): \(step)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Next step

    /// The one thing worth doing next, from the time of day, the plan, the Effort already banked and the night ahead. Anya is
    /// told to close with it, so its advice follows the person's situation and is the same one the numbers give.
    static func nextStep(_ i: Input) -> String? {
        let cal = i.calendar
        let hour = cal.component(.hour, from: i.now)
        let nowSec = hour * 3600 + cal.component(.minute, from: i.now) * 60
        let part = part(hour: hour)
        let banked = i.todayEffort ?? 0
        let debt = i.sleepDebtMin ?? 0

        var bedSec: Int?
        if let mid = i.habitualMidsleepSec, let need = i.sleepNeedMin, need > 0 {
            bedSec = ((asleepBySec(midsleepSec: mid, needMin: need) % 86_400) + 86_400) % 86_400
        }
        /// Minutes until the target bedtime (0...1439), wrapping past midnight.
        let minutesToBed = bedSec.map { ((($0 - nowSec) % 86_400) + 86_400) % 86_400 / 60 }
        let bed = bedSec.map { clock(seconds: $0) }

        // Judged by the same band the Today card uses, so the card and Anya never disagree about whether the day's load is done.
        let sessionDone: Bool = {
            if let lo = i.effortTargetLow { return banked >= lo && banked > 0 }
            if let lo = i.sessionEffortLow, banked >= lo, banked > 0 { return true }
            if let u = i.usualEffort, u > 0, banked >= u { return true }
            return false
        }()

        // Evening and night: the night is the next thing, whatever the plan says.
        if part == .evening || part == .night {
            if hour < 4 {
                return "It is the middle of the night: put sleep first and skip anything hard."
            }
            if let m = minutesToBed, let bed {
                if m > 20 * 60 {
                    return "It is already past the target bedtime of \(bed): stop, wind down and sleep, and skip anything hard."
                }
                if m <= 90 {
                    var s = "Wind down now, lights low and nothing hard, and be asleep by \(bed)."
                    if debt >= 60 { s += " About \(hours(debt)) of sleep debt is carried, so this night matters." }
                    return s
                }
            }
            let tail = bed.map { " so you can be asleep by \($0)" } ?? ""
            if sessionDone {
                return "The day's load is done. Eat, hydrate and keep the evening easy\(tail)."
            }
            if part == .evening, let c = i.chargePct, c >= 50, (minutesToBed ?? 240) >= 180 {
                let by = bed.map { ", finished at least two hours before \($0)" } ?? ""
                return "There is still room for a short easy session, 20 to 30 minutes in zone 1 or 2\(by)."
            }
            return "Keep the evening light\(tail)."
        }

        // The day is still going.
        if sessionDone {
            var s = "The planned load is already banked today. Recover well with food, water and easy movement."
            if let bed { s += " Aim to be asleep by \(bed)." }
            return s
        }
        guard let title = i.sessionTitle, let kind = i.sessionKind else {
            return "There is no Charge to plan from yet: wear the strap overnight and sync, and keep to easy movement until then."
        }
        var s: String
        switch kind {
        case "recovery":
            s = "Keep today easy: \(title). The numbers ask for recovery, not training."
        case "easy", "steady":
            s = "Do the suggested session, \(title), and keep it conversational."
        default:
            s = "A quality session fits today: \(title). Warm up properly and stop if it feels wrong."
            if let m = minutesToBed, m < 4 * 60 {
                s = "A hard session is too close to bedtime: make it easy (\(title) in zone 2) or move it to tomorrow morning."
            }
        }
        // Conditions outside come before the plan: the same session, indoors or easier, is still the right session.
        if kind != "recovery" {
            if i.outdoorLevel == "indoors" {
                s = "It is poor outside today (see OUTDOORS): do \(title) indoors, on a treadmill or a trainer, or move it to a better day."
            } else if i.outdoorLevel == "adjust" {
                s += " Outside is not ideal (see OUTDOORS): keep it shorter and easier, or pick a kinder hour."
            }
        }
        if debt >= 60, let bed { s += " With about \(hours(debt)) of sleep debt, be asleep by \(bed) tonight." }
        return s
    }

    private static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    private static func hours(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}
