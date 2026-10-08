#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Pushes owned by the Nuna Trends stack.
enum NunaTrendsRoute: Hashable {
    case charge, effort, rest
    case chargeEffort, chargeRest
    case heatmap, insights, compare, explore
}

extension View {
    func nunaTrendsDestinations() -> some View {
        navigationDestination(for: NunaTrendsRoute.self) { r in
            switch r {
            case .charge: NunaTrendsMetricView(kind: .charge)
            case .effort: NunaTrendsMetricView(kind: .effort)
            case .rest: NunaTrendsMetricView(kind: .rest)
            case .chargeEffort: NunaChargeEffortView()
            case .chargeRest: NunaChargeRestView()
            case .heatmap: NunaHeatmapView()
            case .insights: NunaInsightsView()
            case .compare: NunaCompareView()
            case .explore: NunaExploreView()
            }
        }
    }
}

/// Trends root (docs/nuna/mockups/Trends.dc.html): range, summary with three rings, the two comparisons, daily
/// signals, the Charge heat map, what moves Charge, the change since the previous period and ways in to Explore,
/// Compare and Insights. Every figure is computed from the stored daily series.
struct NunaTrendsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var m = NunaTrendsModel()
    @State private var range = 30
    @State private var showReport = false
    @State private var showCoach = false
    @AppStorage("noop.coachEnabled") private var coachEnabled = true

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                header
                NunaSegmented(NunaTrendsRange.options, selection: $range)
                if !m.loaded {
                    ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
                } else if !m.hasAnything {
                    NunaCard {
                        Text("Trends appear once your strap has recorded a few days.").font(.nuna(size: 15, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading).textCase(nil)
                    }
                } else {
                    summaryCard
                    rangeReadCard
                    comparisonSection
                    signalsSection
                    heatmapCard
                    sinceCard
                    anyaCard
                    exploreSection
                    exportRow
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .nunaTrendsDestinations()
        .nunaTodayDestinations()
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
        .sheet(isPresented: $showReport) { NunaTrendsReportSheet(days: repo.days).environmentObject(repo) }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "trends") }
        .environment(\.nunaAnyaCardContext, "trends")
    }

    // MARK: Header

    private var rangeCaption: String {
        guard let a = TrendInsights.shift(m.todayKey, by: -(range - 1)), let da = m.date(a), let db = m.date(m.todayKey) else { return "" }
        if range > 90 {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yy")
            return f.string(from: da) + " – " + f.string(from: db)
        }
        return NunaTrendsFormat.short(da) + " – " + NunaTrendsFormat.short(db)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: rangeCaption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text("Trends").font(.nuna(size: NunaTypeSize.h1, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            Spacer()
        }
    }

    // MARK: Summary

    private func delta(_ now: Double?, _ before: Double?) -> Double? { (now != nil && before != nil) ? now! - before! : nil }

    private var summaryCard: some View {
        let c = m.means(m.charge, days: range), e = m.means(m.effort, days: range), r = m.means(m.rest, days: range)
        let win = m.window(m.charge, days: range)
        let green = win.filter { $0.value >= 67 }.count
        let best = win.max { $0.value < $1.value }, worst = win.min { $0.value < $1.value }
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Summary")
                    Spacer()
                    if !win.isEmpty { NunaChip(verbatim: String(localized: "\(green) of \(win.count) days green"), color: NunaPalette.charge) }
                }
                Text(verbatim: summarySentence(c: c, e: e, r: r)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
                HStack(alignment: .top, spacing: 0) {
                    ring(.charge, "Charge", c.now.map { $0 / 100 }, NunaTrendsFormat.num(c.now), "%", NunaPalette.charge, delta(c.now, c.before), suffix: String(localized: "points"), upGood: true)
                    ring(.effort, "Effort", e.now.map { $0 / 100 }, e.now.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–", "", NunaPalette.effortText,
                         delta(e.now, e.before).map { UnitFormatter.effortValue($0, scale: scale) }, suffix: "", upGood: nil)
                    ring(.rest, "Rest", r.now.map { $0 / 100 }, NunaTrendsFormat.num(r.now), "%", NunaPalette.restText, delta(r.now, r.before), suffix: String(localized: "points"), upGood: true)
                }
                if best != nil || worst != nil {
                    NunaDivider()
                    HStack {
                        if let best { stat("Best", "\(Int(best.value.rounded()))%", best.day) }
                        if let worst { stat("Lowest", "\(Int(worst.value.rounded()))%", worst.day) }
                    }
                }
            }
        }
    }

    /// Anya's read of the trends in view, from the same figures as the summary: how Charge moved against the period before, and what Effort
    /// and Rest did. Tapping it opens her with that line, ready to explain.
    @ViewBuilder private var rangeReadCard: some View {
        let c = m.means(m.charge, days: range), e = m.means(m.effort, days: range), r = m.means(m.rest, days: range)
        if coachEnabled, let now = c.now {
            let line: String = {
                guard let before = c.before else { return String(localized: "Charge averaged \(Int(now.rounded()))% over these \(range) days.") }
                let d = Int((now - before).rounded())
                let word = d == 0 ? String(localized: "level with") : (d > 0 ? String(localized: "\(d) points above") : String(localized: "\(-d) points below"))
                return String(localized: "Charge averaged \(Int(now.rounded()))% over these \(range) days, \(word) the period before.")
            }()
            let detail: String? = {
                var parts: [String] = []
                if let eNow = e.now { parts.append(String(localized: "Effort \(UnitFormatter.effortDisplay(eNow, scale: scale))")) }
                if let rNow = r.now { parts.append(String(localized: "Rest \(Int(rNow.rounded()))%")) }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }()
            NunaAnyaCard(verbatim: line, detail: detail) { showCoach = true }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, _ day: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if let d = m.date(day) { Text(verbatim: NunaTrendsFormat.withWeekday(d)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ring(_ route: NunaTrendsRoute, _ title: LocalizedStringKey, _ frac: Double?, _ value: String, _ unit: String, _ color: Color,
                      _ d: Double?, suffix: String, upGood: Bool?) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 8) {
                NunaRingGauge(fraction: frac ?? 0, color: color, size: 96, lineWidth: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                }
                Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if let d, abs(d) >= 0.05 {
                    Text(verbatim: (d > 0 ? "▲ " : "▼ ") + String(format: "%.1f", locale: AppLanguage.activeLocale, abs(d)) + (suffix.isEmpty ? "" : " " + suffix))
                        .font(.nuna(size: 12.5, weight: .heavy))
                        .foregroundStyle(upGood.map { (d > 0) == $0 ? NunaPalette.charge : NunaPalette.warning } ?? NunaPalette.textSecondary)
                }
                Text("Average").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func summarySentence(c: (now: Double?, before: Double?), e: (now: Double?, before: Double?), r: (now: Double?, before: Double?)) -> String {
        var first = ""
        if let d = delta(c.now, c.before) {
            let n = Int(abs(d).rounded())
            first = n == 0 ? String(localized: "Charge held steady against the previous period")
                : (d > 0 ? String(localized: "Charge rose \(n) points from the previous period") : String(localized: "Charge fell \(n) points from the previous period"))
        } else if c.now != nil { first = String(localized: "Charge has no earlier period to compare with yet") }
        var eff = "", rst = ""
        if let d = delta(e.now, e.before) {
            let rel = (e.before ?? 0) > 0 ? abs(d) / e.before! : 0
            eff = rel < 0.05 ? String(localized: "Effort stayed about the same") : (d > 0 ? String(localized: "Effort rose") : String(localized: "Effort fell a little"))
        }
        if let d = delta(r.now, r.before) {
            rst = abs(d) < 1 ? String(localized: "Rest stayed about the same") : (d > 0 ? String(localized: "Rest was higher") : String(localized: "Rest was lower"))
        }
        var out = first
        let tail = [eff, rst].filter { !$0.isEmpty }.joined(separator: ", ")
        if !tail.isEmpty { out += (out.isEmpty ? "" : ", " + String(localized: "while") + " ") + tail }
        if !out.isEmpty { out += "." }
        if let d = delta(c.now, c.before) {
            out += " " + (d >= 2 ? String(localized: "Your recovery is improving.") : (d <= -2 ? String(localized: "Your recovery is slipping.") : String(localized: "Your recovery is steady.")))
        }
        return out
    }

    // MARK: Comparisons

    private var effortEdges: [Double] { scale == .whoop ? [10, 14, 18] : [48, 67, 86] }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comparisons").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text("Tap for details").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            chargeEffortCard
            chargeRestCard
        }
    }

    private var windowStart: String { TrendInsights.shift(m.todayKey, by: -(range - 1)) ?? m.todayKey }

    private var chargeEffortCard: some View {
        let ch = m.window(m.charge, days: range), ef = m.window(m.effort, days: range)
        let pairs = TrendInsights.pairs(driver: ef, outcome: m.charge, lag: 1)
        let corr = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) })
        let efDisp: NunaDaySeries = ef.map { ($0.day, UnitFormatter.effortValue($0.value, scale: scale)) }
        let b = TrendInsights.buckets(driver: efDisp, outcome: m.charge, edges: [effortEdges[0], effortEdges[1]], lag: 1)
        return NavigationLink(value: NunaTrendsRoute.chargeEffort) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        nunaTrendsCap("Charge and Effort")
                        Spacer()
                        if let corr { NunaChip(verbatim: NunaTrendsFormat.relationChip(corr.r)) }
                    }
                    NunaComboChart(start: windowStart, days: range, bars: efDisp, barMax: max(efDisp.map(\.value).max() ?? 1, 1),
                                   line: ch, lineMax: 100, selected: .constant(nil), height: 110, interactive: false)
                    HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.charge, text: "Charge"); NunaLegendItem(color: NunaPalette.effort, text: "Effort", dot: true) }
                    if let hi = b[2].meanOutcome, let lo = b[0].meanOutcome {
                        insightRow("bolt", Text("After a high-Effort day, next-morning Charge averages \(Int(hi.rounded()))%. After a light day, \(Int(lo.rounded()))%."))
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var chargeRestCard: some View {
        let ch = m.window(m.charge, days: range), rs = m.window(m.rest, days: range)
        let pairs = TrendInsights.pairs(driver: rs, outcome: m.charge, lag: 0)
        let corr = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) })
        let b = TrendInsights.buckets(driver: rs, outcome: m.charge, edges: [78, 86], lag: 0)
        return NavigationLink(value: NunaTrendsRoute.chargeRest) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        nunaTrendsCap("Charge and Rest")
                        Spacer()
                        if let corr { NunaChip(verbatim: NunaTrendsFormat.relationChip(corr.r)) }
                    }
                    NunaMultiLineChart(start: windowStart, days: range, lines: [.init(series: rs, max: 100, color: NunaPalette.rest), .init(series: ch, max: 100, color: NunaPalette.charge)], height: 110)
                    HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.charge, text: "Charge"); NunaLegendItem(color: NunaPalette.rest, text: "Rest") }
                    if let hi = b[2].meanOutcome, let lo = b[0].meanOutcome {
                        insightRow("moon", Text("Nights with Rest above 86% are followed by Charge \(Int(hi.rounded()))%, versus \(Int(lo.rounded()))% when Rest is below 78%."))
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func insightRow(_ icon: String, _ text: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 34, height: 34).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            text.font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Daily signals

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily signals").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                signal("HRV", m.hrv, "ms", 0, upGood: true, route: .metricKey("hrv"))
                signal("Resting HR", m.rhr, "bpm", 0, upGood: false, route: .metricKey("rhr"))
                signal("Stress", m.stress, "/ 3", 1, upGood: false, route: .metricKey("stress"))
                signal("Steps", m.steps, "", 0, upGood: true, route: .metricKey("steps_est"))
            }
        }
    }

    enum SignalRoute { case metricKey(String) }

    @ViewBuilder private func signal(_ title: LocalizedStringKey, _ s: NunaDaySeries, _ unit: String, _ digits: Int, upGood: Bool, route: SignalRoute) -> some View {
        let win = m.window(s, days: range)
        let (now, before) = m.means(s, days: range)
        let d = delta(now, before)
        let tile = NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let d, abs(d) >= (digits == 0 ? 0.5 : 0.05) {
                        Text(verbatim: (d > 0 ? "▲ " : "▼ ") + String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, abs(d)))
                            .font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle((d > 0) == upGood ? NunaPalette.charge : NunaPalette.warning)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: NunaTrendsFormat.num(now, digits)).font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                }
                // The same height with or without data, so a card with nothing to plot keeps the shape of the others.
                ZStack {
                    if win.count < 2 { Rectangle().fill(NunaPalette.hairline).frame(height: 1.5) }
                    NunaSpark(values: win.map(\.value))
                }
                .frame(height: 34)
            }
        }
        if case .metricKey(let k) = route, let md = MetricCatalog.metric(key: k, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(md)) { tile }.buttonStyle(.plain)
        } else { tile }
    }

    // MARK: Heat map, since, Anya, explore

    private var heatmapCard: some View {
        NavigationLink(value: NunaTrendsRoute.heatmap) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        nunaTrendsCap("Charge heat map")
                        Spacer()
                        Text("12 weeks · a year").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    NunaHeatGrid(model: m, weeks: 12, cell: 22)
                    HStack(spacing: 14) { zoneKey(NunaPalette.charge, "67+"); zoneKey(NunaPalette.warning, "34–66"); zoneKey(NunaPalette.alert, "0–33") }
                }
            }
        }.buttonStyle(.plain)
    }

    private func zoneKey(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.8)).frame(width: 10, height: 10)
            Text(verbatim: t).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    private var sinceCard: some View {
        let c = m.means(m.charge, days: range), e = m.means(m.effort, days: range), r = m.means(m.rest, days: range)
        return NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                nunaTrendsCap("Against the previous period")
                since("Charge", c, NunaPalette.charge, { NunaTrendsFormat.num($0, 1) + "%" }, 100)
                since("Effort", e, NunaPalette.effort, { $0.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–" }, 100)
                since("Rest", r, NunaPalette.rest, { NunaTrendsFormat.num($0, 1) + "%" }, 100)
                HStack(spacing: 16) {
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink).frame(width: 14, height: 8); Text("This period") }
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink.opacity(0.3)).frame(width: 14, height: 5); Text("Previous period") }
                }
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    private func since(_ title: LocalizedStringKey, _ v: (now: Double?, before: Double?), _ color: Color, _ fmt: (Double?) -> String, _ top: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: fmt(v.now)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "vs " + fmt(v.before).replacingOccurrences(of: "%", with: "")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            NunaProgressBar(fraction: (v.now ?? 0) / top, color: color)
            NunaProgressBar(fraction: (v.before ?? 0) / top, color: NunaPalette.ink.opacity(0.3)).frame(height: 5)
        }
    }

    private var anyaCard: some View {
        let b = TrendInsights.buckets(driver: m.window(m.effort, days: range).map { ($0.day, UnitFormatter.effortValue($0.value, scale: scale)) },
                                      outcome: m.charge, edges: [effortEdges[0], effortEdges[1]], lag: 1)
        let best = b.filter { $0.meanOutcome != nil && $0.n >= 3 }.max { $0.meanOutcome! < $1.meanOutcome! }
        return Group {
            if let best, let mean = best.meanOutcome {
                let band = [String(localized: "light"), String(localized: "moderate"), String(localized: "high")][min(best.band, 2)]
                NunaAnyaCard(verbatim: String(localized: "Your Charge is highest the morning after a \(band) Effort day (\(Int(mean.rounded()))%).")) { showCoach = true }
            }
        }
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore further").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    link(.explore, "Explore", "A catalogue of every signal", "chart.line.uptrend.xyaxis")
                    NunaDivider()
                    link(.compare, "Compare", "Stack 2 to 4 metrics", "slider.horizontal.3")
                    NunaDivider()
                    link(.insights, "Insights", "Behaviour effects and links between metrics", "bolt")
                }
            }
        }
    }

    private func link(_ r: NunaTrendsRoute, _ t: LocalizedStringKey, _ s: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: r) { NunaListRow(t, subtitle: s, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }

    private var exportRow: some View {
        Button { showReport = true } label: {
            NunaCard(small: true) { NunaListRow("Export report", description: "A PDF summary of your trends", systemImage: "square.and.arrow.up", showsChevron: true) }
        }.buttonStyle(.plain)
    }
}

/// Weeks of Charge as small squares, one column per week, oldest on the left. A day with no Charge stays faint.
struct NunaHeatGrid: View {
    @ObservedObject var model: NunaTrendsModel
    let weeks: Int
    let cell: CGFloat
    var body: some View {
        let cal = Calendar.current
        let today = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let byDay = Dictionary(model.charge.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        HStack(spacing: weeks > 16 ? 2 : 4) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: weeks > 16 ? 2 : 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = cal.date(byAdding: .day, value: (w - (weeks - 1)) * 7 + d, to: weekStart) ?? today
                        let v = date > today ? nil : byDay[Repository.localDayKey(date)]
                        RoundedRectangle(cornerRadius: weeks > 16 ? 2 : 5, style: .continuous)
                            .fill(v.map { nunaZoneColor($0).opacity(0.35 + 0.55 * min($0 / 100, 1)) } ?? NunaPalette.ink.opacity(date > today ? 0 : 0.06))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
