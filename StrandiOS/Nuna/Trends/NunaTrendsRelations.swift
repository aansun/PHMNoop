#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Charge and Effort (TrendsChargeEffort)

struct NunaChargeEffortView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var m = NunaTrendsModel()
    @State private var range = 30
    @State private var selected: String?
    @State private var showCoach = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var edges: [Double] { scale == .whoop ? [10, 14] : [48, 67] }
    private var names: [LocalizedStringKey] {
        scale == .whoop ? ["Light · under 10", "Moderate · 10 to 14", "High · over 14"] : ["Light · under 48", "Moderate · 48 to 67", "High · over 67"]
    }
    private var start: String { TrendInsights.shift(m.todayKey, by: -(range - 1)) ?? m.todayKey }

    var body: some View {
        let ef: NunaDaySeries = m.window(m.effort, days: range).map { ($0.day, UnitFormatter.effortValue($0.value, scale: scale)) }
        let efAll: NunaDaySeries = m.effort.map { ($0.day, UnitFormatter.effortValue($0.value, scale: scale)) }
        let pairs = TrendInsights.pairs(driver: efAll.filter { $0.day >= start }, outcome: m.charge, lag: 1)
        let corr = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) })
        let b = TrendInsights.buckets(driver: efAll.filter { $0.day >= start }, outcome: m.charge, edges: edges, lag: 1)
        NunaDetailScreen("Charge and Effort") {
            NunaSegmented(NunaTrendsRange.options, selection: $range)
            relationCard(corr, b)
            chartCard(ef)
            bucketsCard(b)
            scatterCard(pairs, corr)
            if let hi = b[2].meanOutcome, b[2].n >= 2, let lo = b[0].meanOutcome, b[0].n >= 2 {
                NunaCard(highlight: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt").foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: sweetSpot(b, hi: hi, lo: lo)).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            standouts(pairs)
            NunaAnyaCard(verbatim: String(localized: "After Effort above \(Int(edges[1])), give yourself one light day before the next hard session.")) { showCoach = true }
            NunaExpandRow(title: "How to read this", subtitle: "A link, not proof of cause", systemImage: "sparkles",
                          text: "Each point pairs one day's Effort with the Charge you woke up with the next morning. The strength shows how closely they move together in your own data. It does not prove that one causes the other.")
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "trends") }
    }

    private func sweetSpot(_ b: [TrendInsights.Bucket], hi: Double, lo: Double) -> String {
        if let mid = b[1].meanOutcome, b[1].n >= 2, mid >= max(hi, lo) - 1 {
            return String(localized: "Effort between \(Int(edges[0])) and \(Int(edges[1])) keeps tomorrow's Charge around \(Int(mid.rounded()))%.")
        }
        return String(localized: "Light days lead to Charge \(Int(lo.rounded()))% the next morning, high days to \(Int(hi.rounded()))%.")
    }

    private func relationCard(_ c: Correlation?, _ b: [TrendInsights.Bucket]) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    nunaTrendsCap("Relationship")
                    Spacer()
                    if let c { NunaChip(verbatim: NunaTrendsFormat.relationChip(c.r)) }
                }
                if let c {
                    Text(verbatim: c.r < -0.1 ? String(localized: "The harder your Effort today, the lower your Charge tomorrow morning.")
                         : (c.r > 0.1 ? String(localized: "In your data, a harder day is followed by a slightly higher Charge.") : String(localized: "Your Effort and next-day Charge show almost no link in this period.")))
                        .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if let hi = b[2].meanOutcome, let lo = b[0].meanOutcome, b[2].n > 0, b[0].n > 0 {
                        Text(verbatim: String(localized: "The gap is about \(Int(abs(lo - hi).rounded())) points between light and hard days."))
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                } else {
                    Text("Not enough paired days yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func chartCard(_ ef: NunaDaySeries) -> some View {
        let eMax = max(ef.map(\.value).max() ?? 1, 1)
        let ch = m.window(m.charge, days: range)
        let sel = selected
        let eSel = sel.flatMap { s in ef.first { $0.day == s } }, cSel = sel.flatMap { s in ch.first { $0.day == s } }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaTrendsCap(LocalizedStringKey(String(localized: "\(range) days"))); Spacer(); Text("Bars: Effort · Line: Charge").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                NunaComboChart(start: start, days: range, bars: ef, barMax: eMax, line: ch, lineMax: 100, selected: $selected, height: 150)
                HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.charge, text: "Charge"); NunaLegendItem(color: NunaPalette.effort, text: "Effort", dot: true) }
                if let sel, let d = m.date(sel) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt").foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: NunaTrendsFormat.withWeekday(d) + " · " + String(localized: "Effort") + " " + NunaTrendsFormat.num(eSel?.value, 1) + " · Charge " + NunaTrendsFormat.num(cSel?.value) + "%")
                            .font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(NunaPalette.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func bucketsCard(_ b: [TrendInsights.Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Tomorrow's Charge, by Effort") { EmptyView() }
            NunaCard {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(spacing: 8) {
                            HStack {
                                Text(names[i]).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: String(localized: "\(b[i].n) days")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                Text(verbatim: b[i].meanOutcome.map { "\(Int($0.rounded()))%" } ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, alignment: .trailing)
                            }
                            NunaProgressBar(fraction: (b[i].meanOutcome ?? 0) / 100, color: b[i].meanOutcome.map(nunaChargeColor) ?? NunaPalette.zoneBase)
                        }
                    }
                }
            }
        }
    }

    private func scatterCard(_ pairs: [(day: String, x: Double, y: Double)], _ c: Correlation?) -> some View {
        let xs = pairs.map(\.x)
        let lo = xs.min() ?? 0, hi = max(xs.max() ?? 1, lo + 1)
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Spread")
                if pairs.count >= 3 {
                    NunaScatter(points: pairs.map { ($0.x, $0.y) }, xRange: lo...hi, yRange: 0...100, slope: c?.slope, intercept: c?.intercept, color: NunaPalette.effortText)
                    HStack { Text("Effort →").font(.nuna(size: 11.5, weight: .semibold)); Spacer(); Text("↑ next-day Charge").font(.nuna(size: 11.5, weight: .semibold)) }.foregroundStyle(NunaPalette.textMuted)
                    Text("Each dot is one day. The dashed line is the general direction.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text("Not enough paired days yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private func standouts(_ pairs: [(day: String, x: Double, y: Double)]) -> some View {
        let base = m.mean(m.window(m.charge, days: range)) ?? 0
        let worst = pairs.filter { $0.y < base - 8 }.sorted { ($0.x) > ($1.x) }.prefix(3)
        if !worst.isEmpty {
            NunaTitleRow(title: "Days that stand out") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(worst.enumerated()), id: \.offset) { i, p in
                        if i > 0 { NunaDivider() }
                        NunaListRow(LocalizedStringKey((m.date(p.day).map(NunaTrendsFormat.withWeekday) ?? p.day) + ": Effort " + NunaTrendsFormat.num(p.x, 1)),
                                    subtitle: LocalizedStringKey(String(localized: "Charge the next day \(Int(p.y.rounded()))%, \(Int((base - p.y).rounded())) below your average")), systemImage: "bolt")
                    }
                }
            }
        }
    }
}

// MARK: - Charge and Rest (TrendsChargeRest)

struct NunaChargeRestView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var m = NunaTrendsModel()
    @StateObject private var sleep = NunaSleepModel()
    @State private var range = 30
    @State private var showCoach = false

    private var start: String { TrendInsights.shift(m.todayKey, by: -(range - 1)) ?? m.todayKey }

    var body: some View {
        let rs = m.window(m.rest, days: range), ch = m.window(m.charge, days: range)
        let pairs = TrendInsights.pairs(driver: m.rest.filter { $0.day >= start }, outcome: m.charge, lag: 0)
        let corr = CorrelationEngine.pearson(pairs.map { ($0.x, $0.y) })
        let b = TrendInsights.buckets(driver: m.rest.filter { $0.day >= start }, outcome: m.charge, edges: [78, 86], lag: 0)
        NunaDetailScreen("Charge and Rest") {
            NunaSegmented(NunaTrendsRange.options, selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { nunaTrendsCap("Relationship"); Spacer(); if let corr { NunaChip(verbatim: NunaTrendsFormat.relationChip(corr.r)) } }
                    if let corr {
                        Text(verbatim: corr.r > 0.3 ? String(localized: "Sleep is one of the biggest drivers of your Charge.") : String(localized: "Your sleep score and Charge show only a loose link in this period."))
                            .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        if let hi = b[2].meanOutcome, let lo = b[0].meanOutcome, b[2].n > 0, b[0].n > 0 {
                            Text(verbatim: String(localized: "A high-Rest night gives a Charge about \(Int(abs(hi - lo).rounded())) points \(hi >= lo ? String(localized: "better") : String(localized: "lower")).")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    } else { Text("Not enough paired days yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap(LocalizedStringKey(String(localized: "\(range) days"))); Spacer(); Text("Two lines moving together").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    NunaMultiLineChart(start: start, days: range, lines: [.init(series: rs, max: 100, color: NunaPalette.rest), .init(series: ch, max: 100, color: NunaPalette.charge)], height: 150)
                    HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.charge, text: "Charge"); NunaLegendItem(color: NunaPalette.rest, text: "Rest") }
                }
            }
            NunaTitleRow(title: "Charge, by last night's Rest") { EmptyView() }
            NunaCard {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { i in
                        let names: [LocalizedStringKey] = ["Rest under 78%", "Rest 78 to 86%", "Rest over 86%"]
                        VStack(spacing: 8) {
                            HStack {
                                Text(names[i]).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: String(localized: "\(b[i].n) days")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                Text(verbatim: b[i].meanOutcome.map { "\(Int($0.rounded()))%" } ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, alignment: .trailing)
                            }
                            NunaProgressBar(fraction: (b[i].meanOutcome ?? 0) / 100, color: b[i].meanOutcome.map(nunaChargeColor) ?? NunaPalette.zoneBase)
                        }
                    }
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("Spread")
                    if pairs.count >= 3 {
                        let xs = pairs.map(\.x), lo = xs.min() ?? 0, hi = max(xs.max() ?? 1, lo + 1)
                        NunaScatter(points: pairs.map { ($0.x, $0.y) }, xRange: lo...hi, yRange: 0...100, slope: corr?.slope, intercept: corr?.intercept, color: NunaPalette.restText)
                        HStack { Text("Rest →").font(.nuna(size: 11.5, weight: .semibold)); Spacer(); Text("↑ Charge").font(.nuna(size: 11.5, weight: .semibold)) }.foregroundStyle(NunaPalette.textMuted)
                    } else { Text("Not enough paired days yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            restParts
            NavigationLink(value: NunaTodayRoute.sleepPerformance(0)) {
                NunaCard(small: true) { NunaListRow("Sleep performance", subtitle: "Need and sleep debt", systemImage: "moon", showsChevron: true) }
            }.buttonStyle(.plain)
            NunaAnyaCard(verbatim: anyaLine(b)) { showCoach = true }
            NunaExpandRow(title: "How to read this", subtitle: "Rest affects Charge, but is not the only thing", systemImage: "sparkles",
                          text: "Each point pairs a night's Rest with the Charge you woke up with. The line shows the general direction in your own data. Charge also depends on HRV, resting heart rate and how hard the day before was.")
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo); await sleep.load(repo: repo) }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "trends") }
    }

    private func anyaLine(_ b: [TrendInsights.Bucket]) -> String {
        if let hi = b[2].meanOutcome, let lo = b[0].meanOutcome, b[2].n >= 2, b[0].n >= 2, hi > lo {
            return String(localized: "On nights with Rest above 86%, your Charge averages \(Int(hi.rounded()))% against \(Int(lo.rounded()))% below 78%.")
        }
        return String(localized: "More nights of data will show how much your sleep moves your Charge.")
    }

    private var restParts: some View {
        let nights = sleep.nights.filter { $0.dayKey >= start }
        let avg = nights.isEmpty ? nil : nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let need = nights.isEmpty ? nil : nights.map { sleep.need($0) }.reduce(0, +) / Double(nights.count)
        let cons = nights.compactMap { sleep.consistency($0) }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "What shapes Rest") { EmptyView() }
            HStack(spacing: 12) {
                NunaStatTile(label: "Average duration", value: avg.map(NunaSleepFormat.duration) ?? "–", caption: need.map { LocalizedStringKey(String(localized: "needs \(NunaSleepFormat.duration($0))")) })
                NunaStatTile(label: "Consistency", value: cons.isEmpty ? "–" : NunaTrendsFormat.num(cons.reduce(0, +) / Double(cons.count)), unit: cons.isEmpty ? "" : "%", caption: "similar bedtimes")
            }
        }
    }
}

// MARK: - Heat map (TrendsHeatmap)

struct NunaHeatmapView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var m = NunaTrendsModel()
    @State private var months = 6

    var body: some View {
        let weeks = months * 13 / 3
        let from = TrendInsights.shift(m.todayKey, by: -(weeks * 7)) ?? m.todayKey
        let win = m.charge.filter { $0.day >= from }
        let z = TrendInsights.zoneCounts(win.map(\.value), edges: [34, 67])
        let means = TrendInsights.weekdayMeans(win)
        let streak = TrendInsights.longestStreak(win, atLeast: 67)
        NunaDetailScreen("Charge heat map") {
            NunaSegmented([(value: 3, title: "3 mo"), (value: 6, title: "6 mo"), (value: 12, title: "1 yr")], selection: $months)
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { nunaTrendsCap(LocalizedStringKey(String(localized: "Last \(weeks) weeks"))); Spacer(); Text("One square = one day").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    NunaHeatGrid(model: m, weeks: min(weeks, 26), cell: weeks > 20 ? 10 : 14)
                    HStack(spacing: 14) {
                        key(NunaPalette.charge, "67+"); key(NunaPalette.warning, "34–66"); key(NunaPalette.alert, "0–33")
                    }
                }
            }
            HStack(spacing: 10) {
                NunaStatTile(label: "Green", value: "\(z[2])", unit: String(localized: "days"))
                NunaStatTile(label: "Yellow", value: "\(z[1])", unit: String(localized: "days"))
                NunaStatTile(label: "Red", value: "\(z[0])", unit: String(localized: "days"))
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("Weekly pattern")
                    if means.count >= 3 {
                        let top = max(means.values.max() ?? 1, 1)
                        NunaColumns(items: [2, 3, 4, 5, 6, 7, 1].map { wd in
                            NunaColumns.Item(weekday: NunaTrendsFormat.weekdayShort(wd), date: Date(), fraction: means[wd].map { $0 / top }, valueText: means[wd].map { NunaTrendsFormat.num($0) },
                                             highlight: wd == means.max { $0.value < $1.value }?.key, color: means[wd].map(nunaChargeColor))
                        }, color: NunaPalette.charge, showsDates: false)
                        if let hi = means.max(by: { $0.value < $1.value }), let lo = means.min(by: { $0.value < $1.value }), hi.key != lo.key {
                            Text(verbatim: String(localized: "Charge is highest on \(day(hi.key)) and lowest on \(day(lo.key))."))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    } else { Text("Not enough days yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            monthly(win)
            if let streak, let end = m.date(streak.endDay) {
                NunaCard(small: true) {
                    NunaListRow("Best green streak", subtitle: LocalizedStringKey(String(localized: "\(streak.length) days in a row, ending \(nunaAxisDate(end))")), systemImage: "flame")
                }
            }
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
    }

    private func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.8)).frame(width: 10, height: 10); Text(verbatim: t).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
    }

    private func day(_ w: Int) -> String { let f = DateFormatter(); f.locale = AppLanguage.activeLocale; return f.weekdaySymbols[(w - 1) % 7] }

    private func monthly(_ win: NunaDaySeries) -> some View {
        var byMonth: [String: [Double]] = [:]
        for r in win { byMonth[String(r.day.prefix(7)), default: []].append(r.value) }
        let keys = byMonth.keys.sorted().suffix(6)
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM")
        let p = DateFormatter(); p.dateFormat = "yyyy-MM"; p.locale = Locale(identifier: "en_US_POSIX")
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "By month") { EmptyView() }
            NunaCard {
                NunaColumns(items: keys.map { k in
                    let v = byMonth[k] ?? []
                    let avg = v.reduce(0, +) / Double(max(v.count, 1))
                    return NunaColumns.Item(weekday: p.date(from: k).map { f.string(from: $0) } ?? k, date: p.date(from: k) ?? Date(), fraction: avg / 100, valueText: NunaTrendsFormat.num(avg), color: nunaChargeColor(avg))
                }, color: NunaPalette.charge, showsDates: false)
            }
        }
    }
}
#endif
