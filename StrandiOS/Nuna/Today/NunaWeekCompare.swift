#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// "Charge & Effort": the last seven days of Charge and Effort for each of the seven days ending on the day shown, as a capsule (Charge) with a line across it
/// (Effort), both on the same 0 to 100 height. The colours read exactly as they do on the rings above.
struct NunaWeekCompare: View {
    let endDay: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @State private var charge: [String: Double] = [:]
    @State private var effort: [String: Double] = [:]
    @State private var loaded = false
    @State private var selected: String?

    private struct Slot: Identifiable {
        let key: String
        let date: Date
        var id: String { key }
    }

    private var slots: [Slot] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDay)
        return (0..<7).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: end).map { Slot(key: Repository.localDayKey($0), date: $0) }
        }
    }

    var body: some View {
        let days = slots
        let hasData = days.contains { charge[$0.key] != nil || effort[$0.key] != nil }
        NavigationLink(value: NunaTodayRoute.chargeEffort) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    NunaTitleRow(title: "Charge & Effort") {
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    if loaded && !hasData {
                        Text("No readings in the last 7 days yet").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        NunaCapsuleChart(start: days.first?.key ?? Repository.localDayKey(endDay), days: 7,
                                         charge: days.compactMap { s in charge[s.key].map { (s.key, $0) } },
                                         effort: days.compactMap { s in effort[s.key].map { (s.key, $0) } },
                                         effortScale: effortScale, selected: $selected, highlightLast: true)
                        NunaCapsuleLegend()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(Repository.localDayKey(endDay))") { await load() }
    }

    private func load() async {
        async let c = repo.exploreSeries(key: "recovery", source: "my-whoop", days: 30)
        async let e = repo.exploreSeries(key: "strain", source: "my-whoop", days: 30)
        charge = Dictionary(await c.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        effort = Dictionary(await e.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        loaded = true
    }
}
#endif
