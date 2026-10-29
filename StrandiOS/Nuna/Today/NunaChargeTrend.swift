#if os(iOS)
import SwiftUI
import StrandDesign

/// One signal under the Charge ring, drawn like the reference: the icon, the UPPERCASE name, the figure with a small triangle or dot, and the
/// 30-day average it is compared with underneath. The triangle is green when the move is the good way, amber when it is not.
struct NunaSignalRow: View {
    let title: LocalizedStringKey
    let icon: String
    let value: String?
    let trend: NunaTrend?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text(title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            NunaTrendFigure(value: value ?? "–", trend: value == nil ? nil : trend, size: 24, minimumScale: 0.7)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// The card under the ring: a soft gradient, lighter at the top, with a small notch at the top pointing up to the ring it explains.
struct NunaSignalPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            NunaNotch().fill(NunaPalette.cardHighlight).frame(width: 24, height: 9)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 16)
                .background(LinearGradient(colors: [NunaPalette.cardHighlight, NunaPalette.card], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairline.opacity(0.5), lineWidth: 1))
        }
    }
}

private struct NunaNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// "▲▼ Today vs. last 30 days": what the triangles under the ring compare with.
struct NunaTrendLegend: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: "arrowtriangle.up.fill").foregroundStyle(NunaPalette.charge)
                Image(systemName: "arrowtriangle.down.fill").foregroundStyle(NunaPalette.warning)
            }
            .font(.system(size: 8, weight: .bold))
            Text(text).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }
}

/// Under the Charge chart: how many of the days in the window fell in each zone, as one bar split by days and a line for each zone.
struct NunaChargeBreakdown: View {
    let values: [Double]

    private var ready: Int { values.filter { $0 >= 67 }.count }
    private var moderate: Int { values.filter { $0 >= 34 && $0 < 67 }.count }
    private var low: Int { values.filter { $0 < 34 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Charge breakdown").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary)
                Text("(days)").font(.nuna(size: 12, weight: .semibold)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
            }
            bar
            VStack(alignment: .leading, spacing: 12) {
                line(NunaPalette.scoreHigh, ready, "Ready", "67–100%")
                line(NunaPalette.scoreMid, moderate, "Moderate", "34–66%")
                line(NunaPalette.scoreLow, low, "Low", "0–33%")
            }
        }
        .padding(.top, 6)
    }

    /// One bar, split in the proportion of the days; the track alone when there are none.
    private var bar: some View {
        GeometryReader { g in
            let total = max(1, ready + moderate + low)
            let gap: CGFloat = 2
            let parts = [(NunaPalette.scoreHigh, ready), (NunaPalette.scoreMid, moderate), (NunaPalette.scoreLow, low)].filter { $0.1 > 0 }
            let room = g.size.width - gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(part.0).frame(width: room * CGFloat(part.1) / CGFloat(total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NunaPalette.zoneBase.opacity(parts.isEmpty ? 1 : 0)))
        }
        .frame(height: 16)
    }

    private func line(_ color: Color, _ days: Int, _ name: LocalizedStringKey, _ range: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(verbatim: "\(days)×").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 34, alignment: .leading)
            (Text(name) + Text(verbatim: " (\(range))")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 0)
        }
    }
}

/// The page the weekly Charge card opens: the full chart with its week, month and six-month views, and the days per zone under it.
struct NunaChargeTrendView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @StateObject private var series = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0

    var body: some View {
        NunaDetailScreen("Charge") {
            NunaTrendDetailCard(
                caption: "Average", unit: "%",
                readings: { days, back in series.readings(days, endingDaysAgo: back) },
                hasOlder: { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false },
                loaded: series.loaded, band: series.typicalRange,
                lineColor: NunaPalette.charge, decimals: 0, directional: true,
                levelChip: { v in (text: v >= 67 ? "Ready" : (v >= 34 ? "Moderate" : "Low"), color: nunaChargeTextColor(v)) },
                sentence: nil, range: $range, page: $page)
                .columns(color: nunaChargeColor, top: 100)
                .withoutFigures()
                .windowFooter { AnyView(NunaChargeBreakdown(values: $0)) }
                .endingOn(daysAgo: router.todayDayOffset)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await series.load(repo: repo, key: "recovery", source: "my-whoop") }
    }
}
#endif
