#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// "Last 7 days": Charge and Effort for each of the seven days ending on the day shown, side by side. Both are drawn on the same 0 to 100
/// height, so a taller bar always means more, with no second axis to decode. A day's Charge bar takes the colour its ring had that day
/// (green, yellow or red) and its Effort bar the blue of its level, so the colours read exactly as they do on the rings above.
struct NunaWeekCompare: View {
    let endDay: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var charge: [String: Double] = [:]
    @State private var effort: [String: Double] = [:]
    @State private var loaded = false

    private let plotHeight: CGFloat = 96

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
                        HStack(alignment: .bottom, spacing: 0) { ForEach(days) { column($0, isLast: $0.key == days.last?.key) } }
                        HStack(spacing: 16) {
                            NunaLegendItem(color: NunaScoreStyle.chargeSeries, text: "Charge", dot: true)
                            NunaLegendItem(color: NunaScoreStyle.effortSeries, text: "Effort", dot: true)
                        }
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

    private func column(_ s: Slot, isLast: Bool) -> some View {
        let c = charge[s.key], e = effort[s.key]
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                bar(c.map { "\(Int($0.rounded()))" }, fraction: c.map { $0 / 100 }, color: c.map(nunaChargeColor) ?? NunaPalette.textMuted)
                bar(e.map { UnitFormatter.effortDisplay($0, scale: effortScale) }, fraction: e.map { $0 / 100 }, color: e.map(nunaEffortColor) ?? NunaPalette.textMuted)
            }
            .frame(height: plotHeight + 16, alignment: .bottom)
            Text(verbatim: Self.weekday(s.date)).font(.nuna(size: 11, weight: .bold))
                .foregroundStyle(isLast ? NunaPalette.textPrimary : NunaPalette.textSecondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(NunaPalette.ink.opacity(isLast ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bar(_ label: String?, fraction: Double?, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: label ?? "").font(.nuna(size: 9.5, weight: .bold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color)
                .frame(width: 13, height: fraction == nil ? 0 : max(6, plotHeight * CGFloat(min(max(fraction ?? 0, 0), 1))))
        }
        .frame(width: 20)
    }

    private static func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
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
