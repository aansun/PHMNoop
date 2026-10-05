#if os(iOS)
import SwiftUI
import StrandDesign

/// The one card of a metric detail screen: the latest reading at the top left, the W / M / 6M switch and the date
/// stepper at the top right, a sentence about the period, the chart, and the average, lowest and highest as plain text.
/// Every figure is computed from the stored readings of the window the wearer is looking at.
struct NunaTrendDetailCard: View {
    let title: String
    let caption: LocalizedStringKey
    let valueText: String
    var unit = ""
    var chip: (text: LocalizedStringKey, color: Color)?
    var note: String?
    @ObservedObject var series: NunaSeriesModel
    var lineColor: Color = NunaPalette.charge
    var decimals = 0
    var higherIsBetter = true

    @State private var range = 7
    @State private var page = 0

    private static let ranges: [(value: Int, title: String)] = [(7, "W"), (30, "M"), (180, "6M")]

    private func fmt(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    private var windowEnd: Date { Calendar.current.date(byAdding: .day, value: -page * range, to: Date()) ?? Date() }
    private var windowStart: Date { Calendar.current.date(byAdding: .day, value: -(range - 1), to: windowEnd) ?? windowEnd }
    private var canGoBack: Bool {
        guard let first = series.byDay.keys.min() else { return false }
        return Repository.localDayKey(windowStart) > first
    }

    private var dateLabel: String {
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("d MMM")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("d MMM yy")
        return "\(a.string(from: windowStart)) – \(b.string(from: windowEnd))"
    }

    private func average(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    var body: some View {
        let pts = series.readings(range, endingDaysAgo: page * range)
        let vals = pts.map(\.value)
        let prev = average(series.readings(range, endingDaysAgo: (page + 1) * range).map(\.value))
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let s = summary(avg: average(vals), prev: prev) {
                    Text(verbatim: s).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pts.isEmpty {
                    Text(series.loaded ? "No data in this period" : " ").font(.nuna(size: 14, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    NunaLine2Chart(points: pts, color: lineColor, decimals: decimals, baseline: nil,
                                   band: series.band.map { $0.lo...$0.hi }, higherIsBetter: higherIsBetter)
                }
                if let avg = average(vals), let lo = vals.min(), let hi = vals.max() {
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        stat("Average", fmt(avg)); stat("Lowest", fmt(lo)); stat("Highest", fmt(hi))
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: valueText).font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let chip { NunaChip(chip.text, color: chip.color) }
                if let note {
                    Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 12) {
                rangeSwitch
                dateStepper
            }
        }
    }

    private var rangeSwitch: some View {
        HStack(spacing: 2) {
            ForEach(Self.ranges, id: \.value) { r in
                let on = range == r.value
                Button { range = r.value; page = 0 } label: {
                    Text(verbatim: r.title).font(.nuna(size: 13, weight: .bold))
                        .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(width: 48, height: 34)
                        .background(on ? NunaPalette.glassStrong : Color.clear, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(NunaPalette.shade.opacity(0.28), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    private var dateStepper: some View {
        HStack(spacing: 4) {
            Button { page += 1 } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 14, weight: .bold)).frame(width: 26, height: 30)
            }.disabled(!canGoBack).opacity(canGoBack ? 1 : 0.3)
            Text(verbatim: dateLabel).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Button { page = max(0, page - 1) } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).frame(width: 26, height: 30)
            }.disabled(page == 0).opacity(page == 0 ? 0.3 : 1)
        }
        .foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A sentence about the window against the one before it, from the same stored readings.
    private func summary(avg: Double?, prev: Double?) -> String? {
        guard let avg else { return nil }
        guard let prev, prev != 0 else { return String(localized: "Your average over this period was \(fmt(avg)).") }
        let pct = Int(((avg - prev) / abs(prev) * 100).rounded())
        if pct == 0 { return String(localized: "Your average over this period (\(fmt(avg))) matched the period before (\(fmt(prev))).") }
        return pct > 0
            ? String(localized: "Your average over this period (\(fmt(avg))) was \(pct)% above the period before (\(fmt(prev))).")
            : String(localized: "Your average over this period (\(fmt(avg))) was \(-pct)% below the period before (\(fmt(prev))).")
    }
}
#endif
