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

    static let fullHeight: CGFloat = 120
    static let compactHeight: CGFloat = 36

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * min(max(collapse, 0), 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.rest); item(.charge); item(.effort)
        }
        .frame(height: lerp(Self.fullHeight, Self.compactHeight), alignment: .top)
        .clipped()
    }

    @ViewBuilder private func item(_ kind: Kind) -> some View {
        let v = values(kind)
        let size = lerp(92, 26)
        ringLink(v.route) {
            Group {
                if collapse < 0.55 {
                    VStack(spacing: 12) {
                        ringView(v, size: size)
                        // The name with a chevron after it: the ring opens its page.
                        HStack(spacing: 4) {
                            Text(verbatim: englishName(kind)).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            Image(systemName: "chevron.right").font(.nuna(size: 9.5, weight: .heavy))
                        }
                        .foregroundStyle(NunaPalette.textPrimary)
                    }
                } else {
                    HStack(spacing: 8) {
                        ringView(v, size: size)
                        Text(verbatim: englishName(kind)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The ring names stay in English in every app language, like the chips under the rings.
    private func englishName(_ kind: Kind) -> String {
        switch kind { case .charge: return "Charge"; case .effort: return "Effort"; case .rest: return "Rest" }
    }

    /// The figure keeps the size it had in the larger ring (30 pt) while the ring itself is smaller.
    private func numberSize(_ ringSize: CGFloat) -> CGFloat { max(ringSize * 0.27, 31 * min(ringSize / 92, 1)) }

    private func ringView(_ v: RingValues, size: CGFloat) -> some View {
        NunaRingGauge(fraction: v.fraction, color: v.color, gradient: v.gradient, target: v.target, size: size, lineWidth: max(3.5, size * 0.09)) {
            if size >= 60 {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: v.number).font(.nuna(size: numberSize(size), weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(numberSize(size))).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !v.unit.isEmpty && v.number != "–" {
                        Text(verbatim: v.unit).font(.nuna(size: numberSize(size) * 0.68, weight: .bold)).foregroundStyle(NunaPalette.textPrimary.opacity(0.85))
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
        var gradient: [Color]? = nil
        var target: ClosedRange<Double>? = nil
    }

    /// Each ring opens its own metric screen; Rest's has a way into last night's sleep.
    @ViewBuilder private func ringLink<C: View>(_ key: String, @ViewBuilder _ content: () -> C) -> some View {
        if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
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
            return RingValues(fraction: (pct ?? 0) / 100, color: pct.map(nunaChargeColor) ?? NunaPalette.scoreHigh, textColor: pct.map(nunaChargeTextColor) ?? NunaPalette.scoreHigh,
                              number: pct.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                              label: "Charge", state: state, route: HeroRingMetric.charge)
        case .effort:
            let text = effort.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–"
            let state: LocalizedStringKey = effort.map { $0 < 33 ? "Light" : ($0 < 66 ? "Moderate" : "High") } ?? "No data"
            return RingValues(fraction: (effort ?? 0) / 100, color: effort.map(nunaEffortColor) ?? NunaPalette.effortModerate, textColor: effort.map(nunaEffortTextColor) ?? NunaPalette.effortModerate,
                              number: text, unit: "", label: "Effort", state: state, route: HeroRingMetric.effort,
                              gradient: effort.map(nunaEffortRingColors), target: nunaEffortTargetFractions(charge: charge.pct))
        case .rest:
            let state: LocalizedStringKey = rest.map(nunaRestWord) ?? "No data"
            return RingValues(fraction: (rest ?? 0) / 100, color: rest.map(nunaRestColor) ?? NunaPalette.rest, textColor: rest.map(nunaRestTextColor) ?? NunaPalette.restText,
                              number: rest.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                              label: "Rest", state: state, route: HeroRingMetric.rest)
        }
    }
}

// MARK: - Anya card

private struct NunaAnyaCardContextKey: EnvironmentKey { static let defaultValue: String? = nil }

private struct NunaAnyaBorderedKey: EnvironmentKey { static let defaultValue = true }

private struct NunaAnyaRowKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Draws Anya's suggestion as one slim row: her mark in a ring, the line, a chevron. Today turns it on.
    var nunaAnyaRow: Bool {
        get { self[NunaAnyaRowKey.self] }
        set { self[NunaAnyaRowKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// On by default everywhere. Draws Anya's suggestion as a bordered note (a gradient outline in the wing colours, no icon, no fill) instead of the plain row.
    var nunaAnyaBordered: Bool {
        get { self[NunaAnyaBorderedKey.self] }
        set { self[NunaAnyaBorderedKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// The Anya context of the screen. When it is set, a card that carries its own line (a verdict, a zone read, a record) opens the
    /// Anya sheet about that very line instead of the screen's general read, so what is tapped and what opens always agree.
    var nunaAnyaCardContext: String? {
        get { self[NunaAnyaCardContextKey.self] }
        set { self[NunaAnyaCardContextKey.self] = newValue }
    }
}

/// Anya's colours, taken from her wings: light teal, teal and deep teal.
enum NunaAnyaWing {
    static let colors = [Color(red: 0.44, green: 0.90, blue: 0.83), Color(red: 0.15, green: 0.65, blue: 0.62), Color(red: 0.11, green: 0.56, blue: 0.53)]
    static var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    /// Dark ink for text on the gradient.
    static let ink = Color(red: 0.02, green: 0.13, blue: 0.12)
}

extension View {
    /// The outline of Anya's notes: a thin gradient in the wing colours, no fill. Used by every note Anya writes on a screen.
    func nunaAnyaOutline(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color(red: 0.44, green: 0.90, blue: 0.83), Color(red: 0.15, green: 0.65, blue: 0.62), Color(red: 0.11, green: 0.56, blue: 0.53)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }
}

/// Anya's suggestion has no card of its own: it sits on the page background, so it reads as a line of the page rather than one more box.
struct NunaAnyaNote<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.nunaAnyaOutline().contentShape(Rectangle()) }
}

struct NunaAnyaPlain<Content: View>: View {
    let padding: EdgeInsets
    let content: Content
    init(padding: EdgeInsets, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    var body: some View { content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
}

/// Anya's suggestion: icon tile, caption, one-line advice and an optional white action button.
struct NunaAnyaCard: View {
    let title: Text
    var buttonTitle: LocalizedStringKey?
    var onButton: (() -> Void)?
    var highlight = true
    /// A second line under the title, and a thin bar (0 to 1) under that, for cards that report progress.
    var detail: String?
    var progress: Double?
    var progressColor: Color = NunaPalette.effort
    /// More buttons for the sheet, after the one above (a second thing to do about the same line).
    var moreActions: [NunaAnyaCardAction] = []
    let action: () -> Void
    /// The line itself, when it is already text; with a screen context it is what the sheet opens on.
    private var line: String?
    @Environment(\.nunaAnyaCardContext) private var sheetContext
    @Environment(\.nunaAnyaBordered) private var bordered
    @Environment(\.nunaAnyaRow) private var rowStyle
    @State private var showSheet = false

    init(title: LocalizedStringKey, highlight: Bool = true, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.title = Text(title); self.highlight = highlight; self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    /// For text that is already localized (the readiness one-liner).
    init(verbatim: String, detail: String? = nil, progress: Double? = nil, progressColor: Color = NunaPalette.effort, buttonTitle: LocalizedStringKey? = nil, onButton: (() -> Void)? = nil,
         moreActions: [NunaAnyaCardAction] = [], action: @escaping () -> Void) {
        self.moreActions = moreActions
        self.title = Text(verbatim: NunaMark.plain(verbatim)); self.line = verbatim; self.detail = detail; self.progress = progress; self.progressColor = progressColor
        self.buttonTitle = buttonTitle; self.onButton = onButton; self.action = action
    }

    /// "Suggestion cards on each screen" in Anya settings.
    @AppStorage(NunaAnyaPrefs.cardsKey) private var cardsOn = true

    var body: some View {
        if cardsOn {
            content.sheet(isPresented: $showSheet) {
                if let ctx = sheetContext, let line {
                    NunaAnyaSheet(context: ctx, cardLine: .init(headline: line, detail: detail, read: NunaAnyaCardLine.signals(ctx), actions: sheetActions))
                }
            }
        }
    }

    /// The buttons the card would have carried, which the sheet shows instead when the card is kept short.
    private var sheetActions: [NunaAnyaCardAction] {
        (buttonTitle.flatMap { t in onButton.map { [NunaAnyaCardAction(title: t, perform: $0)] } } ?? []) + moreActions
    }

    /// On a screen that opens the sheet from its cards, a card that has more to say (a second line, a bar, a button) shows only its
    /// headline; the rest is in the sheet.
    private var compact: Bool {
        sheetContext != nil && line != nil && (detail != nil || progress != nil || buttonTitle != nil || !moreActions.isEmpty)
    }

    /// A card with its own line opens the sheet about it; the others keep the screen's action.
    private func tapped() {
        if sheetContext != nil, line != nil { showSheet = true } else { action() }
    }

    @ViewBuilder private var content: some View {
        if rowStyle { slimRow }
        else if bordered { borderedNote }
        else if compact { inline(compact: true) }
        else if let buttonTitle, let onButton { stacked(buttonTitle, onButton) } else { inline(compact: false) }
    }

    /// One slim row on a card: Anya's mark in a thin ring, her line (two lines at most) and a chevron. The detail and the buttons are in the sheet it opens.
    private var slimRow: some View {
        Button(action: tapped) {
            NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 16)) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(LinearGradient(colors: Self.wing, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        AnyaMark(size: 19)
                    }
                    .frame(width: 34, height: 34).accessibilityHidden(true)
                    title.font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .multilineTextAlignment(.leading).lineLimit(2).minimumScaleFactor(0.9)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The wing colours, light to deep, for the outline and the link.
    private static let wing = [Color(red: 0.44, green: 0.90, blue: 0.83), Color(red: 0.15, green: 0.65, blue: 0.62), Color(red: 0.11, green: 0.56, blue: 0.53)]

    /// A note in its own outline: the words, then "Learn more with Anya" with an arrow. No icon and no fill; the outline fades from the light
    /// wing teal to the deep one.
    private var borderedNote: some View {
        Button(action: tapped) {
            VStack(alignment: .leading, spacing: 14) {
                bodyView(compact: compact)
                // A screen that does not open the sheet from its cards keeps its own button.
                if !compact, let buttonTitle, let onButton {
                    Button(action: onButton) {
                        Text(buttonTitle).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 20).frame(height: 40)
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Text("Learn more with Anya").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                }
                .foregroundStyle(LinearGradient(colors: Self.wing, startPoint: .leading, endPoint: .trailing))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: Self.wing, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Text("Anya")
            .font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(NunaThemePrefs.skin == .whp ? nil : .uppercase)
            .foregroundStyle(NunaPalette.textSecondary)
    }

    private var body_: some View { bodyView(compact: false) }

    private func bodyView(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.nuna(size: 16, weight: .bold))
                .foregroundStyle(NunaPalette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true).textCase(nil)
            if let detail, !compact {
                Text(verbatim: NunaMark.plain(detail)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.top, 2)
            }
            if let progress, !compact {
                NunaProgressBar(fraction: min(max(progress, 0), 1), color: progressColor).frame(height: 6).padding(.top, 6)
            }
        }
    }

    /// The icon, the words and a chevron in one row; the whole card opens Anya.
    private func inline(compact: Bool) -> some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)) {
            Button(action: tapped) {
                HStack(spacing: 12) {
                    AnyaIconTile()
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        bodyView(compact: compact)
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
        NunaAnyaPlain(padding: EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)) {
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
    /// The day's activities, drawn as bands over the curve.
    var workouts: [WorkoutRow] = []

    private var scored: Bool { curve?.hours.contains { $0.level != nil } ?? false }
    private var highMin: Int? { scored ? curve.map(StressDayCurve.highMinutes) : nil }
    /// The big number: the average over the latest hour (today) or over the day, never above the scale's 3.
    private var level: Double? { curve.flatMap { StressDayCurve.headlineLevel($0, isToday: isToday) } ?? score.map { min(max($0, 0), 3) } }
    /// "Last hour" only when the figure really is the latest reading on the curve; the day-level score that stands in when nothing has been
    /// read yet is a day figure, and says so.
    private var isLastHour: Bool { isToday && curve.flatMap(StressDayCurve.latestLevel) != nil }

    /// The time of the latest reading: when the card was last brought up to date.
    private var lastUpdated: String? {
        guard let ts = curve?.timeline.last(where: { $0.level != nil })?.startTs else { return nil }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private var levelWord: LocalizedStringKey? {
        level.map { $0 < 1 ? "Low" : ($0 < 2 ? "Medium" : "High") }
    }

    var body: some View {
        NavigationLink(value: stressRoute) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Stress monitor").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel)
                            .textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: isToday ? (lastUpdated.map { String(localized: "Last updated \($0)") } ?? "") : String(localized: "Day average"))
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer(minLength: 8)
                        if let level, let levelWord {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(levelWord).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaStressBand.color(for: level))
                                Text(verbatim: Self.format(level)).font(.nuna(size: 26, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }
                        }
                    }
                    NunaStressMonitorChart(points: curve?.timeline ?? [], workouts: workouts, showsNow: isToday).frame(height: 260)
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

/// The day's stress as a line on a 0 to 3 axis, coloured by level (teal calm, green, amber high), with the hours along the bottom and a band with its icon over
/// every activity of the day. A dashed line and a dot close it at the latest reading.
///
/// On the Stress monitor page it also marks the night (a moon and a band over the hours asleep), can be held to read a value, and has a zoom
/// button that narrows it to the last twelve hours.
struct NunaStressMonitorChart: View {
    let points: [DaytimeStress.HourPoint]
    var workouts: [WorkoutRow] = []
    /// Today ends in the latest reading (a dashed line, a dot and the time in bold); a past day only ends.
    var showsNow = true
    /// The hours asleep, as timestamps.
    var sleep: ClosedRange<Int>?
    /// Narrowed to the last twelve hours of the line.
    var zoomed = false
    /// Shows the zoom button and what it does.
    var onZoom: (() -> Void)?
    /// Hold and drag to read the value at a time.
    var reads = false
    /// The window the chart covers, in unix seconds. Without it the chart runs from the first scored point to the last one. With it the
    /// chart is exactly this window (today: the last 24 hours up to now), whatever part of it has data.
    var domain: ClosedRange<Int>?

    @State private var scrubX: CGFloat?

    private func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    var body: some View {
        GeometryReader { geo in
            let left: CGFloat = 38, right: CGFloat = 14, top: CGFloat = 54, bottom: CGFloat = 34
            let w = geo.size.width, h = geo.size.height
            let plot = CGRect(x: left, y: top, width: w - left - right, height: h - top - bottom)
            let allScored = points.filter { $0.level != nil }
            let end = domain?.upperBound ?? allScored.last?.startTs ?? 0
            let begin = domain?.lowerBound ?? allScored.first?.startTs ?? 0
            let t0 = zoomed ? max(begin, end - 12 * 3600) : begin
            let t1 = max(end, t0 + 1)
            let scored = allScored.filter { $0.startTs >= t0 }
            let x: (Int) -> CGFloat = { plot.minX + CGFloat($0 - t0) / CGFloat(t1 - t0) * plot.width }
            let y: (Double) -> CGFloat = { plot.maxY - CGFloat(min(max($0, 0), 3) / 3) * plot.height }
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(NunaPalette.hairline.opacity(0.7)).frame(width: plot.width, height: 1)
                        .position(x: plot.midX, y: y(Double(i)))
                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, Double(i))).font(.nuna(size: 12.5, weight: .heavy))
                        .foregroundStyle(NunaPalette.textMuted).position(x: left / 2 - 2, y: y(Double(i)))
                }
                if scored.count >= 2 {
                    // A vertical line and its time at the whole hours that suit the span (every 8 hours over a day, every 2 over part of one, then
                    // every hour), kept clear of both ends.
                    ForEach(hourMarks(t0, t1, x: x, plotWidth: plot.width), id: \.self) { ts in
                        Rectangle().fill(NunaPalette.hairline.opacity(0.7)).frame(width: 1, height: plot.height).position(x: x(ts), y: plot.midY)
                        Text(verbatim: clock(ts)).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted)
                            .fixedSize().position(x: x(ts), y: plot.maxY + 22)
                    }
                    Text(verbatim: clock(t0)).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted)
                        .fixedSize().position(x: plot.minX + 14, y: plot.maxY + 22)
                    if let sleep {
                        let a = max(sleep.lowerBound, t0), b = min(sleep.upperBound, t1)
                        if b > a {
                            let x0 = x(a), width = max(x(b) - x0, 6)
                            Rectangle().fill(Color.white.opacity(0.05)).frame(width: width, height: plot.height).position(x: x0 + width / 2, y: plot.midY)
                            Rectangle().fill(NunaRestChart.steel).frame(width: width, height: 3).position(x: x0 + width / 2, y: plot.minY)
                            Image(systemName: "moon.fill").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                                .position(x: x0 + width / 2, y: plot.minY - 22)
                        }
                    }
                    ForEach(Array(workouts.enumerated()), id: \.offset) { _, wo in
                        let a = max(wo.startTs, t0), b = min(wo.endTs, t1)
                        if b > a {
                            let x0 = x(a), width = max(x(b) - x0, 6)
                            Rectangle().fill(Color.white.opacity(0.07)).frame(width: width, height: plot.height).position(x: x0 + width / 2, y: plot.midY)
                            Rectangle().fill(NunaRestChart.steel).frame(width: width, height: 3).position(x: x0 + width / 2, y: plot.minY)
                            Image(systemName: ActivitySport.symbol(for: wo.sport)).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                                .position(x: x0 + width / 2, y: plot.minY - 22)
                        }
                    }
                    // The line is coloured by the level itself (blue low, green, then yellow and amber), not by where it sits in its own range: the
                    // gradient is laid on the 0 to 3 axis of the plot.
                    Canvas { ctx, _ in
                        var path = Path()
                        var open = false
                        for p in points where p.startTs >= t0 && p.startTs <= t1 {
                            guard let level = p.level else { open = false; continue }
                            let pt = CGPoint(x: x(p.startTs), y: y(level))
                            if open { path.addLine(to: pt) } else { path.move(to: pt); open = true }
                        }
                        let ramp = Gradient(stops: [.init(color: NunaStressBand.high, location: 0), .init(color: NunaPalette.effort, location: 0.2),
                                                    .init(color: NunaStressBand.medium, location: 0.5), .init(color: NunaStressBand.low, location: 1)])
                        ctx.stroke(path, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: y(3)), endPoint: CGPoint(x: 0, y: y(0))),
                                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: w, height: h)
                    if showsNow {
                        Path { p in p.move(to: CGPoint(x: x(t1), y: plot.minY - 8)); p.addLine(to: CGPoint(x: x(t1), y: plot.maxY)) }
                            .stroke(NunaPalette.textPrimary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(NunaPalette.textPrimary).frame(width: 7, height: 7).position(x: x(t1), y: plot.maxY)
                        Text(verbatim: clock(t1)).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                            .fixedSize().position(x: min(x(t1), w - 24), y: plot.maxY + 22)
                    }
                    if let scrubX, let p = nearest(scored, to: scrubX, x: x), let level = p.level {
                        let px = x(p.startTs), py = y(level)
                        Rectangle().fill(NunaPalette.textPrimary.opacity(0.6)).frame(width: 1, height: plot.height).position(x: px, y: plot.midY)
                        Circle().fill(NunaPalette.textPrimary).frame(width: 10, height: 10).position(x: px, y: py)
                        Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, level) + "  " + clock(p.startTs))
                            .font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(NunaPalette.card.opacity(0.95), in: Capsule())
                            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                            .position(x: min(max(px, plot.minX + 50), plot.maxX - 50), y: plot.minY - 30)
                    }
                    if let onZoom {
                        Button(action: onZoom) {
                            Image(systemName: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass").font(.nuna(size: 20, weight: .regular))
                                .foregroundStyle(NunaPalette.textPrimary).frame(width: 46, height: 46)
                                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text(zoomed ? "Show the whole day" : "Zoom in"))
                        .position(x: plot.maxX - 34, y: plot.maxY - 40)
                    }
                } else {
                    Text("Not enough data yet").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        .multilineTextAlignment(.center).position(x: plot.midX, y: plot.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(reads ? LongPressGesture(minimumDuration: 0.2).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in if case .second(true, let drag?) = value { scrubX = drag.location.x } }
                .onEnded { _ in scrubX = nil } : nil)
        }
        .accessibilityHidden(true)
    }

    private func nearest(_ pts: [DaytimeStress.HourPoint], to px: CGFloat, x: (Int) -> CGFloat) -> DaytimeStress.HourPoint? {
        pts.min { abs(x($0.startTs) - px) < abs(x($1.startTs) - px) }
    }

    /// The whole hours that suit the span, clear of both ends: every 8 hours over more than 13, every 3 over more than 4, then every hour. The
    /// first end is a label, so it gets a wider berth than the last.
    private func hourMarks(_ t0: Int, _ t1: Int, x: (Int) -> CGFloat, plotWidth: CGFloat) -> [Int] {
        let span = t1 - t0
        let step = span > 13 * 3600 ? 8 : (span > 4 * 3600 ? 3 : 1)
        let cal = Calendar.current
        guard let first = cal.date(bySetting: .minute, value: 0, of: Date(timeIntervalSince1970: TimeInterval(t0))) else { return [] }
        var out: [Int] = []
        var d = first
        while Int(d.timeIntervalSince1970) < t1 {
            let ts = Int(d.timeIntervalSince1970)
            if cal.component(.hour, from: d) % step == 0, ts > t0, x(ts) - x(t0) > 62, x(t1) - x(ts) > 34 { out.append(ts) }
            d = cal.date(byAdding: .hour, value: 1, to: d) ?? d.addingTimeInterval(3600)
        }
        return out
    }
}

// MARK: - Key metrics

struct NunaMetricTile: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let route: NunaTodayRoute?
    /// The comparison with the figure before it: a triangle when it moved, a dot when it did not or there is nothing earlier, and the earlier
    /// figure underneath (the chip of the card layout carries "▲ 4" or "● 0").
    var trend: NunaTrend?
    var icon = "circle"
    var tint: Color?
    /// Small line under the label in the long layout, e.g. what the change is measured against.
    var caption: LocalizedStringKey?
    /// The last days of this metric for the trend line of "Detailed tiles"; nil when the option is off or there is nothing to draw.
    var spark: [Double]?
}

/// How the key metrics are laid out: two-column cards, or one long list.
enum NunaMetricsLayout: String { case cards, list }

struct NunaMetricsGrid: View {
    let tiles: [NunaMetricTile]
    var layout: NunaMetricsLayout = .cards
    /// A heading with its buttons, drawn inside the card above the figures instead of floating over it.
    var header: AnyView?
    var body: some View {
        if layout == .list { list } else if header != nil { framedGrid } else { grid }
    }

    private var list: some View {
        NunaCard(small: true, padding: EdgeInsets(top: header == nil ? 4 : 10, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                if let header {
                    // No line under the heading: the space does the separating, as in Today's activities.
                    header.padding(.bottom, 8)
                }
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
            if let spark = tile.spark, spark.count >= 2 {
                NunaSpark(values: spark, color: tile.tint ?? NunaPalette.charge).frame(width: 52, height: 30)
            }
            // The figure on the right with its comparison: a triangle when it moved, a dot when it did not, and what it was before underneath.
            NunaTrendFigure(value: tile.value, trend: tile.trend, size: 20, minimumScale: 0.7)
            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], alignment: .center, spacing: 12) {
            ForEach(tiles) { tile in
                if let route = tile.route {
                    NavigationLink(value: route) { content(tile) }.buttonStyle(.plain)
                } else {
                    content(tile)
                }
            }
        }
    }

    /// The card layout with its heading: one card holds the heading and the tiles, each tile a lighter panel inside it.
    private var framedGrid: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)) {
            VStack(spacing: 8) {
                if let header { header.padding(.horizontal, 6) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(tiles) { tile in
                        if let route = tile.route {
                            NavigationLink(value: route) { content(tile, inCard: true) }.buttonStyle(.plain)
                        } else {
                            content(tile, inCard: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func content(_ tile: NunaMetricTile, inCard: Bool = false) -> some View {
        if inCard {
            tileBody(tile).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(NunaPalette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) { tileBody(tile) }
        }
    }

    /// The same tile as the vital signs: the icon and the label, the value, then the change as a chip under it. With trend lines on, every tile
    /// keeps the room of the chip and of the line, so a tile with no history yet is as tall as the rest.
    private func tileBody(_ tile: NunaMetricTile) -> some View {
        let anyTrend = tiles.contains { $0.trend != nil }
        let anySpark = tiles.contains { ($0.spark?.count ?? 0) >= 2 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: tile.icon).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 24, height: 24)
                Text(tile.label)
                    .font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: tile.value)
                    .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .minimumScaleFactor(0.6).lineLimit(1)
                if !tile.unit.isEmpty && tile.value != "–" {
                    Text(verbatim: tile.unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            if let trend = tile.trend {
                Text(verbatim: trend.chipText)
                    .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(trend.tint)
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(NunaPalette.tint(trend.tint), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(trend.tint.opacity(0.35), lineWidth: 1))
            } else if anyTrend {
                Color.clear.frame(height: 24)
            }
            if let spark = tile.spark, spark.count >= 2 {
                NunaSpark(values: spark, color: tile.tint ?? NunaPalette.charge).frame(height: 38)
            } else if anySpark {
                Color.clear.frame(height: 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
