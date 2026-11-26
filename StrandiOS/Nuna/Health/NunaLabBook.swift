#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Lab Book

/// The Lab Book: your own numbers from a doctor or a pharmacy, next to the signals of the wearable. It opens on the landing page (`NunaLabLandingPage`):
/// the counts, a ring with an arc for every biomarker, the latest tests and the way to add one. The full list is one touch away (`NunaLabSummaryPage`).
struct NunaLabBookView: View {
    var body: some View { NunaLabLandingPage() }
}

// MARK: - One marker

/// One marker on its own page: the latest reading on a gauge laid out like the range from the report, the readings over time, what the numbers say in
/// words, and the signal of the wearable they can be set beside.
struct NunaMarkerDetailView: View {
    let markerKey: String

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var adding = false

    @State private var signal: MetricDescriptor?
    @State private var window: LabWindow = .fortnight
    @State private var pairs: [WindowedPair] = []
    @State private var correlation: Correlation?
    @State private var computing = false

    private var marker: NunaLabMarker? { NunaLabGrouping.markers(rows, reference: .init(heightCm: profile.heightCm, sex: profile.sex)).first { $0.key == markerKey } }
    private var title: String {
        NunaLabGrouping.markerName(markerKey)
    }

    var body: some View {
        NunaDetailScreen("Biomarker details", centersTitle: true) {
            if let m = marker {
                heading(m)
                insightCard(m)
                latest(m)
                trendCard(m)
                recordingsLink(m)
                meaningCard(m)
                if !m.numeric.isEmpty { compareCard(m) }
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                        Text("Add a reading").font(.nuna(size: 17, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                NunaExpandRow(title: "About these numbers", subtitle: "", systemImage: "info.circle",
                              text: "These are your own numbers shown back to you. PHMN doesn't decide whether any value is normal, high or low: a reading is only placed against the range you copied from your own report.")
            } else if loaded {
                NunaCard { Text("No readings for this marker.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .appears(when: loaded)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(isPresented: $adding) {
            NunaLabAddSheet(preselect: markerKey, preselectName: title, preselectUnit: marker?.unit) { drafts in
                await NunaLabStore.save(drafts, repo: repo); rows = await NunaLabStore.load(repo)
            }
            .nunaSheetChrome(detents: [.large])
        }
    }

    // MARK: Top of the page

    /// The marker's name, large, with its kind as tags.
    private func heading(_ m: NunaLabMarker) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: m.name).font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                tag(m.category.displayName)
                if m.range != nil { tag(m.rangeIsWho ? String(localized: "WHO range") : String(localized: "Your range")) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(verbatim: text).font(.nuna(size: 14, weight: .medium)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            .padding(.horizontal, 13).frame(height: 33).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One plain sentence about the latest reading in a card with a violet-to-teal frame, and the way to add the next reading.
    @ViewBuilder private func insightCard(_ m: NunaLabMarker) -> some View {
        if let line = insightLine(m) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: line).font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Text("Add a reading").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                    }
                    .foregroundStyle(LinearGradient(colors: [NunaPalette.insightFrom, NunaPalette.insightBlue], startPoint: .leading, endPoint: .trailing))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 17).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
                .strokeBorder(LinearGradient(colors: [NunaPalette.insightFrom.opacity(0.6), NunaPalette.insightTo.opacity(0.6)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5))
        }
    }

    private func insightLine(_ m: NunaLabMarker) -> String? {
        let ref = m.readings.last(where: { $0.referenceText?.isEmpty == false })?.referenceText ?? ""
        switch m.latestStatus {
        case .some(.within): return String(localized: "Your latest reading is within the range from your report (\(ref)).")
        case .some(.above): return String(localized: "Your latest reading is above the range from your report (\(ref)).")
        case .some(.below): return String(localized: "Your latest reading is below the range from your report (\(ref)).")
        case .none: return String(localized: "Add the range from your own report with a reading, and this page says where each one sits.")
        }
    }

    /// The latest reading, large.
    private func latest(_ m: NunaLabMarker) -> some View {
        let l = m.latest
        return VStack(alignment: .leading, spacing: 12) {
            Text("Latest").font(.nuna(size: 10, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: l.map(m.text) ?? "—").font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: m.unit).font(.nuna(size: 15, weight: .medium)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordingsLink(_ m: NunaLabMarker) -> some View {
        NavigationLink { NunaLabRecordingsView(markerKey: m.key) } label: {
            HStack(spacing: 16) {
                Image(systemName: "list.bullet").font(.nuna(size: 20, weight: .ultraLight)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
                Text("See all recordings").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 16).frame(height: 56).contentShape(Rectangle())
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Trend

    /// The chart shows every reading: from a few days before the first one to now.
    private var windowDates: (from: Date, to: Date) {
        let cal = Calendar.current, now = Date()
        let first = rows.map(\.takenAt).min().map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now
        return (cal.date(byAdding: .day, value: -3, to: first) ?? first, now)
    }

    private func inWindow(_ m: NunaLabMarker) -> [LabMarkerRow] {
        let w = windowDates, a = Int(w.from.timeIntervalSince1970), b = Int(w.to.timeIntervalSince1970)
        return m.numeric.filter { $0.takenAt >= a && $0.takenAt <= b }
    }

    private func trendCard(_ m: NunaLabMarker) -> some View {
        let w = windowDates
        let inside = inWindow(m)
        return VStack(alignment: .leading, spacing: 14) {
            legendPill(m)
            if inside.isEmpty {
                Text("No readings for this marker.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).textCase(nil)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                NunaLabChart(points: inside.map { r in
                    NunaLabChart.Point(id: r.id, date: Date(timeIntervalSince1970: TimeInterval(r.takenAt)), value: r.value ?? 0,
                                       second: m.isPressure ? m.diastolic[r.takenAt]?.value : nil, status: m.status(r))
                }, range: m.range, from: w.from, to: w.to, format: { LabBookFormat.value($0, key: m.key) })
            }
        }
    }

    /// The key of the chart on a dark bar: a short dash of each colour in use and its name.
    private func legendPill(_ m: NunaLabMarker) -> some View {
        HStack(spacing: 18) {
            if m.range != nil {
                legend(NunaPalette.caution, "Out of range")
                legend(NunaPalette.charge, "Within range")
            } else {
                legend(NunaPalette.rangeSteel, "No range")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 24).frame(maxWidth: .infinity).frame(height: 28.5)
        .background(NunaPalette.canvas.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legend(_ tint: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(tint).frame(width: 11, height: 2.4)
            Text(text).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: What it says

    private func meaningCard(_ m: NunaLabMarker) -> some View {
        var lines: [(icon: String, tint: Color, text: String)] = []
        // Where the latest reading sits is said once, in the sentence at the top of the page; here only how far outside the range it is.
        if let s = m.latestStatus, let r = m.range, !m.isPressure, let v = m.latest?.value, s != .within {
            let d = LabBookFormat.value(s == .above ? v - r.high : r.low - v, key: m.key)
            lines.append(("ruler", NunaPalette.textSecondary, s == .above ? String(localized: "That is \(d) \(m.unit) over the top of your range.") : String(localized: "That is \(d) \(m.unit) under the bottom of your range.")))
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
                NunaMenu {
                    ForEach(LabBookSignals.options) { metric in
                        NunaMenuItem(verbatim: metric.title, icon: metric.icon, selected: signal?.id == metric.id) { signal = metric }
                    }
                    if signal != nil { NunaMenuGap(); NunaMenuItem("Clear", icon: "xmark", role: .destructive) { signal = nil } }
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
                    Text("Pick a wearable signal (resting HR, HRV, sleep, Recovery, weight…) to line it up against this marker. PHMN averages the signal over the \(window.phrase) before each reading.")
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
                    ? "1 reading lines up so far, not enough to read a trend yet (PHMN waits for \(LabBookSignals.floor))."
                    : "\(n) readings line up so far, not enough to read a trend yet (PHMN waits for \(LabBookSignals.floor))."))
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
}

// MARK: - Moving between markers

/// Holds the marker on show and puts the dropdown in the header, so the wearer goes from one marker to the next without going back to the list.
struct NunaLabMarkerHost: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var current: String
    @State private var items: [NunaDetailSwitch.Item] = []
    @State private var bodyKeys: Set<String>

    init(markerKey: String, isBody: Bool) {
        _current = State(initialValue: markerKey)
        _bodyKeys = State(initialValue: isBody ? [markerKey] : [])
    }

    var body: some View {
        // Body measurements keep the Weight page they already had, with its BMI and waist cards, rather than a second page of their own.
        Group {
            if bodyKeys.contains(current) { NunaWeightView() } else { NunaMarkerDetailView(markerKey: current) }
        }
        .id(current)
        .environment(\.nunaDetailSwitch, items.count > 1 && items.contains { $0.key == current }
            ? NunaDetailSwitch(current: current, items: items) { current = $0 } : nil)
        .task(id: repo.refreshSeq) {
            let markers = NunaLabGrouping.markers(await NunaLabStore.load(repo), reference: .init(heightCm: profile.heightCm, sex: profile.sex))
            bodyKeys = Set(markers.filter { $0.category == .bodyMeasurement }.map(\.key))
            items = NunaLabGrouping.categoryOrder.flatMap { cat in
                markers.filter { $0.category == cat }.sorted { $0.name < $1.name }
                    .map { NunaDetailSwitch.Item(key: $0.key, title: $0.name, icon: Self.icon($0)) }
            }
        }
    }

    private static func icon(_ m: NunaLabMarker) -> String {
        switch m.category {
        case .bloodPanel: return "testtube.2"
        case .bloodPressure: return "waveform.path.ecg"
        case .bodyMeasurement: return "figure.arms.open"
        case .imaging: return "photo"
        case .appointmentNote: return "note.text"
        case .other: return "list.bullet.clipboard"
        }
    }
}
#endif
