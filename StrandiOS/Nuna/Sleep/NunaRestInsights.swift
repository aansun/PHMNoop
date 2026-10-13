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

/// The card caption, the figure with its move against the usual, and a small line under it.
private struct NunaRestFigure: View {
    let title: LocalizedStringKey
    let value: Double?
    let usual: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.nuna(size: 36, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(36)).foregroundStyle(NunaPalette.textPrimary)
                if let value, let usual, abs(value - usual) >= 0.5 {
                    Image(systemName: value > usual ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.nuna(size: 11, weight: .bold)).foregroundStyle(value > usual ? NunaPalette.charge : NunaPalette.warning)
                }
            }
            if let usual {
                Text(verbatim: String(localized: "14-night average \(Int(usual.rounded()))%")).font(.nuna(size: 12, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
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
            VStack(alignment: .leading, spacing: 14) {
                NunaRestFigure(title: "Hours vs. needed", value: percent, usual: usual)
                VStack(alignment: .leading, spacing: 8) {
                    line("Hours of sleep", hm(asleepMin))
                    bar(fraction: asleepMin / top) {
                        Capsule().fill(LinearGradient(colors: [NunaPalette.rest.opacity(0.25), NunaPalette.rest], startPoint: .leading, endPoint: .trailing))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    line("Sleep needed", hm(neededMin))
                    GeometryReader { geo in
                        let w = geo.size.width * CGFloat(min(neededMin / top, 1))
                        let parts: [(Double, Color)] = [(healthyMin, NunaPalette.zoneBase), (strainMin, NunaPalette.effortModerate), (debtMin, NunaPalette.textPrimary)]
                        let total = max(parts.reduce(0) { $0 + $1.0 }, 1)
                        HStack(spacing: 2) {
                            ForEach(parts.indices, id: \.self) { i in
                                if parts[i].0 > 0 { Rectangle().fill(parts[i].1).frame(width: max(3, w * CGFloat(parts[i].0 / total))) }
                            }
                        }
                        .clipShape(Capsule())
                        .frame(width: w, alignment: .leading)
                    }
                    .frame(height: 14)
                }
                NunaDivider()
                VStack(spacing: 10) {
                    legend("Healthy minimum", NunaPalette.zoneBase, hm(healthyMin))
                    legend("Recent strain", NunaPalette.effortModerate, "+" + hm(strainMin))
                    legend("Sleep debt", NunaPalette.textPrimary, "+" + hm(debtMin))
                }
            }
        }
    }

    private func line(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func bar<Fill: View>(fraction: Double, @ViewBuilder _ fill: () -> Fill) -> some View {
        let content = fill()
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.glassStrong)
                content.frame(width: max(8, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 14)
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(title).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
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
                    .foregroundStyle(n.selected ? NunaPalette.rest : NunaPalette.textMuted.opacity(0.55)).cornerRadius(3)
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
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaPalette.textPrimary).frame(width: 12, height: 12)
                    Text("Wake events").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(events.count)").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
        }
    }

    private func line(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func x(_ t: TimeInterval, _ w: CGFloat) -> CGFloat { totalSec > 0 ? w * CGFloat(min(max(t / totalSec, 0), 1)) : 0 }

    /// The night as one bar, cut at each wake event.
    private var asleepBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.rest)
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
                    Rectangle().fill(NunaPalette.textPrimary).frame(width: max(3, x(events[i].end - events[i].start, geo.size.width)), height: 14)
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
