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

/// "+6 / +4 mmHg".
private func gapText(_ p: PressureLinks.Pressure) -> String {
    func signed(_ v: Double) -> String { let r = Int(v.rounded()); return r > 0 ? "+\(r)" : (r < 0 ? "−\(-r)" : "0") }
    return signed(p.systolic) + " / " + signed(p.diastolic) + " mmHg"
}

@MainActor
final class NunaBPLinksModel: ObservableObject {
    /// One measured level split in two: hours slept, effort or weight.
    struct Level: Identifiable {
        let id: String
        let icon: String
        let title: String
        let first: String
        let second: String
        /// Nil with too little variation or no shared days; `note` then says why.
        let comparison: PressureLinks.Comparison?
        let note: String?
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
        var out = [level("sleep", icon: NunaIcons.sleep, title: String(localized: "Sleep the night before"), daily: daily, values: sleep, minimumSpread: 30,
                         words: { m in (String(localized: "Under \(NunaHighlightEngine.hm(m))"), String(localized: "\(NunaHighlightEngine.hm(m)) or more")) },
                         still: String(localized: "Your sleep is much the same on the days you measured, so there is nothing to compare yet."))]

        // Activity: the effort of the day before, shown for the day of the reading.
        var before: [String: Double] = [:]
        for day in daily.keys {
            guard let date = Self.date(day), let prior = Calendar.current.date(byAdding: .day, value: -1, to: date),
                  let strain = metrics[Repository.localDayKey(prior)]?.strain else { continue }
            before[day] = strain
        }
        out.append(level("activity", icon: "figure.run", title: String(localized: "Activity the day before"), daily: daily, values: before, minimumSpread: 10,
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
        out.append(level("weight", icon: NunaIcons.weight, title: String(localized: "Body weight"), daily: daily, values: weight, minimumSpread: 1,
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

    private func level(_ id: String, icon: String, title: String, daily: [String: PressureLinks.Pressure], values: [String: Double], minimumSpread: Double,
                       words: (Double) -> (String, String), still: String) -> Level {
        if let r = PressureLinks.compareByLevel(daily, level: values, minimumSpread: minimumSpread) {
            let (first, second) = words(r.middle)
            return Level(id: id, icon: icon, title: title, first: first, second: second, comparison: r.comparison, note: nil)
        }
        let shared = daily.keys.filter { values[$0] != nil }.count
        let note = shared < PressureLinks.daysNeeded * 2
            ? String(localized: "Needs \(PressureLinks.daysNeeded * 2) days with both a reading and this figure: \(shared) so far.")
            : still
        return Level(id: id, icon: icon, title: title, first: "", second: "", comparison: nil, note: note)
    }
}

/// The section on the Blood pressure page.
struct NunaBPLinksSection: View {
    let readings: [NunaBPReading]
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaBPLinksModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your readings and your data").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            if model.loaded {
                ForEach(model.levels) { levelCard($0) }
                journalCard
                breathCard
                Text("These are patterns in your own readings, not proof of cause: other things change on the same days, and a cuff reading varies by itself. Not a diagnosis.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(readings.count)-\(readings.last?.takenAt ?? 0)-\(repo.refreshSeq)-\(effortScaleRaw)") {
            await model.load(repo: repo, readings: readings, effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
    }

    private func title(_ icon: String, _ text: String, early: Bool) -> some View {
        HStack(spacing: 10) {
            NunaIcon(name: icon, size: 17, weight: .medium).foregroundStyle(NunaPalette.textSecondary).frame(width: 22)
            Text(verbatim: text).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if early { NunaChip("Early") }
        }
    }

    private func line(_ text: String, color: Color = NunaPalette.textSecondary) -> some View {
        Text(verbatim: text).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(color).textCase(nil)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ label: String, _ side: PressureLinks.Side) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let m = side.mean {
                Text(verbatim: NunaBP.text(m.systolic, m.diastolic)).font(.nuna(size: 24, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaBPCategory.of(m.systolic, m.diastolic).color).monospacedDigit()
            } else {
                Text(verbatim: "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted)
            }
            Text(verbatim: side.days == 1 ? String(localized: "1 day") : String(localized: "\(side.days) days"))
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdict(_ c: PressureLinks.Comparison, first: String, second: String) -> String {
        switch c.verdict {
        case .needMore:
            return String(localized: "Needs \(PressureLinks.daysNeeded) days on each side: \(c.first.days) and \(c.second.days) so far.")
        case .same:
            return String(localized: "No clear difference (\(c.difference.map(gapText) ?? "–")).")
        case .firstHigher:
            return String(localized: "\(first): reads higher (\(c.difference.map(gapText) ?? "–")).")
        case .firstLower:
            return String(localized: "\(first): reads lower (\(c.difference.map(gapText) ?? "–")).")
        }
    }

    private func levelCard(_ level: NunaBPLinksModel.Level) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                title(level.icon, level.title, early: level.comparison.map { $0.verdict != .needMore && $0.early } ?? false)
                if let c = level.comparison {
                    HStack(alignment: .top, spacing: 14) { column(level.first, c.first); column(level.second, c.second) }
                    line(verdict(c, first: level.first, second: level.second), color: c.verdict == .needMore ? NunaPalette.textSecondary : NunaPalette.textPrimary)
                } else if let note = level.note {
                    line(note)
                }
            }
        }
    }

    // MARK: Journal

    private var journalCard: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                title(NunaIcons.journal, String(localized: "Journal: the day after"), early: model.behaviours.contains { $0.comparison.early })
                ForEach(model.behaviours.prefix(6)) { b in
                    NunaDivider()
                    behaviourRow(b)
                }
                if !model.journalAnswered {
                    line(String(localized: "Answer your journal on the days around your readings, and each behaviour is compared here."))
                } else if model.behaviours.isEmpty {
                    line(String(localized: "No behaviour has \(PressureLinks.daysNeeded) measured days after both a Yes and a No yet."))
                } else if model.waiting > 0 {
                    line(String(localized: "Behaviours still short of days: \(model.waiting)."), color: NunaPalette.textMuted)
                }
            }
        }
    }

    /// One behaviour in two lines: its name with the gap (or that there is none), then the two means and their days.
    private func behaviourRow(_ b: NunaBPLinksModel.Behaviour) -> some View {
        let c = b.comparison
        let gap = c.verdict == .same ? String(localized: "No clear difference") : (c.difference.map(gapText) ?? "–")
        func side(_ label: String, _ s: PressureLinks.Side) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: label).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    if let m = s.mean {
                        Text(verbatim: NunaBP.text(m.systolic, m.diastolic)).font(.nuna(size: 15, weight: .bold, design: NunaType.design))
                            .foregroundStyle(NunaBPCategory.of(m.systolic, m.diastolic).color).monospacedDigit()
                    }
                }
                Text(verbatim: s.days == 1 ? String(localized: "1 day") : String(localized: "\(s.days) days"))
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: NunaBehaviorModel.title(b.question)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: gap).font(.nuna(size: 13, weight: .bold)).foregroundStyle(c.verdict == .same ? NunaPalette.textMuted : NunaPalette.textPrimary)
                    .textCase(nil).multilineTextAlignment(.trailing)
            }
            HStack(alignment: .top, spacing: 14) { side(String(localized: "After Yes"), c.first); side(String(localized: "After No"), c.second) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Breathing

    private var breathCard: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                title(NunaIcons.breathing, String(localized: "Breathing sessions"), early: !model.pairs.isEmpty && model.pairs.count < PressureLinks.daysNeeded)
                if let change = PressureLinks.meanChange(model.pairs) {
                    Text(verbatim: gapText(change)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        .monospacedDigit().textCase(nil)
                    line(model.pairs.count == 1 ? String(localized: "From before to after, in 1 session measured both sides.")
                                                : String(localized: "Average from before to after, over \(model.pairs.count) sessions measured both sides."))
                    ForEach(model.pairs.prefix(3), id: \.session.start) { pair in
                        NunaDivider()
                        HStack {
                            Text(verbatim: NunaBP.when(Date(timeIntervalSince1970: TimeInterval(pair.session.start))))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer(minLength: 8)
                            Text(verbatim: NunaBP.text(pair.before.systolic, pair.before.diastolic) + " → " + NunaBP.text(pair.after.systolic, pair.after.diastolic))
                                .font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                        }
                    }
                    line(String(localized: "Sitting still lowers a reading too, so part of a drop may be the rest itself."), color: NunaPalette.textMuted)
                } else {
                    line(String(localized: "Measure within half an hour before a breathing session and again within half an hour after, and the change shows here."))
                }
            }
        }
    }
}
#endif
