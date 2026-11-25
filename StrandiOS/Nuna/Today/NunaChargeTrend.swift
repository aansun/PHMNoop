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
            NunaIcon(name: icon, size: 18, weight: .regular).foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
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

    /// WHP: the panel is the page lifted by white at 9% at its top and clear at its bottom (WHOOP sleep page: #262D2F fading to the page colour).
    private static var top: Color { NunaThemePrefs.skin == .whp ? Color.white.opacity(0.096) : NunaPalette.cardHighlight }
    private static var bottom: Color { NunaThemePrefs.skin == .whp ? Color.white.opacity(0) : NunaPalette.canvas }

    /// The panel's surface. In WHP it is lit from the top middle, as on the WHOOP pages: brightest at the centre of the top edge, dark at the left and right
    /// edges, and fading into the page by the bottom (white 9.6% at the centre top, 2% at the edges, about 1% at the foot, measured from the screenshots).
    @ViewBuilder private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
        if NunaThemePrefs.skin == .whp {
            shape.fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.096), location: 0), .init(color: Color.white.opacity(0.08), location: 0.3),
                                              .init(color: Color.white.opacity(0.03), location: 0.7), .init(color: Color.white.opacity(0.005), location: 1)],
                                      startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0), .init(color: .black.opacity(0.46), location: 0.17),
                                             .init(color: .black.opacity(0.83), location: 0.33), .init(color: .black, location: 0.5),
                                             .init(color: .black.opacity(0.83), location: 0.67), .init(color: .black.opacity(0.46), location: 0.83),
                                             .init(color: .black.opacity(0.2), location: 1)], startPoint: .leading, endPoint: .trailing))
        } else {
            shape.fill(LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NunaNotch().fill(Self.top).frame(width: 24, height: 9)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 16)
                // Lighter at the top, and by the bottom the same as the screen behind it: no edge down there, the card fades into the page.
                .background { surface }
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
    static var chargeBands: [Band] {
        [
            Band(color: NunaPalette.scoreHigh, name: "Ready", range: "67–100%") { $0 >= 67 },
            Band(color: NunaPalette.scoreMid, name: "Moderate", range: "34–66%") { $0 >= 34 && $0 < 67 },
            Band(color: NunaPalette.scoreLow, name: "Low", range: "0–33%") { $0 < 34 },
        ]
    }

    static func charge(_ values: [Double]) -> NunaDaysBreakdown {
        NunaDaysBreakdown(title: "Recovery breakdown", bands: chargeBands, values: values)
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
            NunaIcon(name: icon, size: 18, weight: .regular).foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
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

/// A row of the same panel for a figure that is not a percentage (a clock time, minutes): icon, UPPERCASE name, the three-bar level when there is one,
/// and the figure in the same size and weight as the percentages in `NunaLevelRow`.
struct NunaFigureRow: View {
    let title: LocalizedStringKey
    let icon: String
    let value: String
    var unit = ""
    var level: NunaLevel?

    var body: some View {
        HStack(spacing: 14) {
            NunaIcon(name: icon, size: 18, weight: .regular).foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
            Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 6)
            if let level {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(level.rawValue == i ? level.color : NunaPalette.ink.opacity(0.14)).frame(width: 14, height: 4)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            .frame(minWidth: 56, alignment: .trailing)
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
