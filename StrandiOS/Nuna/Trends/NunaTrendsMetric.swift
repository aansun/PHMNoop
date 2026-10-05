#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

enum NunaTrendsMetricKind { case charge, effort, rest }

/// Charge, Effort and Rest trend screens (TrendsCharge / TrendsEffort / TrendsRest): average with the change from the
/// previous period, the daily chart, zones, patterns by weekday, extremes and what sits behind the number.
struct NunaTrendsMetricView: View {
    let kind: NunaTrendsMetricKind
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var m = NunaTrendsModel()
    @StateObject private var sleep = NunaSleepModel()
    @StateObject private var day = NunaTodayModel()
    @EnvironmentObject private var profile: ProfileStore
    @State private var range = 30

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // MARK: Per-kind configuration

    private var title: LocalizedStringKey { kind == .charge ? "Charge" : (kind == .effort ? "Effort" : "Rest") }
    private var color: Color { kind == .charge ? NunaPalette.charge : (kind == .effort ? NunaPalette.effortText : NunaPalette.restText) }
    private var bar: Color { kind == .charge ? NunaPalette.charge : (kind == .effort ? NunaPalette.effort : NunaPalette.rest) }
    private var raw: NunaDaySeries { kind == .charge ? m.charge : (kind == .effort ? m.effort : m.rest) }
    /// Display value for a stored one (Effort follows the chosen scale).
    private func disp(_ v: Double) -> Double { kind == .effort ? UnitFormatter.effortValue(v, scale: scale) : v }
    private var decimals: Int { kind == .effort ? 1 : 0 }
    private var unit: String { kind == .effort ? "" : "%" }
    /// Lower bounds of the zones above the first one, in display units, and their names.
    private var edges: [Double] {
        switch kind {
        case .charge: return [34, 67]
        case .effort: return scale == .whoop ? [10, 14, 18] : [48, 67, 86]
        case .rest: return [65, 80]
        }
    }
    private var zoneNames: [LocalizedStringKey] {
        switch kind {
        case .charge: return ["Red · 0 to 33", "Yellow · 34 to 66", "Green · 67 and up"]
        case .effort: return scale == .whoop ? ["Light · under 10", "Moderate · 10 to 14", "Heavy · 14 to 18", "Maximal · 18 and up"]
                                              : ["Light · under 48", "Moderate · 48 to 67", "Heavy · 67 to 86", "Maximal · 86 and up"]
        case .rest: return ["Low · under 65", "Fair · 65 to 79", "Good · 80 and up"]
        }
    }
    private var zoneColors: [Color] {
        switch kind {
        case .charge: return [NunaPalette.alert, NunaPalette.warning, NunaPalette.charge]
        case .effort: return [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.effort, NunaPalette.alert]
        case .rest: return [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.restLight]
        }
    }
    private func level(_ v: Double) -> LocalizedStringKey {
        let z = edges.filter { v >= $0 }.count
        switch kind {
        case .charge: return z == 2 ? "Ready" : (z == 1 ? "Steady" : "Low")
        case .effort: return ["Light", "Moderate", "Heavy", "Maximal"][min(z, 3)].asKey
        case .rest: return z == 2 ? "Good" : (z == 1 ? "Fair" : "Low")
        }
    }

    var body: some View {
        let win = m.window(raw, days: range)
        let dispWin: NunaDaySeries = win.map { ($0.day, disp($0.value)) }
        let (nowS, beforeS) = m.means(raw, days: range)
        let now = nowS.map(disp), before = beforeS.map(disp)
        NunaDetailScreen(title) {
            NunaSegmented(NunaTrendsRange.options, selection: $range)
            hero(now, before)
            chartCard(dispWin)
            zonesCard(dispWin)
            if kind == .effort { weeklyLoad } 
            if kind == .rest { restParts(win) }
            weekdayCard(dispWin)
            extremes(dispWin)
            previousCard(now, before)
            if kind == .charge { drivers }
            links
        }
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            if kind == .rest { await sleep.load(repo: repo) }
            if kind == .charge { await day.load(repo: repo, profile: profile) }
        }
    }

    // MARK: Cards

    private func hero(_ now: Double?, _ before: Double?) -> some View {
        let d = (now != nil && before != nil) ? now! - before! : nil
        let frac: Double = (now ?? 0) / (kind == .effort ? (scale == .whoop ? 21 : 100) : 100)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    NunaRingGauge(fraction: frac, color: color, size: 112, lineWidth: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(verbatim: NunaTrendsFormat.num(now, decimals)).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: String(localized: "\(range)-day average")).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        if let now { NunaChip(level(now), color: color) }
                        if let d, abs(d) >= (kind == .effort ? 0.05 : 0.5) {
                            Text(verbatim: (d > 0 ? "▲ " : "▼ ") + String(format: "%.\(kind == .effort ? 1 : 1)f", locale: AppLanguage.activeLocale, abs(d)) + (kind == .effort ? "" : " " + String(localized: "points")))
                                .font(.nuna(size: 14, weight: .heavy)).foregroundStyle(kind == .effort ? NunaPalette.textSecondary : ((d > 0) ? NunaPalette.charge : NunaPalette.warning))
                        }
                        if let before { Text(verbatim: String(localized: "Previous period \(NunaTrendsFormat.num(before, decimals))\(unit)")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: heroSentence(d)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heroSentence(_ d: Double?) -> String {
        guard let d else { return String(localized: "There is no earlier period to compare with yet.") }
        switch kind {
        case .charge: return abs(d) < 1 ? String(localized: "Your recovery is about the same as the previous period.")
            : (d > 0 ? String(localized: "Your recovery is up from the previous period.") : String(localized: "Your recovery is down from the previous period."))
        case .effort: return abs(d) < 0.3 ? String(localized: "Your load is steady compared with the previous period.")
            : (d > 0 ? String(localized: "Your load is higher than in the previous period.") : String(localized: "Your load is lower than in the previous period."))
        case .rest: return abs(d) < 1 ? String(localized: "Your sleep score is about the same as the previous period.")
            : (d > 0 ? String(localized: "Your sleep score is up from the previous period.") : String(localized: "Your sleep score is down from the previous period."))
        }
    }

    private func chartCard(_ w: NunaDaySeries) -> some View {
        let vals = w.map(\.value)
        let first = TrendInsights.shift(m.todayKey, by: -(range - 1)) ?? m.todayKey
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    nunaTrendsCap(kind == .charge ? "Daily Charge" : (kind == .effort ? "Daily Effort" : "Daily Rest"))
                }
                if range == 7 {
                    let top = max(vals.max() ?? 1, 1)
                    let slots = (0..<7).map { i -> (Date, String) in
                        let k = TrendInsights.shift(first, by: i) ?? first
                        return (m.date(k) ?? Date(), k)
                    }
                    let byDay = Dictionary(w.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
                    NunaColumns(items: slots.map { s in
                        let v = byDay[s.1]
                        return NunaColumns.Item(weekday: NunaTrendsFormat.weekdayShort(TrendInsights.weekday(s.1) ?? 1), date: s.0, fraction: v.map { $0 / top },
                                                valueText: v.map { NunaTrendsFormat.num($0, decimals) }, highlight: s.1 == m.todayKey,
                                                color: v.map { val in zoneColors[edges.filter { val >= $0 }.count] })
                    }, color: bar, highlightColor: color)
                } else {
                    NunaLine2Chart(points: w.compactMap { r in m.date(r.day).map { ($0, r.value) } }, color: color, decimals: decimals, height: 190)
                }
                if !vals.isEmpty {
                    NunaDivider()
                    HStack {
                        mini("Average", NunaTrendsFormat.num(vals.reduce(0, +) / Double(vals.count), decimals))
                        mini("Highest", NunaTrendsFormat.num(vals.max(), decimals))
                        mini("Lowest", NunaTrendsFormat.num(vals.min(), decimals))
                        mini("Days", "\(vals.count)")
                    }
                } else {
                    Text("No data in this period").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func mini(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zonesCard(_ w: NunaDaySeries) -> some View {
        let counts = TrendInsights.zoneCounts(w.map(\.value), edges: edges)
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: kind == .effort ? "Load zones" : "Zones") { EmptyView() }
            NunaCard {
                VStack(spacing: 14) {
                    ForEach(0..<zoneNames.count, id: \.self) { i in
                        // Charge and Rest list the best zone first, Effort the lightest first.
                        let ci = kind == .effort ? i : (zoneNames.count - 1 - i)
                        HStack(spacing: 10) {
                            Circle().fill(zoneColors[ci]).frame(width: 9, height: 9)
                            Text(zoneNames[ci]).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: String(localized: "\(counts[ci]) days")).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    NunaProportionBar(parts: (0..<counts.count).map { (Double(counts[$0]), zoneColors[$0]) }, height: 10)
                }
            }
        }
    }

    // Effort only: total load for each 7-day block.
    private var weeklyLoad: some View {
        let weeks = max(4, min(range / 7, 12))
        let t = TrendInsights.weeklyTotals(m.effort, lastDay: m.todayKey, weeks: weeks)
        let top = max(t.map(\.total).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Load per week") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    if t.isEmpty {
                        Text("No data in this period").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        NunaColumns(items: t.enumerated().map { i, w in
                            NunaColumns.Item(weekday: "W\(i + 1)", date: m.date(w.endDay) ?? Date(), fraction: w.total / top,
                                             valueText: NunaTrendsFormat.num(disp(w.total), 0), highlight: i == t.count - 1)
                        }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText)
                        if let last = t.last {
                            let avg = t.map(\.total).reduce(0, +) / Double(t.count)
                            Text(verbatim: String(localized: "Total Effort for every 7 days. This week \(NunaTrendsFormat.num(disp(last.total), 0)), average \(NunaTrendsFormat.num(disp(avg), 0))."))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // Rest only: what forms the score, from the nights in the window.
    private func restParts(_ win: NunaDaySeries) -> some View {
        let nights = sleep.nights.filter { n in win.contains { $0.day == n.dayKey } }
        let avgMin = nights.isEmpty ? nil : nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let need = nights.isEmpty ? nil : nights.map { sleep.need($0) }.reduce(0, +) / Double(nights.count)
        let eff = nights.compactMap { sleep.efficiency($0) }
        let cons = nights.compactMap { sleep.consistency($0) }
        let debt = (avgMin != nil && need != nil) ? max(0, need! - avgMin!) : nil
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "What shapes Rest") { EmptyView() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                NunaStatTile(label: "Average duration", value: avgMin.map(NunaSleepFormat.duration) ?? "–", caption: need.map { LocalizedStringKey(String(localized: "needs \(NunaSleepFormat.duration($0))")) })
                NunaStatTile(label: "Consistency", value: cons.isEmpty ? "–" : NunaTrendsFormat.num(cons.reduce(0, +) / Double(cons.count)), unit: cons.isEmpty ? "" : "%", caption: "similar bedtimes")
                NunaStatTile(label: "Efficiency", value: eff.isEmpty ? "–" : NunaTrendsFormat.num(eff.reduce(0, +) / Double(eff.count)), unit: eff.isEmpty ? "" : "%", caption: "of time in bed asleep")
                NunaStatTile(label: "Sleep debt", value: debt.map { NunaTrendsFormat.num($0) } ?? "–", unit: debt == nil ? "" : "min", caption: "average gap to your need")
            }
        }
    }

    private func weekdayCard(_ w: NunaDaySeries) -> some View {
        let means = TrendInsights.weekdayMeans(w)
        let order = [2, 3, 4, 5, 6, 7, 1]
        let top = max(means.values.max() ?? 1, 1)
        let hi = means.max { $0.value < $1.value }, lo = means.min { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Weekly pattern") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    if means.count < 3 {
                        Text("Not enough days yet to show a pattern.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        NunaColumns(items: order.map { wd in
                            let v = means[wd]
                            return NunaColumns.Item(weekday: NunaTrendsFormat.weekdayShort(wd), date: Date(), fraction: v.map { $0 / top }, valueText: v.map { NunaTrendsFormat.num($0, decimals) },
                                                    highlight: wd == hi?.key)
                        }, color: bar, highlightColor: color, showsDates: false)
                        if let hi, let lo, hi.key != lo.key {
                            Text(verbatim: String(localized: "Highest on \(longDay(hi.key)), lowest on \(longDay(lo.key))."))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func longDay(_ w: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        return f.weekdaySymbols[(w - 1) % 7]
    }

    private func extremes(_ w: NunaDaySeries) -> some View {
        let hi = w.max { $0.value < $1.value }, lo = w.min { $0.value < $1.value }
        return HStack(spacing: 12) {
            ext("Highest", hi)
            ext("Lowest", lo)
        }
    }

    private func ext(_ l: LocalizedStringKey, _ r: (day: String, value: Double)?) -> some View {
        NunaStatTile(label: l, value: NunaTrendsFormat.num(r?.value, decimals), unit: r == nil ? "" : unit,
                     caption: r.flatMap { m.date($0.day) }.map { LocalizedStringKey(NunaTrendsFormat.withWeekday($0)) })
    }

    private func previousCard(_ now: Double?, _ before: Double?) -> some View {
        let top: Double = kind == .effort ? (scale == .whoop ? 21 : 100) : 100
        return NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                nunaTrendsCap("Against the previous period")
                HStack {
                    Text(title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: NunaTrendsFormat.num(now, kind == .effort ? 1 : 1) + unit).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "vs " + NunaTrendsFormat.num(before, 1)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaProgressBar(fraction: (now ?? 0) / top, color: bar)
                NunaProgressBar(fraction: (before ?? 0) / top, color: NunaPalette.ink.opacity(0.3)).frame(height: 5)
            }
        }
    }

    // Charge only: what sits behind the average.
    private var drivers: some View {
        let hrvNow = m.means(m.hrv, days: range), rhrNow = m.means(m.rhr, days: range), restNow = m.means(m.rest, days: range)
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Drivers") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    if let a = hrvNow.now, let b = hrvNow.before {
                        driver("waveform.path.ecg", a >= b ? String(localized: "HRV up \(Int(abs(a - b).rounded())) ms from the previous period") : String(localized: "HRV down \(Int(abs(a - b).rounded())) ms from the previous period"))
                    }
                    if let a = rhrNow.now, let b = rhrNow.before {
                        NunaDivider()
                        driver("heart", a <= b ? String(localized: "Resting HR down \(Int(abs(a - b).rounded())) bpm") : String(localized: "Resting HR up \(Int(abs(a - b).rounded())) bpm"))
                    }
                    if let r = restNow.now {
                        NunaDivider()
                        NavigationLink(value: NunaTrendsRoute.rest) { driver("moon", String(localized: "Rest averaged \(Int(r.rounded()))%"), chevron: true) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func driver(_ icon: String, _ text: String, chevron: Bool = false) -> some View {
        NunaListRow(LocalizedStringKey(text), systemImage: icon, showsChevron: chevron)
    }

    private var links: some View {
        VStack(spacing: 12) {
            if kind == .effort || kind == .rest {
                NavigationLink(value: kind == .effort ? NunaTrendsRoute.chargeEffort : NunaTrendsRoute.chargeRest) {
                    NunaCard(small: true) { NunaListRow("Compare with Charge", subtitle: kind == .effort ? "How Effort shapes tomorrow's Charge" : "How sleep shapes Charge", systemImage: "chart.line.uptrend.xyaxis", showsChevron: true) }
                }.buttonStyle(.plain)
            } else {
                NavigationLink(value: NunaTrendsRoute.chargeEffort) {
                    NunaCard(small: true) { NunaListRow("Compare with Effort", subtitle: "The link between load and recovery", systemImage: "chart.line.uptrend.xyaxis", showsChevron: true) }
                }.buttonStyle(.plain)
            }
            if let md = MetricCatalog.metric(key: kind == .charge ? "recovery" : (kind == .effort ? "strain" : "sleep_performance"), source: "my-whoop") {
                NavigationLink(value: NunaTodayRoute.metric(md)) {
                    NunaCard(small: true) { NunaListRow(kind == .charge ? "See today's Charge" : (kind == .effort ? "See today's Effort" : "See last night"), systemImage: kind == .rest ? "moon" : "bolt", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
    }
}

private extension String {
    var asKey: LocalizedStringKey { LocalizedStringKey(self) }
}
#endif
