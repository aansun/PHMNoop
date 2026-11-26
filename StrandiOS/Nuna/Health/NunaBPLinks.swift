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
    @Published private(set) var journalAnswered = false
    @Published private(set) var pairs: [PressureLinks.BreathPair] = []
    @Published private(set) var loaded = false
    /// What the charts draw, each by day: the readings' day means, the sleep, effort and weight set beside them, the journal's answers (on the day
    /// after they were given) and the mean change over a day's breathing sessions.
    @Published private(set) var daily: [String: PressureLinks.Pressure] = [:]
    @Published private(set) var series: [NunaBPTopic: [String: Double]] = [:]
    @Published private(set) var answers: [String: [String: Bool]] = [:]
    @Published private(set) var breathChange: [String: PressureLinks.Pressure] = [:]
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

        pairs = PressureLinks.breathPairs(pressure, sessions: NunaBreathLog.all().map { .init(start: $0.startTs, end: $0.startTs + $0.seconds) })
        breathChange = Dictionary(grouping: pairs) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.session.start))) }
            .compactMapValues { PressureLinks.meanChange($0) }
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
            return Self.verdict(c, first: String(localized: "After a Yes to \(NunaBehaviorModel.title(q))"))
        case .breathing:
            guard let change = PressureLinks.meanChange(pairs) else { return String(localized: "No session measured before and after yet") }
            let words = pairs.count == 1 ? String(localized: "From before to after, in 1 session measured both sides.")
                                         : String(localized: "Average from before to after, over \(pairs.count) sessions measured both sides.")
            return Self.changeText(change) + "\u{00A0}mmHg. " + words
        }
    }

    /// How a topic's sides are worked out.
    static func method(_ topic: NunaBPTopic) -> String {
        let needed = PressureLinks.daysNeeded
        switch topic {
        case .sleep: return String(localized: "Your measured days are split at the middle of your own sleep, taken from the night before each one. Each day counts once, as the average of its readings. A side needs \(needed) days.")
        case .activity: return String(localized: "Your measured days are split at the middle of your own strain on the day before each one. Each day counts once, as the average of its readings. A side needs \(needed) days.")
        case .weight: return String(localized: "Your measured days are split at the middle of your own weight, using the latest weighing in the two weeks up to each one. A side needs \(needed) days.")
        case .journal: return String(localized: "A day's journal answer is compared with the readings of the day after. Each side needs \(needed) measured days.")
        case .breathing: return String(localized: "Measure within half an hour before a breathing session and again within half an hour after. Sitting still lowers a reading too, so part of a drop may be the rest itself.")
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

// MARK: - The page

/// "Your readings and your data": a week at a time, with its own way back and forth.
struct NunaBPLinksView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var loaded = false
    /// How many weeks back from the one ending today.
    @State private var back = 0

    private var window: NunaTrendWindow { NunaTrendWindow(range: 7, page: back, endingDaysAgo: 0) }

    var body: some View {
        let w = window
        NunaDetailScreen("Your readings and your data", centersTitle: true) {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                NunaDateStepper(label: w.label, canGoBack: readings.first.map { $0.date < w.start } ?? false, canGoForward: back > 0,
                                back: { back += 1 }, forward: { back = max(0, back - 1) })
                    .frame(maxWidth: .infinity)
                NunaBPLinksSection(readings: readings, days: w.noons)
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            readings = await NunaBP.load(repo)
            loaded = true
        }
    }
}

// MARK: - The week

/// A side of a comparison: its name, the mean and its days. While it is short of days, five marks show how far it has come.
struct NunaBPSideView: View {
    let label: String
    let side: PressureLinks.Side
    var size: CGFloat = 24
    var progress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: side.mean.map { NunaBP.text($0.systolic, $0.diastolic) } ?? "–")
                .font(.nuna(size: size, weight: .bold, design: NunaType.design))
                .foregroundStyle(side.mean.map { NunaBPCategory.of($0.systolic, $0.diastolic).color } ?? NunaPalette.textMuted)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: side.days == 1 ? String(localized: "1 day") : String(localized: "\(side.days) days"))
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            if progress {
                HStack(spacing: 4) {
                    ForEach(0..<PressureLinks.daysNeeded, id: \.self) { i in
                        Capsule().fill(i < side.days ? NunaPalette.textPrimary : NunaPalette.ink.opacity(0.14)).frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A week, a row a thing: the sleep of the night before, the strain of the day before, the weight, the journal's yes
/// or no and the change around breathing sessions. A row opens downward to say what its figures are and what they show beside the pressure.
struct NunaBPLinksSection: View {
    let readings: [NunaBPReading]
    /// The seven days of the rows, oldest first.
    let days: [Date]
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()
    @State private var open: NunaBPTopic?

    /// The columns beside the seven days: the row's icon at the left, its arrow at the right.
    private let gutter: CGFloat = 28
    private let arrow: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.loaded {
                card
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

    private var card: some View {
        let keys = days.map { Repository.localDayKey($0) }
        let question = model.leadQuestion
        return NunaCard(small: true) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutter, height: 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, date in
                        dayLabel(date, lit: i == days.count - 1)
                    }
                    Color.clear.frame(width: arrow, height: 1)
                }
                .padding(.bottom, 8)
                row(.sleep, keys) { k in model.series[.sleep]?[k].map { Cell(model.figureText(.sleep, $0)) } }
                row(.activity, keys) { k in model.series[.activity]?[k].map { Cell(model.figureText(.activity, $0)) } }
                row(.weight, keys) { k in model.series[.weight]?[k].map { Cell(model.figureText(.weight, $0)) } }
                row(.journal, keys) { k in
                    question.flatMap { model.answers[$0]?[k] }.map { yes in
                        Cell(yes ? String(localized: "bp.week.yes", defaultValue: "Y") : String(localized: "bp.week.no", defaultValue: "N"),
                             color: yes ? NunaPalette.textPrimary : NunaPalette.textMuted)
                    }
                }
                row(.breathing, keys) { k in
                    model.breathChange[k].map { c in Cell(model.figureText(.breathing, c.systolic), model.figureText(.breathing, c.diastolic)) }
                }
            }
        }
    }

    private func dayLabel(_ date: Date, lit: Bool) -> some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(spacing: 1) {
            Text(verbatim: f.string(from: date)).font(.nuna(size: 11.5, weight: .semibold)).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.nuna(size: 12.5, weight: .heavy)).textCase(nil)
        }
        .foregroundStyle(lit ? NunaPalette.textPrimary : NunaPalette.textSecondary)
        .frame(maxWidth: .infinity)
    }

    /// What one day says in a row: a figure, or an upper and a lower one.
    private struct Cell {
        let upper: String
        let lower: String?
        let color: Color
        init(_ upper: String, _ lower: String? = nil, color: Color = NunaPalette.textPrimary) {
            self.upper = upper; self.lower = lower; self.color = color
        }
        var spoken: String { [upper, lower].compactMap { $0 }.joined(separator: " ") }
    }

    private func row(_ topic: NunaBPTopic, _ keys: [String], _ cell: @escaping (String) -> Cell?) -> some View {
        let shown = open == topic
        return VStack(spacing: 0) {
            NunaDivider()
            Button { withAnimation(.easeInOut(duration: 0.2)) { open = shown ? nil : topic } } label: {
                HStack(spacing: 0) {
                    NunaIcon(name: topic.icon, size: 17, weight: .medium).foregroundStyle(NunaPalette.textSecondary).frame(width: gutter, alignment: .leading)
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                        let c = cell(k)
                        VStack(spacing: 0) {
                            Text(verbatim: c?.upper ?? "–")
                            if let lower = c?.lower { Text(verbatim: lower) }
                        }
                        .font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(c?.color ?? NunaPalette.textMuted)
                        .monospacedDigit().textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    }
                    Image(systemName: shown ? "chevron.up" : "chevron.down").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: arrow, alignment: .trailing)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: topic.title + ": " + keys.map { cell($0)?.spoken ?? "–" }.joined(separator: ", ")))
            .accessibilityHint(Text(shown ? "Hides the explanation" : "Shows the explanation"))
            if shown { explanation(topic) }
        }
    }

    /// Under an open row: what its figures are, what they show beside the pressure and how that is worked out.
    private func explanation(_ topic: NunaBPTopic) -> some View {
        let question = model.leadQuestion
        var comparison: (String, PressureLinks.Side, String, PressureLinks.Side, Bool)?
        var early = false
        if topic == .journal {
            if let b = model.behaviours.first(where: { $0.question == question }) {
                comparison = (String(localized: "After Yes"), b.comparison.first, String(localized: "After No"), b.comparison.second, false)
                early = b.comparison.early
            }
        } else if let level = model.levels.first(where: { $0.topic == topic }), let c = level.comparison {
            comparison = (level.first, c.first, level.second, c.second, c.verdict == .needMore)
            early = c.verdict != .needMore && c.early
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                nunaTrendsCap(LocalizedStringKey(topic.title))
                Spacer(minLength: 8)
                if early { NunaChip("Early") }
            }
            words(figures(topic, question), color: NunaPalette.textSecondary)
            words(model.sentence(topic, question: question))
            if let (first, a, second, b, short) = comparison {
                HStack(alignment: .top, spacing: 14) {
                    NunaBPSideView(label: first, side: a, size: 22, progress: short)
                    NunaBPSideView(label: second, side: b, size: 22, progress: short)
                }
            }
            Text(verbatim: NunaBPLinksModel.method(topic)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                .textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4).padding(.bottom, 14)
    }

    private func words(_ text: String, color: Color = NunaPalette.textPrimary) -> some View {
        Text(verbatim: text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(color).textCase(nil).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the numbers of a row are.
    private func figures(_ topic: NunaBPTopic, _ question: String?) -> String {
        switch topic {
        case .sleep: return String(localized: "Each figure is the sleep of the night before that day, in hours and minutes.")
        case .activity: return String(localized: "Each figure is the strain of the day before.")
        case .weight: return String(localized: "Each figure is the weight recorded that day, in kg.")
        case .journal:
            guard let question else { return String(localized: "Y or N is your journal answer from the day before.") }
            return String(localized: "Y or N is your answer from the day before for \(NunaBehaviorModel.title(question)).")
        case .breathing: return String(localized: "The change around that day's breathing sessions: upper figure above, lower figure below.")
        }
    }
}
#endif
