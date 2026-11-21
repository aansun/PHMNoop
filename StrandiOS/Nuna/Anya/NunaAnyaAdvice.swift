#if os(iOS)
import Foundation
import StrandAnalytics

/// What a page's reading is about, so the advice that goes with a verdict fits it (a low HRV and a long Strain day do not call for the same thing).
typealias NunaAnyaTopic = AnyaSurface.Topic

/// The phone's own judgement of a page's reading against the person's baseline: good, steady or needs attention, and the sentence behind it.
/// It goes to the provider as a fact to explain (so she does not make a judgement up) and, without a provider, it is what the pill says.
struct NunaAnyaVerdict: Equatable {
    enum Level: String, Equatable { case good, steady, attention }
    var level: Level
    /// The reading against the baseline, in one sentence that cites its figures.
    var why: String
    var topic: NunaAnyaTopic

    /// How the level is worded to the provider (English, as the rest of her context).
    var providerWord: String {
        switch level { case .good: return "good"; case .steady: return "steady"; case .attention: return "needs attention" }
    }

    var providerLine: String {
        "PAGE VERDICT (worked out on this phone against the person's own baseline; do not contradict it): \(providerWord). \(why)"
    }

    /// One next step: to improve the reading when it is poor, to keep it when it is good.
    var advice: String {
        let bad = level == .attention
        switch topic {
        case .hrv:
            return bad ? String(localized: "Low HRV usually follows a short night, alcohol, a hard week or stress. Sleep earlier tonight, keep today easy and skip alcohol; it often recovers within a few days.")
                       : String(localized: "Keep what is working: regular bed and wake times, steady training and little alcohol.")
        case .restingHR:
            return bad ? String(localized: "A raised resting heart rate often follows poor sleep, heat, alcohol, illness or a heavy week. Keep today easy, drink water and check again tomorrow.")
                       : String(localized: "Keep the routine that got you here: regular sleep, steady training and enough water.")
        case .vitals:
            return bad ? String(localized: "A reading outside your usual range can come from a loose fit, a blocked nose or a bad night. Check the strap fit and recheck tomorrow; if it stays off for several nights, speak to a clinician.")
                       : String(localized: "Your usual range holds. Keep the strap snug and worn overnight so the reading stays reliable.")
        case .recovery:
            return bad ? String(localized: "Your body is asking for less today: easy movement, food, water and an earlier night.")
                       : String(localized: "You are ready for a quality session today; warm up well, then spend it where it counts.")
        case .sleep:
            return bad ? String(localized: "Be asleep 30 minutes earlier tonight and keep your wake time; sleep debt is repaid over several nights, not in one.")
                       : String(localized: "Repeat what you did yesterday evening: same bedtime, no late meal, screens down early.")
        case .strain:
            if level == .steady { return String(localized: "There is room left: a short session in zone 2 would fit if you feel like it.") }
            return bad ? String(localized: "You are above what your Recovery supports: stop adding load today, eat well and protect tonight's sleep.")
                       : String(localized: "You are inside the range your Recovery supports: finish the day easy and keep the same rhythm.")
        case .stress:
            return bad ? String(localized: "A tense day: take five minutes of slow breathing now and keep the evening light.")
                       : String(localized: "You are calm: keep the breaks, movement and sleep that got you here.")
        case .skinTemp:
            return bad ? String(localized: "A rise this size, with a lower HRV or a higher resting heart rate, can come before an illness: drink water, ease off today, sleep more and watch the next two nights. It is an early signal, not a diagnosis.")
                       : String(localized: "Your skin temperature is within your usual band: nothing to change.")
        case .weight:
            return bad ? String(localized: "Keep today easy, look at last night's sleep first and check again tomorrow before changing your plan.")
                       : String(localized: "Nothing to change: keep your routine and check again tomorrow.")
        case .trend:
            if level == .steady { return String(localized: "The trend is level: keep your routine and change one thing at a time so you can see what moves it.") }
            return bad ? String(localized: "The trend is slipping: protect sleep, put an easy day after each hard one and look at what changed this week before adding anything.")
                       : String(localized: "The trend is up: whatever you changed is working, so keep it for two more weeks before adding anything.")
        case .load:
            return bad ? String(localized: "Your load is well above your usual: make tomorrow easy and keep one full rest day this week.")
                       : String(localized: "Your load is in your usual range: keep one hard day followed by an easy one.")
        case .other:
            return bad ? String(localized: "Keep today easy, look at last night's sleep first and check again tomorrow before changing your plan.")
                       : String(localized: "Nothing to change: keep your routine and check again tomorrow.")
        }
    }

    /// What the pill and the sheet say when no provider is connected: the verdict, the reading behind it and the next step.
    func localInsight(reading: String) -> AnyaPageInsightLocal {
        AnyaPageInsightLocal(headline: why + ".", see: reading, advice: advice)
    }
}

extension NunaAnyaVerdict {
    /// This week's Strain against the weeks before it (oldest first, the last block is this week): half as much again as the earlier average is well above usual.
    static func load(weeks: [Double]) -> NunaAnyaVerdict? {
        guard weeks.count >= 2, let current = weeks.last, current > 0 else { return nil }
        let earlier = Array(weeks.dropLast().suffix(3)).filter { $0 > 0 }
        guard !earlier.isEmpty else { return nil }
        let usual = earlier.reduce(0, +) / Double(earlier.count)
        let ratio = current / usual
        return ratio > 1.5
            ? NunaAnyaVerdict(level: .attention, why: String(localized: "This week's Strain is \(Int(((ratio - 1) * 100).rounded()))% above your usual week"), topic: .load)
            : NunaAnyaVerdict(level: .good, why: String(localized: "This week's Strain is in your usual range"), topic: .load)
    }

    /// The nights of a week against what the person needs: 30 minutes short or more is worth a step, within 30 minutes is on course.
    static func sleep(averageMin: Double, needMin: Double?) -> NunaAnyaVerdict? {
        guard let needMin, needMin > 0 else { return nil }
        let gap = averageMin - needMin
        return NunaAnyaVerdict(level: gap <= -30 ? .attention : .good, why: "", topic: .sleep)
    }
}

/// Turns a provider reply (or a local verdict) into what the pill and the sheet show: a headline for the pill, the full text for the sheet.
enum NunaAnyaInsightText {
    static func titles() -> (see: String, mean: String, advice: String) {
        (String(localized: "What the numbers say"), String(localized: "What it means"), String(localized: "What to do"))
    }

    /// Words that name a problem. A good reading has none to explain, so a meaning that carries one is the model's invention, not the data's.
    private static let problemCause = try! NSRegularExpression(pattern: #"short night|short sleep|alcohol|illness|\bsick|disrupted|hard block|hard session|overtrain|lack of sleep|poor sleep|stress|strain|fatigue"#, options: .caseInsensitive)

    /// The provider's reply: in the four-paragraph shape it becomes a headline plus titled parts; in any other shape it stays plain prose.
    /// With a good verdict the model is not trusted to explain a cause: if its meaning names a problem, or its next step is a fix, they are replaced by what the phone
    /// knows (the reading sits on the better side of the person's own baseline) and the habit step for the topic.
    static func fromProvider(_ raw: String, verdict: NunaAnyaVerdict? = nil, facts: String? = nil) -> (headline: String?, text: String) {
        if var i = AnyaPageInsight.parse(raw) {
            // The model words the reading in full sentences. Only when it gave none is the verdict's own sentence and the page's figures, written in code, used.
            // A reading that is a run of figures ("Recovery is 18, yesterday 35, 30-day average 63, HRV is 52 ms, ...") is the context read back, not a sentence: the same fallback.
            if let v = verdict, i.see.trimmingCharacters(in: .whitespaces).isEmpty || figureCount(i.see) > 5 { i.see = seeText(v, facts: facts, headline: i.headline) }
            if let v = verdict, v.level == .good {
                let range = NSRange(i.mean.startIndex..., in: i.mean)
                if problemCause.firstMatch(in: i.mean, range: range) != nil {
                    i.mean = String(localized: "It sits on the better side of your own baseline, so the routine behind it is working.")
                }
                let adviceRange = NSRange(i.advice.startIndex..., in: i.advice)
                if problemCause.firstMatch(in: i.advice, range: adviceRange) != nil || i.advice.lowercased().contains("keep today easy") { i.advice = v.advice }
            }
            i.see = AnyaReplyCleaner.clean(i.see); i.mean = AnyaReplyCleaner.clean(i.mean); i.advice = AnyaReplyCleaner.clean(i.advice)
            return (i.headline, i.paragraphs())
        }
        return (nil, AnyaReplyCleaner.clean(AnyaActions.proseOnly(raw)))
    }

    /// How many figures a text carries.
    static func figureCount(_ text: String) -> Int {
        let re = try! NSRegularExpression(pattern: #"\d+(?:[.,:]\d+)?"#)
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// "Recovery 82% is in the green band. Resting heart rate up 7 bpm. Strain so far 15.5.": the verdict's sentence, then the page's own figures.
    static func seeText(_ v: NunaAnyaVerdict, facts: String?, headline: String = "") -> String {
        var first = v.why.trimmingCharacters(in: .whitespaces)
        if let last = first.last, !".!?".contains(last) { first += "." }
        // The headline already says the verdict's figure ("Recovery is 18, ..."): saying it again right after it would read as a stutter.
        let figure = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#).firstMatch(in: first, range: NSRange(first.startIndex..., in: first))
            .flatMap { Range($0.range, in: first).map { String(first[$0]) } }
        if let figure, headline.contains(figure) { first = "" }
        // Sleep and Strain carry their next step (and a sum of the week's sessions) in the page's detail: it is advice or a different figure, not what the page reads.
        let own = v.topic != .sleep && v.topic != .strain
        let more = own ? (facts.map { NunaMark.plain($0).trimmingCharacters(in: .whitespaces) } ?? "") : ""
        return [first, more].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// With no provider (or none that answered): the verdict, the reading behind it and the next step, all worked out on this phone.
    static func fromVerdict(_ v: NunaAnyaVerdict, reading: String?) -> (headline: String?, text: String) {
        let l = v.localInsight(reading: reading ?? "")
        let i = AnyaPageInsight(headline: l.headline, see: l.see, mean: "", advice: l.advice)
        return (l.headline, i.paragraphs())
    }
}

/// The local twin of `AnyaPageInsight`, written from the verdict alone (no meaning paragraph: that needs the person's habits, which a model reads).
struct AnyaPageInsightLocal: Equatable {
    var headline: String
    var see: String
    var advice: String
}
#endif
