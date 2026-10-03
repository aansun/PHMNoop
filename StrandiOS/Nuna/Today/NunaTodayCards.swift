#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Section title row ("Metrik utama   Atur  Semua >")

struct NunaTitleRow<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: NunaTypeSize.h2, weight: .heavy, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 14) { trailing }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NunaPalette.textPrimary)
        }
        .padding(.horizontal, 2)
    }
}

/// Small "Semua >" style link label.
struct NunaLinkLabel: View {
    let text: LocalizedStringKey
    var systemImage: String?
    var chevron = false
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            Text(text)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)) }
        }
    }
}

// MARK: - Strap chip (watch, battery, percent)

struct NunaStrapChip: View {
    let connected: Bool
    let battery: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(connected ? NunaPalette.charge : NunaPalette.textMuted)
            if let battery {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(NunaPalette.textSecondary, lineWidth: 1.5)
                    .frame(width: 24, height: 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(battery < 20 ? NunaPalette.alertText : NunaPalette.charge)
                            .frame(width: max(2, 18 * CGFloat(min(max(battery, 0), 100) / 100)), height: 7)
                            .padding(.leading, 2.5)
                    }
                Text(verbatim: "\(Int(battery.rounded()))%").font(.system(size: 13, weight: .heavy))
            } else {
                Text(connected ? "Connected" : "Connect").font(.system(size: 13, weight: .heavy))
            }
        }
        .foregroundStyle(NunaPalette.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(NunaPalette.glassStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Score card (Charge / Effort / Rest)

struct NunaScoreCard: View {
    let charge: LiquidTodayView.ChargeDisplay
    let effort: Double?          // stored 0-100
    let rest: Double?            // 0-100
    let effortScale: EffortScale
    let readyLine: LocalizedStringKey?
    let heartRate: Int?

    var body: some View {
        NunaCard(padding: EdgeInsets(top: 22, leading: 12, bottom: 16, trailing: 12)) {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 0) {
                    ring(.charge)
                    ring(.effort)
                    ring(.rest)
                }
                if readyLine != nil || heartRate != nil {
                    HStack {
                        if let readyLine { NunaChip(readyLine, systemImage: "bolt.fill", color: NunaPalette.charge) }
                        Spacer(minLength: 8)
                        if let heartRate {
                            NavigationLink(value: TabRoute.fullDayChart) {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.alert)
                                    Text(verbatim: "\(heartRate) bpm").font(.system(size: 12.5, weight: .bold))
                                }
                                .foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(NunaPalette.glassStrong, in: Capsule())
                                .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private enum Kind { case charge, effort, rest }

    private struct RingValues {
        let fraction: Double
        let color: Color
        let textColor: Color
        let number: String
        let unit: String
        let label: LocalizedStringKey
        let state: LocalizedStringKey
        let route: String
    }

    @ViewBuilder private func ring(_ kind: Kind) -> some View {
        let v = values(kind)
        ringLink(v.route) {
            VStack(spacing: 8) {
                NunaRingGauge(fraction: v.fraction, color: v.color, size: 98, lineWidth: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: v.number)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(NunaPalette.textPrimary)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if !v.unit.isEmpty && v.number != "–" {
                            Text(verbatim: v.unit).font(.system(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                Text(v.label)
                    .font(.system(size: NunaTypeSize.caption, weight: .heavy))
                    .tracking(1.15).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(v.state)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(v.number == "–" ? NunaPalette.textMuted : v.textColor)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Charge and Effort open the Nuna metric screen; Rest opens the Nuna sleep screen.
    @ViewBuilder private func ringLink<C: View>(_ key: String, @ViewBuilder _ content: () -> C) -> some View {
        if key == HeroRingMetric.rest {
            NavigationLink(value: NunaTodayRoute.sleep(0)) { content() }.buttonStyle(.plain)
        } else if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { content() }.buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func values(_ kind: Kind) -> RingValues {
        switch kind {
        case .charge:
            let pct = charge.pct
            let state: LocalizedStringKey = pct.map { $0 >= 67 ? "Ready" : ($0 >= 34 ? "Moderate" : "Low") } ?? "No data"
            return RingValues(fraction: (pct ?? 0) / 100, color: NunaPalette.charge, textColor: NunaPalette.charge,
                              number: pct.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                              label: "Charge", state: state, route: HeroRingMetric.charge)
        case .effort:
            let text = effort.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–"
            let state: LocalizedStringKey = effort.map { $0 < 33 ? "Light" : ($0 < 66 ? "Moderate" : "High") } ?? "No data"
            return RingValues(fraction: (effort ?? 0) / 100, color: NunaPalette.effort, textColor: NunaPalette.effortText,
                              number: text, unit: "", label: "Effort", state: state, route: HeroRingMetric.effort)
        case .rest:
            let state: LocalizedStringKey = rest.map { $0 >= 80 ? "Good" : ($0 >= 65 ? "Fair" : "Low") } ?? "No data"
            return RingValues(fraction: (rest ?? 0) / 100, color: NunaPalette.rest, textColor: NunaPalette.restText,
                              number: rest.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                              label: "Rest", state: state, route: HeroRingMetric.rest)
        }
    }
}

// MARK: - Anya card

/// Highlighted Anya card: icon tile, caption, one-line advice and an optional white action button.
struct NunaAnyaCard: View {
    let title: Text
    var buttonTitle: LocalizedStringKey?
    var onButton: (() -> Void)?
    let action: () -> Void

    init(title: LocalizedStringKey, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.title = Text(title); self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    /// For text that is already localized (the readiness one-liner).
    init(verbatim: String, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.title = Text(verbatim: verbatim); self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    var body: some View {
        NunaCard(small: true, highlight: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            HStack(spacing: 12) {
                Button(action: action) {
                    HStack(spacing: 12) {
                        NunaIconTile("sparkles")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anya")
                                .font(.system(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary)
                            title
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(NunaPalette.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if buttonTitle == nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                if let buttonTitle, let onButton {
                    Button(action: onButton) { Text(buttonTitle) }
                        .buttonStyle(.nuna(.primary, height: 40))
                        .fixedSize()
                }
            }
        }
    }
}

// MARK: - Stress card (NOOP's own intraday curve, in a Nuna card)

struct NunaStressCard: View {
    let score: Double?                       // day score, 0-3
    let curve: DaytimeStress.Result?         // the day's hourly curve
    var isToday = true

    private var scored: [DaytimeStress.HourPoint] { curve?.hours.filter { $0.level != nil } ?? [] }
    private var latest: Double? { curve?.hours.last(where: { $0.level != nil })?.level }
    private var headline: Double? { score ?? latest }

    var body: some View {
        NavigationLink(value: stressRoute) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 10) {
                            NunaIconTile("wind", tint: NunaPalette.charge)
                            Text("Stress monitor").font(.system(size: 11.5, weight: .heavy)).tracking(1.15)
                                .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if let h = headline { NunaChip(level(h).0, color: level(h).1) }
                    }
                    HStack(alignment: .lastTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: headline.map { format($0) } ?? "–")
                                .font(.system(size: NunaTypeSize.numberL, weight: .bold, design: .rounded))
                                .foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: "/ 3").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if let latest, isToday {
                            Text(verbatim: String(localized: "Now \(format(latest)) · \(wording(latest))"))
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    if let curve, !scored.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .trailing, spacing: 0) {
                                ForEach([3, 2, 1, 0], id: \.self) { tick in
                                    Text(verbatim: "\(tick)").font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                                    if tick > 0 { Spacer(minLength: 0) }
                                }
                            }
                            .frame(width: 14, height: 78)
                            // The same drawing the Default Today screen and the widget use.
                            DaytimeLoadLine(hours: curve.hours).frame(height: 78)
                        }
                        axis
                        if let peak = curve.peak, let level = peak.level {
                            Text(verbatim: String(localized: "Peak \(format(level)) · \(clock(peak.startTs))"))
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(NunaPalette.warning.opacity(0.18), in: Capsule())
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var axis: some View {
        HStack {
            if let first = scored.first { Text(verbatim: clock(first.startTs)) }
            Spacer()
            if let last = scored.last, last.startTs != scored.first?.startTs {
                if isToday { Text("Now") } else { Text(verbatim: clock(last.startTs)) }
            }
        }
        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        .padding(.leading, 22)
    }

    private func clock(_ ts: Int) -> String { NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(ts))) }

    private func format(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }

    private func wording(_ v: Double) -> String {
        v < 1 ? String(localized: "calm") : (v < 2 ? String(localized: "moderate") : String(localized: "high"))
    }

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private func level(_ v: Double) -> (LocalizedStringKey, Color) {
        v < 1 ? ("Low", NunaPalette.charge) : (v < 2 ? ("Medium", NunaPalette.warning) : ("High", NunaPalette.alert))
    }
}

// MARK: - Key metrics

struct NunaMetricTile: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let route: NunaTodayRoute?
    /// "▲ 4" style change against the previous day, and whether the change is good (nil = neutral).
    var delta: String?
    var deltaGood: Bool?
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
        NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(tile.label)
                        .font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let delta = tile.delta {
                        let tint: Color = tile.deltaGood == nil ? NunaPalette.textSecondary
                            : (tile.deltaGood! ? NunaPalette.charge : NunaPalette.warning)
                        Text(verbatim: delta)
                            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(tint)
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(NunaPalette.tint(tint), in: Capsule())
                            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: tile.value)
                        .font(.system(size: NunaTypeSize.numberM, weight: .bold, design: .rounded))
                        .foregroundStyle(NunaPalette.textPrimary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if !tile.unit.isEmpty && tile.value != "–" {
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
            NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                HStack(spacing: 12) {
                    NunaIconTile("flame", tint: NunaPalette.effortText)
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
        if let m = workout.distanceM, m > 0 { parts.append(String(format: "%.1f km", locale: AppLanguage.activeLocale, m / 1000)) }
        if let d = workout.durationS { parts.append(String(localized: "\(Int((d / 60).rounded())) min")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Quick log chips (water, journal, mood)

struct NunaQuickChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .bold)).foregroundStyle(tint ?? NunaPalette.textPrimary)
                Text(title).font(.system(size: 13.5, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 16).frame(height: 40)
            .background(NunaPalette.glassStrong, in: Capsule())
            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
#endif
