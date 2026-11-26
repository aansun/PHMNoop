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
        waiting = compared.count - behaviours.count

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

/// One card for a week: the blood pressure drawn on top, then under the same days, a row each, the sleep of the night before, the strain of the day
/// before, the weight, the journal's yes or no and the change around breathing sessions. A row opens that topic's trend page.
struct NunaBPLinksSection: View {
    let readings: [NunaBPReading]
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()
    /// How many weeks back from the one ending today.
    @State private var back = 0

    /// The width of the column the row icons stand in, left of the seven days.
    private let gutter: CGFloat = 30
    private var window: NunaTrendWindow { NunaTrendWindow(range: 7, page: back, endingDaysAgo: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your readings and your data").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .accessibilityAddTraits(.isHeader).padding(.top, 8).padding(.bottom, 2).padding(.horizontal, 4)
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
        let w = window
        let days = w.noons
        let keys = days.map { Repository.localDayKey($0) }
        let question = model.leadQuestion
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    NunaDateStepper(label: w.label, canGoBack: model.daily.keys.min().map { Repository.localDayKey(w.start) > $0 } ?? false,
                                    canGoForward: back > 0, back: { back += 1 }, forward: { back = max(0, back - 1) })
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        icon(NunaIcons.bloodPressure)
                        NunaBPWeekPlot(days: keys.map { model.daily[$0] }).frame(height: 170)
                    }
                    HStack(spacing: 0) {
                        Color.clear.frame(width: gutter, height: 1)
                        ForEach(Array(days.enumerated()), id: \.offset) { i, date in dayLabel(date, last: back == 0 && i == days.count - 1) }
                    }
                    .padding(.vertical, 6)
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
                .background(alignment: .topLeading) { if back == 0 { today } }
                NunaDivider()
                Text(verbatim: key(question)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    /// Today's column, lifted as on the weekly cards.
    private var today: some View {
        GeometryReader { g in
            let column = (g.size.width - gutter) / 7
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NunaPalette.glassStrong)
                .frame(width: max(column - 2, 0), height: g.size.height).offset(x: gutter + column * 6 + 1)
        }
        .accessibilityHidden(true)
    }

    private func icon(_ name: String) -> some View {
        NunaIcon(name: name, size: 17, weight: .medium).foregroundStyle(NunaPalette.textSecondary).frame(width: gutter, alignment: .leading)
    }

    private func dayLabel(_ date: Date, last: Bool) -> some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(spacing: 1) {
            Text(verbatim: f.string(from: date)).font(.nuna(size: 11.5, weight: .semibold)).textCase(nil)
            Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.nuna(size: 12.5, weight: .heavy)).textCase(nil)
        }
        .foregroundStyle(last ? NunaPalette.textPrimary : NunaPalette.textSecondary)
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
    }

    private func row(_ topic: NunaBPTopic, _ keys: [String], _ cell: @escaping (String) -> Cell?) -> some View {
        NavigationLink { NunaBPTrendView(topic: topic) } label: {
            VStack(spacing: 0) {
                NunaDivider()
                HStack(spacing: 0) {
                    icon(topic.icon)
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                        let c = cell(k)
                        VStack(spacing: 0) {
                            Text(verbatim: c?.upper ?? "–")
                            if let lower = c?.lower { Text(verbatim: lower) }
                        }
                        .font(.nuna(size: 13.5, weight: .bold, design: NunaType.design)).foregroundStyle(c?.color ?? NunaPalette.textMuted)
                        .monospacedDigit().textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 48)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: topic.title + ": " + keys.map { k in cell(k).map { [$0.upper, $0.lower].compactMap { $0 }.joined(separator: " ") } ?? "–" }.joined(separator: ", ")))
    }

    /// What each icon's figures are, once, under the rows.
    private func key(_ question: String?) -> String {
        let journal = question.map { NunaBehaviorModel.title($0) } ?? String(localized: "no answer yet")
        return String(localized: "Sleep: hours the night before. Strain: the day before. Weight in kg. Journal: \(journal), the day before. Breathing: change in pressure around a session. Tap a row for its trend.")
    }
}

/// The week's blood pressure over seven equal columns: the upper and the lower figure of each measured day, joined to the day beside it.
private struct NunaBPWeekPlot: View {
    let days: [PressureLinks.Pressure?]

    var body: some View {
        Canvas { ctx, size in
            let present = days.compactMap { $0 }
            let column = size.width / CGFloat(max(days.count, 1))
            for fraction in [0.0, 0.5, 1.0] {
                var rule = Path(); let y = max(0.5, min(size.height - 0.5, size.height * fraction))
                rule.move(to: CGPoint(x: 0, y: y)); rule.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(rule, with: .color(NunaPalette.ink.opacity(0.08)), lineWidth: 1)
            }
            guard !present.isEmpty else {
                ctx.draw(Text("No reading in this period.").font(.nuna(size: 13, weight: .semibold)).foregroundColor(NunaPalette.textSecondary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2 - 12), anchor: .center)
                return
            }
            let low = (present.map(\.diastolic).min() ?? 70) - 6, high = (present.map(\.systolic).max() ?? 130) + 6
            // Room over the highest and under the lowest for their figures.
            let top: CGFloat = 24, bottom: CGFloat = 24
            func y(_ v: Double) -> CGFloat { top + (size.height - top - bottom) * CGFloat((high - v) / max(high - low, 1)) }
            func x(_ i: Int) -> CGFloat { column * (CGFloat(i) + 0.5) }
            for upper in [true, false] {
                var line = Path()
                var open = false
                for (i, day) in days.enumerated() {
                    guard let day else { open = false; continue }
                    let at = CGPoint(x: x(i), y: y(upper ? day.systolic : day.diastolic))
                    if open { line.addLine(to: at) } else { line.move(to: at); open = true }
                }
                ctx.stroke(line, with: .color(NunaPalette.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: upper ? [] : [4, 3]))
            }
            for (i, day) in days.enumerated() {
                guard let day else { continue }
                let tone = NunaBPCategory.of(day.systolic, day.diastolic).color
                for (v, lift) in [(day.systolic, -15.0), (day.diastolic, 15.0)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x(i) - 4.5, y: y(v) - 4.5, width: 9, height: 9)), with: .color(tone))
                    ctx.draw(Text(verbatim: "\(Int(v.rounded()))").font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundColor(tone),
                             at: CGPoint(x: x(i), y: y(v) + CGFloat(lift)), anchor: .center)
                }
            }
        }
        .textCase(nil)
        .accessibilityLabel(Text("Blood pressure"))
        .accessibilityValue(Text(verbatim: days.map { $0.map { NunaBP.text($0.systolic, $0.diastolic) } ?? "–" }.joined(separator: ", ")))
    }
}
#endif
