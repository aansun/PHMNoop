#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// The Lab Book as a summary: how many markers sit where, then every marker as a card under its status. Lab Book gives no verdicts of its own, so the
// three statuses are only about the range the person copied from their own report (or the WHO reference for weight and waist): inside it, outside it,
// or no range to judge by. A marker in the catalog with no reading yet sits last, as "No data available".

// MARK: - Status

enum NunaLabStatus: CaseIterable, Hashable {
    case outside, within, noRange, noData

    var title: LocalizedStringKey {
        switch self {
        case .outside: return "Out of range"
        case .within: return "Within range"
        case .noRange: return "No range"
        case .noData: return "No data available"
        }
    }

    var tint: Color {
        switch self {
        case .outside: return NunaPalette.warning
        case .within: return NunaPalette.charge
        case .noRange: return NunaPalette.effortModerate
        case .noData: return NunaPalette.textMuted
        }
    }

    var symbol: String {
        switch self {
        case .outside: return "exclamationmark"
        case .within: return "checkmark"
        case .noRange: return "circle.fill"
        case .noData: return "minus"
        }
    }

    /// The statuses a reading can have, in the order the summary lists them.
    static let readable: [NunaLabStatus] = [.within, .noRange, .outside]
}

extension NunaLabMarker {
    var status: NunaLabStatus {
        switch latestStatus {
        case .some(.within): return .within
        case .some: return .outside
        case .none: return .noRange
        }
    }
}

/// A status as a small tinted tag: a mark and its name.
struct NunaLabStatusChip: View {
    let status: NunaLabStatus
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: status.symbol).font(.nuna(size: status == .noRange ? 7 : 11, weight: .heavy))
            Text(status.title).font(.nuna(size: 13.5, weight: .semibold)).textCase(nil).lineLimit(1)
        }
        .foregroundStyle(status.tint).padding(.horizontal, 10).frame(height: 28)
        .background(status.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }
}

// MARK: - Ring

/// Markers by status as a ring of arcs with a small gap between them, and whatever the screen puts in the middle.
struct NunaLabStatusRing<Center: View>: View {
    let within: Int
    let noRange: Int
    let outside: Int
    var lineWidth: CGFloat = 16
    let center: Center

    init(within: Int, noRange: Int, outside: Int, lineWidth: CGFloat = 16, @ViewBuilder center: () -> Center) {
        self.within = within; self.noRange = noRange; self.outside = outside; self.lineWidth = lineWidth; self.center = center()
    }

    var body: some View {
        let parts: [(Int, Color)] = [(within, NunaLabStatus.within.tint), (noRange, NunaLabStatus.noRange.tint), (outside, NunaLabStatus.outside.tint)].filter { $0.0 > 0 }
        let total = Double(max(parts.reduce(0) { $0 + $1.0 }, 1))
        let gap = parts.count > 1 ? 0.012 : 0
        ZStack {
            Circle().stroke(NunaPalette.ringTrack, lineWidth: lineWidth)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                let a = Double(parts[..<i].reduce(0) { $0 + $1.0 }) / total, b = a + Double(p.0) / total
                Circle().trim(from: a + gap / 2, to: max(a + gap / 2 + 0.001, b - gap / 2))
                    .stroke(p.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .shadow(color: p.1.opacity(0.4), radius: 6)
            }
            .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Range strip

/// Where the latest reading sits against its range, on a short bar: amber below, green inside, amber above, with a small mark over the reading.
/// Without a range the bar is one neutral run and the mark shows where the reading is among the person's own.
struct NunaLabRangeStrip: View {
    /// 0...1 across the bar; the middle 60% is the range.
    let position: Double
    let ranged: Bool
    var tint: Color = NunaPalette.textPrimary

    var body: some View {
        Canvas { ctx, size in
            let barY: CGFloat = 14, h = size.height - barY, gap: CGFloat = 2
            let w = size.width
            func segment(_ x0: CGFloat, _ x1: CGFloat, _ color: Color, left: CGFloat, right: CGFloat) {
                let rect = CGRect(x: x0, y: barY, width: max(x1 - x0, 1), height: h)
                let shape = UnevenRoundedRectangle(topLeadingRadius: left, bottomLeadingRadius: left, bottomTrailingRadius: right, topTrailingRadius: right, style: .continuous)
                ctx.fill(shape.path(in: rect), with: .color(color.opacity(0.22)))
                var top = Path(); top.move(to: CGPoint(x: x0 + left * 0.6, y: barY + 1.5)); top.addLine(to: CGPoint(x: x1 - right * 0.6, y: barY + 1.5))
                ctx.stroke(top, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if ranged {
                let a = w * 0.2, b = w * 0.8
                segment(0, a - gap / 2, NunaLabStatus.outside.tint, left: 7, right: 2)
                segment(a + gap / 2, b - gap / 2, NunaLabStatus.within.tint, left: 2, right: 2)
                segment(b + gap / 2, w, NunaLabStatus.outside.tint, left: 2, right: 7)
            } else {
                segment(0, w, NunaLabStatus.noRange.tint, left: 7, right: 7)
            }
            let x = min(max(CGFloat(position) * w, 6), w - 6)
            var tri = Path()
            tri.move(to: CGPoint(x: x - 6, y: 1)); tri.addLine(to: CGPoint(x: x + 6, y: 1)); tri.addLine(to: CGPoint(x: x, y: 11)); tri.closeSubpath()
            ctx.fill(tri, with: .color(tint))
        }
        .frame(width: 138, height: 38)
        .accessibilityHidden(true)
    }
}

// MARK: - The card on the Health tab

/// The Lab Book on the Health tab: how many markers sit inside their range, outside it, or have none to judge by, with the date of the last result and
/// the total as a ring. It opens the Lab Book.
struct NunaLabBookCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false

    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(rows, reference: .init(heightCm: profile.heightCm, sex: profile.sex)) }

    var body: some View {
        let ms = markers
        let counts = Dictionary(grouping: ms, by: \.status).mapValues(\.count)
        let last = rows.map(\.takenAt).max()
        NavigationLink(value: NunaTodayRoute.labBook) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Lab Book").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(NunaLabStatus.readable, id: \.self) { s in
                                HStack(spacing: 0) {
                                    NunaLabStatusChip(status: s)
                                    Spacer(minLength: 8)
                                    Text(verbatim: "\(counts[s] ?? 0)").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }
                            if let last {
                                Text(verbatim: String(localized: "Last updated: \(LabBookFormat.day(last))")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            } else if loaded {
                                Text("No results yet").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        NunaLabStatusRing(within: counts[.within] ?? 0, noRange: counts[.noRange] ?? 0, outside: counts[.outside] ?? 0, lineWidth: 13) {
                            VStack(spacing: 2) {
                                Text(verbatim: "\(ms.count)").font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                HStack(spacing: 2) {
                                    Text("Biomarkers").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    Image(systemName: "chevron.right").font(.nuna(size: 9, weight: .bold))
                                }.foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                        .frame(width: 138, height: 138)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
    }
}

// MARK: - The summary page

/// The Lab Book page, and the same page for one test (`testId`): the ring and the three counts, a line about where the markers sit, a search and the
/// filter, then the markers under their status. The whole book also shows the latest tests and the way to add a result.
struct NunaLabSummaryPage: View {
    let title: LocalizedStringKey
    /// The test to show (`NunaLabTests.key`); nil shows every reading.
    var testId: String?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var adding = false
    @State private var addingMarker: MarkerDefinition?
    @State private var sort: Sort = .status
    @State private var filter: Set<NunaLabStatus> = []
    @State private var query = ""
    @State private var filtering = false
    @FocusState private var searching: Bool

    enum Sort { case status, alphabetical }

    private var shown: [LabMarkerRow] { testId.map { id in rows.filter { NunaLabTests.key($0) == id } } ?? rows }
    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(shown, reference: .init(heightCm: profile.heightCm, sex: profile.sex)) }

    /// Catalog markers with no reading yet, for the "No data available" section of the whole book.
    private var missing: [MarkerDefinition] {
        guard testId == nil else { return [] }
        let have = Set(markers.map(\.key))
        return MarkerCatalog.builtIn.filter { $0.key != LabBookProjection.bpDiastolicKey && $0.category != .bodyMeasurement && !have.contains($0.key) }
    }

    var body: some View {
        let ms = markers
        NunaDetailScreen(title) {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else if ms.isEmpty && testId == nil {
                emptyCard
                addButton
            } else {
                header(ms)
                insight(ms)
                searchField
                filterRow
                list(ms)
                if testId == nil { history }
                if testId == nil { addButton }
            }
            NunaExpandRow(title: "About the Lab Book", subtitle: "", systemImage: "lock",
                          text: "Lab Book keeps your own numbers. It doesn't test, read, or judge them, and it's not medical advice. A range shows where a reading sits against the one you copied from your own report or, for weight and waist, against the WHO reference. Everything stays on this iPhone.")
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(isPresented: $adding) {
            NunaLabTestFlow { rows = await NunaLabStore.load(repo) }
                .nunaSheetChrome(detents: [.large])
        }
        .sheet(item: $addingMarker) { def in
            NunaLabAddSheet(preselect: def.key, preselectName: def.displayName, preselectUnit: def.canonicalUnit) { drafts in
                await NunaLabStore.save(drafts, repo: repo); rows = await NunaLabStore.load(repo)
            }
            .nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $filtering) {
            NunaLabFilterSheet(sort: $sort, filter: $filter)
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private func header(_ ms: [NunaLabMarker]) -> some View {
        let counts = Dictionary(grouping: ms, by: \.status).mapValues(\.count)
        let last = shown.map(\.takenAt).max()
        return HStack(alignment: .center, spacing: 12) {
            NunaLabStatusRing(within: counts[.within] ?? 0, noRange: counts[.noRange] ?? 0, outside: counts[.outside] ?? 0, lineWidth: 15) {
                VStack(spacing: 2) {
                    Text(verbatim: "\(ms.count)").font(.nuna(size: 44, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Biomarkers").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            .frame(width: 158, height: 158)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NunaLabStatus.readable, id: \.self) { s in
                    HStack(spacing: 0) {
                        NunaLabStatusChip(status: s)
                        Spacer(minLength: 6)
                        Text(verbatim: "\(counts[s] ?? 0)").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
                if let last {
                    Text(verbatim: String(localized: "Last updated: \(LabBookFormat.day(last))")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    /// One plain sentence about where the markers sit, in an outlined card.
    private func insight(_ ms: [NunaLabMarker]) -> some View {
        let judged = ms.filter { $0.latestStatus != nil }
        let outside = judged.filter { $0.latestStatus != .within }.count
        let text: String
        if judged.isEmpty { text = String(localized: "Add the range from your own report with a result, and this page shows which markers sit inside it.") }
        else if outside == 0 { text = String(localized: "Every marker with a range sits inside it.") }
        else { text = String(localized: "\(outside) of \(judged.count) markers with a range sit outside it. The range comes from your own report; Lab Book doesn't judge it.") }
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            if testId == nil {
                NavigationLink { NunaLabHistoryView() } label: {
                    HStack(spacing: 8) {
                        Text("See lab history").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 14, weight: .bold))
                    }.foregroundStyle(NunaPalette.effortModerate)
                }.buttonStyle(.plain)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.effortModerate.opacity(0.55), lineWidth: 1.5))
    }

    // MARK: Search and filter

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
            TextField("", text: $query, prompt: Text("Search for LDL, ferritin, etc.").foregroundStyle(NunaPalette.textMuted))
                .font(.nunaWords(size: 16)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .focused($searching).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textMuted) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture { searching = true }
    }

    private var filterRow: some View {
        Button { filtering = true } label: {
            HStack {
                Text("Filter & sort").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if !filter.isEmpty {
                    Text(verbatim: "\(filter.count)").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.onAccent)
                        .frame(minWidth: 20, minHeight: 20).background(NunaPalette.accent, in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 20).frame(height: 54).contentShape(Rectangle())
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: List

    private func visible(_ status: NunaLabStatus) -> Bool { filter.isEmpty || filter.contains(status) }

    private func list(_ ms: [NunaLabMarker]) -> some View {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ name: String) -> Bool { word.isEmpty || name.localizedCaseInsensitiveContains(word) }
        let found = ms.filter { visible($0.status) && matches($0.name) }
        let gaps = missing.filter { visible(.noData) && matches($0.displayName) }
        let byName: (NunaLabMarker, NunaLabMarker) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 16) {
            if sort == .alphabetical {
                let items: [(name: String, view: AnyView)] =
                    found.map { m in (m.name, AnyView(markerCard(m))) } + gaps.map { d in (d.displayName, AnyView(emptyCard(d))) }
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, id: \.name) { $0.view }
            } else {
                ForEach([NunaLabStatus.outside, .within, .noRange], id: \.self) { s in
                    let group = found.filter { $0.status == s }.sorted(by: byName)
                    if !group.isEmpty {
                        section(s.title, count: group.count)
                        ForEach(group) { markerCard($0) }
                    }
                }
                if !gaps.isEmpty {
                    section(NunaLabStatus.noData.title, count: gaps.count)
                    ForEach(gaps, id: \.key) { emptyCard($0) }
                }
            }
            if found.isEmpty && gaps.isEmpty {
                Text("No marker matches.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, count: Int) -> some View {
        VStack(spacing: 12) {
            NunaDivider().padding(.top, 8)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                Text(count == 1 ? LocalizedStringKey("1 biomarker") : LocalizedStringKey("\(count) biomarkers")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    private func markerCard(_ m: NunaLabMarker) -> some View {
        let latest = m.latest, value = latest?.value
        return NavigationLink { NunaLabMarkerHost(markerKey: m.key, isBody: m.category == .bodyMeasurement) } label: {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(verbatim: m.name).font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(verbatim: latest.map(m.text) ?? "—").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                                Text(verbatim: m.unit).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                            }
                            NunaLabStatusChip(status: m.status)
                        }
                        Spacer(minLength: 0)
                        if let v = value { strip(m, v) }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func strip(_ m: NunaLabMarker, _ v: Double) -> some View {
        if let r = m.range {
            NunaLabRangeStrip(position: Self.position(v, r), ranged: true)
        } else {
            let values = m.numeric.compactMap(\.value)
            if let lo = values.min(), let hi = values.max(), hi > lo {
                NunaLabRangeStrip(position: 0.1 + 0.8 * (v - lo) / (hi - lo), ranged: false)
            }
        }
    }

    /// A catalog marker with nothing recorded yet: its name and a dash, and a touch opens the sheet to add its first reading.
    private func emptyCard(_ def: MarkerDefinition) -> some View {
        Button { addingMarker = def } label: {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(verbatim: def.key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : def.displayName)
                            .font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    Text(verbatim: "--").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }

    /// Where a value sits on the strip: the middle 60% is the range, the sides are what is below and above it.
    static func position(_ v: Double, _ r: NunaLabRange) -> Double {
        let span = max(r.high - r.low, 0.000_1)
        if v < r.low { return max(0.02, 0.2 - 0.18 * min((r.low - v) / (span * 0.5), 1)) }
        if v > r.high { return min(0.98, 0.8 + 0.18 * min((v - r.high) / (span * 0.5), 1)) }
        return 0.2 + 0.6 * (v - r.low) / span
    }

    // MARK: Test history and adding

    private var history: some View {
        let tests = NunaLabTests.group(rows)
        return VStack(alignment: .leading, spacing: 12) {
            NunaDivider().padding(.top, 8)
            HStack(alignment: .firstTextBaseline) {
                Text("Test history").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                NavigationLink { NunaLabHistoryView() } label: {
                    HStack(spacing: 6) {
                        Text("View all").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 14, weight: .bold))
                    }.foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain)
            }
            ForEach(tests.prefix(3)) { NunaLabTestRow(test: $0) }
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                Text("Add results").font(.nuna(size: 17, weight: .bold))
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
}

// MARK: - Filter and sort

/// How the list is sorted (by status, or A to Z) and which statuses it shows. Taking effect as the boxes are ticked.
struct NunaLabFilterSheet: View {
    @Binding var sort: NunaLabSummaryPage.Sort
    @Binding var filter: Set<NunaLabStatus>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Filter & sort").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity)
                NunaRuledHeader("Sort by")
                VStack(spacing: 10) {
                    choice("Status", on: sort == .status) { sort = .status }
                    choice("A to Z", on: sort == .alphabetical) { sort = .alphabetical }
                }
                NunaRuledHeader("Filter by status")
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(NunaLabStatus.allCases, id: \.self) { s in box(s) }
                }
                .padding(.top, 4)
                if !filter.isEmpty {
                    Button { filter = [] } label: {
                        Text("Clear all").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 26).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func choice(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func box(_ s: NunaLabStatus) -> some View {
        let on = filter.contains(s)
        return Button { if on { filter.remove(s) } else { filter.insert(s) } } label: {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? NunaPalette.accent : NunaPalette.textPrimary, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? NunaPalette.accent : Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay { if on { Image(systemName: "checkmark").font(.nuna(size: 16, weight: .heavy)).foregroundStyle(NunaPalette.onAccent) } }
                Text(s.title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}
#endif
