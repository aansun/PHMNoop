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

/// The card under the ring: a soft gradient, lighter at the top and melting into the page toward the bottom, with a small notch at the top
/// pointing up to the ring it explains.
struct NunaSignalPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            NunaNotch().fill(NunaPalette.cardHighlight).frame(width: 24, height: 9)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 16)
                // Lighter at the top, and by the bottom the same as the screen behind it: no edge down there, the card fades into the page.
                .background(LinearGradient(colors: [NunaPalette.cardHighlight, NunaPalette.canvas], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [NunaPalette.hairline.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1))
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

/// Under a score's chart: how many of the days in the window fell in each band, as one bar split by days and a line for each band.
struct NunaDaysBreakdown: View {
    struct Band {
        let color: Color
        let name: LocalizedStringKey
        let range: String
        let contains: (Double) -> Bool
    }

    let title: LocalizedStringKey
    let bands: [Band]
    let values: [Double]

    private func days(_ band: Band) -> Int { values.filter(band.contains).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text("(days)").font(.nuna(size: 11, weight: .semibold)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
            }
            bar
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in line(band) }
            }
        }
        .padding(.top, 6)
    }

    /// One bar, split in the proportion of the days; the track alone when there are none.
    private var bar: some View {
        GeometryReader { g in
            let counts = bands.map { ($0.color, days($0)) }
            let total = max(1, counts.reduce(0) { $0 + $1.1 })
            let parts = counts.filter { $0.1 > 0 }
            let gap: CGFloat = 2
            let room = g.size.width - gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(part.0).frame(width: room * CGFloat(part.1) / CGFloat(total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NunaPalette.zoneBase.opacity(parts.isEmpty ? 1 : 0)))
        }
        .frame(height: 14)
    }

    private func line(_ band: Band) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(band.color).frame(width: 10, height: 10)
            Text(verbatim: "\(days(band))×").font(.nuna(size: 14.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 32, alignment: .leading)
            (Text(band.name) + Text(verbatim: " (\(band.range))")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 0)
        }
    }
}

extension NunaDaysBreakdown {
    /// Charge's three zones.
    static func charge(_ values: [Double]) -> NunaDaysBreakdown {
        NunaDaysBreakdown(title: "Charge breakdown", bands: [
            Band(color: NunaPalette.scoreHigh, name: "Ready", range: "67–100%") { $0 >= 67 },
            Band(color: NunaPalette.scoreMid, name: "Moderate", range: "34–66%") { $0 >= 34 && $0 < 67 },
            Band(color: NunaPalette.scoreLow, name: "Low", range: "0–33%") { $0 < 34 },
        ], values: values)
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
                .windowFooter { AnyView(NunaDaysBreakdown.charge($0)) }
                .endingOn(daysAgo: router.todayDayOffset)
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: repo.refreshSeq) { await series.load(repo: repo, key: "recovery", source: "my-whoop") }
    }
}

/// How a part of the night reads: poor, sufficient or optimal, drawn as three short bars with the one that applies lit.
enum NunaLevel: Int {
    case poor, sufficient, optimal

    var color: Color {
        switch self {
        case .poor: return NunaPalette.warning
        case .sufficient: return NunaPalette.textSecondary
        case .optimal: return NunaPalette.charge
        }
    }

    /// `edges` are where sufficient and optimal begin, on the part's own 0 to 100 scale.
    static func of(_ value: Double, sufficientFrom: Double, optimalFrom: Double) -> NunaLevel {
        value >= optimalFrom ? .optimal : (value >= sufficientFrom ? .sufficient : .poor)
    }
}

/// One part of the night under the ring: icon, UPPERCASE name, the three-bar level and the figure.
struct NunaLevelRow: View {
    let title: LocalizedStringKey
    let icon: String
    let percent: Double?
    let level: NunaLevel?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(level.map { $0.rawValue == i ? $0.color : NunaPalette.ink.opacity(0.14) } ?? NunaPalette.ink.opacity(0.14))
                        .frame(width: 14, height: 4)
                }
            }
            Text(verbatim: percent.map { String(format: "%.0f%%", locale: AppLanguage.activeLocale, $0) } ?? "–")
                .font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .frame(minWidth: 56, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

/// "Poor · Sufficient · Optimal": what the bars under the ring mean.
struct NunaLevelLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(NunaLevel.poor, "Poor"); item(NunaLevel.sufficient, "Sufficient"); item(NunaLevel.optimal, "Optimal")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private func item(_ level: NunaLevel, _ name: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(level.color).frame(width: 16, height: 4)
            Text(name).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
#endif
