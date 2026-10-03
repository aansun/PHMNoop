#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Score card (Charge / Effort / Rest)

struct NunaScoreCard: View {
    let charge: LiquidTodayView.ChargeDisplay
    let effort: Double?          // stored 0-100
    let rest: Double?            // 0-100
    let effortScale: EffortScale
    let readyLine: LocalizedStringKey?
    let heartRate: Int?

    var body: some View {
        NunaCard {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 0) {
                    ring(.charge)
                    ring(.effort)
                    ring(.rest)
                }
                HStack {
                    if let readyLine { NunaChip(readyLine, systemImage: "bolt.fill", color: NunaPalette.charge) }
                    Spacer(minLength: 8)
                    if let heartRate {
                        NavigationLink(value: TabRoute.fullDayChart) {
                            NunaChip(verbatim: "\(heartRate) bpm", systemImage: "heart.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private enum Kind { case charge, effort, rest }

    @ViewBuilder private func ring(_ kind: Kind) -> some View {
        let (fraction, color, textColor, value, label, state, route) = values(kind)
        NavigationLink(value: route) {
            VStack(spacing: 8) {
                NunaRingGauge(fraction: fraction, color: color, size: 98, lineWidth: 9) {
                    Text(verbatim: value)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(NunaPalette.textPrimary)
                        .minimumScaleFactor(0.6)
                }
                Text(label)
                    .font(.system(size: NunaTypeSize.caption, weight: .heavy))
                    .tracking(1.15).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(state)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(value == "–" ? NunaPalette.textMuted : textColor)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func values(_ kind: Kind) -> (Double, Color, Color, String, LocalizedStringKey, LocalizedStringKey, TabRoute) {
        switch kind {
        case .charge:
            let pct = charge.pct
            let state: LocalizedStringKey = pct.map { $0 >= 67 ? "Ready" : ($0 >= 34 ? "Moderate" : "Low") } ?? "No data"
            return ((pct ?? 0) / 100, NunaPalette.charge, NunaPalette.charge, pct.map { "\(Int($0.rounded()))%" } ?? "–",
                    "Charge", state, .metric(HeroRingMetric.charge))
        case .effort:
            let text = effort.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–"
            let state: LocalizedStringKey = effort.map { $0 < 33 ? "Light" : ($0 < 66 ? "Moderate" : "High") } ?? "No data"
            return ((effort ?? 0) / 100, NunaPalette.effort, NunaPalette.effortText, text, "Effort", state, .metric(HeroRingMetric.effort))
        case .rest:
            let state: LocalizedStringKey = rest.map { $0 >= 80 ? "Good" : ($0 >= 65 ? "Fair" : "Low") } ?? "No data"
            return ((rest ?? 0) / 100, NunaPalette.rest, NunaPalette.restText, rest.map { "\(Int($0.rounded()))%" } ?? "–",
                    "Rest", state, .metric(HeroRingMetric.rest))
        }
    }
}

// MARK: - Anya card

struct NunaAnyaCard: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NunaCard(small: true, highlight: true) {
                HStack(spacing: 12) {
                    NunaIconTile("sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anya")
                            .font(.system(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(NunaPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stress card

struct NunaStressCard: View {
    let stress: Double?     // 0-3

    var body: some View {
        NavigationLink(value: TabRoute.stress) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 10) {
                            NunaIconTile("wind", tint: NunaPalette.charge)
                            Text("Stress monitor").font(.system(size: 11.5, weight: .heavy)).tracking(1.15)
                                .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if let stress { NunaChip(level(stress).0, color: level(stress).1) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: stress.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                            .font(.system(size: NunaTypeSize.numberL, weight: .bold, design: .rounded))
                            .foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: "/ 3").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    scale
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func level(_ v: Double) -> (LocalizedStringKey, Color) {
        v < 1 ? ("Low", NunaPalette.charge) : (v < 2 ? ("Medium", NunaPalette.warning) : ("High", NunaPalette.alert))
    }

    private var scale: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    Capsule().fill(NunaPalette.charge.opacity(0.85))
                    Capsule().fill(NunaPalette.warning.opacity(0.85))
                    Capsule().fill(NunaPalette.alert.opacity(0.85))
                }
                .frame(height: 8)
                if let stress {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .offset(x: max(0, min(geo.size.width - 14, geo.size.width * min(stress, 3) / 3 - 7)))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Key metrics card

struct NunaMetricTile: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let route: TabRoute?
}

struct NunaMetricsGrid: View {
    let tiles: [NunaMetricTile]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(tiles) { tile in
                if let route = tile.route {
                    NavigationLink(value: route) { content(tile) }.buttonStyle(.plain)
                } else {
                    content(tile)
                }
            }
        }
    }

    private func content(_ tile: NunaMetricTile) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tile.label)
                    .font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: tile.value)
                        .font(.system(size: NunaTypeSize.numberM, weight: .bold, design: .rounded))
                        .foregroundStyle(NunaPalette.textPrimary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if !tile.unit.isEmpty {
                        Text(verbatim: tile.unit).font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Latest activity row

struct NunaActivityRow: View {
    let workout: WorkoutRow
    let effortScale: EffortScale

    var body: some View {
        NavigationLink(value: TabRoute.workouts) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("flame.fill", tint: NunaPalette.effortText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: WorkoutSource.displaySport(workout.sport))
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: detail)
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if let s = workout.strain {
                        NunaChip(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: effortScale), color: NunaPalette.effortText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var detail: String {
        var parts: [String] = []
        if let d = workout.durationS { parts.append("\(Int((d / 60).rounded())) min") }
        if let m = workout.distanceM, m > 0 { parts.append(String(format: "%.1f km", locale: AppLanguage.activeLocale, m / 1000)) }
        return parts.joined(separator: " · ")
    }
}
#endif
