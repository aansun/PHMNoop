#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What the journal's behaviors do to Charge. It reads the same journal and the same daily Charge the rest of the app does and leaves the
/// maths to `BehaviorInsights`; this is the page.
@MainActor
final class NunaBehaviorModel: ObservableObject {
    @Published private(set) var rows: [BehaviorSummary.Row] = []
    /// behavior → day → answered yes.
    @Published private(set) var answers: [String: [String: Bool]] = [:]
    @Published private(set) var charge: [String: Double] = [:]
    @Published private(set) var loaded = false

    /// The window the effects are read over: the last 90 days.
    static let windowDays = 90

    static func sinceKey() -> String {
        let d = Calendar.current.date(byAdding: .day, value: -windowDays, to: Date()) ?? Date()
        return Repository.localDayKey(d)
    }

    func load(repo: Repository) async {
        let entries = await repo.journalEntries(days: 400)
        var map: [String: [String: Bool]] = [:]
        for e in entries { map[e.question, default: [:]][e.day] = e.answeredYes }
        let series = await repo.exploreSeries(key: "recovery", source: "my-whoop", days: 400)
        charge = Dictionary(series.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        answers = map
        rows = BehaviorSummary.rows(answers: map, outcomeByDay: charge, since: Self.sinceKey(), outcome: "Charge")
        loaded = true
    }

    /// The short name of a journal question: "Did you drink any alcohol?" is "Alcohol". The starter questions have their own names; any other
    /// question loses its "Did you" and its question mark and is shown as the sentence it is.
    private static let shortNames: [String: String] = [
        "Did you drink any alcohol?": "Alcohol",
        "Did you have caffeine late in the day?": "Late caffeine",
        "Did you view a screen in bed?": "Screen in bed",
        "Did you eat close to bedtime?": "Late meal",
        "Did you feel stressed?": "Stress",
        "Did you use a sauna?": "Sauna",
        "Did you share your bed?": "Shared bed",
        "Did you feel sick or ill?": "Feeling ill",
        "Did you take magnesium?": "Magnesium",
        "Did you read before bed?": "Read in bed",
    ]

    static func title(_ question: String) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if let known = shortNames[q] { return String(localized: String.LocalizationValue(known)) }
        var t = q
        if t.hasSuffix("?") { t.removeLast() }
        if t.hasPrefix("Did you ") { t.removeFirst("Did you ".count) }
        return t.isEmpty ? question : t.prefix(1).uppercased() + t.dropFirst()
    }
}

// MARK: - The list

struct NunaBehaviorInsightsView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaBehaviorModel()
    @State private var open: String?

    var body: some View {
        NunaDetailScreen("Behavior insights", centersTitle: true) {
            if model.loaded {
                if model.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log your behaviors to reveal personalized insights").font(.nuna(size: 24, weight: .bold, design: NunaType.design))
                            .foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                        Text("Record at least 5 yes's and no's in your journal to see how behaviors impact your Charge.")
                            .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    header
                    ForEach(model.rows) { row in
                        NavigationLink(value: NunaBehaviorRoute(behavior: row.behavior)) { listRow(row) }.buttonStyle(.plain)
                    }
                    discovered
                }
            }
        }
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .navigationDestination(for: NunaBehaviorRoute.self) { NunaBehaviorDetailView(behavior: $0.behavior, model: model) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log your behaviors to reveal personalized insights").font(.nuna(size: 24, weight: .bold, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            Text("Record at least 5 yes's and no's in your journal to see how behaviors impact your Charge.")
                .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }

    private func listRow(_ row: BehaviorSummary.Row) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: NunaBehaviorModel.title(row.behavior)).font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
                HStack(alignment: .center, spacing: 14) {
                    NunaImpactBar(percent: row.percent, scale: 20)
                    counts(row)
                }
            }
        }
    }

    private func counts(_ row: BehaviorSummary.Row) -> some View {
        HStack(spacing: 8) {
            count("xmark", row.no)
            count("checkmark", row.yes)
        }
    }

    private func count(_ symbol: String, _ n: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.nuna(size: 9, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
                .frame(width: 18, height: 18).overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(NunaPalette.textSecondary, lineWidth: 1.4))
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    /// The behaviors with a finding, split into those that hurt and those that help.
    @ViewBuilder private var discovered: some View {
        let split = BehaviorSummary.split(model.rows)
        if !split.hurts.isEmpty || !split.helps.isEmpty {
            NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 14, bottom: 14, trailing: 14)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                        Text("What moves your Charge").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    }
                    HStack {
                        Label("Hurts", systemImage: "arrowtriangle.down.fill").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel)
                            .textCase(.uppercase).foregroundStyle(NunaPalette.warning)
                        Spacer()
                        Text("% impact").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Label("Helps", systemImage: "arrowtriangle.up.fill").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel)
                            .textCase(.uppercase).foregroundStyle(NunaPalette.charge)
                    }
                    ForEach(split.helps + split.hurts) { row in
                        NavigationLink(value: NunaBehaviorRoute(behavior: row.behavior)) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(verbatim: NunaBehaviorModel.title(row.behavior)).font(.nuna(size: 16, weight: .semibold))
                                        .foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                    NunaImpactBar(percent: row.percent, scale: 20)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                            .padding(14).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct NunaBehaviorRoute: Hashable { let behavior: String }

/// A bar from a centre mark: green to the right for a behavior that helps, amber to the left for one that hurts, hatched where there is no
/// finding yet, with the figure at its end.
struct NunaImpactBar: View {
    let percent: Double?
    /// The percent at which the bar reaches its end.
    var scale: Double = 20

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width, mid = w / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(NunaPalette.hairline.opacity(0.55)).frame(height: 7)
                        .overlay(NunaHatch().clipShape(Capsule()).opacity(0.6))
                    if let p = percent {
                        let len = min(abs(p) / scale, 1) * mid
                        Capsule().fill(p >= 0 ? NunaPalette.charge : NunaPalette.warning).frame(width: max(len, 6), height: 7)
                            .offset(x: p >= 0 ? mid : mid - len)
                    }
                    Circle().fill(NunaPalette.textPrimary).frame(width: 9, height: 9).overlay(Circle().strokeBorder(NunaPalette.canvas, lineWidth: 2))
                        .offset(x: mid - 4.5)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            if let p = percent {
                Text(verbatim: String(format: "%+.0f%%", p)).font(.nuna(size: 15, weight: .bold, design: NunaType.design))
                    .foregroundStyle(p >= 0 ? NunaPalette.charge : NunaPalette.warning).frame(minWidth: 52, alignment: .trailing).textCase(nil)
            }
        }
    }
}

/// Fine diagonal stripes: the mark of a range that has no figure yet.
private struct NunaHatch: View {
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(NunaPalette.textMuted.opacity(0.55)), lineWidth: 1.2)
                x += 5
            }
        }
    }
}

// MARK: - One behavior

/// One behavior: what it does to Charge and every day it was answered, three months at a time.
struct NunaBehaviorDetailView: View {
    let behavior: String
    @ObservedObject var model: NunaBehaviorModel
    @State private var endMonth = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
    @State private var open = true

    private var row: BehaviorSummary.Row? { model.rows.first { $0.behavior == behavior } }
    private var byDay: [String: Bool] { model.answers[behavior] ?? [:] }

    var body: some View {
        NunaDetailScreen("Behavior details", centersTitle: true) {
            Text(verbatim: NunaBehaviorModel.title(behavior)).font(.nuna(size: 32, weight: .bold, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            impact
            Text("Logging history").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            history
        }
    }

    // MARK: Impact

    private var impact: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 14) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack {
                        Text("Charge impact").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Text(verbatim: row?.percent == nil ? String(localized: "Not available") : String(localized: "Your data"))
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .padding(.horizontal, 10).frame(height: 28).background(NunaPalette.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                NunaImpactBar(percent: row?.percent, scale: 20)
                if open {
                    Text(verbatim: message).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var message: String {
        guard let row else { return String(localized: "Continue logging to unlock insights. At least 5 yes's and no's are required in the past 90 days.") }
        if let e = row.effect, e.significant {
            // The sentence names the behavior by its short name, not by the question the journal asks.
            let named = BehaviorEffect(behavior: NunaBehaviorModel.title(e.behavior), outcome: e.outcome, meanWith: e.meanWith, meanWithout: e.meanWithout,
                                       delta: e.delta, pctChange: e.pctChange, nWith: e.nWith, nWithout: e.nWithout,
                                       cohensD: e.cohensD, pApprox: e.pApprox, significant: e.significant)
            return BehaviorInsights.sentence(named)
        }
        if row.unlocked { return String(localized: "No clear effect on your Charge yet. It stays hidden until the difference is large enough to trust.") }
        return String(localized: "Continue logging to unlock insights. At least 5 yes's and no's are required in the past 90 days.")
    }

    // MARK: Logging history

    private var months: [DateComponents] {
        (0..<3).reversed().compactMap { back in
            var c = DateComponents(); c.year = endMonth.year; c.month = (endMonth.month ?? 1) - back
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: c.year, month: c.month, day: 1))
                .map { Calendar(identifier: .gregorian).dateComponents([.year, .month], from: $0) }
        }
    }

    /// "AUG '26 - OCT '26": the first and the last month on show.
    private var rangeTitle: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM")
        let cal = Calendar(identifier: .gregorian)
        func label(_ c: DateComponents) -> String {
            guard let d = cal.date(from: DateComponents(year: c.year, month: c.month, day: 1)) else { return "" }
            return f.string(from: d) + " '" + String(format: "%02d", (c.year ?? 0) % 100)
        }
        guard let a = months.first, let b = months.last else { return "" }
        return label(a) + " - " + label(b)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button { shift(-3) } label: { Image(systemName: "chevron.left").font(.nuna(size: 15, weight: .bold)).frame(width: 36, height: 36) }
                Text(verbatim: rangeTitle).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                Button { shift(3) } label: { Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .bold)).frame(width: 36, height: 36) }
                    .disabled(!canGoForward).opacity(canGoForward ? 1 : 0.35)
            }
            .foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain)
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in monthGrid(m) }
            }
            legend
        }
    }

    private var canGoForward: Bool {
        let now = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        return (endMonth.year ?? 0) * 12 + (endMonth.month ?? 0) < (now.year ?? 0) * 12 + (now.month ?? 0)
    }

    private func shift(_ delta: Int) {
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(from: DateComponents(year: endMonth.year, month: (endMonth.month ?? 1) + delta, day: 1)) else { return }
        let next = cal.dateComponents([.year, .month], from: d)
        let now = cal.dateComponents([.year, .month], from: Date())
        if (next.year ?? 0) * 12 + (next.month ?? 0) > (now.year ?? 0) * 12 + (now.month ?? 0) { endMonth = now } else { endMonth = next }
    }

    private func monthGrid(_ m: DateComponents) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let layout = BehaviorSummary.month(year: m.year ?? 2026, month: m.month ?? 1)
        let name: String = {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM")
            return cal.date(from: DateComponents(year: m.year, month: m.month, day: 1)).map { f.string(from: $0) } ?? ""
        }()
        let today = Repository.localDayKey(Date())
        let yesCount = layout?.days.filter { byDay[$0] == true }.count ?? 0
        let cells: [String?] = Array(repeating: nil, count: layout?.firstWeekday ?? 0) + (layout?.days.map { Optional($0) } ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: name).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Spacer(minLength: 0)
                if yesCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.nuna(size: 9, weight: .heavy))
                        Text(verbatim: "\(yesCount)").font(.nuna(size: 11, weight: .heavy, design: NunaType.design))
                    }
                    .foregroundStyle(NunaPalette.restText).padding(.horizontal, 6).frame(height: 20)
                    .background(NunaRestChart.steel.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(verbatim: d).font(.nuna(size: 10.5, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).frame(height: 14)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, key in
                    if let key { dot(key, today: key == today) } else { Color.clear.frame(height: 12) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func dot(_ key: String, today: Bool) -> some View {
        let a = BehaviorSummary.answer(byDay, on: key)
        ZStack {
            switch a {
            case .yes: Circle().fill(NunaRestChart.steel)
            case .no: Circle().fill(NunaPalette.textMuted)
            case .missing: Circle().strokeBorder(NunaPalette.textMuted.opacity(0.7), lineWidth: 1.2)
            }
            if today { Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: 1.6).padding(-3) }
        }
        .frame(width: 11, height: 11).frame(maxWidth: .infinity)
    }

    private var legend: some View {
        let all = byDay
        let yes = all.values.filter { $0 }.count, no = all.values.filter { !$0 }.count
        let missing = max(Self.daysInRange(months) - all.filter { shown($0.key) }.count, 0)
        return HStack(spacing: 22) {
            legendItem(Circle().fill(NunaRestChart.steel), "Yes", yes)
            legendItem(Circle().fill(NunaPalette.textMuted), "No", no)
            legendItem(Circle().strokeBorder(NunaPalette.textMuted.opacity(0.7), lineWidth: 1.2), "Missing", missing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem<S: View>(_ shape: S, _ title: LocalizedStringKey, _ n: Int) -> some View {
        HStack(spacing: 7) {
            shape.frame(width: 11, height: 11)
            Text(title).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(verbatim: "(\(n))").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func shown(_ key: String) -> Bool {
        guard let first = months.first, let last = months.last,
              let a = BehaviorSummary.month(year: first.year ?? 0, month: first.month ?? 1)?.days.first,
              let b = BehaviorSummary.month(year: last.year ?? 0, month: last.month ?? 1)?.days.last else { return false }
        return key >= a && key <= b
    }

    private static func daysInRange(_ months: [DateComponents]) -> Int {
        months.reduce(0) { $0 + (BehaviorSummary.month(year: $1.year ?? 0, month: $1.month ?? 1)?.days.count ?? 0) }
    }
}
#endif
