#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Day In Review: from the late afternoon the Daily Outlook card becomes a look back at the day (how the load and the stress sat against what
/// the Recovery asked for) and a look ahead at the night, with one thing to commit to: the bedtime.
enum NunaReviewGate {
    /// The hour the Outlook gives way to the review.
    static let startHour = 16
    /// The day the review was last opened: the card is in colour until then, and plain for the rest of that day.
    static let seenDayKey = "nuna.review.seenDay"
    /// The day and time of the bedtime committed to, "yyyy-MM-dd|HH:mm".
    static let bedtimeKey = "nuna.review.bedtime"

    static func isEvening(now: Date = Date()) -> Bool {
#if DEBUG
        // `--demo-review=on` / `=off` forces the review or the Outlook, whatever the clock says.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-review=") }) { return arg.hasSuffix("on") }
#endif
        return Calendar.current.component(.hour, from: now) >= startHour
    }

    static func committedBedtime(on day: String = Repository.localDayKey(Date())) -> String? {
        let raw = UserDefaults.standard.string(forKey: bedtimeKey) ?? ""
        let parts = raw.split(separator: "|").map(String.init)
        return parts.count == 2 && parts[0] == day ? parts[1] : nil
    }

    static func commitBedtime(_ time: String, on day: String = Repository.localDayKey(Date())) {
        UserDefaults.standard.set("\(day)|\(time)", forKey: bedtimeKey)
    }
}

/// The numbers the review is written from, all on this iPhone. Anything that is missing leaves its sentence out.
struct NunaReviewInputs: Equatable {
    var name = ""
    /// Strain on the stored 0 to 100 axis, with the floor and the aim worth reaching at today's Recovery.
    var strain: Double?
    var floor: Double?
    var target: Double?
    var scale: EffortScale = .whoop
    /// Minutes of high non-activity stress today and their 30-day average.
    var highStressMin: Double?
    var highStressAvgMin: Double?
    var charge: Double?
    var chargeAvg: Double?
    var steps: Double?
    var stepsAvg: Double?
    /// Days of the last seven that ended under their strain floor, and how many days that was judged over.
    var daysUnderFloor: Int?
    var daysJudged = 0
    var debtMin: Double?
    /// When to be asleep, "HH:mm".
    var bedtime: String?
}

struct NunaDayReview: Equatable {
    var opening: String
    /// Light markdown (bold figures).
    var paragraphs: [String]
    var question: String
    var bedtime: NunaOutlookIdea?
    var chips: [NunaAnyaQuestion]
}

enum NunaDayReviewEngine {
    enum Load { case unknown, under, on, over }

    static func load(_ i: NunaReviewInputs) -> Load {
        guard let s = i.strain, let floor = i.floor, let target = i.target else { return .unknown }
        if s < floor { return .under }
        return s > target + 10 ? .over : .on
    }

    static func hot(_ i: NunaReviewInputs) -> Bool {
        guard let high = i.highStressMin, let avg = i.highStressAvgMin else { return false }
        return high > avg * 1.25 && high - avg >= 20
    }

    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
    }

    private static func num(_ v: Double) -> String { nunaThousands(v) }

    /// "21:30" from "22:15" less 45 minutes.
    private static func before(_ clock: String, minutes: Int) -> String {
        let p = clock.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return clock }
        let t = ((p[0] * 60 + p[1] - minutes) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    static func build(_ i: NunaReviewInputs) -> NunaDayReview {
        let state = load(i), hot = hot(i)
        func shown(_ stored: Double) -> String { UnitFormatter.effortDisplay(stored, scale: i.scale) }

        // The opening line.
        let clause: String
        switch (state, hot) {
        case (.under, true): clause = String(localized: "your body is underloaded but running hot today 🔥")
        case (.under, false): clause = String(localized: "your body is underloaded and calm today 🌿")
        case (.on, true): clause = String(localized: "you hit your strain target, but stress ran high 🔥")
        case (.on, false): clause = String(localized: "you landed right in your strain target today 👏")
        case (.over, true): clause = String(localized: "you pushed hard today and stress ran high 🔥")
        case (.over, false): clause = String(localized: "you pushed hard today 💪")
        case (.unknown, _): clause = String(localized: "here is how your day looks so far")
        }
        let opening = i.name.isEmpty ? clause.prefix(1).uppercased() + clause.dropFirst() : "\(i.name), \(clause)"

        // The figures.
        var first: [String] = []
        if let s = i.strain, let t = i.target, let f = i.floor {
            first.append(String(localized: "Strain is **\(shown(s))** (target: \(shown(t)), lower bound: \(shown(f)))."))
        } else if let s = i.strain {
            first.append(String(localized: "Strain is **\(shown(s))**."))
        }
        if let high = i.highStressMin {
            first.append(i.highStressAvgMin.map { String(localized: "Non-activity high stress is **\(hm(high))** (30d avg: \(hm($0))).") }
                         ?? String(localized: "Non-activity high stress is **\(hm(high))**."))
        }
        if let c = i.charge {
            first.append(i.chargeAvg.map { String(localized: "Recovery sits at **\(Int(c.rounded()))%** (30d avg: \(Int($0.rounded()))%).") }
                         ?? String(localized: "Recovery sits at **\(Int(c.rounded()))%**."))
        }
        switch (state, hot) {
        case (.under, true): first.append(String(localized: "That combination keeps your nervous system activated without enough daytime load to build sleep pressure, so recovery stays capped even on lighter days."))
        case (.under, false): first.append(String(localized: "A calm day is easy on recovery, but a little more movement builds the sleep pressure you want tonight."))
        case (.on, true), (.over, true): first.append(String(localized: "You earned the load, but the stress on top of it asks for a deliberate wind-down so it does not cost you tonight's sleep."))
        case (.on, false), (.over, false): first.append(String(localized: "Load and calm together are what recovery likes, so tonight is about protecting it."))
        case (.unknown, _): break
        }

        // The week, and tonight.
        var second: [String] = []
        let stepsLow = (i.steps ?? 0) > 0 && (i.stepsAvg ?? 0) > 0 && (i.steps ?? 0) < (i.stepsAvg ?? 0) * 0.8
        var weekSentence: String?
        if let n = i.daysUnderFloor, n >= 2, i.daysJudged >= 4 {
            weekSentence = String(localized: "You have been under your strain floor **\(n) of the last \(i.daysJudged) days**")
        }
        if let steps = i.steps, steps > 0 {
            let avg = i.stepsAvg.map { String(localized: " (30d avg: \(num($0)))") } ?? ""
            if let w = weekSentence, stepsLow {
                second.append(String(localized: "\(w), and today's **\(num(steps)) steps**\(avg) keep the weekly movement behind too."))
            } else if let w = weekSentence {
                second.append(w + ".")
                second.append(String(localized: "Today's **\(num(steps)) steps**\(avg) are doing their part."))
            } else if stepsLow {
                second.append(String(localized: "Today's **\(num(steps)) steps**\(avg) leave the day's movement short."))
            }
        } else if let w = weekSentence {
            second.append(w + ".")
        }
        let action = (hot || state == .under)
            ? String(localized: "a **10-minute breathwork or meditation** session after dinner is the highest-leverage move")
            : String(localized: "an **easy evening** with the lights low is the highest-leverage move")
        var tonight = String(localized: "Tonight, \(action)")
        if let bed = i.bedtime {
            tonight += String(localized: ", then **screens off by \(before(bed, minutes: 45))** so you can protect your bedtime around **\(bed)**")
        }
        if let debt = i.debtMin, debt >= 10 { tonight += String(localized: " and chip at the **\(hm(debt))** sleep debt") }
        second.append(tonight + ".")

        let question = hot
            ? String(localized: "What has been pulling your stress up this week: work, travel, or something else?")
            : String(localized: "How are you feeling about tonight: is anything on your mind?")
        let chips: [NunaAnyaQuestion] = hot
            ? [NunaAnyaQuestion(title: String(localized: "Mostly work stress lately"), prompt: "Mostly work stress lately. What should I change this evening to settle down?"),
               NunaAnyaQuestion(title: String(localized: "Travel has thrown me off"), prompt: "Travel has thrown me off. How should I handle tonight and the next few days?"),
               NunaAnyaQuestion(title: String(localized: "I'm not sure what it is"), prompt: "I'm not sure what is behind my stress. Help me work it out from my data.")]
            : [NunaAnyaQuestion(title: String(localized: "I feel good tonight"), prompt: "I feel good tonight. How do I protect it?"),
               NunaAnyaQuestion(title: String(localized: "A bit tired"), prompt: "I feel a bit tired. What should I do this evening?"),
               NunaAnyaQuestion(title: String(localized: "Something is on my mind"), prompt: "Something is on my mind tonight. Help me wind down.")]

        let bedtime = i.bedtime.map {
            NunaOutlookIdea(id: "bedtime", sport: "Sleep", title: String(localized: "Asleep by \($0)"), emoji: "🌙",
                            line: String(localized: "Getting to bed by this time gets you your full sleep need tonight."),
                            card: String(localized: "Getting to bed by this time gets you your full sleep need tonight."), minutes: 0, strain: 0)
        }
        return NunaDayReview(opening: opening, paragraphs: [first.joined(separator: " "), second.joined(separator: " ")].filter { !$0.isEmpty },
                             question: question, bedtime: bedtime, chips: chips)
    }

    /// A short local answer to a follow-up chip, for when Anya is not connected.
    static func reply(to chip: String) -> String {
        let t = chip.lowercased()
        if t.contains("work") { return String(localized: "Work stress usually shows as high daytime stress and a restless first half of the night. Close the laptop by your screens-off time and take the slow breathing before dinner, not after.") }
        if t.contains("travel") { return String(localized: "Travel unsettles your body clock and your sleep. Keep tonight's bedtime where it is, get some daylight early tomorrow, and keep the evening light until your sleep settles.") }
        if t.contains("good") { return String(localized: "Good. Keep tonight simple: dinner a few hours before bed, screens off on time and a cool, dark room.") }
        if t.contains("tired") { return String(localized: "Being tired is a reason to protect tonight. Skip anything hard, eat well and go to bed at the time above.") }
        return String(localized: "Thanks for telling me. Keep the evening easy, switch screens off on time and be asleep by the bedtime above. Connect Anya if you want help working out what is behind it.")
    }

    /// The read as text, for the provider to build on.
    static func summary(_ r: NunaDayReview) -> String {
        "DAY IN REVIEW\n" + NunaMark.plain(r.opening + "\n" + r.paragraphs.joined(separator: "\n")) + (r.bedtime.map { "\nBedtime: \($0.title)" } ?? "")
    }
}

/// Reads what the review is made from, on this iPhone.
enum NunaReviewLoader {
    @MainActor static func inputs(repo: Repository, profile: ProfileStore) async -> NunaReviewInputs {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        let days = repo.days
        let todayKey = repo.today?.day ?? Repository.localDayKey(Date())
        var i = NunaReviewInputs()
        i.name = profile.displayName.split(separator: " ").first.map(String.init) ?? ""
        i.scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? EffortScale.whoop.rawValue)
        i.charge = m.charge.pct
        i.strain = days.last(where: { $0.day == todayKey })?.strain ?? m.effort
        if let aim = NunaScoreStyle.effortAim(charge: i.charge) {
            i.target = aim * 100
            i.floor = max(aim - 0.1, 0) * 100
        }
        func mean(_ v: [Double], minimum: Int = 3) -> Double? { v.count >= minimum ? v.reduce(0, +) / Double(v.count) : nil }
        let before = days.filter { $0.day != todayKey }.suffix(30)
        i.chargeAvg = mean(before.compactMap(\.recovery))
        i.steps = m.steps
        i.stepsAvg = mean(before.compactMap { $0.steps.map(Double.init) })

        i.highStressMin = m.stressWhoop?.zones(.nonActivity)?.high
        let history = NunaStressHistory().entries.filter { $0.key < todayKey }.sorted { $0.key < $1.key }.suffix(30)
        i.highStressAvgMin = mean(history.compactMap { $0.value.zones(.nonActivity)?.high })
        if i.highStressMin != nil, i.highStressMin == 0 { i.highStressMin = nil }

        // How many of the last seven days ended under the floor their own Recovery set.
        var judged = 0, under = 0
        for d in days.suffix(7) {
            guard let s = d.strain, let aim = NunaScoreStyle.effortAim(charge: d.recovery ?? (d.day == todayKey ? i.charge : nil)) else { continue }
            judged += 1
            if s < max(aim - 0.1, 0) * 100 { under += 1 }
        }
        i.daysJudged = judged
        i.daysUnderFloor = judged > 0 ? under : nil

        let need = SleepModel.debtNeedMin(days: days)
        let ledger = SleepDebt.ledger(series: days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: need / 60)
        if ledger.nightCount > 0 {
            i.debtMin = ledger.magnitudeMin
            if let mid = await repo.habitualMidsleepSec() { i.bedtime = AnyaDayContext.clock(seconds: AnyaDayContext.asleepBySec(midsleepSec: mid, needMin: need)) }
        }
#if DEBUG
        // `--demo-review=on` has no stress history or bedtime to speak of in the demo year, so give the review something to show.
        if CommandLine.arguments.contains("--demo-review=on") {
            if i.highStressMin == nil { i.highStressMin = 165; i.highStressAvgMin = 79 }
            if i.bedtime == nil { i.bedtime = "19:14"; i.debtMin = i.debtMin ?? 67 }
        }
#endif
        return i
    }
}

/// The opening line, the read, the question, and the bedtime card to commit to.
struct NunaReviewContent: View {
    let review: NunaDayReview
    /// The provider's own words for the read, when it wrote some; the local paragraphs otherwise.
    let provider: String?
    let committed: Bool
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let provider {
                Text(Self.body(provider)).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
            } else {
                Text(verbatim: review.opening).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
                ForEach(Array(review.paragraphs.enumerated()), id: \.offset) { _, p in
                    Text(Self.body(p)).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
                }
            }
            Text(verbatim: review.question).font(.nunaStrong(size: 16)).lineSpacing(7).padding(.top, 4)
            if let idea = review.bedtime {
                NunaOutlookIdeaCard(idea: idea, symbol: "moon.fill", done: committed, onCommit: onCommit)
                    .padding(.top, 6)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The markdown of the read, with its bold figures set in the app's own bold (a plain `.font` would flatten them).
    private static func body(_ markdown: String) -> AttributedString {
        var a = NunaAnyaSheet.markdown(markdown)
        for run in a.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            a[run.range].font = .nunaStrong(size: 16)
        }
        return a
    }
}
#endif
