#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The person's own readings beside their sleep, activity, weight, journal and breathing sessions. The comparisons are `PressureLinks`; this file
// gathers the data and words the result. Nothing here says that one thing causes another.

extension NunaBPReading {
    var linked: PressureLinks.Reading { .init(takenAt: takenAt, systolic: systolic, diastolic: diastolic) }
}

/// The five things the readings are compared with, one row each on the Blood pressure page.
enum NunaBPTopic: String, CaseIterable, Identifiable, Hashable {
    case sleep, activity, weight, journal, breathing
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .sleep: return NunaIcons.sleep
        case .activity: return "figure.run"
        case .weight: return NunaIcons.weight
        case .journal: return NunaIcons.journal
        case .breathing: return NunaIcons.breathing
        }
    }
    var color: Color {
        switch self {
        case .sleep: return NunaPalette.restDeep
        case .journal: return NunaPalette.textSecondary
        default: return NunaPalette.effortModerate
        }
    }
    var title: String {
        switch self {
        case .sleep: return String(localized: "Sleep")
        case .activity: return String(localized: "Activity")
        case .weight: return String(localized: "Body weight")
        case .journal: return String(localized: "Journal")
        case .breathing: return String(localized: "Breathing sessions")
        }
    }
}

@MainActor
final class NunaBPLinksModel: ObservableObject {
    /// One measured level split in two: hours slept, effort or weight.
    struct Level: Identifiable {
        let topic: NunaBPTopic
        var id: NunaBPTopic { topic }
        let title: String
        let first: String
        let second: String
        /// Nil with too little variation or no shared days; `note` then says why.
        let comparison: PressureLinks.Comparison?
        let note: String?
        /// Days with both a reading and this figure.
        let shared: Int
    }

    struct Behaviour: Identifiable {
        var id: String { question }
        let question: String
        let comparison: PressureLinks.Comparison
    }

    @Published private(set) var levels: [Level] = []
    @Published private(set) var behaviours: [Behaviour] = []
    /// Journal questions answered but still short of days.
    @Published private(set) var waiting = 0
    @Published private(set) var journalAnswered = false
    @Published private(set) var pairs: [PressureLinks.BreathPair] = []
    @Published private(set) var loaded = false
    /// What the charts draw, each by day: the readings' day means, the sleep, effort and weight set beside them, the journal's answers (on the day
    /// after they were given) and the mean change over a day's breathing sessions.
    @Published private(set) var daily: [String: PressureLinks.Pressure] = [:]
    @Published private(set) var series: [NunaBPTopic: [String: Double]] = [:]
    @Published private(set) var answers: [String: [String: Bool]] = [:]
    @Published private(set) var breathChange: [String: Double] = [:]
    private(set) var effortScale = EffortScale.whoop

    func load(repo: Repository, readings: [NunaBPReading], effortScale: EffortScale) async {
        let pressure = readings.map(\.linked)
        let daily = PressureLinks.daily(pressure) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0))) }
        self.daily = daily
        self.effortScale = effortScale
        let metrics = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, l in l })

        // Sleep: the night that ended on the morning of the reading's day.
        let sleep = metrics.compactMapValues(\.totalSleepMin)
        var out = [level(.sleep, title: String(localized: "Sleep the night before"), daily: daily, values: sleep, minimumSpread: 30,
                         words: { m in (String(localized: "Under \(NunaHighlightEngine.hm(m))"), String(localized: "\(NunaHighlightEngine.hm(m)) or more")) },
                         still: String(localized: "Your sleep is much the same on the days you measured, so there is nothing to compare yet."))]

        // Activity: the effort of the day before, shown for the day of the reading.
        var before: [String: Double] = [:]
        for day in daily.keys {
            guard let date = Self.date(day), let prior = Calendar.current.date(byAdding: .day, value: -1, to: date),
                  let strain = metrics[Repository.localDayKey(prior)]?.strain else { continue }
            before[day] = strain
        }
        out.append(level(.activity, title: String(localized: "Activity the day before"), daily: daily, values: before, minimumSpread: 10,
                         words: { m in
                             let shown = UnitFormatter.effortDisplay(m, scale: effortScale)
                             return (String(localized: "Strain under \(shown)"), String(localized: "Strain \(shown) or more"))
                         },
                         still: String(localized: "Your activity is much the same before the days you measured, so there is nothing to compare yet.")))

        // For the charts, every day has its own figure: a day's activity is the one before it.
        var dayBefore: [String: Double] = [:]
        for (day, m) in metrics {
            guard let strain = m.strain, let date = Self.date(day), let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { continue }
            dayBefore[Repository.localDayKey(next)] = strain
        }

        // Weight: the latest weighing in the two weeks up to the reading's day; a typed one wins over an imported one.
        var weighed: [String: Double] = [:]
        for source in ["apple-health", nunaManualSource] {
            for p in await repo.exploreSeries(key: "weight", source: source, days: 800) where p.value > 0 { weighed[p.day] = p.value }
        }
        var weight: [String: Double] = [:]
        for day in daily.keys {
            guard let date = Self.date(day) else { continue }
            for back in 0..<14 {
                if let d = Calendar.current.date(byAdding: .day, value: -back, to: date), let w = weighed[Repository.localDayKey(d)] { weight[day] = w; break }
            }
        }
        out.append(level(.weight, title: String(localized: "Body weight"), daily: daily, values: weight, minimumSpread: 1,
                         words: { m in
                             let shown = String(format: "%.1f kg", locale: AppLanguage.activeLocale, m)
                             return (String(localized: "Under \(shown)"), String(localized: "\(shown) or more"))
                         },
                         still: String(localized: "Your weight has moved less than 1 kg across the days you measured, so there is nothing to compare yet.")))
        levels = out
        series = [.sleep: sleep, .activity: dayBefore, .weight: weighed]

        // Journal: what was answered for a day, beside the readings of the day after.
        let entries = await repo.journalEntries(days: 400)
        var answers: [String: [String: Bool]] = [:]
        for e in entries {
            guard let date = Self.date(e.day), let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { continue }
            answers[e.question, default: [:]][Repository.localDayKey(next)] = e.answeredYes
        }
        let compared = answers.map { Behaviour(question: $0.key, comparison: PressureLinks.compare(daily, flags: $0.value)) }
        journalAnswered = !answers.isEmpty
        self.answers = answers
        behaviours = compared.filter { $0.comparison.verdict != .needMore }.sorted { a, b in
            // Those with a gap first, the widest at the top.
            let x = a.comparison.verdict == .same ? 0 : abs(a.comparison.difference?.systolic ?? 0)
            let y = b.comparison.verdict == .same ? 0 : abs(b.comparison.difference?.systolic ?? 0)
            return x != y ? x > y : a.question < b.question
        }
        waiting = compared.count - behaviours.count

        pairs = PressureLinks.breathPairs(pressure, sessions: NunaBreathLog.all().map { .init(start: $0.startTs, end: $0.startTs + $0.seconds) })
        breathChange = Dictionary(grouping: pairs) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.session.start))) }
            .compactMapValues { PressureLinks.meanChange($0)?.systolic }
        loaded = true
    }

    // MARK: Wording

    /// "+6 / +4", held together so a sentence never breaks inside the pair.
    static func changeText(_ p: PressureLinks.Pressure) -> String {
        func signed(_ v: Double) -> String { let r = Int(v.rounded()); return r > 0 ? "+\(r)" : (r < 0 ? "−\(-r)" : "0") }
        return signed(p.systolic) + "\u{00A0}/\u{00A0}" + signed(p.diastolic)
    }

    /// The behaviour the journal's chart opens on: the one with the widest gap, else the one answered on the most measured days.
    var leadQuestion: String? {
        if let first = behaviours.first { return first.question }
        func measured(_ q: String) -> Int { answers[q]?.keys.filter { daily[$0] != nil }.count ?? 0 }
        return answers.keys.sorted().max { measured($0) < measured($1) }
    }

    /// How a topic's own figure is written: hours and minutes of sleep, strain on the person's scale, kilograms.
    func figureText(_ topic: NunaBPTopic, _ v: Double) -> String {
        switch topic {
        case .sleep: let m = Int(v.rounded()); return String(format: "%d:%02d", m / 60, m % 60)
        case .activity: return UnitFormatter.effortDisplay(v, scale: effortScale)
        case .weight: return String(format: "%.1f", locale: AppLanguage.activeLocale, v)
        case .journal: return v > 0 ? String(localized: "Yes") : String(localized: "No")
        case .breathing: let r = Int(v.rounded()); return r > 0 ? "+\(r)" : (r < 0 ? "−\(-r)" : "0")
        }
    }

    /// What a topic says so far, over all the readings, in a sentence.
    func sentence(_ topic: NunaBPTopic, question: String? = nil) -> String {
        let needed = PressureLinks.daysNeeded
        switch topic {
        case .sleep, .activity, .weight:
            guard let level = levels.first(where: { $0.topic == topic }) else { return "–" }
            guard let c = level.comparison else { return level.note ?? "–" }
            return Self.verdict(c, first: level.first)
        case .journal:
            guard journalAnswered else { return String(localized: "Answer your journal on the days around your readings, and each behaviour is compared here.") }
            guard let q = question ?? leadQuestion, let flags = answers[q] else { return String(localized: "No behaviour has \(needed) measured days after both a Yes and a No yet.") }
            let c = PressureLinks.compare(daily, flags: flags)
            return Self.verdict(c, first: String(localized: "After Yes: \(NunaBehaviorModel.title(q))"))
        case .breathing:
            guard let change = PressureLinks.meanChange(pairs) else { return String(localized: "No session measured before and after yet") }
            let words = pairs.count == 1 ? String(localized: "From before to after, in 1 session measured both sides.")
                                         : String(localized: "Average from before to after, over \(pairs.count) sessions measured both sides.")
            return Self.changeText(change) + "\u{00A0}mmHg. " + words
        }
    }

    static func verdict(_ c: PressureLinks.Comparison, first: String) -> String {
        let gap = c.difference.map { changeText($0) + "\u{00A0}mmHg" } ?? "–"
        switch c.verdict {
        case .needMore: return String(localized: "Needs \(PressureLinks.daysNeeded) days on each side: \(c.first.days) and \(c.second.days) so far.")
        case .same: return String(localized: "No clear difference (\(gap)).")
        case .firstHigher: return String(localized: "\(first): reads higher (\(gap)).")
        case .firstLower: return String(localized: "\(first): reads lower (\(gap)).")
        }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    /// Noon of a day key, so stepping a day back or forth never lands on the wrong date.
    private static func date(_ day: String) -> Date? { dayFormat.date(from: day).map { $0.addingTimeInterval(12 * 3600) } }

    private func level(_ topic: NunaBPTopic, title: String, daily: [String: PressureLinks.Pressure], values: [String: Double], minimumSpread: Double,
                       words: (Double) -> (String, String), still: String) -> Level {
        let shared = daily.keys.filter { values[$0] != nil }.count
        if let r = PressureLinks.compareByLevel(daily, level: values, minimumSpread: minimumSpread) {
            let (first, second) = words(r.middle)
            return Level(topic: topic, title: title, first: first, second: second, comparison: r.comparison, note: nil, shared: shared)
        }
        let note = shared < PressureLinks.daysNeeded * 2
            ? String(localized: "Needs \(PressureLinks.daysNeeded * 2) days with both a reading and this figure: \(shared) so far.")
            : still
        return Level(topic: topic, title: title, first: "", second: "", comparison: nil, note: note, shared: shared)
    }
}

// MARK: - On the Blood pressure page

/// A week a topic, drawn like the weekly trend cards of the other pages, with the blood pressure of each day under it. A card opens the topic's
/// trend page.
struct NunaBPLinksSection: View {
    let readings: [NunaBPReading]
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your readings and your data").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .accessibilityAddTraits(.isHeader).padding(.top, 8).padding(.bottom, 2).padding(.horizontal, 4)
            if model.loaded {
                ForEach(NunaBPTopic.allCases) { card($0) }
            } else {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            }
            Text("Patterns in your own readings, not proof of cause.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(readings.count)-\(readings.last?.takenAt ?? 0)-\(repo.refreshSeq)-\(effortScaleRaw)") {
            await model.load(repo: repo, readings: readings, effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
    }

    private func card(_ topic: NunaBPTopic) -> some View {
        let values: [String: Double]
        switch topic {
        case .journal: values = (model.leadQuestion.flatMap { model.answers[$0] } ?? [:]).mapValues { $0 ? 1 : 0 }
        case .breathing: values = model.breathChange
        default: values = model.series[topic] ?? [:]
        }
        return NunaWeeklyTrendCard(title: LocalizedStringKey(cardTitle(topic)), key: "bp.\(topic.rawValue)",
                                   style: topic == .weight || topic == .breathing ? .line : .bars,
                                   color: topic.color,
                                   destination: { AnyView(NunaBPTrendView(topic: topic)) },
                                   points: values.map { (day: $0.key, value: $0.value) },
                                   valueText: { model.figureText(topic, $0) },
                                   autoScale: true,
                                   under: { date in
                                       model.daily[Repository.localDayKey(date)].map { p in
                                           ("\(Int(p.systolic.rounded()))", "\(Int(p.diastolic.rounded()))", NunaBPCategory.of(p.systolic, p.diastolic).color)
                                       }
                                   },
                                   underCaption: "Blood pressure",
                                   note: model.sentence(topic))
    }

    /// What the card's drawing is, with its unit.
    private func cardTitle(_ topic: NunaBPTopic) -> String {
        switch topic {
        case .sleep: return String(localized: "Sleep the night before")
        case .activity: return String(localized: "Activity the day before")
        case .weight: return String(localized: "Body weight (kg)")
        case .journal: return model.leadQuestion.map { String(localized: "Journal: \(NunaBehaviorModel.title($0))") } ?? String(localized: "Journal")
        case .breathing: return String(localized: "Breathing sessions: change")
        }
    }
}
#endif
