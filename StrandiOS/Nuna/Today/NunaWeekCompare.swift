#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// "Last 7 days": Charge and Effort for each of the seven days ending on the day shown, as a capsule (Charge) with a line across it
/// (Effort), both on the same 0 to 100 height. The colours read exactly as they do on the rings above.
struct NunaWeekCompare: View {
    let endDay: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var charge: [String: Double] = [:]
    @State private var effort: [String: Double] = [:]
    @State private var loaded = false

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

    private func mean(_ s: [String: Double], _ slots: [Slot]) -> Double? {
        let v = slots.compactMap { s[$0.key] }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    var body: some View {
        let days = slots
        let hasData = days.contains { charge[$0.key] != nil || effort[$0.key] != nil }
        Button { router.requestedDestination = .trends } label: {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    NunaTitleRow(title: "Last 7 days") {
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    if loaded && !hasData {
                        Text("No readings in the last 7 days yet").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        averages(days)
                        NunaCapsuleChart(start: days.first?.key ?? Repository.localDayKey(endDay), days: 7,
                                         charge: days.compactMap { s in charge[s.key].map { (s.key, $0) } },
                                         effort: days.compactMap { s in effort[s.key].map { (s.key, $0) } },
                                         effortScale: effortScale, highlightLast: true)
                        NunaCapsuleLegend()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(Repository.localDayKey(endDay))") { await load() }
    }

    private func averages(_ days: [Slot]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            average("Charge", mean(charge, days).map { "\(Int($0.rounded()))" }, unit: "%", color: mean(charge, days).map(nunaChargeColor) ?? NunaPalette.textMuted)
            average("Effort", mean(effort, days).map { UnitFormatter.effortDisplay($0, scale: effortScale) }, unit: "",
                    color: mean(effort, days).map(nunaEffortColor) ?? NunaPalette.textMuted)
        }
    }

    private func average(_ title: LocalizedStringKey, _ value: String?, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if !unit.isEmpty && value != nil { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            Text("7-day average").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
