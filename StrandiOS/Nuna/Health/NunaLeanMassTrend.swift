#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import WhoopStore

/// The trend page of the lean body mass: the share of the body that is not fat, as a percentage, with body fat beside it, over a week, a month or six months.
/// Both come from body fat as Apple Health (a smart scale) or a hand entry gives it; lean mass is what is left of 100%. Nothing is estimated: with no reading
/// the page says so.
struct NunaLeanMassTrendView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var fatS = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    /// The days whose reading was typed in by hand.
    @State private var manualDays: Set<String> = []

    private let leanColor = Color(hex: "#9B97EE")
    private let fatColor = Color(hex: "#F2A65A")

    private var window: NunaTrendWindow { NunaTrendWindow(range: range, page: page, endingDaysAgo: 0) }

    /// Lean body mass percentage for a day: what body fat leaves of 100.
    private func lean(_ fat: Double) -> Double { 100 - fat }

    private struct Reading: Identifiable { let date: Date; let fat: Double; var id: Date { date } }

    private func readings(in w: NunaTrendWindow) -> [Reading] {
        let cal = Calendar.current
        return (0..<w.range).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start), let fat = fatS.byDay[Repository.localDayKey(d)] else { return nil }
            return Reading(date: w.noon(d), fat: fat)
        }
    }

    private func average(_ r: [Reading]) -> Double? { r.isEmpty ? nil : r.map { lean($0.fat) }.reduce(0, +) / Double(r.count) }

    private var periodWord: String { range == 7 ? String(localized: "week") : (range == 30 ? String(localized: "month") : String(localized: "six months")) }

    var body: some View {
        let w = window
        let current = readings(in: w)
        let avg = average(current)
        let prior: Double? = range <= 30 ? average(readings(in: NunaTrendWindow(range: range, page: page + 1, endingDaysAgo: 0))) : nil
        NunaDetailScreen("Trend view", centersTitle: true) {
            NunaTrendNameBox(icon: "met:lean-body-mass", title: "Lean body mass")
            header(avg: avg, prior: prior, w: w)
            Text(verbatim: summary(avg: avg, prior: prior)).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 8).padding(.top, 6)
            legend
            chart(current, w)
            footer
            NunaBodyRows()
            NunaTrendInfo(kind: .leanBodyMass)
        }
        .appears(when: fatS.loaded)
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .nunaBodyMeasurementChanged)) { _ in Task { await load() } }
    }

    // MARK: Header, sentence, legend

    private func header(avg: Double?, prior: Double?, w: NunaTrendWindow) -> some View {
        let cal = Calendar.current
        let oldest = fatS.byDay.keys.sorted().first.flatMap { k in cal.dateComponents([.year, .month, .day], from: Date()).year.map { _ in k } }
        _ = oldest
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Avg. lean body mass").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: avg.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary)
                    if avg != nil { Text(verbatim: "%").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil) }
                }
                NunaChangeChip(average: avg, prior: average(readings(in: NunaTrendWindow(range: range, page: page + 1, endingDaysAgo: 0))), range: range, upIsGood: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(range: $range) { page = 0 }
                NunaDateStepper(label: w.label, canGoBack: page < 52, canGoForward: page > 0, back: { page += 1 }, forward: { page = max(0, page - 1) })
            }
        }
        .padding(.horizontal, 2)
    }

    private func summary(avg: Double?, prior: Double?) -> String {
        func f(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }
        guard let avg else { return String(localized: "No lean body mass readings in this period yet. They come from Apple Health, for example from a smart scale, or from a measurement you add.") }
        if range == 7 {
            guard let prior else { return String(localized: "Your average lean body mass percentage this week was \(f(avg))%. Keep tracking your lean body mass to see how this changes over time.") }
            let how = abs(avg - prior) < 0.05 ? String(localized: "in line with") : (avg > prior ? String(localized: "above") : String(localized: "below"))
            return String(localized: "Your average lean body mass percentage this week (\(f(avg))%) was \(how) your previous 7-day average of \(f(prior))%.")
        }
        let span = range == 30 ? String(localized: "the last 30 days") : String(localized: "the last 6 months")
        return String(localized: "Your average lean body mass percentage over \(span) was \(f(avg))%. Keep tracking your lean body mass to see how this changes over time.")
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            item(leanColor, "Lean body mass")
            item(fatColor, "Body fat")
        }
        .padding(.horizontal, 2).padding(.top, 6)
    }

    private func item(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(color, lineWidth: 2.5).frame(width: 11, height: 11)
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    // MARK: Chart

    private func chart(_ r: [Reading], _ w: NunaTrendWindow) -> some View {
        let isWeek = range == 7
        return Chart {
            ForEach(r) { x in
                if isWeek {
                    PointMark(x: .value("Day", x.date), y: .value("Lean", lean(x.fat)))
                        .symbol { Circle().strokeBorder(leanColor, lineWidth: 2.5).frame(width: 11, height: 11) }
                    PointMark(x: .value("Day", x.date), y: .value("Fat", x.fat))
                        .symbol { Circle().strokeBorder(fatColor, lineWidth: 2.5).frame(width: 11, height: 11) }
                } else {
                    LineMark(x: .value("Day", x.date), y: .value("Lean", lean(x.fat)), series: .value("Series", "lean")).foregroundStyle(leanColor)
                    LineMark(x: .value("Day", x.date), y: .value("Fat", x.fat), series: .value("Series", "fat")).foregroundStyle(fatColor)
                    AreaMark(x: .value("Day", x.date), yStart: .value("Base", 0), yEnd: .value("Lean", lean(x.fat)), series: .value("Series", "leanArea"))
                        .foregroundStyle(LinearGradient(colors: [leanColor.opacity(0.18), leanColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                    AreaMark(x: .value("Day", x.date), yStart: .value("Base", 0), yEnd: .value("Fat", x.fat), series: .value("Series", "fatArea"))
                        .foregroundStyle(LinearGradient(colors: [fatColor.opacity(0.14), fatColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
            }
            if !isWeek, let last = r.last {
                PointMark(x: .value("Day", last.date), y: .value("Lean", lean(last.fat)))
                    .symbol { Circle().strokeBorder(leanColor, lineWidth: 2.5).frame(width: 11, height: 11) }
                PointMark(x: .value("Day", last.date), y: .value("Fat", last.fat))
                    .symbol { Circle().strokeBorder(fatColor, lineWidth: 2.5).frame(width: 11, height: 11) }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: w.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine().foregroundStyle(NunaPalette.textMuted.opacity(0.25))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: "\(Int(d))%").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) } }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 46) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ForEach(w.axisDates, id: \.self) { d in
                        if let x = proxy.position(forX: d) { w.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 25).allowsHitTesting(false) }
                    }
                    // The figures sit just above their rings: every day on a week, the newest reading on a longer stretch.
                    ForEach(isWeek ? r : (r.last.map { [$0] } ?? [])) { x in
                        if let px = proxy.position(forX: x.date) {
                            if let py = proxy.position(forY: lean(x.fat)) { label(lean(x.fat), leanColor).position(x: frame.minX + px, y: frame.minY + py - 16).allowsHitTesting(false) }
                            if let py = proxy.position(forY: x.fat) { label(x.fat, fatColor).position(x: frame.minX + px, y: frame.minY + py - 16).allowsHitTesting(false) }
                        }
                    }
                }
            }
        }
        .frame(height: 360)
        .accessibilityLabel(Text("Lean body mass"))
    }

    private func label(_ v: Double, _ color: Color) -> some View {
        Text(verbatim: String(format: "%.1f%%", locale: AppLanguage.activeLocale, v)).font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(color).textCase(nil)
    }

    private var footer: some View {
        let last = fatS.byDay.keys.sorted().last
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        let when = last.flatMap { k -> String? in
            let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"
            return p.date(from: k).map { f.string(from: $0) }
        }
        return HStack(alignment: .top) {
            Text(verbatim: when.map { String(localized: "Last updated: \($0)") } ?? "").font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 8)
            if when != nil {
                Text(last.map { manualDays.contains($0) } == true ? "Added by hand" : "Imported from Apple Health")
                    .font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Data

    private func load() async {
        await fatS.load(repo: repo, key: "body_fat", source: "apple-health", days: 400, also: nunaManualSource)
        manualDays = Set(await repo.exploreSeries(key: "body_fat", source: nunaManualSource, days: 400).map(\.day))
    }
}

/// Every weight and body fat reading on the phone, newest first and grouped by month, with where it came from.
struct NunaBodyRecordingsView: View {
    @EnvironmentObject private var repo: Repository
    @State private var entries: [Entry] = []

    private struct Entry: Identifiable {
        let id = UUID()
        let day: String
        let value: Double
        let unit: String
        let label: String
        let manual: Bool
    }

    var body: some View {
        NunaDetailScreen("All recorded data", centersTitle: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("All recorded data").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("View all of your past recorded weight and body fat data below.").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    .textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
            ForEach(months, id: \.key) { month in
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader(LocalizedStringKey(month.title))
                    ForEach(month.entries) { e in entryRow(e) }
                }
            }
            if entries.isEmpty {
                Text("No readings yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private var months: [(key: String, title: String, entries: [Entry])] {
        let grouped = Dictionary(grouping: entries) { String($0.day.prefix(7)) }
        return grouped.keys.sorted(by: >).map { key in
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateFormat = "yyyy-MM"
            let title = f.date(from: key).map { d -> String in
                let o = DateFormatter(); o.locale = AppLanguage.activeLocale; o.setLocalizedDateFormatFromTemplate("MMM yyyy"); return o.string(from: d).uppercased()
            } ?? key
            return (key, title, grouped[key]!.sorted { $0.day > $1.day })
        }
    }

    private func entryRow(_ e: Entry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: e.manual ? "pencil" : "heart.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .frame(width: 44, height: 44).background(NunaPalette.textMuted.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, e.value)).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: e.unit).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Text(verbatim: e.label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).padding(.leading, 6)
                }
                Text(verbatim: (e.manual ? String(localized: "Added by hand") : "Apple Health") + " · " + e.day).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private func load() async {
        var out: [Entry] = []
        for (key, unit, label) in [("weight", "kg", String(localized: "Weight")), ("body_fat", "%", String(localized: "Body fat"))] {
            for p in await repo.exploreSeries(key: key, source: "apple-health", days: 4000) { out.append(Entry(day: p.day, value: p.value, unit: unit, label: label, manual: false)) }
            for p in await repo.exploreSeries(key: key, source: nunaManualSource, days: 4000) { out.append(Entry(day: p.day, value: p.value, unit: unit, label: label, manual: true)) }
        }
        entries = out
    }
}
#endif
