#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Stage colours (tokens only)

extension SleepStage {
    var nunaColor: Color {
        switch self {
        case .awake: return NunaPalette.zoneBase
        case .rem:   return NunaPalette.restLight
        case .light: return NunaPalette.rest
        case .deep:  return NunaPalette.restDeep
        }
    }
    var nunaName: LocalizedStringKey {
        switch self {
        case .awake: return "Awake"
        case .rem:   return "REM"
        case .light: return "Light"
        case .deep:  return "Deep"
        }
    }
}

// MARK: - Hypnogram strip

/// Four lanes (awake, REM, light, deep from top) with one block per interval. Plain Canvas: no hover,
/// no animation, so it stays cheap inside a scroll view.
struct NunaHypnogramStrip: View {
    let intervals: [SleepInterval]
    var height: CGFloat = 96

    private static let lanes: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        let total = max(intervals.map(\.end).max() ?? 1, 1)
        Canvas { ctx, size in
            let laneH = size.height / CGFloat(Self.lanes.count)
            for (i, lane) in Self.lanes.enumerated() {
                let band = CGRect(x: 0, y: CGFloat(i) * laneH + 2, width: size.width, height: laneH - 4)
                ctx.fill(Path(roundedRect: band, cornerRadius: 4), with: .color(NunaPalette.ink.opacity(0.04)))
                for iv in intervals where iv.stage == lane {
                    let x = size.width * CGFloat(iv.start / total)
                    let w = max(2, size.width * CGFloat((iv.end - iv.start) / total))
                    let r = CGRect(x: x, y: band.minY, width: w, height: band.height)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(lane.nunaColor))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Movement ticks under the hypnogram, on the same time axis. Tick height follows magnitude (square-root
/// scaled so small movements still show); strong bursts are drawn brighter.
struct NunaMotionStrip: View {
    let epochs: [NunaMotionEpoch]
    let total: TimeInterval
    var height: CGFloat = 34

    var body: some View {
        let peak = max(epochs.map(\.v).max() ?? 1, 1)
        Canvas { ctx, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5)); base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(base, with: .color(NunaPalette.ink.opacity(0.12)), lineWidth: 1)
            for e in epochs where e.v > NunaMovementSummary.moveThreshold {
                let x = size.width * CGFloat(min(max(e.t / max(total, 1), 0), 1))
                let h = max(3, (size.height - 2) * CGFloat((e.v / peak).squareRoot()))
                let strong = e.v > NunaMovementSummary.positionPeak
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height - 1)); p.addLine(to: CGPoint(x: x, y: size.height - 1 - h))
                ctx.stroke(p, with: .color(NunaPalette.textSecondary.opacity(strong ? 1 : 0.6)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Movement, position changes and restlessness for the night.
struct NunaMovementStats: View {
    let night: NunaNight
    var body: some View {
        if let m = NunaMovementSummary(night.motion, hours: max(night.inBedMin / 60, 0.1)) {
            HStack(alignment: .top, spacing: 8) {
                cell("Movement", "\(m.movements)", "×")
                cell("Position changes", "\(m.positionChanges)", "×")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restlessness").font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(m.level == .low ? "Low" : (m.level == .medium ? "Medium" : "High"))
                        .font(.nuna(size: 21, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(NunaPalette.hairline).frame(height: 1) }
        }
    }

    private func cell(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value).font(.nuna(size: 21, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One stacked bar of the stage split (the fallback when there is no timeline).
struct NunaStageSplitBar: View {
    let stages: Stages
    var body: some View {
        GeometryReader { geo in
            let parts: [(SleepStage, Double)] = [(.deep, stages.deep), (.rem, stages.rem),
                                                              (.light, stages.light), (.awake, stages.awake)]
            let total = max(parts.map(\.1).reduce(0, +), 1)
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    if parts[i].1 > 0 {
                        Capsule().fill(parts[i].0.nunaColor)
                            .frame(width: max(4, geo.size.width * CGFloat(parts[i].1 / total) - 2))
                    }
                }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

struct NunaStageLegend: View {
    var showsMovement = false
    var body: some View {
        HStack(spacing: 14) {
            ForEach([SleepStage.awake, .rem, .light, .deep], id: \.self) { s in
                HStack(spacing: 6) {
                    Circle().fill(s.nunaColor).frame(width: 9, height: 9)
                    Text(s.nunaName).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            if showsMovement {
                HStack(spacing: 6) {
                    Capsule().fill(NunaPalette.textSecondary).frame(width: 3, height: 12)
                    Text("Movement").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Start / middle / end clock labels under a timeline.
struct NunaTimeAxis: View {
    let start: Date
    let end: Date
    var body: some View {
        HStack {
            Text(verbatim: NunaSleepFormat.clock(start))
            Spacer()
            Text(verbatim: NunaSleepFormat.clock(Date(timeIntervalSince1970: (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2)))
            Spacer()
            Text(verbatim: NunaSleepFormat.clock(end))
        }
        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
    }
}

// MARK: - Small shared pieces

struct NunaProgressBar: View {
    let fraction: Double
    var color: Color = NunaPalette.rest
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.ink.opacity(0.09))
                Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A bar from `lo` to `hi` with a marker for the current value and a tick for the average. Everything on it
/// is a stored reading or an average of stored readings.
struct NunaRangeBar: View {
    let value: Double?
    let lo: Double
    let hi: Double
    var mean: Double?
    var color: Color = NunaPalette.rest
    var showsMarkerDot = true

    var body: some View {
        GeometryReader { geo in
            let span = max(hi - lo, 0.0001)
            let x: (Double) -> CGFloat = { geo.size.width * CGFloat(min(max(($0 - lo) / span, 0), 1)) }
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.ink.opacity(0.09))
                if let value, !showsMarkerDot { Capsule().fill(color).frame(width: max(6, x(value))) }
                if let mean { Rectangle().fill(NunaPalette.ink.opacity(0.7)).frame(width: 2, height: 16).offset(x: x(mean) - 1) }
                if let value, showsMarkerDot {
                    Circle().fill(NunaPalette.ink).frame(width: 14, height: 14).offset(x: min(max(x(value) - 7, 0), geo.size.width - 14))
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

struct NunaStatTile: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var fraction: Double?
    var color: Color = NunaPalette.rest
    var caption: LocalizedStringKey?
    var body: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let fraction { NunaProgressBar(fraction: fraction, color: color) }
                if let caption {
                    Text(caption).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Last night" style picker: older / newer chevrons around a title.
struct NunaNightPicker: View {
    @ObservedObject var model: NunaSleepModel
    var caption: LocalizedStringKey?
    var date: Date?
    var body: some View {
        HStack {
            step("chevron.left", enabled: model.hasOlder) { model.index += 1 }
            Spacer()
            VStack(spacing: 2) {
                Text(caption ?? (model.index == 0 ? "Last night" : "Earlier night"))
                    .font(.nuna(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: (date ?? model.night?.wakeDate).map { NunaSleepFormat.nightTitle($0) } ?? "–")
                    .font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
            Spacer()
            step("chevron.right", enabled: model.hasNewer) { model.index -= 1 }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 15, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 44, height: 44).background(NunaPalette.ink.opacity(0.08), in: Circle())
        }
        .disabled(!enabled)
    }
}

/// Header + scroll + background shared by the sleep screens.
struct NunaScreen<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaHeader(title, onBack: { dismiss() })
                content
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
#endif
