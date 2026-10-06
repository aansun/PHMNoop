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
                .font(.nuna(size: 17, weight: .heavy, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 14) { trailing }
                .font(.nuna(size: 14, weight: .bold))
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
            if let systemImage { Image(systemName: systemImage).font(.nuna(size: 12, weight: .bold)) }
            Text(text)
            if chevron { Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .heavy)) }
        }
    }
}

// MARK: - Strap chip (watch, battery, percent)

struct NunaStrapChip: View {
    let connected: Bool
    let battery: Double?

    var body: some View {
        HStack(spacing: 6) {
            if let battery {
                Text(verbatim: "\(Int(battery.rounded()))%").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            Image(systemName: "applewatch").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(connected ? NunaPalette.charge : NunaPalette.textMuted).frame(width: 7, height: 7).offset(x: 2, y: -1)
                }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Score card (Charge / Effort / Rest)

/// The three daily scores, drawn straight on the screen (no card) and pinned to the top of Today. `collapse` runs from 0 (full
/// size: big rings with their name and state under them) to 1 (small rings with the name beside them), driven by how far the page
/// has scrolled, so the rings stay in view and shrink instead of scrolling away.
struct NunaScoreRings: View {
    let charge: LiquidTodayView.ChargeDisplay
    let effort: Double?          // stored 0-100
    let rest: Double?            // 0-100
    let effortScale: EffortScale
    var collapse: CGFloat = 0

    static let fullHeight: CGFloat = 168
    static let compactHeight: CGFloat = 36

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * min(max(collapse, 0), 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.charge); item(.effort); item(.rest)
        }
        .frame(height: lerp(Self.fullHeight, Self.compactHeight), alignment: .top)
        .clipped()
    }

    @ViewBuilder private func item(_ kind: Kind) -> some View {
        let v = values(kind)
        let size = lerp(112, 26)
        ringLink(v.route) {
            Group {
                if collapse < 0.55 {
                    VStack(spacing: 8) {
                        ringView(v, size: size)
                        Text(v.label).font(.nuna(size: NunaTypeSize.caption, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text(v.state).font(.nuna(size: 13, weight: .heavy))
                            .foregroundStyle(v.number == "–" ? NunaPalette.textMuted : v.textColor)
                            .opacity(Double(1 - collapse * 2.2))
                    }
                } else {
                    HStack(spacing: 8) {
                        ringView(v, size: size)
                        Text(v.label).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func ringView(_ v: RingValues, size: CGFloat) -> some View {
        NunaRingGauge(fraction: v.fraction, color: v.color, size: size, lineWidth: max(3.5, size * 0.09)) {
            if size >= 60 {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: v.number).font(.nuna(size: size * 0.27, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(size * 0.27)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !v.unit.isEmpty && v.number != "–" {
                        Text(verbatim: v.unit).font(.nuna(size: size * 0.13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
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

private struct NunaAnyaCardContextKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// The Anya context of the screen. When it is set, a card that carries its own line (a verdict, a zone read, a record) opens the
    /// Anya sheet about that very line instead of the screen's general read, so what is tapped and what opens always agree.
    var nunaAnyaCardContext: String? {
        get { self[NunaAnyaCardContextKey.self] }
        set { self[NunaAnyaCardContextKey.self] = newValue }
    }
}

/// Highlighted Anya card: icon tile, caption, one-line advice and an optional white action button.
struct NunaAnyaCard: View {
    let title: Text
    var buttonTitle: LocalizedStringKey?
    var onButton: (() -> Void)?
    var highlight = true
    /// A second line under the title, and a thin bar (0 to 1) under that, for cards that report progress.
    var detail: String?
    var progress: Double?
    var progressColor: Color = NunaPalette.effort
    let action: () -> Void
    /// The line itself, when it is already text; with a screen context it is what the sheet opens on.
    private var line: String?
    @Environment(\.nunaAnyaCardContext) private var sheetContext
    @State private var showSheet = false

    init(title: LocalizedStringKey, highlight: Bool = true, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.title = Text(title); self.highlight = highlight; self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    /// For text that is already localized (the readiness one-liner).
    init(verbatim: String, detail: String? = nil, progress: Double? = nil, progressColor: Color = NunaPalette.effort, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.title = Text(verbatim: verbatim); self.line = verbatim; self.detail = detail; self.progress = progress; self.progressColor = progressColor
        self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    /// "Suggestion cards on each screen" in Anya settings.
    @AppStorage(NunaAnyaPrefs.cardsKey) private var cardsOn = true

    var body: some View {
        if cardsOn {
            content.sheet(isPresented: $showSheet) {
                if let ctx = sheetContext, let line { NunaAnyaSheet(context: ctx, cardLine: .init(headline: line, detail: detail, read: NunaAnyaCardLine.signals(ctx))) }
            }
        }
    }

    /// A card with its own line opens the sheet about it; the others keep the screen's action.
    private func tapped() {
        if sheetContext != nil, line != nil { showSheet = true } else { action() }
    }

    @ViewBuilder private var content: some View {
        if let buttonTitle, let onButton { stacked(buttonTitle, onButton) } else { inline }
    }

    private var label: some View {
        Text("Anya")
            .font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(NunaThemePrefs.skin == .whp ? nil : .uppercase)
            .foregroundStyle(NunaPalette.textSecondary)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.nuna(size: 16, weight: .bold))
                .foregroundStyle(NunaPalette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true).textCase(nil)
            if let detail {
                Text(verbatim: detail).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.top, 2)
            }
            if let progress {
                NunaProgressBar(fraction: min(max(progress, 0), 1), color: progressColor).frame(height: 6).padding(.top, 6)
            }
        }
    }

    /// No button: the icon, the words and a chevron in one row, the whole card opens Anya.
    private var inline: some View {
        NunaCard(small: true, highlight: highlight, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            Button(action: tapped) {
                HStack(spacing: 12) {
                    AnyaIconTile()
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        body_
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// With an action: the icon and "Anya" on top, the words across the full width under them, and a small translucent button under that, on the left.
    private func stacked(_ buttonTitle: LocalizedStringKey, _ onButton: @escaping () -> Void) -> some View {
        NunaCard(small: true, highlight: highlight, padding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: tapped) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            AnyaIconTile()
                            label
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        body_.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                Button(action: onButton) {
                    Text(buttonTitle).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 22).frame(height: 40)
                        .background(NunaPalette.textPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Stress card (NOOP's own intraday curve, in a Nuna card)

/// Today's high stress as a time, the comparison with a typical day of the week, and the day's curve with a marker on the latest reading.
struct NunaStressCard: View {
    let score: Double?                       // day score, 0-3
    let curve: DaytimeStress.Result?         // the day's curve
    var baseline: Double?                    // the wearer's usual stress, 0-3
    var isToday = true

    private var scored: Bool { curve?.hours.contains { $0.level != nil } ?? false }
    private var highMin: Int? { scored ? curve.map(StressDayCurve.highMinutes) : nil }
    /// The big number: the average over the latest hour (today) or over the day, never above the scale's 3.
    private var level: Double? { curve.flatMap { StressDayCurve.headlineLevel($0, isToday: isToday) } ?? score.map { min(max($0, 0), 3) } }
    /// "Last hour" only when the figure really is the latest reading on the curve; the day-level score that stands in when nothing has been
    /// read yet is a day figure, and says so.
    private var isLastHour: Bool { isToday && curve.flatMap(StressDayCurve.latestLevel) != nil }

    var body: some View {
        NavigationLink(value: stressRoute) {
            NunaCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Stress monitor").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel)
                            .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Spacer(minLength: 8)
                        if let highMin {
                            Text(verbatim: String(format: String(localized: "High %@ hrs"), StressTrace.clock(minutes: highMin)))
                                .font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isLastHour ? "Last hour average" : "Day average").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel)
                                .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(verbatim: level.map(Self.format) ?? "–")
                                    .font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(NunaTypeSize.numberL))
                                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
                                if level != nil { Text(verbatim: "/ 3").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                            }
                            comparison
                        }
                        .frame(width: 160, alignment: .leading)
                        NunaStressDayChart(points: curve?.timeline ?? [], showsValue: isToday).frame(height: 116)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    static func format(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }

    /// The arrow against the wearer's own baseline: below it is the good way (green), above it is not (amber).
    @ViewBuilder private var comparison: some View {
        if let level, let baseline {
            let diff = level - baseline
            let flat = abs(diff) < 0.05
            let tint: Color = flat ? NunaPalette.textSecondary : (diff < 0 ? NunaPalette.charge : NunaPalette.warning)
            // One line whatever the language: the text shrinks a little before it would wrap.
            HStack(spacing: 5) {
                Image(systemName: flat ? "equal" : (diff < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")).font(.nuna(size: 9, weight: .bold))
                Text(verbatim: flat ? String(localized: "At your baseline") : String(format: String(localized: "%@ vs baseline"), Self.format(abs(diff))))
                    .font(.nuna(size: 11.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65)
            }
            .foregroundStyle(tint).padding(.horizontal, 10).frame(height: 28)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }
}

/// The day's stress line on a fixed 0 to 3 scale, coloured by level (blue calm, green steady, amber high). A gap in the readings is a gap in
/// the line. A dashed line and a dot mark the latest reading, which sits at the right edge.
struct NunaStressDayChart: View {
    let points: [DaytimeStress.HourPoint]
    /// The latest reading as a number beside the dot. Only for today, where it is the figure that is moving.
    var showsValue = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset: CGFloat = 7
            let scored = points.filter { $0.level != nil }
            let t0 = scored.first?.startTs ?? 0, t1 = scored.last?.startTs ?? 0
            let place: (DaytimeStress.HourPoint) -> CGPoint = { p in
                let f = t1 > t0 ? CGFloat(p.startTs - t0) / CGFloat(t1 - t0) : 1
                let level = min(max(p.level ?? 0, 0), 3)
                return CGPoint(x: inset + f * (w - 2 * inset), y: inset + (1 - CGFloat(level / 3)) * (h - 2 * inset))
            }
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(NunaPalette.hairline.opacity(0.7)).frame(height: 1).position(x: w / 2, y: inset + CGFloat(i) / 3 * (h - 2 * inset))
                }
                if scored.count >= 2 {
                    Path { path in
                        var open = false
                        for p in points {
                            guard p.level != nil else { open = false; continue }
                            let pt = place(p)
                            if open { path.addLine(to: pt) } else { path.move(to: pt); open = true }
                        }
                    }
                    .stroke(LinearGradient(colors: StressRamp.stops.map(\.color).reversed(), startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = scored.last {
                        let end = place(last)
                        Path { p in p.move(to: CGPoint(x: end.x, y: 0)); p.addLine(to: CGPoint(x: end.x, y: h)) }
                            .stroke(NunaPalette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(NunaPalette.textPrimary).frame(width: 12, height: 12).position(end)
                        if showsValue, let latest = last.level {
                            let valueText = String(format: "%.1f", locale: AppLanguage.activeLocale, min(max(latest, 0), 3))
                            // The latest reading as a number on the chart, so it reads without opening the screen. Beside the dot, on the side with room, and kept inside the chart.
                            Text(verbatim: valueText).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 8).frame(height: 22)
                                .background(NunaPalette.card.opacity(0.92), in: Capsule())
                                .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                                .position(x: max(end.x - 26, 22), y: min(max(end.y - 22, 12), h - 12))
                        }
                    }
                } else {
                    Text("Not enough data yet").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        .multilineTextAlignment(.center).position(x: w / 2, y: h / 2)
                }
            }
        }
        .accessibilityHidden(true)
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
    var icon = "circle"
    var tint: Color?
    /// Small line under the label in the long layout, e.g. what the change is measured against.
    var caption: LocalizedStringKey?
}

/// How the key metrics are laid out: two-column cards, or one long list.
enum NunaMetricsLayout: String { case cards, list }

struct NunaMetricsGrid: View {
    let tiles: [NunaMetricTile]
    var layout: NunaMetricsLayout = .cards
    var body: some View {
        if layout == .list { list } else { grid }
    }

    private var list: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { idx, tile in
                    if idx > 0 { NunaDivider() }
                    if let route = tile.route { NavigationLink(value: route) { row(tile) }.buttonStyle(.plain) } else { row(tile) }
                }
            }
        }
    }

    private func row(_ tile: NunaMetricTile) -> some View {
        HStack(spacing: 12) {
            NunaIconTile(tile.icon, tint: tile.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.label).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                if let c = tile.caption { Text(c).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: 8)
            // The figure on the right with its change as a small triangle (no unit), and what it was before underneath. The triangle's slot
            // is always there, so the figures of every row end on the same line.
            let trend = Self.trend(tile)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .center, spacing: 5) {
                    Text(verbatim: tile.value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Group {
                        if let trend {
                            Image(systemName: trend.up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(trend.tint)
                        } else { Color.clear }
                    }
                    .frame(width: 10, height: 10)
                }
                if let before = trend?.previous {
                    Text(verbatim: before).font(.nuna(size: 12, weight: .semibold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textSecondary).monospacedDigit().padding(.trailing, 15)
                }
            }
            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    /// Reads the "▲ 3" change: which way it went, its colour, and the value before it (this value minus the change). nil without a change.
    private static func trend(_ tile: NunaMetricTile) -> (up: Bool, tint: Color, previous: String?)? {
        guard let delta = tile.delta, let first = delta.first, first == "▲" || first == "▼" else { return nil }
        let up = first == "▲"
        let tint: Color = tile.deltaGood == nil ? NunaPalette.textSecondary : (tile.deltaGood! ? NunaPalette.charge : NunaPalette.warning)
        func number(_ t: String) -> Double? {
            Double(t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").filter { "0123456789.-".contains($0) })
        }
        var previous: String?
        if let now = number(tile.value), let change = number(String(delta.dropFirst())) {
            let before = up ? now - change : now + change
            let decimals = tile.value.contains(",") || tile.value.contains(".") ? 1 : 0
            previous = String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, before)
        }
        return (up, tint, previous)
    }

    private func deltaChip(_ text: String, good: Bool?) -> some View {
        let tint: Color = good == nil ? NunaPalette.textSecondary : (good! ? NunaPalette.charge : NunaPalette.warning)
        return Text(verbatim: text)
            .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(tint)
            .padding(.horizontal, 8).frame(height: 24)
            .background(NunaPalette.tint(tint), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }

    private var grid: some View {
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
                HStack(alignment: .center) {
                    Text(tile.label)
                        .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let delta = tile.delta {
                        let tint: Color = tile.deltaGood == nil ? NunaPalette.textSecondary
                            : (tile.deltaGood! ? NunaPalette.charge : NunaPalette.warning)
                        Text(verbatim: delta)
                            .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(tint)
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(NunaPalette.tint(tint), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
                    }
                }
                .frame(minHeight: 24, alignment: .top)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: tile.value)
                        .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if !tile.unit.isEmpty && tile.value != "–" {
                        Text(verbatim: tile.unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
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
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        Button { router.requestedDestination = .workouts } label: {
            NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                HStack(spacing: 12) {
                    NunaIconTile("flame", tint: NunaPalette.effortText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: WorkoutSource.displaySport(workout.sport))
                            .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: detail)
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 8)
                    if let s = workout.strain {
                        NunaChip(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: effortScale), color: NunaPalette.effortText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
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
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.nuna(size: 13, weight: .bold)).foregroundStyle(tint ?? NunaPalette.textPrimary)
                    .frame(width: 28, height: 28).background((tint ?? NunaPalette.textPrimary).opacity(0.14), in: Circle())
                Text(title).font(.nuna(size: 13.5, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .padding(.leading, 8).padding(.trailing, 16).frame(height: 44)
            .background(NunaPalette.glassStrong, in: Capsule())
            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Journal week card

/// "My journal": the last seven days ending today, a check for each day with answers in the journal, an empty ring for a day
/// without, and the card opens the journal. Reads the days that have a native journal answer.
struct NunaJournalWeekCard: View {
    @EnvironmentObject private var repo: Repository
    let onOpen: () -> Void
    @State private var logged: Set<String> = []

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        Button(action: onOpen) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("My journal").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(days, id: \.self) { d in
                            let isToday = Calendar.current.isDateInToday(d)
                            VStack(spacing: 6) {
                                Text(verbatim: Self.weekday(d)).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    .foregroundStyle(NunaPalette.textSecondary)
                                Text(verbatim: String(Calendar.current.component(.day, from: d))).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                                    .foregroundStyle(isToday ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                                mark(done: logged.contains(Repository.localDayKey(d)))
                            }
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(isToday ? NunaPalette.glassStrong : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(isToday ? NunaPalette.hairline : .clear, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: repo.refreshSeq) {
            guard let first = days.first, let last = days.last else { return }
            logged = await repo.nativeJournalDays(from: Repository.localDayKey(first), to: Repository.localDayKey(last))
        }
    }

    @ViewBuilder private func mark(done: Bool) -> some View {
        if done {
            Image(systemName: "checkmark").font(.nuna(size: 11, weight: .black)).foregroundStyle(.black)
                .frame(width: 22, height: 22).background(NunaPalette.charge, in: Circle())
        } else {
            Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1.5).frame(width: 22, height: 22)
        }
    }

    private static func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }
}
#endif
