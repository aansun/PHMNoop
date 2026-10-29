#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

// The detail cards of the Rest screen: hours against need, bedtime consistency over the last nights, and efficiency with the wake events.
// Display only. The figures are the ones the other sleep screens read from `NunaSleepModel`; nothing here is scored again.

/// Whether naps the strap finds are listed. Naps added by hand are always listed.
enum NunaNapPrefs {
    static let autoDetectKey = "nuna.sleep.autoDetectNaps"
    static var autoDetect: Bool { UserDefaults.standard.object(forKey: autoDetectKey) as? Bool ?? true }
}

private func hm(_ minutes: Double) -> String {
    let m = max(0, Int(minutes.rounded()))
    return String(format: "%d:%02d", m / 60, m % 60)
}

private func clockText(_ hour: Double) -> String {
    let h = hour.truncatingRemainder(dividingBy: 24)
    let wrapped = h < 0 ? h + 24 : h
    let total = Int((wrapped * 60).rounded()) % (24 * 60)
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// The card caption, the figure with a small triangle against the usual, and that usual underneath.
private struct NunaRestFigure: View {
    let title: LocalizedStringKey
    let value: Double?
    let usual: Double?

    var body: some View {
        let trend = NunaTrend.make(current: value, previous: usual, decimals: 0, upIsGood: true, format: { "\(Int($0.rounded()))%" })
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: value.map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(.nuna(size: 28, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if let trend, trend.direction != 0 {
                        Image(systemName: trend.direction > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(trend.tint)
                    }
                }
                if let trend {
                    Text(verbatim: trend.previous).font(.nuna(size: 12.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }
}

/// A small notch on the top edge of a panel, pointing up at the bar it explains.
private struct NunaPanelNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Hours vs needed

struct NunaHoursVsNeededCard: View {
    let asleepMin: Double
    /// What the night had to be: the healthy minimum plus recent strain plus sleep debt.
    let healthyMin: Double
    let strainMin: Double
    let debtMin: Double
    let percent: Double?
    let usual: Double?

    private var neededMin: Double { healthyMin + strainMin + debtMin }

    var body: some View {
        let top = max(asleepMin, neededMin, 1)
        NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                NunaRestFigure(title: "Hours vs. needed", value: percent, usual: usual)
                VStack(alignment: .leading, spacing: 8) {
                    line("Hours of sleep", NunaRestChart.hm(asleepMin))
                    GeometryReader { geo in
                        let w = geo.size.width * CGFloat(min(asleepMin / top, 1))
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: [NunaRestChart.steel.opacity(0.05), NunaRestChart.steel], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, w)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 20)
                }
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        let w = geo.size.width * CGFloat(min(neededMin / top, 1))
                        let parts: [(Double, AnyShapeStyle)] = [
                            (healthyMin, AnyShapeStyle(LinearGradient(colors: [NunaPalette.zoneBase.opacity(0.35), Color(hex: "#6B727B")], startPoint: .leading, endPoint: .trailing))),
                            (strainMin, AnyShapeStyle(NunaRestChart.strain)), (debtMin, AnyShapeStyle(NunaRestChart.paleGrey)),
                        ]
                        let total = max(parts.reduce(0) { $0 + $1.0 }, 1)
                        HStack(spacing: 0) {
                            ForEach(parts.indices, id: \.self) { i in
                                if parts[i].0 > 0 { Rectangle().fill(parts[i].1).frame(width: max(3, w * CGFloat(parts[i].0 / total))) }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .frame(width: w, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 20)
                    line("Sleep needed", NunaRestChart.hm(neededMin))
                }
                VStack(spacing: 0) {
                    HStack { Spacer(); NunaPanelNotch().fill(NunaPalette.field).frame(width: 22, height: 8).padding(.trailing, 24) }
                    VStack(spacing: 14) {
                        legend("Healthy minimum", NunaPalette.zoneBase, NunaRestChart.hm(healthyMin))
                        legend("Recent strain", NunaRestChart.strain, "+" + NunaRestChart.hm(strainMin))
                        legend("Sleep debt", NunaRestChart.paleGrey, "+" + NunaRestChart.hm(debtMin))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                }
            }
        }
    }

    private func line(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 17, weight: .semibold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 18, height: 18)
            Text(title).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 14, weight: .semibold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
        }
    }
}

// MARK: - Consistency

struct NunaConsistencyCard: View {
    struct Night: Identifiable {
        let id: String
        let label: String
        /// Hours counted from midnight of the evening it began (a bedtime after midnight is 24 and more).
        let bed: Double
        let wake: Double
        /// The bed and wake time your recent nights point to, for this night.
        let idealBed: Double
        let idealWake: Double
        let selected: Bool
    }

    let nights: [Night]
    let percent: Double?
    let usual: Double?

    /// 21:00 down to 13:00 the next day, widened when a night falls outside it, in whole four-hour steps.
    private var span: (lo: Double, hi: Double) {
        let lo = min(21, floor(nights.map { min($0.bed, $0.idealBed) }.min() ?? 21))
        var hi = max(37, ceil(nights.map { max($0.wake, $0.idealWake) }.max() ?? 37))
        hi = lo + ceil((hi - lo) / 4) * 4
        return (lo, hi)
    }

    /// Time runs downwards: an earlier hour sits higher.
    private func y(_ hour: Double, _ s: (lo: Double, hi: Double)) -> Double { s.hi + s.lo - hour }

    var body: some View {
        let s = span
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NunaRestFigure(title: "Sleep consistency", value: percent, usual: usual)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Rectangle().fill(.clear).frame(width: 22, height: 2).overlay {
                        Rectangle().stroke(NunaPalette.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    Text("Optimal bed/wake time").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                }
                if nights.isEmpty {
                    Text("Not enough nights yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160).textCase(nil)
                } else {
                    chart(s)
                }
            }
        }
    }

    private func chart(_ s: (lo: Double, hi: Double)) -> some View {
        Chart {
            ForEach(nights) { n in
                BarMark(x: .value("Night", n.id), yStart: .value("Bed", y(n.bed, s)), yEnd: .value("Wake", y(n.wake, s)), width: .fixed(16))
                    .foregroundStyle(n.selected ? NunaRestChart.steel : NunaPalette.textMuted.opacity(0.5)).cornerRadius(3)
                LineMark(x: .value("Night", n.id), y: .value("Ideal bed", y(n.idealBed, s)), series: .value("Line", "bed"))
                    .foregroundStyle(NunaPalette.textSecondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3])).interpolationMethod(.catmullRom)
                LineMark(x: .value("Night", n.id), y: .value("Ideal wake", y(n.idealWake, s)), series: .value("Line", "wake"))
                    .foregroundStyle(NunaPalette.textSecondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3])).interpolationMethod(.catmullRom)
                if n.selected {
                    PointMark(x: .value("Night", n.id), y: .value("Bed", y(n.bed, s)))
                        .opacity(0).annotation(position: .top, spacing: 2) { tag(clockText(n.bed)) }
                    PointMark(x: .value("Night", n.id), y: .value("Wake", y(n.wake, s)))
                        .opacity(0).annotation(position: .bottom, spacing: 2) { tag(clockText(n.wake)) }
                }
            }
        }
        .chartYScale(domain: s.lo...s.hi)
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: s.lo, through: s.hi, by: 4).map { $0 }) { value in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(verbatim: clockText(s.hi + s.lo - v)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: nights.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let n = nights.first(where: { $0.id == id }) {
                        Text(verbatim: n.label).font(.nuna(size: 11.5, weight: n.selected ? .bold : .semibold))
                            .foregroundStyle(n.selected ? NunaPalette.textPrimary : NunaPalette.textMuted)
                    }
                }
            }
        }
        .frame(height: 240)
        .accessibilityLabel(Text("Bed and wake times"))
    }

    private func tag(_ text: String) -> some View {
        Text(verbatim: text).font(.nuna(size: 11.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
    }
}

// MARK: - Efficiency

struct NunaEfficiencyCard: View {
    let asleepMin: Double
    let awakeMin: Double
    /// Awake stretches as (start, end) in seconds from onset, within `totalSec`.
    let events: [(start: TimeInterval, end: TimeInterval)]
    let totalSec: TimeInterval
    let percent: Double?
    let usual: Double?

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                NunaRestFigure(title: "Sleep efficiency", value: percent, usual: usual)
                VStack(alignment: .leading, spacing: 8) {
                    line("Asleep", hm(asleepMin))
                    asleepBar
                }
                VStack(alignment: .leading, spacing: 8) {
                    awakeBar
                    line("Awake", hm(awakeMin))
                }
                NunaDivider()
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaRestChart.paleGrey).frame(width: 18, height: 18)
                    Text("Wake events").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(events.count)").font(.nuna(size: 20, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
        }
    }

    private func line(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 17, weight: .semibold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func x(_ t: TimeInterval, _ w: CGFloat) -> CGFloat { totalSec > 0 ? w * CGFloat(min(max(t / totalSec, 0), 1)) : 0 }

    /// The night as one bar, cut at each wake event.
    private var asleepBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NunaRestChart.steel)
                ForEach(events.indices, id: \.self) { i in
                    Rectangle().fill(NunaPalette.card).frame(width: max(2, x(events[i].end - events[i].start, geo.size.width)))
                        .offset(x: x(events[i].start, geo.size.width))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 16)
    }

    /// The same night in hatching, with a mark where each wake event was.
    private var awakeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    var path = Path()
                    var xPos: CGFloat = -size.height
                    while xPos < size.width {
                        path.move(to: CGPoint(x: xPos, y: size.height)); path.addLine(to: CGPoint(x: xPos + size.height, y: 0))
                        xPos += 6
                    }
                    ctx.stroke(path, with: .color(NunaPalette.textMuted.opacity(0.45)), lineWidth: 1.2)
                }
                .clipShape(Capsule())
                ForEach(events.indices, id: \.self) { i in
                    Rectangle().fill(NunaRestChart.paleGrey).frame(width: max(3, x(events[i].end - events[i].start, geo.size.width)), height: 14)
                        .offset(x: x(events[i].start, geo.size.width))
                }
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Settings

/// What the Rest screen's top-right button opens: the smart alarm, the bedtime reminder and whether naps are found on their own.
struct NunaSleepSettingsView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(NunaNapPrefs.autoDetectKey) private var autoNaps = true

    var body: some View {
        NunaDetailScreen("Sleep settings") {
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaTodayRoute.smartAlarm) {
                        NunaListRow("Smart alarm", subtitle: behavior.smartAlarmEnabled ? "On" : "Off", systemImage: "alarm", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.windDown) {
                        NunaListRow("Bedtime reminder", subtitle: "A nudge before your usual bedtime", systemImage: "moon.stars", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NunaToggleRow("Detect naps automatically", subtitle: "Naps found from your strap are listed. Naps you add yourself always are.",
                                  systemImage: "moon.zzz", isOn: $autoNaps).padding(.vertical, 8)
                }
            }
            Text("Turning nap detection off only changes what is listed. Your strap keeps recording as before.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
    }
}
#endif
