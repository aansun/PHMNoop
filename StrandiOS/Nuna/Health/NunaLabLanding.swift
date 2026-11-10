#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

/// The way into the Lab Book, and the page the Health card opens: what the latest test updated, three counts, and one large ring with an arc for
/// every biomarker. Touching an arc picks it out (its card takes the place of the counts and the arc grows into a wedge); the button in the middle opens
/// the full list. Below: the latest tests, the way to add another, and what Lab Book is and is not.
struct NunaLabLandingPage: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var adding = false
    @State private var selected: Int?

    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(rows, reference: .init(heightCm: profile.heightCm, sex: profile.sex)) }

    /// Markers in the order of the ring: within range, then no range, then outside it, each by name.
    private var ordered: [NunaLabMarker] {
        let rank: (NunaLabStatus) -> Int = { s in NunaLabStatus.readable.firstIndex(of: s) ?? 0 }
        return markers.sorted { a, b in
            rank(a.status) != rank(b.status) ? rank(a.status) < rank(b.status) : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        let list = ordered
        NunaDetailScreen("Lab Book") {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else if list.isEmpty {
                emptyCard
                addButton
                disclaimer
            } else {
                heading
                selector(list)
                ring(list)
                history
                haveOthers
                disclaimer
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true; selected = nil }
        .sheet(isPresented: $adding) {
            NunaLabTestFlow { rows = await NunaLabStore.load(repo) }.nunaSheetChrome(detents: [.large])
        }
    }

    // MARK: Top

    private var heading: some View {
        let latest = NunaLabTests.group(rows).first
        let n = latest.map { Set($0.rows.map(\.markerKey).filter { $0 != LabBookProjection.bpDiastolicKey }).count } ?? 0
        let date = latest.map { LabBookFormat.day($0.takenAt) } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text("Labs summary").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(verbatim: n == 1 ? String(localized: "1 biomarker was updated from your latest test, collected on \(date).")
                                  : String(localized: "\(n) biomarkers were updated from your latest test, collected on \(date)."))
                .font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three counts, or the card of the biomarker picked on the ring; both fill the same space, so the ring does not move.
    private func selector(_ list: [NunaLabMarker]) -> some View {
        let counts = Dictionary(grouping: list, by: \.status).mapValues(\.count)
        return Group {
            if let i = selected, list.indices.contains(i) {
                NunaLabMarkerCard(marker: list[i])
            } else {
                HStack(spacing: 12) {
                    ForEach(NunaLabStatus.readable, id: \.self) { s in tile(s, counts[s] ?? 0) }
                }
            }
        }
        .frame(height: 116, alignment: .top)
    }

    private func tile(_ s: NunaLabStatus, _ count: Int) -> some View {
        VStack(spacing: 10) {
            Text(verbatim: "\(count)").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            NunaLabStatusChip(status: s)
        }
        .frame(maxWidth: .infinity).frame(height: 73)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
    }

    // MARK: Ring

    private func ring(_ list: [NunaLabMarker]) -> some View {
        let diameter: CGFloat = 240
        return NunaLabStatusRing(tints: list.map { $0.status.tint }, lineWidth: 12, selected: selected,
                                 onPick: { i in withAnimation(.easeInOut(duration: 0.3)) { selected = i } }) {
            if selected == nil {
                ZStack {
                    Text(verbatim: "\(list.count)").font(.nuna(size: 44, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).offset(y: -22)
                    NavigationLink { NunaLabSummaryPage(title: "Labs summary") } label: {
                        HStack(spacing: 6) {
                            Text("Biomarkers").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(width: 124, height: 39)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain).offset(y: 30)
                }
                .transition(.opacity)
            }
        }
        .frame(width: diameter + 6, height: diameter + 6)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Below the ring

    private var history: some View {
        let tests = NunaLabTests.group(rows)
        return VStack(alignment: .leading, spacing: 12) {
            NunaDivider().padding(.bottom, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("Test history").font(.nuna(size: 24, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                NavigationLink { NunaLabHistoryView() } label: {
                    HStack(spacing: 6) {
                        Text("View all").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 15, weight: .bold))
                    }.foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain)
            }
            ForEach(tests.prefix(3)) { NunaLabTestRow(test: $0) }
        }
    }

    private var haveOthers: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Have other tests?").font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Add more tests to follow your biomarkers over time.").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { adding = true } label: {
                Text("Add results").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(18).background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    /// What Lab Book is and is not, in three short parts.
    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 14) {
            note("Your privacy comes first", "Everything you add stays on this iPhone. Lab Book has no account and sends nothing anywhere.")
            note("Important note", "Lab Book is not a laboratory or a healthcare provider. It keeps the numbers you give it and shows them against the range from your own report, and it cannot check them.")
            note("Medical disclaimer", "What Lab Book shows is not medical advice and is not meant to diagnose, prevent, monitor or treat any condition. Talk to your doctor about your results, and don't change your care because of this page.")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    private func note(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(text).font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
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
#endif
