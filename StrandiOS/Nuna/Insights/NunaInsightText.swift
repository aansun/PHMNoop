#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// The sentences Anya writes on the detail screens, composed from the reads in `InsightReads`. Each says what is behind a figure and
/// what to do about it; none of them restates what the screen already shows. Everything is localised through the string catalog.
enum NunaInsightText {

    // MARK: Sleep

    static func duration(_ minutes: Int) -> String {
        let m = max(minutes, 0)
        return m >= 60 ? String(localized: "\(m / 60)h \(m % 60)m") : String(localized: "\(m) min")
    }

    /// Why the night scored as it did, and what to do about it tonight.
    static func sleep(_ r: SleepRead, factors: NunaSleepFactorContext? = nil, wakeDay: String? = nil) -> String {
        let p = sleepParts(r, factors: factors, wakeDay: wakeDay)
        return p.why + " " + p.action
    }

    static func sleepParts(_ r: SleepRead, factors: NunaSleepFactorContext? = nil, wakeDay: String? = nil) -> (why: String, action: String) {
        var why: String
        switch r.verdict {
        case .heldBack(.duration):
            let short = max(-r.durationGapMin, 0)
            why = short < 10 ? String(localized: "Time asleep held this night back, just under what you need.")
                             : String(localized: "Time asleep held this night back: you got \(duration(short)) less than you need.")
            if let d = r.debtMin, d >= 30 { why += " " + String(localized: "That adds to \(duration(d)) of sleep debt.") }
        case .heldBack(.efficiency):
            if let n = r.wakeEvents, let a = r.awakeMin, n > 0 {
                why = String(localized: "Broken sleep held this night back: \(n) wake-ups and \(duration(a)) awake in bed.")
            } else {
                why = String(localized: "Broken sleep held this night back: too much of your time in bed was spent awake.")
            }
        case .heldBack(.restorative):
            if let d = r.deepDeltaPct, d <= -10 {
                why = String(localized: "Deep sleep held this night back: \(-d)% less than your usual.")
            } else if let d = r.remDeltaPct, d <= -10 {
                why = String(localized: "REM sleep held this night back: \(-d)% less than your usual.")
            } else {
                why = String(localized: "Deep and REM made up a smaller share of the night than usual.")
            }
        case .heldBack(.consistency):
            if let s = r.bedShiftMin, abs(s) >= 20 {
                why = s > 0 ? String(localized: "An irregular bedtime held this night back: you fell asleep \(duration(s)) later than your usual.")
                            : String(localized: "An irregular bedtime held this night back: you fell asleep \(duration(-s)) earlier than your usual.")
            } else {
                why = String(localized: "A bedtime that moves around has been costing Rest lately.")
            }
        case .carriedBy(.duration):
            why = r.durationGapMin >= 15 ? String(localized: "A full night did the work: you slept \(duration(r.durationGapMin)) past what you need.")
                                         : String(localized: "You covered what you need, and that carried this night.")
        case .carriedBy(.efficiency):
            why = String(localized: "You stayed asleep: very little of the night was spent awake.")
        case .carriedBy(.restorative):
            if let d = r.deepDeltaPct, d >= 10 { why = String(localized: "A restorative night: deep sleep ran \(d)% above your usual.") }
            else { why = String(localized: "A restorative night: a good share of deep and REM.") }
        case .carriedBy(.consistency):
            why = String(localized: "A regular bedtime held this night up.")
        case .balanced:
            why = String(localized: "A balanced night: no one part stands out.")
        }
        switch r.body {
        case .supportive: why += " " + String(localized: "HRV and resting heart rate agree: your body took it well.")
        case .lagging: why += " " + String(localized: "HRV and resting heart rate have not followed the sleep yet, so recovery may lag it.")
        case .neutral: break
        }
        var action = sleepAction(r)
        if let wakeDay, let note = factorNote(factors, wakeDay: wakeDay) {
            why += " " + note.why
            if let a = note.action { action = a }
        }
        return (why, action)
    }

    private static func sleepAction(_ r: SleepRead) -> String {
        switch r.verdict {
        case .heldBack(.duration):
            let short = max(-r.durationGapMin, 0)
            let m = min(max((short + 2) / 5 * 5, 15), 60)
            var s = String(localized: "Aim to be asleep about \(m) minutes earlier tonight.")
            if let d = r.debtMin, d >= 30 { s += " " + String(localized: "Thirty extra minutes a night clears the debt in about \((d + 29) / 30) nights.") }
            return s
        case .heldBack(.efficiency):
            return String(localized: "A cool, dark room and fewer fluids and caffeine late in the evening cut wake-ups; check yesterday's journal for what was different.")
        case .heldBack(.restorative):
            return String(localized: "Alcohol, a late meal or a hard late session are the usual reasons deep sleep drops. Keep tonight's evening light and see whether it comes back.")
        case .heldBack(.consistency):
            return String(localized: "Hold your bedtime within 30 minutes of your usual, weekends included.")
        case .carriedBy, .balanced:
            return String(localized: "Repeat what you did yesterday evening: it worked.")
        }
    }

    // Card notes

    static func hoursNote(asleepMin: Double, needMin: Double, debtMin: Double) -> String {
        let gap = Int((asleepMin - needMin).rounded())
        if gap >= -10 { return String(localized: "You met your need. Meeting it most nights is what keeps debt from building.") }
        var s = String(localized: "\(duration(-gap)) short of what you need.")
        if debtMin >= 30 { s += " " + String(localized: "With \(duration(Int(debtMin.rounded()))) of debt, 30 extra minutes a night clears it in about \((Int(debtMin) + 29) / 30) nights.") }
        return s
    }

    static func consistencyNote(shiftMin: Double?) -> String? {
        guard let s = shiftMin else { return nil }
        if abs(s) <= 20 { return String(localized: "Within 20 minutes of your usual bedtime: your body clock is steady.") }
        let m = Int(abs(s).rounded())
        return (s > 0 ? String(localized: "\(duration(m)) later than your usual bedtime.") : String(localized: "\(duration(m)) earlier than your usual bedtime."))
            + " " + String(localized: "Swings of more than an hour are what cost Rest.")
    }

    static func efficiencyNote(events: [(start: TimeInterval, end: TimeInterval)], totalSec: TimeInterval) -> String {
        guard !events.isEmpty else { return String(localized: "No wake-up lasted more than a minute: an unbroken night.") }
        let longest = Int((events.map { $0.end - $0.start }.max() ?? 0) / 60)
        var s = String(localized: "\(events.count) wake-ups, the longest \(max(longest, 1)) min.")
        if totalSec > 0 {
            let late = events.filter { $0.start >= totalSec * 2 / 3 }.count
            if events.count >= 2, Double(late) / Double(events.count) >= 0.6 {
                s += " " + String(localized: "Most came in the last third of the night, when sleep is lightest and noise or light wake you more easily.")
            }
        }
        return s
    }

    // MARK: Charge

    static func charge(_ r: ChargeRead, chargePct: Double) -> String {
        var parts: [String] = []
        if let l = r.lift {
            switch l.factor {
            case .hrv: parts.append(String(localized: "A higher HRV than usual is carrying today's Charge."))
            case .restingHr: parts.append(String(localized: "A lower resting heart rate than usual is carrying today's Charge."))
            case .sleep: parts.append(String(localized: "A good night's sleep is carrying today's Charge."))
            default: break
            }
        }
        if let d = r.drag {
            switch d.factor {
            case .hrv: parts.append(String(localized: "HRV sitting under its usual is what holds Charge back."))
            case .restingHr: parts.append(String(localized: "A resting heart rate above your usual is holding Charge back."))
            case .sleep: parts.append(String(localized: "A short or broken night is holding Charge back."))
            case .load: parts.append(String(localized: "Yesterday's hard Effort is still weighing on Charge."))
            case .breathing: parts.append(String(localized: "A breathing rate off its usual is holding Charge back."))
            case .skinTemp: parts.append(String(localized: "A skin temperature off your baseline is holding Charge back."))
            }
        }
        if parts.isEmpty { parts.append(String(localized: "Nothing stands out: your signals sit at their usual, so Charge is simply where your baseline puts it.")) }
        parts.append(chargePct >= 67 ? String(localized: "A good day for quality work.")
                     : (chargePct >= 34 ? String(localized: "Keep intensity controlled and let how you feel decide.")
                                        : String(localized: "Make it an easy day: sleep is the best training today.")))
        return parts.joined(separator: " ")
    }

    // MARK: A vital sign

    /// Nil when the metric has no sentence of its own and no read; the caller then falls back to its older line.
    static func vital(key: String, title: String, latest: Double, read: VitalRead?, higherIsBetter: Bool?) -> String? {
        func streak(_ r: VitalRead) -> String { r.streakDays >= 2 ? " " + String(localized: "for \(r.streakDays) days running") : "" }
        func pct(_ r: VitalRead) -> Int { Int(abs(r.pctFromUsual).rounded()) }
        switch key {
        case "spo2":
            if latest < 95 { return String(localized: "Blood oxygen is under 95%. One night is noise; several in a row are worth mentioning to a doctor if you feel it.") }
            return String(localized: "Blood oxygen is in the normal range. It matters only if it falls under 95% on several nights.")
        case "skin_temp":
            if latest >= 0.5 { return String(localized: "Skin temperature is above your baseline. With a higher resting heart rate that can mean your body is fighting something; a warm room does the same.") }
            if latest <= -0.5 { return String(localized: "Skin temperature is below your baseline: a cool room, or a dip after being unwell.") }
            return String(localized: "Skin temperature is at your baseline: nothing to act on.")
        default: break
        }
        guard let r = read else { return nil }
        switch (key, r.position) {
        case ("hrv", .above): return String(localized: "HRV is \(pct(r))% above your usual\(streak(r)): your body is absorbing load well.")
        case ("hrv", .below): return String(localized: "HRV is \(pct(r))% under your usual\(streak(r)): your body is still paying for load, short sleep or stress. Keep today easier.")
        case ("rhr", .above) where r.deltaFromUsual >= 2:
            return String(localized: "Resting heart rate is \(Int(r.deltaFromUsual.rounded())) bpm above your usual\(streak(r)). It usually follows a short night, alcohol, illness or a hard block: see whether it is still there tomorrow before pushing.")
        case ("rhr", .below) where r.deltaFromUsual <= -2:
            return String(localized: "Resting heart rate is \(Int(abs(r.deltaFromUsual).rounded())) bpm under your usual: a sign of good recovery.")
        case ("resp_rate", .above): return String(localized: "Breathing rate is up on your usual\(streak(r)). It rises with illness, altitude or a heavy evening session.")
        case ("resp_rate", .below): return String(localized: "Breathing rate is under your usual: your body is calm.")
        case (_, .within): return String(localized: "\(title) is right at your usual: nothing to act on.")
        case (_, .above): return String(localized: "\(title) is \(pct(r))% above your usual\(streak(r)).")
        case (_, .below): return String(localized: "\(title) is \(pct(r))% under your usual\(streak(r)).")
        }
    }

    // MARK: Health (HRV and resting heart rate together)

    static func health(hrv: VitalRead, rhr: VitalRead) -> (headline: String, detail: String) {
        let up = hrv.position == .above, down = hrv.position == .below
        let rUp = rhr.position == .above && rhr.deltaFromUsual >= 2
        let rDown = rhr.position == .below && rhr.deltaFromUsual <= -2
        let headline: String
        let detail: String
        switch (up, down, rUp, rDown) {
        case (_, _, _, true) where up || !down:
            headline = String(localized: "Your body looks recovered: HRV is at or above its usual and resting heart rate is under it.")
            detail = String(localized: "A good day to train if Charge agrees.")
        case (_, true, true, _):
            headline = String(localized: "Both overnight signals point the same way: HRV is under its usual and resting heart rate is above it.")
            detail = String(localized: "That pairing usually follows a short night, alcohol, illness or a hard block. Keep today easy and see whether it clears.")
        case (_, true, _, _):
            headline = String(localized: "HRV is under its usual while resting heart rate is normal: your body is still absorbing recent load or stress.")
            detail = String(localized: "Keep intensity controlled today.")
        case (_, _, true, _):
            headline = String(localized: "Resting heart rate is above your usual while HRV holds: often one short night or a late meal.")
            detail = String(localized: "Check it again tomorrow before changing your plan.")
        case (true, _, _, _):
            headline = String(localized: "HRV is above its usual: your body is handling load well.")
            detail = String(localized: "Resting heart rate is normal, so nothing is working against it.")
        default:
            headline = String(localized: "HRV and resting heart rate both sit at your usual: nothing is asking for a change.")
            detail = String(localized: "Look at the trend over a week, not a single morning.")
        }
        return (headline, detail)
    }

    // MARK: Stress

    static func stress(_ r: StressRead) -> String {
        func clock(_ h: Int) -> String { String(format: "%02d:00", h) }
        guard let start = r.peakStartHour, r.peakHours >= 1 else {
            return String(localized: "Stress stayed out of the high band so far today, with \(r.calmHours) of \(r.scoredHours) hours calm. That is a good start to tonight's sleep.")
        }
        var s = String(localized: "Stress was highest from \(clock(start)) for \(r.peakHours) h.")
        if let since = r.calmSinceHours, since >= 2 { s += " " + String(localized: "It has been calmer for the last \(since) h.") }
        else { s += " " + String(localized: "It has not settled yet.") }
        return s + " " + String(localized: "A two-minute breathing session when it climbs is the quickest way to bring it down.")
    }

    // MARK: Effort

    static func effort(effort: Double, chargePct: Double?) -> String? {
        guard let chargePct, let band = CoupledView.optimalStrainRange(recovery: chargePct) else { return nil }
        let lo = Double(band.lowerBound) / UnitFormatter.effortScaleFactor
        let hi = Double(band.upperBound) / UnitFormatter.effortScaleFactor
        if effort < lo { return String(localized: "You are under the Effort your Charge supports today, so there is room for a session if you feel like it.") }
        if effort <= hi { return String(localized: "You are inside the Effort your Charge supports today: more adds load without much return.") }
        return String(localized: "You are past the Effort your Charge supports today: food, water and an early night are the work now.")
    }
}

// MARK: - Evening habits from the journal

/// The journal's evening habits (alcohol, late caffeine, a meal close to bedtime) and what they have cost this wearer's Rest, for the
/// sleep line. Built once per screen from the journal and the Rest series.
struct NunaSleepFactorContext {
    let journal: [SleepFactors.Entry]
    let evidence: [SleepFactors.Evidence]

    static func load(repo: Repository, restByWakeDay: [String: Double]) async -> NunaSleepFactorContext {
        let entries = await repo.journalEntries(days: 400).map { SleepFactors.Entry(day: $0.day, question: $0.question, yes: $0.answeredYes) }
        return NunaSleepFactorContext(journal: entries, evidence: SleepFactors.evidence(journal: entries, restByWakeDay: restByWakeDay))
    }

    func logged(wakeDay: String) -> Set<SleepFactorKind> { SleepFactors.loggedYes(journal: journal, wakeDay: wakeDay) }
}

extension NunaInsightText {
    private static func habitName(_ k: SleepFactorKind) -> String {
        switch k {
        case .alcohol: return String(localized: "alcohol")
        case .lateCaffeine: return String(localized: "caffeine late in the day")
        case .lateMeal: return String(localized: "a meal close to bedtime")
        }
    }

    /// What the journal adds to a night's line: a habit named as a cause only where this wearer's own nights show it costing Rest,
    /// and an honest "not enough nights yet" where it was logged but there is nothing to compare.
    static func factorNote(_ context: NunaSleepFactorContext?, wakeDay: String) -> (why: String, action: String?)? {
        guard let context else { return nil }
        let logged = context.logged(wakeDay: wakeDay)
        guard !logged.isEmpty else { return nil }
        let evidence = context.evidence.filter { logged.contains($0.kind) }
        if let worst = evidence.filter(\.costsRest).min(by: { ($0.restDelta ?? 0) < ($1.restDelta ?? 0) }), let d = worst.restDelta {
            let why = String(localized: "Your journal explains part of it: you logged \(habitName(worst.kind)) yesterday, and after the \(worst.nYes) nights you did, your Rest ran \(Int(abs(d).rounded())) points lower.")
            return (why, String(localized: "Skip it tonight and see whether the night recovers."))
        }
        if let first = evidence.first {
            return (String(localized: "You logged \(habitName(first.kind)) yesterday; with only \(first.nYes) such night(s) so far there is not enough to say whether it moves your sleep."), nil)
        }
        return nil
    }
}

// MARK: - From the sleep model

extension NunaSleepModel {
    /// What the insight reads need about one night: the four parts of Rest, the stages against the usual, the bedtime against the
    /// usual and the overnight HRV and resting heart rate against the nights before.
    func sleepFacts(_ night: NunaNight, debtMin: Double?) -> SleepFacts {
        let before = nights.drop { $0.id != night.id }.dropFirst().prefix(14)
        let typical = self.typical()
        func mean(_ f: (NunaNight) -> Double?) -> Double? {
            let v = before.compactMap(f)
            return v.count >= 3 ? v.reduce(0, +) / Double(v.count) : nil
        }
        // Bed time as minutes after noon, so a bedtime after midnight is a larger number.
        func bedMinutes(_ n: NunaNight) -> Double {
            let c = Calendar.current.dateComponents([.hour, .minute], from: n.onset)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m < 12 * 60 { m += 24 * 60 }
            return m
        }
        let usualBed = mean { bedMinutes($0) }
        let hrvUsual = mean { $0.daily?.avgHrv }
        let rhrUsual = mean { $0.daily?.restingHr.map(Double.init) }
        let wakeEvents = night.intervals.filter { $0.stage == .awake && $0.end - $0.start >= 60 }.count
        return SleepFacts(
            restPct: value("sleep_performance", night),
            asleepMin: night.daily?.totalSleepMin ?? night.asleepMin,
            needMin: need(night), debtMin: debtMin,
            hoursPct: hoursVsNeeded(night), efficiencyPct: efficiency(night), restorativePct: restorative(night),
            consistencyPct: consistency(night),
            deepMin: night.stages.deep, remMin: night.stages.rem, awakeMin: night.stages.awake, wakeEvents: wakeEvents,
            usualDeepMin: typical?.deep, usualRemMin: typical?.rem,
            bedShiftMin: usualBed.map { bedMinutes(night) - $0 },
            hrvDeltaPct: night.daily?.avgHrv.flatMap { v in hrvUsual.map { $0 > 0 ? (v - $0) / $0 * 100 : 0 } },
            rhrDeltaBpm: night.daily?.restingHr.flatMap { v in rhrUsual.map { Double(v) - $0 } })
    }
}
#endif
