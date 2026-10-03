#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Header with the white Anya button

struct NunaDetailHeader: View {
    let title: LocalizedStringKey
    var onAnya: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(NunaPalette.glassStrong, in: Circle())
                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }
            .accessibilityLabel(Text("Back"))
            Text(title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            if let onAnya {
                Button(action: onAnya) {
                    Image(systemName: "sparkles").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(NunaPalette.onAccent)
                        .frame(width: 44, height: 44).background(NunaPalette.textPrimary, in: Circle())
                }
                .accessibilityLabel(Text("Ask Anya"))
            }
        }
    }
}

/// Header + scroll + background for the Today detail screens.
struct NunaDetailScreen<Content: View>: View {
    let title: LocalizedStringKey
    var onAnya: (() -> Void)?
    let content: Content
    init(_ title: LocalizedStringKey, onAnya: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.onAnya = onAnya; self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaDetailHeader(title: title, onAnya: onAnya)
                content
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Hero card

struct NunaHeroCard<Footer: View>: View {
    let caption: LocalizedStringKey
    var chip: LocalizedStringKey?
    var chipColor: Color?
    let number: String
    var unit: String = ""
    var suffix: String = ""
    let color: Color
    let footer: Footer

    init(caption: LocalizedStringKey, chip: LocalizedStringKey? = nil, chipColor: Color? = nil, number: String,
         unit: String = "", suffix: String = "", color: Color, @ViewBuilder footer: () -> Footer) {
        self.caption = caption; self.chip = chip; self.chipColor = chipColor; self.number = number
        self.unit = unit; self.suffix = suffix; self.color = color; self.footer = footer()
    }

    var body: some View {
        NunaCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(caption).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let chip { NunaChip(chip, color: chipColor) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: number)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if !suffix.isEmpty {
                        Text(verbatim: suffix).font(.system(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                footer
            }
        }
    }
}

extension NunaHeroCard where Footer == EmptyView {
    init(caption: LocalizedStringKey, chip: LocalizedStringKey? = nil, chipColor: Color? = nil, number: String,
         unit: String = "", suffix: String = "", color: Color) {
        self.init(caption: caption, chip: chip, chipColor: chipColor, number: number, unit: unit, suffix: suffix,
                  color: color) { EmptyView() }
    }
}

// MARK: - Collapsible "How it's calculated" row

struct NunaExpandRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var systemImage = "sparkles"
    let text: LocalizedStringKey
    @State private var open = false

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(spacing: 12) {
                        NunaIconTile(systemImage)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(subtitle).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NunaPalette.textMuted).rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                if open {
                    Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Charts

/// Charge zone colour: green 67+, yellow 34 to 66, red 0 to 33.
func nunaChargeColor(_ v: Double) -> Color {
    v >= 67 ? NunaPalette.charge : (v >= 34 ? NunaPalette.warning : NunaPalette.alert)
}

/// Rounded vertical bars, one per slot, coloured by `color(value)`. Gaps draw as a faint stub.
struct NunaColorBars: View {
    let values: [Double?]
    let maxValue: Double
    let color: (Double) -> Color
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = values.count > 40 ? 2 : 5
            let w = min(28, max(2, (geo.size.width - gap * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1))))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(values.indices, id: \.self) { i in
                    if let v = values[i] {
                        RoundedRectangle(cornerRadius: min(5, w / 2), style: .continuous).fill(color(v))
                            .frame(width: w, height: max(6, height * CGFloat(min(max(v / maxValue, 0), 1))))
                    } else {
                        RoundedRectangle(cornerRadius: min(5, w / 2), style: .continuous).fill(Color.white.opacity(0.06))
                            .frame(width: w, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay {
                if values.allSatisfy({ $0 == nil }) {
                    Text("No data in this period").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
        .frame(height: height)
    }
}

/// Tall capsule columns with a fill and a label, as in the Effort and Steps mockups.
struct NunaColumns: View {
    struct Item: Identifiable { let id = UUID(); let label: String; let fraction: Double?; var highlight = false }
    let items: [Item]
    let color: Color
    var highlightColor: Color?

    var body: some View {
        HStack(alignment: .bottom) {
            ForEach(items) { item in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(width: 30, height: 110)
                        Capsule().fill(item.highlight ? (highlightColor ?? color) : color)
                            .frame(width: 30, height: max(14, 110 * CGFloat(min(max(item.fraction ?? 0, 0), 1))))
                            .opacity(item.fraction == nil ? 0 : 1)
                    }
                    Text(verbatim: item.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Smooth line over a soft "normal range" band, with a ring on the last point.
struct NunaBandLine: View {
    let values: [Double?]
    let color: Color
    var height: CGFloat = 130

    var body: some View {
        let present = values.compactMap { $0 }
        GeometryReader { geo in
            if present.count >= 2 {
                let mean = present.reduce(0, +) / Double(present.count)
                let sd = (present.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(present.count)).squareRoot()
                let lo = min(present.min()!, mean - sd) , hi = max(present.max()!, mean + sd)
                let pad = (hi - lo) * 0.12
                let span = max(hi - lo + 2 * pad, 0.0001)
                let y: (Double) -> CGFloat = { geo.size.height * CGFloat(1 - ($0 - (lo - pad)) / span) }
                let n = values.count
                let x: (Int) -> CGFloat = { n <= 1 ? 0 : geo.size.width * CGFloat($0) / CGFloat(n - 1) }
                let pts: [CGPoint] = values.enumerated().compactMap { i, v in v.map { CGPoint(x: x(i), y: y($0)) } }
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.12))
                        .frame(height: max(8, y(mean - sd) - y(mean + sd)))
                        .position(x: geo.size.width / 2, y: (y(mean - sd) + y(mean + sd)) / 2)
                    Path { p in
                        p.move(to: pts[0])
                        for i in 1..<pts.count {
                            let a = pts[i - 1], b = pts[i]
                            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                            p.addQuadCurve(to: mid, control: CGPoint(x: (a.x + mid.x) / 2 + 0.01, y: a.y))
                            p.addQuadCurve(to: b, control: CGPoint(x: (mid.x + b.x) / 2 - 0.01, y: b.y))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        Circle().strokeBorder(color, lineWidth: 3).background(Circle().fill(NunaPalette.card))
                            .frame(width: 11, height: 11).position(last)
                    }
                }
            } else {
                Text("Not enough data yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Series helper

/// One metric's daily values over the last `days` days (oldest first), nil where missing.
@MainActor
final class NunaSeriesModel: ObservableObject {
    @Published private(set) var byDay: [String: Double] = [:]
    @Published private(set) var loaded = false

    func load(repo: Repository, key: String, source: String) async {
        let s = await repo.exploreSeries(key: key, source: source, days: 130)
        byDay = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        loaded = true
    }

    /// Slots for the last `days` calendar days ending today.
    func window(_ days: Int) -> [(date: Date, value: Double?)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<days).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today) ?? today
            return (d, byDay[Repository.localDayKey(d)])
        }
    }

    var latest: (day: String, value: Double)? {
        guard let k = byDay.keys.sorted().last, let v = byDay[k] else { return nil }
        return (k, v)
    }

    /// Mean of the last 30 days that have a value, excluding the latest one.
    var baseline: Double? {
        let keys = byDay.keys.sorted().dropLast().suffix(30)
        let v = keys.compactMap { byDay[$0] }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}
#endif
