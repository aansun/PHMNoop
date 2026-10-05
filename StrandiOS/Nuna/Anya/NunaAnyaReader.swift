#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What Anya reads on one screen, worked out on the phone from numbers that are already stored: a line that always cites
/// its figures, an optional second line, the names of the signals it came from and the questions worth asking next.
/// No provider is involved, so the card and the top of the sheet work without a connection. When there are no figures to
/// cite the read is nil and nothing is shown (a card without numbers is not drawn).
struct NunaAnyaRead: Equatable {
    var headline: String
    var detail: String?
    /// Plain names of the signals behind the line ("Charge", "HRV", …); shown as "Read:" chips.
    var read: [String]
    var module: NunaAnyaModule
    var questions: [NunaAnyaQuestion]
}

struct NunaAnyaQuestion: Equatable, Identifiable {
    enum Kind: Equatable { case ask, plan }
    var id: String { title }
    let title: String
    let prompt: String
    var kind: Kind = .ask
}

/// The modules Anya appears in (docs/nuna/mockups/AnyaMap.dc.html).
enum NunaAnyaModule: String, Equatable {
    case today, health, trends, sleep, workouts, nutrition, device, breathing

    init(context: String) {
        let c = context.lowercased()
        if c.contains("breath") { self = .breathing }
        else if c.contains("sleep") || c.contains("nap") || c.contains("body clock") || c.contains("rest") { self = .sleep }
        else if c.contains("trend") { self = .trends }
        else if c.contains("workout") || c.contains("effort") || c.contains("training") { self = .workouts }
        else if c.contains("health") || c.contains("stress") || c.contains("warning") || c.contains("hrv") || c.contains("heart") || c.contains("oxygen") || c.contains("respir") || c.contains("weight") || c.contains("body") { self = .health }
        else if c.contains("nutrition") || c.contains("water") || c.contains("calor") { self = .nutrition }
        else if c.contains("device") || c.contains("battery") || c.contains("strap") { self = .device }
        else { self = .today }
    }

    var title: LocalizedStringKey {
        switch self {
        case .today: return "Today"; case .health: return "Health"; case .trends: return "Trends"; case .sleep: return "Sleep"
        case .workouts: return "Workouts"; case .nutrition: return "Nutrition"; case .device: return "Devices"; case .breathing: return "Breathing"
        }
    }
}

@MainActor
enum NunaAnyaReader {
    static func read(context: String, repo: Repository, profile: ProfileStore, scale: EffortScale) async -> NunaAnyaRead? {
        let module = NunaAnyaModule(context: context)
        switch module {
        case .today, .nutrition, .device: return await today(module, repo: repo, profile: profile, scale: scale)
        case .sleep: return await sleep(repo: repo, profile: profile)
        case .health: return await health(repo: repo, profile: profile)
        case .trends: return trends(repo: repo)
        case .workouts: return await workouts(repo: repo, scale: scale)
        case .breathing: return await breathing(repo: repo, profile: profile)
        }
    }

    /// Writes this module's note for the day and adds what moved since the last day it noted to the read's detail.
    private static func remembering(_ read: NunaAnyaRead, values: [String: Double]) -> NunaAnyaRead {
        var r = read
        let note = r.headline + (r.detail.map { " " + $0 } ?? "")
        if let moved = NunaAnyaMemory.snapshot(r.module, headline: note, values: values) {
            r.detail = [r.detail, moved].compactMap { $0 }.joined(separator: " ")
        }
        return r
    }

    // MARK: Today

    private static func today(_ module: NunaAnyaModule, repo: Repository, profile: ProfileStore, scale: EffortScale) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        guard let charge = m.charge.pct else { return nil }
        let c = Int(charge.rounded())
        let level = m.readiness?.level
        let tail: String
        switch level {
        case .primed: tail = String(localized: "ready for a hard session")
        case .balanced: tail = String(localized: "ready for a moderate load")
        case .strained, .rundown: tail = String(localized: "take it easy today")
        default: tail = String(localized: "still learning your baseline")
        }
        var bits: [String] = []
        if let d = m.restingHrDelta, abs(d) >= 1 {
            let n = Int(abs(d).rounded())
            bits.append(d < 0 ? String(localized: "Resting heart rate down \(n) bpm") : String(localized: "Resting heart rate up \(n) bpm"))
        }
        if let d = m.hrvDelta, abs(d) >= 1 {
            let n = Int(abs(d).rounded())
            bits.append(d > 0 ? String(localized: "HRV up \(n) ms") : String(localized: "HRV down \(n) ms"))
        }
        var read = ["Charge"]
        if m.restingHr != nil { read.append("Resting HR") }
        if m.hrv != nil { read.append("HRV") }
        if let e = m.effort { read.append("Effort"); bits.append(String(localized: "Effort so far \(UnitFormatter.effortDisplay(e, scale: scale))")) }
        if m.rest != nil { read.append("Rest") }
        var vals: [String: Double] = ["charge": charge]
        if let v = m.effort { vals["effort"] = Double(UnitFormatter.effortDisplay(v, scale: scale)) ?? v }
        if let v = m.rest { vals["rest"] = v }
        if let v = m.hrv { vals["hrv"] = v }
        if let v = m.restingHr { vals["rhr"] = v }
        return remembering(NunaAnyaRead(headline: String(localized: "Charge \(c)%, \(tail)"),
                                        detail: bits.isEmpty ? nil : bits.joined(separator: ". ") + ".",
                                        read: read, module: module, questions: questions(.today)), values: vals)
    }

    // MARK: Sleep

    private static func sleep(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        guard let rest = m.rest else { return nil }
        let hours = m.sleepMinutes.map { NunaAnyaReader.hm($0) }
        var bits: [String] = []
        if let e = m.day?.efficiency { bits.append(String(localized: "Sleep efficiency \(Int(e.rounded()))%")) }
        if let d = m.day?.deepMin, d > 0 { bits.append(String(localized: "Deep sleep \(hm(d))")) }
        if let n = m.day?.disturbances { bits.append(String(localized: "\(n) wake-ups")) }
        var read = ["Rest"]; if hours != nil { read.append("Sleep duration") }
        let head = hours.map { String(localized: "Rest \(Int(rest.rounded()))% after \($0) of sleep") } ?? String(localized: "Rest \(Int(rest.rounded()))%")
        var vals: [String: Double] = ["rest": rest]
        if let v = m.sleepMinutes { vals["sleepMin"] = v }
        if let v = m.day?.efficiency { vals["efficiency"] = v }
        if let v = m.day?.deepMin, v > 0 { vals["deepMin"] = v }
        return remembering(NunaAnyaRead(headline: head, detail: bits.isEmpty ? nil : bits.joined(separator: ". ") + ".",
                                        read: read, module: .sleep, questions: questions(.sleep)), values: vals)
    }

    // MARK: Health

    private static func health(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        var parts: [String] = [], read: [String] = []
        if let v = m.hrv { parts.append("HRV \(Int(v.rounded())) ms"); read.append("HRV") }
        if let v = m.restingHr { parts.append(String(localized: "resting heart rate \(Int(v.rounded())) bpm")); read.append("Resting HR") }
        guard !parts.isEmpty else { return nil }
        var more: [String] = []
        if let v = m.spo2 { more.append("SpO₂ \(Int(v.rounded()))%"); read.append("Blood Oxygen") }
        if let v = m.respiratory { more.append(String(localized: "breathing \(String(format: "%.1f", locale: AppLanguage.activeLocale, v)) per minute")); read.append("Respiratory") }
        let head = parts.joined(separator: ", ")
        var vals: [String: Double] = [:]
        if let v = m.hrv { vals["hrv"] = v }
        if let v = m.restingHr { vals["rhr"] = v }
        if let v = m.spo2 { vals["spo2"] = v }
        if let v = m.respiratory { vals["resp"] = v }
        return remembering(NunaAnyaRead(headline: String(head.prefix(1)).uppercased() + String(head.dropFirst()), detail: more.isEmpty ? nil : more.joined(separator: ", ") + ".",
                                        read: read, module: .health, questions: questions(.health)), values: vals)
    }

    // MARK: Trends

    private static func trends(repo: Repository) -> NunaAnyaRead? {
        let vals = repo.days.compactMap { d in d.recovery.map { (d.day, $0) } }
        guard vals.count >= 14 else { return nil }
        let last7 = vals.suffix(7).map(\.1), prior = vals.dropLast(7).suffix(30).map(\.1)
        guard !prior.isEmpty else { return nil }
        let a = last7.reduce(0, +) / Double(last7.count), b = prior.reduce(0, +) / Double(prior.count)
        let diff = Int((a - b).rounded())
        let word = diff == 0 ? String(localized: "level with") : (diff > 0 ? String(localized: "\(diff) points above") : String(localized: "\(-diff) points below"))
        return remembering(NunaAnyaRead(headline: String(localized: "Charge averaged \(Int(a.rounded()))% this week, \(word) the month before"),
                                        detail: String(localized: "Compared with \(prior.count) earlier days (\(Int(b.rounded()))% on average)."),
                                        read: ["Charge", "30 days"], module: .trends, questions: questions(.trends)), values: ["week": a, "before": b])
    }

    // MARK: Breathing

    /// The Breathing module's read: the advisor's pick for right now, with the figures behind it and a note on the last session.
    private static func breathing(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let s = await NunaBreathAdviceMaker.make(repo: repo, profile: profile)
        var detail = s.detail
        if let last = NunaBreathLog.all().first, let pct = last.rmssdChangePct {
            let note = String(localized: "Last session: HRV \(String(format: "%+.0f", locale: AppLanguage.activeLocale, pct))% over \(last.durationText).")
            detail = [detail, note].compactMap { $0 }.joined(separator: " ")
        }
        return NunaAnyaRead(headline: s.headline, detail: detail, read: s.read, module: .breathing, questions: questions(.breathing))
    }

    // MARK: Workouts

    private static func workouts(repo: Repository, scale: EffortScale) async -> NunaAnyaRead? {
        let rows = await repo.workoutRows()
        let from = Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
        let week = rows.filter { $0.startTs >= from }
        guard !week.isEmpty else { return nil }
        let effort = week.compactMap(\.strain).reduce(0, +)
        let minutes = Int(week.reduce(0.0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) } / 60)
        return remembering(NunaAnyaRead(headline: String(localized: "\(week.count) sessions this week, Effort \(UnitFormatter.effortDisplay(effort, scale: scale))"),
                                        detail: String(localized: "\(minutes) minutes of training in the last 7 days."),
                                        read: ["Workouts 7 days", "Effort"], module: .workouts, questions: questions(.workouts)),
                           values: ["sessions": Double(week.count), "minutes": Double(minutes), "weekEffort": Double(UnitFormatter.effortDisplay(effort, scale: scale)) ?? effort])
    }

    // MARK: Questions per module (AnyaSheet*.dc.html)

    static func questions(_ module: NunaAnyaModule) -> [NunaAnyaQuestion] {
        switch module {
        case .today:
            return [NunaAnyaQuestion(title: String(localized: "Build today's plan"), prompt: "", kind: .plan),
                    NunaAnyaQuestion(title: String(localized: "Why did Charge change?"), prompt: "Why did my Charge change compared with yesterday? Use my sleep, HRV and resting heart rate."),
                    NunaAnyaQuestion(title: String(localized: "Summarise my day"), prompt: "Summarise my day so far in a few sentences, using my numbers.")]
        case .health:
            return [NunaAnyaQuestion(title: String(localized: "Explain my HRV"), prompt: "Explain what my HRV is telling me today, compared with my own baseline."),
                    NunaAnyaQuestion(title: String(localized: "What is fitness age?"), prompt: "What is fitness age and how is mine worked out in this app?"),
                    NunaAnyaQuestion(title: String(localized: "Check my lab results"), prompt: "Look at my Lab Book markers and tell me neutrally what stands out.")]
        case .sleep:
            return [NunaAnyaQuestion(title: String(localized: "Why did I wake up?"), prompt: "Why might I have woken up several times last night? Use my sleep numbers."),
                    NunaAnyaQuestion(title: String(localized: "Compare with last week"), prompt: "Compare my sleep this week with last week."),
                    NunaAnyaQuestion(title: String(localized: "How can I sleep better tonight?"), prompt: "Give me one practical step to sleep better tonight, based on my recent nights.")]
        case .trends:
            return [NunaAnyaQuestion(title: String(localized: "Why did Charge move?"), prompt: "Why did my Charge move over the last month? Point to the behaviours in my data."),
                    NunaAnyaQuestion(title: String(localized: "My hardest day"), prompt: "Which day was hardest on my body this month and what followed it?"),
                    NunaAnyaQuestion(title: String(localized: "Plan next week"), prompt: "Suggest how to spread training across next week given my recent load and recovery.")]
        case .workouts:
            return [NunaAnyaQuestion(title: String(localized: "Today's recommendation"), prompt: "Recommend the best workout for today using my Charge, Effort, Rest and recent workouts."),
                    NunaAnyaQuestion(title: String(localized: "Plan this week"), prompt: "Plan my training for this week from my current load and recovery."),
                    NunaAnyaQuestion(title: String(localized: "Recover faster"), prompt: "What helps me recover faster after my recent sessions?")]
        case .nutrition:
            return [NunaAnyaQuestion(title: String(localized: "Dinner suggestion"), prompt: "Suggest what to eat tonight given today's activity."),
                    NunaAnyaQuestion(title: String(localized: "How much protein do I need?"), prompt: "How much protein should I aim for, given my training?")]
        case .breathing:
            return [NunaAnyaQuestion(title: String(localized: "Which exercise fits me now?"), prompt: "Which breathing exercise fits me right now? Use my live heart rate, HRV, stress and Charge, and what worked in my earlier breathing sessions."),
                    NunaAnyaQuestion(title: String(localized: "How did my last sessions go?"), prompt: "How did my recent breathing sessions go? Look at the HRV and heart rate change in each and tell me what is working."),
                    NunaAnyaQuestion(title: String(localized: "How do I breathe better?"), prompt: "Give me one practical tip to get more from my breathing sessions, given how my body responded before.")]
        case .device:
            return [NunaAnyaQuestion(title: String(localized: "Why did the strap disconnect?"), prompt: "Why might my strap keep disconnecting from the phone?"),
                    NunaAnyaQuestion(title: String(localized: "How do I charge the battery?"), prompt: "How should I charge my strap and how long does the battery last?")]
        }
    }

    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
#endif
