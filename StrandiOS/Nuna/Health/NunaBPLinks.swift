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

/// "+6 / +4"; the unit is written beside it where there is room.
private func changeText(_ p: PressureLinks.Pressure) -> String {
    func signed(_ v: Double) -> String { let r = Int(v.rounded()); return r > 0 ? "+\(r)" : (r < 0 ? "−\(-r)" : "0") }
    // Held together, so a sentence never breaks inside the pair.
    return signed(p.systolic) + "\u{00A0}/\u{00A0}" + signed(p.diastolic)
}

/// How much higher the higher side reads, "6 / 4"; a figure that leans the other way keeps its minus.
private func gapSize(_ c: PressureLinks.Comparison) -> String? {
    guard let d = c.difference, c.verdict == .firstHigher || c.verdict == .firstLower else { return nil }
    let way = c.verdict == .firstHigher ? 1.0 : -1.0
    func shown(_ v: Double) -> String { let r = Int((v * way).rounded()); return r < 0 ? "−\(-r)" : "\(r)" }
    return shown(d.systolic) + " / " + shown(d.diastolic)
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

    func load(repo: Repository, readings: [NunaBPReading], effortScale: EffortScale) async {
        let pressure = readings.map(\.linked)
        let daily = PressureLinks.daily(pressure) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0))) }
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

        // Journal: what was answered for a day, beside the readings of the day after.
        let entries = await repo.journalEntries(days: 400)
        var answers: [String: [String: Bool]] = [:]
        for e in entries {
            guard let date = Self.date(e.day), let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { continue }
            answers[e.question, default: [:]][Repository.localDayKey(next)] = e.answeredYes
        }
        let compared = answers.map { Behaviour(question: $0.key, comparison: PressureLinks.compare(daily, flags: $0.value)) }
        journalAnswered = !answers.isEmpty
        behaviours = compared.filter { $0.comparison.verdict != .needMore }.sorted { a, b in
            // Those with a gap first, the widest at the top.
            let x = a.comparison.verdict == .same ? 0 : abs(a.comparison.difference?.systolic ?? 0)
            let y = b.comparison.verdict == .same ? 0 : abs(b.comparison.difference?.systolic ?? 0)
            return x != y ? x > y : a.question < b.question
        }
        waiting = compared.count - behaviours.count

        pairs = PressureLinks.breathPairs(pressure, sessions: NunaBreathLog.all().map { .init(start: $0.startTs, end: $0.startTs + $0.seconds) })
        loaded = true
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

/// One row a topic: what it shows so far, and the way to the figures behind it.
struct NunaBPLinksSection: View {
    let readings: [NunaBPReading]
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your readings and your data").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    ForEach(NunaBPTopic.allCases) { topic in
                        if topic != .sleep { NunaDivider() }
                        NavigationLink(value: NunaTodayRoute.bloodPressureLinks(topic)) { row(topic) }.buttonStyle(.plain)
                    }
                }
            }
            Text("Patterns in your own readings, not proof of cause.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(readings.count)-\(readings.last?.takenAt ?? 0)-\(repo.refreshSeq)-\(effortScaleRaw)") {
            await model.load(repo: repo, readings: readings, effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
    }

    private func row(_ topic: NunaBPTopic) -> some View {
        let (state, figure) = model.loaded ? summary(topic) : ("…", nil)
        return NunaListRow(LocalizedStringKey(topic.title), subtitle: LocalizedStringKey(state), systemImage: topic.icon, showsChevron: true) {
            if let figure {
                Text(verbatim: figure).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .monospacedDigit().textCase(nil).lineLimit(1).fixedSize()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// The row's second line and, where there is one, the size of the gap or change.
    private func summary(_ topic: NunaBPTopic) -> (String, String?) {
        let needed = PressureLinks.daysNeeded
        func collected(_ n: Int) -> String { String(localized: "\(n) of \(needed * 2) days collected") }
        switch topic {
        case .sleep, .activity, .weight:
            guard let level = model.levels.first(where: { $0.topic == topic }) else { return ("–", nil) }
            guard let c = level.comparison else {
                return (level.shared < needed * 2 ? collected(level.shared) : String(localized: "Too little variation to compare"), nil)
            }
            switch c.verdict {
            case .needMore: return (collected(min(c.first.days, needed) + min(c.second.days, needed)), nil)
            case .same: return (String(localized: "No clear difference"), nil)
            case .firstHigher, .firstLower:
                let higher = c.verdict == .firstHigher
                let words: String
                switch topic {
                case .sleep: words = higher ? String(localized: "Higher after shorter sleep") : String(localized: "Lower after shorter sleep")
                case .activity: words = higher ? String(localized: "Higher after lighter days") : String(localized: "Lower after lighter days")
                default: words = higher ? String(localized: "Higher at lower weight") : String(localized: "Higher at higher weight")
                }
                return (words, gapSize(c))
            }
        case .journal:
            if !model.journalAnswered { return (String(localized: "Answer your journal to compare"), nil) }
            guard let top = model.behaviours.first else { return (String(localized: "No behaviour has enough days yet"), nil) }
            guard let size = gapSize(top.comparison) else { return (String(localized: "No clear difference"), nil) }
            let name = NunaBehaviorModel.title(top.question)
            return (top.comparison.verdict == .firstHigher ? String(localized: "Higher the day after: \(name)") : String(localized: "Lower the day after: \(name)"), size)
        case .breathing:
            guard let change = PressureLinks.meanChange(model.pairs) else { return (String(localized: "No session measured before and after yet"), nil) }
            return (model.pairs.count == 1 ? String(localized: "Change in 1 session") : String(localized: "Average change, \(model.pairs.count) sessions"), changeText(change))
        }
    }
}

// MARK: - The detail page

/// One topic at a time: the two sides and their days, what that says, and how it is worked out.
struct NunaBPLinksView: View {
    @State var topic: NunaBPTopic
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()

    var body: some View {
        NunaDetailScreen("Your readings and your data", centersTitle: true) {
            chips
            if !model.loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                switch topic {
                case .sleep, .activity, .weight:
                    if let level = model.levels.first(where: { $0.topic == topic }) { levelCard(level) }
                case .journal: journal
                case .breathing: breathing
                }
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("How it is compared")
                    Text(verbatim: method).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3)
                        .textCase(nil).fixedSize(horizontal: false, vertical: true)
                    Text("These are patterns in your own readings, not proof of cause: other things change on the same days, and a cuff reading varies by itself. Not a diagnosis.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)-\(effortScaleRaw)") {
            await model.load(repo: repo, readings: await NunaBP.load(repo), effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(NunaBPTopic.allCases) { t in
                        NunaBPTopicChip(title: t.title, selected: t == topic) { topic = t }.id(t)
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH)
            }
            .scrollIndicators(.hidden)
            // Out to the screen's edges, so a chip cut off there reads as more to come.
            .padding(.horizontal, -NunaSpacing.screenH)
            .onAppear { proxy.scrollTo(topic, anchor: .center) }
        }
    }

    private var method: String {
        let needed = PressureLinks.daysNeeded
        switch topic {
        case .sleep: return String(localized: "Your measured days are split at the middle of your own sleep, taken from the night before each one. Each day counts once, as the average of its readings. A side needs \(needed) days.")
        case .activity: return String(localized: "Your measured days are split at the middle of your own strain on the day before each one. Each day counts once, as the average of its readings. A side needs \(needed) days.")
        case .weight: return String(localized: "Your measured days are split at the middle of your own weight, using the latest weighing in the two weeks up to each one. A side needs \(needed) days.")
        case .journal: return String(localized: "A day's journal answer is compared with the readings of the day after. Each side needs \(needed) measured days.")
        case .breathing: return String(localized: "Measure within half an hour before a breathing session and again within half an hour after. Sitting still lowers a reading too, so part of a drop may be the rest itself.")
        }
    }

    private func words(_ text: String, color: Color = NunaPalette.textPrimary) -> some View {
        Text(verbatim: text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(color).textCase(nil)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A side of a comparison. While it is short of days, five marks show how far it has come.
    private func side(_ label: String, _ s: PressureLinks.Side, size: CGFloat, progress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: s.mean.map { NunaBP.text($0.systolic, $0.diastolic) } ?? "–")
                .font(.nuna(size: size, weight: .bold, design: NunaType.design))
                .foregroundStyle(s.mean.map { NunaBPCategory.of($0.systolic, $0.diastolic).color } ?? NunaPalette.textMuted)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: s.days == 1 ? String(localized: "1 day") : String(localized: "\(s.days) days"))
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            if progress { marks(min(s.days, PressureLinks.daysNeeded), of: PressureLinks.daysNeeded) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func marks(_ done: Int, of total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule().fill(i < done ? NunaPalette.textPrimary : NunaPalette.ink.opacity(0.14)).frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func levelCard(_ level: NunaBPLinksModel.Level) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    nunaTrendsCap(LocalizedStringKey(level.title))
                    Spacer(minLength: 8)
                    if let c = level.comparison, c.verdict != .needMore, c.early { NunaChip("Early") }
                }
                if let c = level.comparison {
                    HStack(alignment: .top, spacing: 18) {
                        side(level.first, c.first, size: 34, progress: c.verdict == .needMore)
                        side(level.second, c.second, size: 34, progress: c.verdict == .needMore)
                    }
                    NunaDivider()
                    words(verdict(c, first: level.first))
                } else if let note = level.note {
                    if level.shared < PressureLinks.daysNeeded * 2 { marks(level.shared, of: PressureLinks.daysNeeded * 2) }
                    words(note)
                }
            }
        }
    }

    private func verdict(_ c: PressureLinks.Comparison, first: String) -> String {
        let gap = c.difference.map { changeText($0) + "\u{00A0}mmHg" } ?? "–"
        switch c.verdict {
        case .needMore: return String(localized: "Needs \(PressureLinks.daysNeeded) days on each side: \(c.first.days) and \(c.second.days) so far.")
        case .same: return String(localized: "No clear difference (\(gap)).")
        case .firstHigher: return String(localized: "\(first): reads higher (\(gap)).")
        case .firstLower: return String(localized: "\(first): reads lower (\(gap)).")
        }
    }

    @ViewBuilder private var journal: some View {
        if model.behaviours.isEmpty {
            NunaCard {
                words(model.journalAnswered ? String(localized: "No behaviour has \(PressureLinks.daysNeeded) measured days after both a Yes and a No yet.")
                                            : String(localized: "Answer your journal on the days around your readings, and each behaviour is compared here."))
            }
        } else {
            ForEach(model.behaviours) { b in
                let c = b.comparison
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(verbatim: NunaBehaviorModel.title(b.question)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .textCase(nil).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if c.verdict == .same { NunaChip("No clear difference") }
                            else if let d = c.difference { NunaChip(verbatim: changeText(d) + " mmHg", color: NunaPalette.textPrimary).textCase(nil) }
                        }
                        HStack(alignment: .top, spacing: 18) {
                            side(String(localized: "After Yes"), c.first, size: 24, progress: false)
                            side(String(localized: "After No"), c.second, size: 24, progress: false)
                        }
                    }
                }
            }
            if model.waiting > 0 { words(String(localized: "Behaviours still short of days: \(model.waiting)."), color: NunaPalette.textMuted) }
        }
    }

    @ViewBuilder private var breathing: some View {
        if let change = PressureLinks.meanChange(model.pairs) {
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        nunaTrendsCap("Average change")
                        Spacer(minLength: 8)
                        if model.pairs.count < PressureLinks.daysNeeded { NunaChip("Early") }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: changeText(change)).font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                        Text(verbatim: "mmHg").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    words(model.pairs.count == 1 ? String(localized: "From before to after, in 1 session measured both sides.")
                                                 : String(localized: "Average from before to after, over \(model.pairs.count) sessions measured both sides."),
                          color: NunaPalette.textSecondary)
                }
            }
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    ForEach(model.pairs.prefix(10), id: \.session.start) { pair in
                        if pair.session.start != model.pairs.first?.session.start { NunaDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: NunaBP.when(Date(timeIntervalSince1970: TimeInterval(pair.session.start))))
                                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Text(verbatim: NunaBP.text(pair.before.systolic, pair.before.diastolic) + "  →  " + NunaBP.text(pair.after.systolic, pair.after.diastolic))
                                .font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } else {
            NunaCard { words(String(localized: "No session measured before and after yet")) }
        }
    }
}
#endif
