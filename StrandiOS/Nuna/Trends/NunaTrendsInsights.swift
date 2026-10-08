#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Insights (TrendsInsights)

/// What shifts Charge, from the user's own journal and workouts: behaviour effects, the cost of hard sessions and the links
/// between metrics. Reuses `BehaviorInsights`, `ActivityCostEngine` and `CorrelationEngine`; nothing is estimated here.
struct NunaInsightsView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var m = NunaTrendsModel()
    @State private var effects: [BehaviorEffect] = []
    @State private var costs: [ActivityCost] = []
    @State private var loggedDays: [String: Int] = [:]
    @State private var journalDays = 0
    @State private var showCoach = false

    private var ready: Bool { m.charge.count >= 14 }

    var body: some View {
        NunaDetailScreen("Insights") {
            Text("What moves your Charge, from your own habits.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            NunaCard(small: true) {
                NunaListRow(ready ? "Enough data" : "Not enough data yet",
                            subtitle: LocalizedStringKey(String(localized: "\(m.charge.count) days recorded. At least 14 needed.")), systemImage: ready ? "checkmark" : "hourglass") {
                    NunaChip(ready ? "Ready" : "Waiting", color: ready ? NunaPalette.charge : NunaPalette.warning)
                }
            }
            behaviourSection
            costSection
            relationSection
            trackedSection
            NunaAnyaCard(verbatim: anyaLine) { showCoach = true }
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted)
                    Text("A link is not proof of cause. Effects are computed from your own data and recalculated every day. Confidence rises as more days are logged.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "trends") }
        .environment(\.nunaAnyaCardContext, "trends")
    }

    private var anyaLine: String {
        if let e = effects.first(where: { $0.significant }) {
            return BehaviorInsights.sentence(e)
        }
        if let c = CorrelationEngine.pearson(CorrelationEngine.alignByDay(m.rest, m.charge)), abs(c.r) >= 0.3 {
            return String(localized: "Your Charge follows your Rest closely (r = \(String(format: "%.2f", locale: AppLanguage.activeLocale, c.r))). Protecting sleep is your biggest lever.")
        }
        return String(localized: "Keep logging habits in your journal. After a few weeks this page shows what moves your Charge.")
    }

    // MARK: Behaviour effects

    private func confidence(_ e: BehaviorEffect) -> LocalizedStringKey {
        let n = min(e.nWith, e.nWithout)
        return n >= 10 && e.significant ? "High confidence" : (n >= 5 ? "Medium confidence" : "Low confidence")
    }

    @ViewBuilder private var behaviourSection: some View {
        NunaTitleRow(title: "Behaviour effects") { EmptyView() }
        if effects.isEmpty {
            NunaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No behaviour effects yet").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Log yes or no habits in your journal (caffeine, alcohol, hydration, late workouts). Once a habit has days with and without it, its effect on Charge shows here.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(effects.prefix(6), id: \.behavior) { e in
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: e.behavior).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: NunaTrendsFormat.signed(e.delta, 0)).font(.nuna(size: 26, weight: .bold, design: NunaType.design))
                                .foregroundStyle(e.delta >= 0 ? NunaPalette.charge : NunaPalette.warning)
                        }
                        HStack {
                            Text(verbatim: String(localized: "\(e.nWith) days with, \(e.nWithout) days without")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer()
                            Text("Charge, points").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        NunaChip(confidence(e), color: e.significant ? NunaPalette.restText : nil)
                    }
                }
            }
        }
    }

    // MARK: Activity cost

    @ViewBuilder private var costSection: some View {
        if let c = costs.first {
            NunaTitleRow(title: "Cost of activity") { EmptyView() }
            ForEach(costs.prefix(3), id: \.sport) { cost in
                NunaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(verbatim: WorkoutSource.displaySport(cost.sport)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: NunaTrendsFormat.signed(-cost.delta, 0)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(cost.delta >= 1 ? NunaPalette.warning : NunaPalette.charge)
                        }
                        Text(verbatim: cost.sentence()).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        if let d = cost.daysToBaseline {
                            HStack(spacing: 10) {
                                NunaChip(verbatim: String(localized: "+\(d) day"), color: nil)
                                Text("back to normal").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        }
                    }
                }
            }
            .id(c.sport)
        }
    }

    // MARK: Relationships

    private struct Rel: Identifiable { let id: String; let title: LocalizedStringKey; let r: Double }

    private var relations: [Rel] {
        var out: [Rel] = []
        func add(_ id: String, _ t: LocalizedStringKey, _ a: NunaDaySeries, _ b: NunaDaySeries, lag: Int = 0) {
            let pairs = TrendInsights.pairs(driver: a, outcome: b, lag: lag)
            if let c = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) }), c.n >= 7 { out.append(Rel(id: id, title: t, r: c.r)) }
        }
        add("hrv", "HRV ↔ Charge", m.hrv, m.charge)
        add("rhr", "Resting HR ↔ Charge", m.rhr, m.charge)
        add("stress", "Stress ↔ Rest", m.stress, m.rest)
        add("steps", "Steps ↔ Rest", m.steps, m.rest)
        return out
    }

    @ViewBuilder private var relationSection: some View {
        if !relations.isEmpty {
            NunaTitleRow(title: "Links between metrics") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(relations.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { NunaDivider() }
                        NunaListRow(r.title) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: NunaTrendsFormat.signed(r.r, 2)).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: NunaTrendsFormat.strengthLabel(r.r)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Tracked behaviours

    @ViewBuilder private var trackedSection: some View {
        NunaTitleRow(title: "Tracked behaviours") { EmptyView() }
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                if loggedDays.isEmpty {
                    NunaListRow("Nothing logged yet", subtitle: "Habits you log in the journal appear here", systemImage: "list.bullet.clipboard")
                } else {
                    ForEach(Array(loggedDays.sorted { $0.value > $1.value }.prefix(6).enumerated()), id: \.element.key) { i, kv in
                        if i > 0 { NunaDivider() }
                        NunaListRow(LocalizedStringKey(kv.key), subtitle: LocalizedStringKey(String(localized: "\(kv.value) days logged")), systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    // MARK: Load

    private func load() async {
        await m.load(repo: repo)
        let entries = await repo.journalEntries()
        var yes: [String: Set<String>] = [:], no: [String: Set<String>] = [:]
        for e in entries { if e.answeredYes { yes[e.question, default: []].insert(e.day) } else { no[e.question, default: []].insert(e.day) } }
        loggedDays = yes.mapValues(\.count)
        journalDays = Set(entries.map(\.day)).count
        let outcome = Dictionary(m.charge.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        effects = BehaviorInsights.rank(behaviors: yes, controls: no, outcomeByDay: outcome, outcome: String(localized: "Charge"))
        costs = InsightsView.computeActivityCosts(workouts: await repo.workoutRows(), days: repo.days)
    }
}

// MARK: - Compare (TrendsCompare)

/// Metrics the Compare and Explore screens can draw. `high` says whether a higher value is the better direction.
struct NunaSignal: Identifiable, Hashable {
    let id: String          // metric key
    let source: String
    let title: String
    let group: String
    let unit: String
    let digits: Int
}

enum NunaSignals {
    static let all: [NunaSignal] = [
        .init(id: "recovery", source: "my-whoop", title: String(localized: "Charge"), group: "Scores", unit: "%", digits: 0),
        .init(id: "strain", source: "my-whoop", title: String(localized: "Effort"), group: "Scores", unit: "", digits: 1),
        .init(id: "sleep_performance", source: "my-whoop", title: String(localized: "Rest"), group: "Scores", unit: "%", digits: 0),
        .init(id: "hrv", source: "my-whoop", title: String(localized: "HRV"), group: "Heart", unit: "ms", digits: 0),
        .init(id: "rhr", source: "my-whoop", title: String(localized: "Resting HR"), group: "Heart", unit: "bpm", digits: 0),
        .init(id: "max_hr", source: "my-whoop", title: String(localized: "Max heart rate"), group: "Heart", unit: "bpm", digits: 0),
        .init(id: "spo2", source: "my-whoop", title: "SpO₂", group: "Breathing and oxygen", unit: "%", digits: 0),
        .init(id: "resp_rate", source: "my-whoop", title: String(localized: "Respiratory rate"), group: "Breathing and oxygen", unit: "/min", digits: 1),
        .init(id: "skin_temp", source: "my-whoop", title: String(localized: "Skin temperature"), group: "Body", unit: "°C", digits: 1),
        .init(id: "weight", source: "apple-health", title: String(localized: "Weight"), group: "Body", unit: "kg", digits: 1),
        .init(id: "fitness_age", source: "my-whoop", title: String(localized: "Fitness age"), group: "Body", unit: "yr", digits: 0),
        .init(id: "steps_est", source: "my-whoop", title: String(localized: "Steps"), group: "Activity", unit: "", digits: 0),
        .init(id: "stress", source: "my-whoop", title: String(localized: "Stress"), group: "Activity", unit: "/ 3", digits: 1),
        .init(id: "sleep_total_min", source: "my-whoop", title: String(localized: "Sleep duration"), group: "Sleep", unit: "min", digits: 0),
        .init(id: "sleep_efficiency", source: "my-whoop", title: String(localized: "Efficiency"), group: "Sleep", unit: "%", digits: 0),
        .init(id: "sleep_consistency", source: "my-whoop", title: String(localized: "Consistency"), group: "Sleep", unit: "%", digits: 0),
    ]
    static func find(_ id: String) -> NunaSignal? { all.first { $0.id == id } }
}

/// Loads signals on demand and caches them for the lifetime of the screen.
@MainActor
final class NunaSignalStore: ObservableObject {
    @Published private(set) var series: [String: NunaDaySeries] = [:]
    func isEmpty(_ id: String) -> Bool { series[id]?.isEmpty == true }
    private var loading: Set<String> = []

    func ensure(_ s: NunaSignal, repo: Repository) async {
        guard series[s.id] == nil, !loading.contains(s.id) else { return }
        loading.insert(s.id)
        let rows = await repo.exploreSeries(key: s.id, source: s.source, days: 400)
        let clean = Dictionary(rows.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l }).map { (day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
        series[s.id] = clean
        loading.remove(s.id)
    }
}

struct NunaCompareView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var store = NunaSignalStore()
    @State private var picked: [String] = ["recovery", "sleep_performance"]
    @State private var range = 30
    @State private var shiftBack = false
    @State private var saved: [SavedComparison] = SavedComparison.load()
    private let today = Repository.localDayKey(Date())

    struct SavedComparison: Codable, Identifiable, Equatable {
        var id = UUID()
        var keys: [String]; var days: Int
        static let key = "nuna.compare.saved.v1"
        static func load() -> [SavedComparison] {
            guard let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode([SavedComparison].self, from: d) else { return [] }
            return v
        }
        static func store(_ v: [SavedComparison]) { if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) } }
    }

    private var colors: [Color] { [NunaPalette.charge, NunaPalette.restLight, NunaPalette.effortText, NunaPalette.warning] }
    private var start: String { TrendInsights.shift(today, by: -(range - 1)) ?? today }

    private func window(_ id: String, back: Int = 0) -> NunaDaySeries {
        guard let s = store.series[id], let lo = TrendInsights.shift(today, by: -(back + range - 1)), let hi = TrendInsights.shift(today, by: -back) else { return [] }
        return s.filter { $0.day >= lo && $0.day <= hi }
    }

    var body: some View {
        NunaDetailScreen("Compare") {
            pickerCard
            NunaSegmented(NunaTrendsRange.options, selection: $range)
            chartCard
            if picked.count >= 2 { correlationCard }
            shiftCard
            savedSection
        }
        .task { for id in picked { if let s = NunaSignals.find(id) { await store.ensure(s, repo: repo) } } }
    }

    private var pickerCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaTrendsCap("Pick 2 to 4 metrics"); Spacer(); Text(verbatim: String(localized: "\(picked.count) picked")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                NunaFlowChips(items: NunaSignals.all.map(\.id)) { id in
                    let on = picked.contains(id)
                    Button {
                        if on { if picked.count > 2 { picked.removeAll { $0 == id } } }
                        else if picked.count < 4 { picked.append(id); if let s = NunaSignals.find(id) { Task { await store.ensure(s, repo: repo) } } }
                    } label: {
                        Text(verbatim: NunaSignals.find(id)?.title ?? id).font(.nuna(size: 13.5, weight: .bold))
                            .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 38)
                            .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: on ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var chartCard: some View {
        // Each line is scaled to its own range in the window, so different units can share one box.
        var lines: [NunaMultiLineChart.Line] = []
        for (i, id) in picked.enumerated() {
            let w = window(id)
            guard let lo = w.map(\.value).min(), let hi = w.map(\.value).max() else { continue }
            let span = max(hi - lo, 0.0001)
            lines.append(.init(series: w.map { ($0.day, ($0.value - lo) / span) }, max: 1, color: colors[i % colors.count]))
            if shiftBack, i == 0 {
                let p = window(id, back: range)
                let shifted: NunaDaySeries = p.compactMap { r in TrendInsights.shift(r.day, by: range).map { ($0, (r.value - lo) / span) } }
                lines.append(.init(series: shifted, max: 1, color: colors[0].opacity(0.35)))
            }
        }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaTrendsCap("Compared"); Spacer(); Text("Scale normalised").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                if lines.isEmpty {
                    ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    NunaMultiLineChart(start: start, days: range, lines: lines, height: 160)
                }
                HStack(spacing: 14) {
                    ForEach(Array(picked.enumerated()), id: \.offset) { i, id in
                        HStack(spacing: 6) { RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(colors[i % colors.count]).frame(width: 14, height: 8)
                            Text(verbatim: NunaSignals.find(id)?.title ?? id).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }
                }
            }
        }
    }

    private var correlationCard: some View {
        let ids = Array(picked.prefix(4))
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Correlation")
                ForEach(0..<ids.count, id: \.self) { i in
                    ForEach((i + 1)..<max(ids.count, i + 1), id: \.self) { j in
                        let pairs = TrendInsights.pairs(driver: window(ids[i]), outcome: window(ids[j]), lag: 0)
                        HStack {
                            Text(verbatim: (NunaSignals.find(ids[i])?.title ?? "") + " · " + (NunaSignals.find(ids[j])?.title ?? "")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            if let c = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) }) { NunaChip(verbatim: NunaTrendsFormat.relationChip(c.r)) }
                            else { Text("Not enough days").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                        }
                    }
                }
            }
        }
    }

    private var shiftCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Shift the period")
                NunaListRow(LocalizedStringKey(String(localized: "Compare with the previous \(range) days")), description: "Draws the first metric from the period before as a faint line") {
                    Toggle("", isOn: $shiftBack).labelsHidden().tint(NunaPalette.charge)
                }
                Button {
                    let item = SavedComparison(keys: picked, days: range)
                    if !saved.contains(where: { $0.keys == item.keys && $0.days == item.days }) { saved.append(item); SavedComparison.store(saved) }
                } label: {
                    HStack(spacing: 8) { Image(systemName: "checkmark").font(.nuna(size: 13, weight: .bold)); Text("Save comparison").font(.nuna(size: 15, weight: .bold)) }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var savedSection: some View {
        if !saved.isEmpty {
            NunaTitleRow(title: "Saved") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(saved.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 8) {
                            Button {
                                picked = s.keys; range = [7, 30, 90, 365].contains(s.days) ? s.days : 30
                                Task { for id in s.keys { if let sig = NunaSignals.find(id) { await store.ensure(sig, repo: repo) } } }
                            } label: {
                                NunaListRow(LocalizedStringKey(s.keys.compactMap { NunaSignals.find($0)?.title }.joined(separator: ", ")),
                                            subtitle: LocalizedStringKey(String(localized: "\(s.days) days")), systemImage: "chart.line.uptrend.xyaxis", showsChevron: true)
                            }.buttonStyle(.plain)
                            Button { saved.removeAll { $0.id == s.id }; SavedComparison.store(saved) } label: {
                                Image(systemName: "trash").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted).frame(width: 36, height: 36)
                            }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Explore (TrendsExplore)

struct NunaExploreView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var store = NunaSignalStore()
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var query = ""
    @State private var filter = "all"
    @State private var favourites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "nuna.explore.fav") ?? [])

    private var visible: [NunaSignal] {
        NunaSignals.all.filter { s in
            !store.isEmpty(s.id)
                && (query.isEmpty || s.title.localizedCaseInsensitiveContains(query))
                && (filter == "all" || (filter == "fav" && favourites.contains(s.id)) || s.group == filter)
        }
    }
    private var groups: [String] { var seen: [String] = []; for s in visible where !seen.contains(s.group) { seen.append(s.group) }; return seen }

    var body: some View {
        NunaDetailScreen("Explore") {
            Color.clear.frame(height: 0).task { for s in NunaSignals.all { await store.ensure(s, repo: repo) } }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                TextField("", text: $query, prompt: Text("Search signals").foregroundStyle(NunaPalette.textMuted)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            }
            .padding(.horizontal, 16).frame(height: 48).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("all", String(localized: "All")); chip("fav", String(localized: "Favourites"))
                    chip("Scores", String(localized: "Scores")); chip("Heart", String(localized: "Heart")); chip("Sleep", String(localized: "Sleep")); chip("Body", String(localized: "Body"))
                }
            }
            ForEach(groups, id: \.self) { g in
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey(g)).font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    NunaCard(small: true, padding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)) {
                        VStack(spacing: 0) {
                            let rows = visible.filter { $0.group == g }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { NunaDivider() }
                                row(s)
                            }
                        }
                    }
                }
            }
            if visible.isEmpty && !store.series.isEmpty { Text("No signals match.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
        }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        Button { filter = id } label: {
            Text(verbatim: title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(filter == id ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 36).background(filter == id ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func row(_ s: NunaSignal) -> some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let conv: (Double) -> Double = { s.id == "strain" ? UnitFormatter.effortValue($0, scale: scale) : $0 }
        let data = (store.series[s.id] ?? []).map { (day: $0.day, value: conv($0.value)) }
        let last30 = Array(data.suffix(30)).map(\.value)
        let route: NunaTodayRoute? = MetricCatalog.metric(key: s.id, source: s.source).map { .metric($0) }
        return HStack(spacing: 10) {
            Button {
                if favourites.contains(s.id) { favourites.remove(s.id) } else { favourites.insert(s.id) }
                UserDefaults.standard.set(Array(favourites), forKey: "nuna.explore.fav")
            } label: {
                Image(systemName: favourites.contains(s.id) ? "star.fill" : "star").font(.nuna(size: 14, weight: .bold))
                    .foregroundStyle(favourites.contains(s.id) ? NunaPalette.textPrimary : NunaPalette.textMuted).frame(width: 30, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("Favourite"))
            Group {
                if let route {
                    NavigationLink(value: route) { content(s, last30, data.last?.value) }.buttonStyle(.plain)
                } else { content(s, last30, data.last?.value) }
            }
        }
        .frame(minHeight: 64)
        .task { await store.ensure(s, repo: repo) }
    }

    private func content(_ s: NunaSignal, _ spark: [Double], _ last: Double?) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: s.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            NunaSpark(values: spark).frame(width: 64, height: 30)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: last.map { s.id == "strain" ? NunaTrendsFormat.num($0, 1) : NunaTrendsFormat.num($0, s.digits) } ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if last != nil, !s.unit.isEmpty { Text(verbatim: s.unit).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            .frame(minWidth: 70, alignment: .trailing)
            Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .contentShape(Rectangle())
    }
}
#endif
