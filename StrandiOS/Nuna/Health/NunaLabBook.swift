#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Lab Book

/// Your own numbers from a doctor or a pharmacy, next to the signals of the wearable. The page says what is there at a glance (when the last test was,
/// how many markers sit inside the range from the person's own report), then lists every marker with its latest reading, how it moved and where it sits.
/// Adding a result, by hand or from a file, is one sheet.
struct NunaLabBookView: View {
    @EnvironmentObject private var repo: Repository
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var adding = false

    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(rows) }

    var body: some View {
        let ms = markers
        NunaDetailScreen("Lab Book") {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else if ms.isEmpty {
                emptyCard
            } else {
                summary(ms)
                ForEach(NunaLabGrouping.categoryOrder, id: \.self) { category in
                    let inCategory = ms.filter { $0.category == category }
                    if !inCategory.isEmpty {
                        NunaTitleRow(title: LocalizedStringKey(category.displayName)) {
                            Text(verbatim: "\(inCategory.count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        ForEach(inCategory) { markerRow($0) }
                    }
                }
            }
            if loaded { addButton }
            NunaExpandRow(title: "About the Lab Book", subtitle: "", systemImage: "lock",
                          text: "Lab Book keeps your own numbers. It doesn't test, read, or judge them, and it's not medical advice. A range only shows where a reading sits against the one you copied from your own report. Everything stays on this iPhone.")
        }
        .task(id: repo.refreshSeq) { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(isPresented: $adding) {
            NunaLabAddSheet { drafts in await NunaLabStore.save(drafts, repo: repo); rows = await NunaLabStore.load(repo) }
                .nunaSheetChrome(detents: [.large])
        }
    }

    // MARK: Parts

    private var addButton: some View {
        Button { adding = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                Text("Add a result").font(.nuna(size: 17, weight: .bold))
            }
            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var emptyCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "testtube.2").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Text("Your own logbook").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Keep the numbers you get from your doctor or pharmacy, next to your wearable signals. Add a result by hand or bring in a file. Everything stays on this phone.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ ms: [NunaLabMarker]) -> some View {
        let last = rows.map(\.takenAt).max()
        let judged = ms.compactMap(\.latestStatus)
        let within = judged.filter { $0 == .within }.count
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        nunaTrendsCap("Last test")
                        Text(verbatim: last.map(LabBookFormat.day) ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: String(localized: "\(ms.count) markers · \(rows.count) readings"))
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 8)
                    if !judged.isEmpty {
                        HStack(spacing: 20) {
                            figure("Within", within, NunaPalette.charge)
                            figure("Outside", judged.count - within, NunaPalette.warning)
                        }
                    }
                }
                if judged.isEmpty {
                    Text("Add the range from your own report with a result, and this page shows which markers sit inside it.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                } else {
                    Text("Counted against the ranges you copied from your own reports, on each marker's latest reading.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }

    private func figure(_ label: LocalizedStringKey, _ n: Int, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(verbatim: "\(n)").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(tint)
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func markerRow(_ m: NunaLabMarker) -> some View {
        let latest = m.latest
        let value = latest?.value
        return NavigationLink { NunaMarkerDetailView(markerKey: m.key) } label: {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: m.name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        if let s = m.latestStatus { NunaChip(NunaLabRange.word(s), color: NunaLabRange.tint(s)) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: latest.map(m.text) ?? "—").font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                        Text(verbatim: m.unit).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        if let c = m.change, abs(c.delta) > 0.000_001 {
                            Text(verbatim: (c.delta > 0 ? "▲ " : "▼ ") + LabBookFormat.value(abs(c.delta), key: m.key))
                                .font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(m.changeTone(c.delta))
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    if let r = m.range, let v = value {
                        NunaScaleBar(parts: [(2, NunaPalette.warning.opacity(0.5)), (6, NunaPalette.charge.opacity(0.85)), (2, NunaPalette.warning.opacity(0.5))], position: Self.position(v, r))
                        HStack {
                            Text(verbatim: LabBookFormat.value(r.low, key: m.key)); Spacer(); Text(verbatim: LabBookFormat.value(r.high, key: m.key))
                        }.font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Text(verbatim: latest.map { String(localized: "last taken \(LabBookFormat.day($0.takenAt))") + " · " + (m.readings.count == 1 ? String(localized: "1 reading") : String(localized: "\(m.readings.count) readings")) } ?? "")
                        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }.buttonStyle(.plain)
    }

    /// Where a value sits on the bar: the middle 60% is the range, the sides are what is below and above it.
    static func position(_ v: Double, _ r: NunaLabRange) -> Double {
        let span = max(r.high - r.low, 0.000_1)
        if v < r.low { return max(0.02, 0.2 - 0.18 * min((r.low - v) / (span * 0.5), 1)) }
        if v > r.high { return min(0.98, 0.8 + 0.18 * min((v - r.high) / (span * 0.5), 1)) }
        return 0.2 + 0.6 * (v - r.low) / span
    }
}

// MARK: - One marker

/// One marker on its own page: the latest reading on a gauge laid out like the range from the report, the readings over time, what the numbers say in
/// words, the signal of the wearable they can be set beside, and every reading with its date.
struct NunaMarkerDetailView: View {
    let markerKey: String

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    /// The span of the chart in days; 0 shows every reading.
    @State private var span = 365
    @State private var page = 0
    @State private var adding = false
    @State private var deleting: LabMarkerRow?

    @State private var signal: MetricDescriptor?
    @State private var window: LabWindow = .fortnight
    @State private var pairs: [WindowedPair] = []
    @State private var correlation: Correlation?
    @State private var computing = false

    private var marker: NunaLabMarker? { NunaLabGrouping.markers(rows).first { $0.key == markerKey } }
    private var title: String {
        markerKey == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : (MarkerCatalog.definition(for: markerKey)?.displayName ?? LabBookView.humanise(markerKey))
    }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(title)) {
            if let m = marker {
                hero(m)
                trendCard(m)
                meaningCard(m)
                if !m.numeric.isEmpty { compareCard(m) }
                historyCard(m)
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                        Text("Add a reading").font(.nuna(size: 17, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                NunaExpandRow(title: "About these numbers", subtitle: "", systemImage: "info.circle",
                              text: "These are your own numbers shown back to you. NOOP doesn't decide whether any value is normal, high or low: a reading is only placed against the range you copied from your own report.")
            } else if loaded {
                NunaCard { Text("No readings for this marker.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .task(id: repo.refreshSeq) { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(isPresented: $adding) {
            NunaLabAddSheet(preselect: markerKey, preselectName: title, preselectUnit: marker?.unit) { drafts in
                await NunaLabStore.save(drafts, repo: repo); rows = await NunaLabStore.load(repo)
            }
            .nunaSheetChrome(detents: [.large])
        }
        .confirmationDialog("Delete this reading?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let r = deleting { Task { await delete(r) } }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("It is removed from this iPhone. This cannot be undone.") }
    }

    private func delete(_ row: LabMarkerRow) async {
        var ids = [row.id]
        if let m = marker, m.isPressure, let d = m.diastolic[row.takenAt] { ids.append(d.id) }
        await NunaLabStore.delete(ids: ids, repo: repo)
        rows = await NunaLabStore.load(repo)
        if marker == nil { dismiss() }
    }

    // MARK: Hero

    private func hero(_ m: NunaLabMarker) -> some View {
        let latest = m.latest
        let status = m.latestStatus
        return NunaCard(padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
            VStack(spacing: 14) {
                HStack {
                    nunaTrendsCap("Latest reading")
                    Spacer()
                    Text(verbatim: latest.map { LabBookFormat.dayFromKey($0.day) } ?? "").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if let r = m.range, let v = latest?.value {
                    ZStack(alignment: .bottom) {
                        NunaRangeGauge(value: v, range: r).frame(height: 150)
                        VStack(spacing: 2) {
                            Text(verbatim: latest.map(m.text) ?? "—").font(.nuna(size: 44, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                            Text(verbatim: m.unit).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }.padding(.bottom, 4)
                    }
                    if let s = status { NunaChip(NunaLabRange.word(s), color: NunaLabRange.tint(s)) }
                    HStack(alignment: .top, spacing: 0) {
                        if m.isPressure {
                            stat("Systolic", rangeText(m.range, key: m.key), unit: m.unit)
                            stat("Diastolic", rangeText(m.diastolicRange, key: LabBookProjection.bpDiastolicKey), unit: m.unit)
                        } else {
                            stat("Your range", rangeText(r, key: m.key), unit: m.unit)
                            changeStat(m)
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: latest.map(m.text) ?? "—").font(.nuna(size: 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                            Text(verbatim: m.unit).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if let c = m.change, abs(c.delta) > 0.000_001 { changeLine(m, c) }
                    }.frame(maxWidth: .infinity)
                    Text("Add the range from your own report with a reading, and a gauge here shows where it sits.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }

    private func rangeText(_ r: NunaLabRange?, key: String) -> String {
        guard let r else { return "–" }
        return LabBookFormat.value(r.low, key: key) + "–" + LabBookFormat.value(r.high, key: key)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: unit).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private func changeStat(_ m: NunaLabMarker) -> some View {
        VStack(spacing: 3) {
            Text("Since last time").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            if let c = m.change {
                Text(verbatim: (c.delta > 0 ? "▲ " : (c.delta < 0 ? "▼ " : "")) + LabBookFormat.value(abs(c.delta), key: m.key))
                    .font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(m.changeTone(c.delta))
                Text(verbatim: c.percent.map { String(format: "%+.0f%%", locale: AppLanguage.activeLocale, $0) } ?? m.unit)
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            } else {
                Text(verbatim: "–").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                Text("One reading").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }.frame(maxWidth: .infinity)
    }

    private func changeLine(_ m: NunaLabMarker, _ c: (delta: Double, percent: Double?, since: Int)) -> some View {
        Text(verbatim: (c.delta > 0 ? "▲ " : "▼ ") + LabBookFormat.value(abs(c.delta), key: m.key) + " " + m.unit + (c.percent.map { " (" + String(format: "%+.0f%%", locale: AppLanguage.activeLocale, $0) + ")" } ?? ""))
            .font(.nuna(size: 14, weight: .bold)).foregroundStyle(m.changeTone(c.delta))
    }

    // MARK: Trend

    private var windowDates: (from: Date, to: Date) {
        let cal = Calendar.current, now = Date()
        if span == 0 {
            let first = rows.map(\.takenAt).min().map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now
            return (cal.date(byAdding: .day, value: -3, to: first) ?? first, now)
        }
        let to = cal.date(byAdding: .day, value: -page * span, to: now) ?? now
        return (cal.date(byAdding: .day, value: -span, to: to) ?? to, to)
    }

    private func inWindow(_ m: NunaLabMarker) -> [LabMarkerRow] {
        let w = windowDates, a = Int(w.from.timeIntervalSince1970), b = Int(w.to.timeIntervalSince1970)
        return m.numeric.filter { $0.takenAt >= a && $0.takenAt <= b }
    }

    private func trendCard(_ m: NunaLabMarker) -> some View {
        let w = windowDates
        let inside = inWindow(m)
        let values = inside.compactMap(\.value)
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yy")
        let earliest = m.numeric.first?.takenAt ?? 0
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    NunaRangeSwitch(choices: [(90, "3M"), (365, "1Y"), (0, "All")], range: $span, onSelect: { page = 0 })
                    Spacer(minLength: 6)
                    if span != 0 {
                        NunaDateStepper(label: f.string(from: w.from) + " – " + f.string(from: w.to), canGoBack: Int(w.from.timeIntervalSince1970) > earliest, canGoForward: page > 0,
                                        back: { page += 1 }, forward: { page = max(0, page - 1) })
                    }
                }
                HStack(spacing: 14) {
                    legend(NunaPalette.charge, "Within your range")
                    legend(NunaPalette.warning, "Outside your range")
                    Spacer(minLength: 0)
                }
                if inside.isEmpty {
                    Text("No readings in this period. Use the arrows to look at an earlier one.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).textCase(nil)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    NunaLabChart(points: inside.map { r in
                        NunaLabChart.Point(id: r.id, date: Date(timeIntervalSince1970: TimeInterval(r.takenAt)), value: r.value ?? 0,
                                           second: m.isPressure ? m.diastolic[r.takenAt]?.value : nil, status: m.status(r))
                    }, range: m.range, from: w.from, to: w.to, format: { LabBookFormat.value($0, key: m.key) })
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        summaryFigure("Lowest", values.min(), m)
                        summaryFigure("Average", values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), m)
                        summaryFigure("Highest", values.max(), m)
                    }
                }
            }
        }
    }

    private func legend(_ tint: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(text).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func summaryFigure(_ label: LocalizedStringKey, _ v: Double?, _ m: NunaLabMarker) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v.map { LabBookFormat.value($0, key: m.key) } ?? "–").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: What it says

    private func meaningCard(_ m: NunaLabMarker) -> some View {
        var lines: [(icon: String, tint: Color, text: String)] = []
        let ref = m.readings.last(where: { $0.referenceText?.isEmpty == false })?.referenceText ?? ""
        if let s = m.latestStatus, let r = m.range {
            switch s {
            case .within: lines.append(("checkmark.circle.fill", NunaPalette.charge, String(localized: "Your latest reading is within the range from your report (\(ref)).")))
            case .above: lines.append(("arrow.up.circle.fill", NunaPalette.warning, String(localized: "Your latest reading is above the range from your report (\(ref)).")))
            case .below: lines.append(("arrow.down.circle.fill", NunaPalette.warning, String(localized: "Your latest reading is below the range from your report (\(ref)).")))
            }
            if !m.isPressure, let v = m.latest?.value, s != .within {
                let d = LabBookFormat.value(s == .above ? v - r.high : r.low - v, key: m.key)
                lines.append(("ruler", NunaPalette.textSecondary, s == .above ? String(localized: "That is \(d) \(m.unit) over the top of your range.") : String(localized: "That is \(d) \(m.unit) under the bottom of your range.")))
            }
        } else {
            lines.append(("slider.horizontal.3", NunaPalette.textSecondary, String(localized: "Add the range from your own report with a reading, and this page says where each one sits.")))
        }
        if let c = m.change {
            let since = LabBookFormat.day(c.since)
            let amount = LabBookFormat.value(abs(c.delta), key: m.key) + " " + m.unit
            let pct = c.percent.map { String(format: "%+.0f%%", locale: AppLanguage.activeLocale, $0) } ?? ""
            if abs(c.delta) < 0.000_001 { lines.append(("equal.circle.fill", NunaPalette.textSecondary, String(localized: "Unchanged since \(since).")))
            } else if c.delta > 0 { lines.append(("arrow.up.right.circle.fill", m.changeTone(c.delta), String(localized: "Up \(amount) (\(pct)) since \(since).")))
            } else { lines.append(("arrow.down.right.circle.fill", m.changeTone(c.delta), String(localized: "Down \(amount) (\(pct)) since \(since).")))
            }
        }
        if m.numeric.count == 1 {
            lines.append(("plus.circle", NunaPalette.textSecondary, String(localized: "Only one reading so far. Add a few more to see a trend.")))
        } else if m.numeric.count > 1, let first = m.numeric.first {
            lines.append(("calendar", NunaPalette.textSecondary, String(localized: "\(m.numeric.count) readings so far, the first on \(LabBookFormat.day(first.takenAt)).")))
        }
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("What it says")
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: l.icon).font(.nuna(size: 17, weight: .semibold)).foregroundStyle(l.tint).frame(width: 26)
                        Text(verbatim: l.text).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: Compare with a signal

    private func compareCard(_ m: NunaLabMarker) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    nunaTrendsCap("Compare with a signal")
                    Text(verbatim: String(localized: "side by side · \(window.phrase) before each reading")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Menu {
                    ForEach(LabBookSignals.options) { metric in
                        Button { signal = metric } label: { Label(metric.title, systemImage: signal?.id == metric.id ? "checkmark" : metric.icon) }
                    }
                    if signal != nil { Divider(); Button(role: .destructive) { signal = nil } label: { Label("Clear", systemImage: "xmark") } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.nuna(size: 16, weight: .bold))
                        Text(verbatim: signal?.title ?? String(localized: "Choose a signal")).font(.nuna(size: 15, weight: .bold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 46)
                    .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
                NunaSegmented(LabWindow.allCases.map { (value: $0, title: LocalizedStringKey($0.label)) }, selection: $window)
                if signal == nil {
                    Text("Pick a wearable signal (resting HR, HRV, sleep, Charge, weight…) to line it up against this marker. NOOP averages the signal over the \(window.phrase) before each reading.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                } else {
                    resultBlock(m)
                }
            }
        }
        .task(id: "\(signal?.id ?? "")|\(window.rawValue)|\(repo.refreshSeq)") { await recompute() }
    }

    @ViewBuilder private func resultBlock(_ m: NunaLabMarker) -> some View {
        let n = pairs.count
        let muted = Font.nuna(size: 13.5, weight: .semibold)
        if computing {
            Text("Lining them up…").font(muted).foregroundStyle(NunaPalette.textSecondary)
        } else if n < LabBookSignals.floor {
            Text(n == 0
                 ? "No overlap yet between this marker and \(signal?.title.lowercased() ?? String(localized: "that signal")). Log a few more readings (and keep wearing your strap)."
                 : (n == 1
                    ? "1 reading lines up so far, not enough to read a trend yet (NOOP waits for \(LabBookSignals.floor))."
                    : "\(n) readings line up so far, not enough to read a trend yet (NOOP waits for \(LabBookSignals.floor))."))
                .font(muted).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
        } else if let c = correlation {
            let tint = NunaPalette.effortText
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(m.name) ↔ \(signal?.title ?? "")").font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                    Spacer(minLength: 6)
                    Text(verbatim: "r = \(LabBookSignals.signedR(c.r))").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(tint)
                }
                Text(verbatim: LabBookSignals.insightSentence(markerName: m.name, signalName: signal?.title ?? String(localized: "the signal"), r: c.r))
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NunaPalette.ink.opacity(0.09))
                        Capsule().fill(tint).frame(width: max(6, g.size.width * min(abs(c.r), 1)))
                    }
                }.frame(height: 8)
                Text("\(n) readings used · \(LabBookSignals.strengthWord(c.r)) \(LabBookSignals.directionWord(c.r)) association. This is your own data sitting side by side. It's not a medical finding, and it shows association, not cause.")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        } else {
            Text("\(n) readings line up, but there isn't enough variation to compute a relationship.")
                .font(muted).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    private func recompute() async {
        guard let signal else { pairs = []; correlation = nil; return }
        computing = true
        defer { computing = false }
        let markerSeries = await repo.series(key: markerKey, source: WhoopStore.labBookSourceId)
        let wearable = await repo.exploreSeries(key: signal.key, source: signal.source)
        let built = LabBookProjection.pairMarkerToWearable(marker: markerSeries, wearable: wearable, windowDays: window.days)
        pairs = built
        correlation = built.count >= LabBookSignals.floor ? CorrelationEngine.pearson(LabBookProjection.correlationInput(built)) : nil
    }

    // MARK: History

    private func historyCard(_ m: NunaLabMarker) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)) {
            VStack(spacing: 0) {
                HStack {
                    nunaTrendsCap("History")
                    Spacer()
                    Text(verbatim: "\(m.readings.count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                }.padding(.vertical, 10)
                ForEach(Array(m.readings.reversed().enumerated()), id: \.element.id) { i, row in
                    NunaDivider()
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(verbatim: m.text(row)).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: row.unit).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Text(verbatim: LabBookFormat.dayFromKey(row.day)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            if let note = row.note, !note.isEmpty {
                                Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                        Spacer(minLength: 8)
                        if let s = m.status(row) { NunaChip(NunaLabRange.word(s), color: NunaLabRange.tint(s)) }
                        Button { deleting = row } label: {
                            Image(systemName: "trash").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.alertText).frame(width: 38, height: 38).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(Text("Delete this reading"))
                    }
                    .padding(.vertical, 10).accessibilityElement(children: .combine)
                    .id(i)
                }
            }
        }
    }
}
#endif
