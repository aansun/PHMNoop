#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The measuring view's place on the screen, for iOS 17.
private struct NunaFitnessScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Reports how far a scroll view has gone up. From iOS 18 it is the scroll view's own offset; before that the page reads its position from a measuring view in
/// its content (`NunaFitnessScrollKey`), which is enough for the header to follow.
private struct NunaFitnessScrollOffset: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in offset = new }
        } else {
            content
        }
    }
}

/// The fitness age page (docs/FITNESS_AGE.md): one age, the Body Age the nine inputs of the Healthspan model make from the latest 7 days, its gap to the real age, the
/// pace of aging, the nine inputs each as the years it adds or takes away, and how the age moved.
///
/// The inputs are grouped as on the WHOOP Healthspan page: Sleep (consistency, hours), Strain (time in heart-rate zones 1–3 and 4–5, strength, steps) and Fitness
/// (VO₂ max, resting heart rate, lean body mass). All nine are always listed; one with no data says so and says what it needs, and is left out of the age rather than
/// counted as zero. It is a wellness estimate, not a biological age.
struct NunaFitnessAgeView: View {
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    /// The Body Age stored each week, which the pace and the trends are read from.
    @State private var bodyAges: [(day: String, value: Double)] = []
    @State private var healthspan: NunaHealthspanResult?
    @State private var loaded = false
    @State private var scrollY: CGFloat = 0
    @State private var restY: CGFloat?
    @State private var opened: Set<String> = []
    @State private var showInfo = false
    @State private var showWaist = false

    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    /// The latest 7 days, the only data the age is made from.
    private var days: [DailyMetric] { Array(repo.days.sorted { $0.day < $1.day }.suffix(7)) }
    private var bodyAge: Double? { healthspan?.bodyAge }

    /// Calendar age minus the age in whole years; positive is younger.
    private var gap: Int? {
        guard let bodyAge, profile.age > 0 else { return nil }
        return Int((Double(profile.age) - bodyAge).rounded())
    }
    private var tint: Color { NunaFitnessAgeTone.tint(gap: gap) }
    /// The outline of the orb follows the pace of aging: a ring when it is slow, an amoeba when it is fast.
    private var orbShape: Double { NunaFitnessAgeTone.irregularity(pace: pace?.pace) }

    private var readings: [PaceOfAging.Reading] {
        bodyAges.compactMap { r in date(r.day).map { PaceOfAging.Reading(time: $0.timeIntervalSince1970, fitnessAge: r.value) } }
    }
    private var pace: PaceOfAging.Result? { PaceOfAging.compute(readings) }

    // MARK: Body

    /// How much of the page's own header has taken over from the big one: 0 at the top, 1 once the big figure has scrolled away.
    private var collapse: Double { min(max(Double((scrollY - 200) / 140), 0), 1) }

    var body: some View {
        ZStack(alignment: .top) {
            NunaBackdrop()
            ScrollView {
                ZStack(alignment: .top) {
                    // Zero height, at the very top of the content: its place on the screen is how far the page has gone up (iOS 17).
                    GeometryReader { g in Color.clear.preference(key: NunaFitnessScrollKey.self, value: g.frame(in: .global).minY) }.frame(height: 0)
                    VStack(spacing: 30) {
                        // Nothing until the week is read: a "not ready" card here would be replaced by the page a moment later.
                        if loaded {
                            if bodyAge != nil {
                                hero
                                paceSection
                            } else {
                                notReady
                            }
                            if let healthspan { factors(healthspan) }
                            if bodyAge != nil { trends }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 60).padding(.bottom, 120)
                }
            }
            .modifier(NunaFitnessScrollOffset(offset: $scrollY))
            .onPreferenceChange(NunaFitnessScrollKey.self) { y in
                if restY == nil { restY = y }
                if #unavailable(iOS 18.0) { scrollY = (restY ?? y) - y }
            }
            .scrollIndicators(.hidden)
            if bodyAge != nil { compactHeader.opacity(collapse).allowsHitTesting(false) }
            topBar
        }
        .animation(.easeOut(duration: 0.22), value: loaded)
        .toolbar(.hidden, for: .navigationBar)
        // The age of the latest 7 days and the stored weekly ages: read again when the days or the profile change, and shown together.
        .task(id: "\(days.last?.day ?? "")-\(days.count)-\(repo.refreshSeq)-\(profile.age)-\(profile.sex)-\(profile.waistCm)") {
            guard await repo.nunaAwaitFirstRead() else { return }
            async let stored = repo.exploreSeries(key: "body_age", source: "my-whoop", days: 400)
            async let latest = NunaHealthspan.latest(repo: repo, profile: profile)
            let (ages, result) = await (stored, latest)
            guard !Task.isCancelled else { return }
            bodyAges = ages
            healthspan = result
            loaded = true
        }
        .sheet(isPresented: $showWaist) { NunaWaistSheet() }
        .sheet(isPresented: $showInfo) { NunaFitnessAgeInfoSheet(pace: pace?.pace).nunaSheetChrome(detents: [.large]) }
    }

    // MARK: Header

    private func cap(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
    }

    private func heading(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
    }

    /// The days the age is made from, as "Nov 9 – Nov 15".
    private var latestRange: String {
        guard let first = days.first, let last = days.last, let start = date(first.day), let end = date(last.day) else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: start) + " – " + f.string(from: end)
    }

    /// The way back, the page's name with the days it covers, and the info page.
    private var topBar: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("Body age").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if bodyAge != nil {
                    Text(verbatim: latestRange).font(.nuna(size: 11.5, weight: .semibold)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            .opacity(1 - collapse)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("Back"))
                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info").font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 34, height: 34).overlay(Circle().strokeBorder(NunaPalette.textSecondary, lineWidth: 1.5)).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("About Body age"))
            }
        }
        .padding(.horizontal, 12).frame(height: 56)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0.95), NunaPalette.canvas.opacity(0.95 * collapse)], startPoint: .top, endPoint: .bottom))
    }

    /// The figure and the two statements, small, once the big one has scrolled off: the gap at the left, the pace at the right.
    private var compactHeader: some View {
        HStack(alignment: .center) {
            VStack(spacing: 3) {
                Text(verbatim: gap.map { String(abs($0)) } ?? "–").font(.nuna(size: 32, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restLight).textCase(nil)
                Text(gapCaption).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
            // Drawn larger than the room it takes, so its glow is not cut off at the edge of the drawing.
            NunaFitnessOrb(tint: tint, size: 170, irregularity: orbShape) { NunaFitnessOrbCenter(value: bodyAge, gap: nil, numberSize: 30, captionSize: 10.5, showsGap: false) }
                .frame(width: 130, height: 130)
            VStack(spacing: 3) {
                Text(verbatim: pace.map { String(format: "%.1fx", locale: AppLanguage.activeLocale, $0.pace) } ?? "–").font(.nuna(size: 32, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Pace of aging").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 74).frame(height: 216, alignment: .top)
        // Solid behind the figures, so nothing of the page shows through them, and fading out only at the foot.
        .background(LinearGradient(stops: [.init(color: NunaPalette.canvas, location: 0), .init(color: NunaPalette.canvas, location: 0.8),
                                           .init(color: NunaPalette.canvas.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private var gapCaption: LocalizedStringKey { (gap ?? 0) > 0 ? "years younger" : ((gap ?? 0) < 0 ? "years older" : "about your age") }

    // MARK: Hero

    private var hero: some View {
        // Drawn over a room as wide as the page, so an orb a little wider than the page does not widen the page.
        Color.clear.frame(maxWidth: .infinity).frame(height: 350)
            .overlay { NunaFitnessOrb(tint: tint, size: 380, irregularity: orbShape) { NunaFitnessOrbCenter(value: bodyAge, gap: gap, numberSize: 48) } }
            .padding(.top, 4)
    }

    // MARK: Pace of aging

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            cap("Pace of aging")
            if let pace {
                NunaPaceDial(value: pace.pace, showsValue: true)
            } else {
                Text(verbatim: String(localized: "Pace of aging appears after 6 weekly readings. You have \(readings.count) so far."))
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                NunaPaceDial(value: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The nine inputs

    /// One input, read against a scale: where it is, where it stops adding to the age (its break-even), and the years it adds or takes away.
    private struct Factor: Identifiable {
        let id: String
        let title: LocalizedStringKey
        /// nil when the week has no data for it.
        let value: Double?
        /// The figure and its unit, set apart because the unit is smaller and grey.
        let valueText: String
        let unit: String
        let range: ClosedRange<Double>
        let reference: Double
        let referenceText: String
        let higherIsBetter: Bool
        /// Years it adds (older, positive) or takes away (younger, negative); nil with no data.
        let years: Double?
        let lowText: String
        let highText: String
        let note: LocalizedStringKey
        /// What it needs, said when there is no data.
        let missing: LocalizedStringKey
        /// The trend page "View trend" opens.
        let trend: NunaTrendPage
    }

    private func n(_ v: Double, _ decimals: Int = 0) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }

    /// Minutes as hours and minutes: 38 → "0:38".
    private func hm(_ minutes: Double) -> String { let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60) }

    private func groups(_ r: NunaHealthspanResult) -> [(title: LocalizedStringKey, items: [Factor])] {
        let i = r.inputs
        let expectedVO2 = VitalityEngine.expectedVO2max(age: Double(profile.age), sex: profile.sex)
        let consistency = i.sleepConsistency.map { $0 * 100 }
        return [
            ("Sleep", [
                Factor(id: "consistency", title: "Sleep consistency", value: consistency, valueText: consistency.map { n($0) } ?? "", unit: "%", range: 40...100,
                       reference: VitalityEngine.consistencyBreakEven * 100, referenceText: n(VitalityEngine.consistencyBreakEven * 100) + "%", higherIsBetter: true,
                       years: r.years("consistency"), lowText: "40%", highText: "100%",
                       note: "How regular your sleep and wake times are over the last 7 days. Around 70% is where it stops adding to your age.",
                       missing: "Needs at least 3 nights of sleep.", trend: .consistency),
                Factor(id: "sleep", title: "Hours of sleep", value: i.sleepHours, valueText: i.sleepHours.map { hm($0 * 60) } ?? "", unit: "h", range: 4...9,
                       reference: 7.5, referenceText: "7:30", higherIsBetter: true,
                       years: r.years("sleep"), lowText: "4h", highText: "9h",
                       note: "Your average night over the last 7 days. About 7½ hours is where it stops adding to your age; much less or much more adds to it.",
                       missing: "Needs sleep from your nights.", trend: .hoursNeededHours),
            ]),
            ("Strain", [
                Factor(id: "zonesLow", title: "Time in HR zones 1–3 (weekly)", value: i.zonesLowMin, valueText: i.zonesLowMin.map { hm($0) } ?? "", unit: "h", range: 0...180,
                       reference: VitalityEngine.lowZoneBreakEven, referenceText: hm(VitalityEngine.lowZoneBreakEven), higherIsBetter: true,
                       years: r.years("zonesLow"), lowText: "0h", highText: "3h",
                       note: "Time in heart rate zones 1 to 3 over the last 7 days. The first hour and a half a week counts the most.",
                       missing: "Needs heart rate samples from the last 7 days.", trend: .hrZonesLow),
                Factor(id: "zonesHigh", title: "Time in HR zones 4–5 (weekly)", value: i.zonesHighMin, valueText: i.zonesHighMin.map { hm($0) } ?? "", unit: "h", range: 0...60,
                       reference: VitalityEngine.highZoneBreakEven, referenceText: hm(VitalityEngine.highZoneBreakEven), higherIsBetter: true,
                       years: r.years("zonesHigh"), lowText: "0h", highText: "1h",
                       note: "Time in heart rate zones 4 and 5, the hard efforts, over the last 7 days. A few minutes is enough to stop it adding to your age.",
                       missing: "Needs heart rate samples from the last 7 days.", trend: .hrZonesHigh),
                Factor(id: "strength", title: "Strength activity time (weekly)", value: i.strengthMin, valueText: i.strengthMin.map { hm($0) } ?? "", unit: "h", range: 0...120,
                       reference: VitalityEngine.strengthBreakEven, referenceText: hm(VitalityEngine.strengthBreakEven), higherIsBetter: true,
                       years: r.years("strength"), lowText: "0h", highText: "2h",
                       note: "Time in strength training over the last 7 days. Around 45 minutes a week is where it stops adding to your age.",
                       missing: "Needs heart rate samples from the last 7 days.", trend: .strengthTime),
                Factor(id: "steps", title: "Steps", value: i.steps, valueText: i.steps.map { Int($0.rounded()).formatted() } ?? "", unit: "steps", range: 0...16000,
                       reference: 7000, referenceText: (7000).formatted(), higherIsBetter: true,
                       years: r.years("steps"), lowText: "0K", highText: "16K",
                       note: "Your average daily steps over the last 7 days. Around 7,000 a day is where it stops adding to your age.",
                       missing: "Needs steps from at least 3 days.", trend: .steps),
            ]),
            ("Fitness", [
                Factor(id: "vo2max", title: "VO₂ max", value: i.vo2max, valueText: i.vo2max.map { n($0) } ?? "", unit: "ml/kg/min", range: 15...70,
                       reference: expectedVO2, referenceText: n(expectedVO2), higherIsBetter: true,
                       years: r.years("vo2max"), lowText: "15", highText: "70",
                       note: "Your cardio fitness, entered by you or worked out with your waist, against the typical figure for your age and sex.",
                       missing: "Enter a VO₂ max, or add your waist so it can be worked out.", trend: .vo2max),
                Factor(id: "rhr", title: "Resting HR", value: i.restingHR, valueText: i.restingHR.map { n($0) } ?? "", unit: "bpm", range: 40...80,
                       reference: VitalityEngine.restingHRBreakEven, referenceText: n(VitalityEngine.restingHRBreakEven) + " bpm", higherIsBetter: false,
                       years: r.years("rhr"), lowText: "40bpm", highText: "80bpm",
                       note: "The median of your resting heart rate over the last 7 days. Around 60 bpm is where it stops adding to your age; lower takes years off.",
                       missing: "Needs resting heart rate from your nights.", trend: .rhr),
                Factor(id: "leanMass", title: "Lean body mass", value: i.leanMassPct, valueText: i.leanMassPct.map { n($0, 1) } ?? "", unit: "%", range: 60...90,
                       reference: VitalityEngine.leanMassBreakEven, referenceText: n(VitalityEngine.leanMassBreakEven) + "%", higherIsBetter: true,
                       years: r.years("leanMass"), lowText: "60%", highText: "90%",
                       note: "The share of your body that is not fat, from your last 30 days of body fat. From 78% up it adds nothing; below that it adds to your age.",
                       missing: "Needs body fat from Apple Health or a measurement you add.", trend: .leanBodyMass),
            ]),
        ]
    }

    @ViewBuilder private func factors(_ r: NunaHealthspanResult) -> some View {
        ForEach(Array(groups(r).enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 14) {
                sectionHead(group.title)
                card {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, f in
                        if index > 0 { NunaDivider().padding(.horizontal, 18) }
                        factorRow(f)
                    }
                }
            }
        }
        Text("\(r.inputsUsed) of 9 inputs").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, -14)
    }

    /// A section's name large, and at its right what the two markers on the bars mean.
    private func sectionHead(_ t: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            heading(t)
            Spacer(minLength: 4)
            legendMark("arrowtriangle.down.fill", "Last 7 days")
            Rectangle().fill(NunaPalette.textMuted.opacity(0.5)).frame(width: 1, height: 18)
            legendMark("arrowtriangle.up.fill", "Break-even")
        }
    }

    private func legendMark(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.nuna(size: 10))
            Text(text).font(.nuna(size: 13.5, weight: .regular)).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }.foregroundStyle(NunaPalette.textSecondary)
    }

    /// The rows of a section on one card, each full width, so an open row can have its own, darker band as on the reference.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NunaCard(small: true, padding: EdgeInsets()) {
            VStack(spacing: 0) { content() }.clipShape(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        }
    }

    private func yearsText(_ y: Double) -> String {
        abs(y) < 0.05 ? "0.0" : String(format: "%+.1f", locale: AppLanguage.activeLocale, y)
    }
    private func yearsColor(_ y: Double) -> Color { y > 0.05 ? NunaPalette.caution : (y < -0.05 ? NunaPalette.charge : NunaPalette.textSecondary) }

    /// Better (1), worse (-1) or level (0) than the break-even, from the years it adds.
    private func standing(_ f: Factor) -> Int? {
        guard let y = f.years else { return nil }
        return y < -0.05 ? 1 : (y > 0.05 ? -1 : 0)
    }

    /// What stands at the right of the bar: the years the row adds to or takes off the age, as on the reference.
    private func sideFigure(_ f: Factor) -> some View {
        VStack(spacing: 2) {
            if let y = f.years {
                Text(verbatim: yearsText(y)).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(yearsColor(y)).lineLimit(1).minimumScaleFactor(0.7).textCase(nil)
            } else {
                Text(verbatim: "–").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            Text("years").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(width: 66)
    }

    @ViewBuilder private func factorRow(_ f: Factor) -> some View {
        if let value = f.value { dataRow(f, value: value) } else { missingRow(f) }
    }

    private func rowTitle(_ f: Factor, chevron: String?) -> some View {
        HStack {
            Text(f.title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            if let chevron { Image(systemName: chevron).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
        }
        .frame(minHeight: 50).contentShape(Rectangle())
    }

    /// Shut, a row is its name, the reading on a thin bar and the years. Open, the bar becomes tall blocks with the reading and the break-even named at their
    /// markers, and under it come what it means for the age and the way to its trend.
    private func dataRow(_ f: Factor, value: Double) -> some View {
        let open = opened.contains(f.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.22)) { if open { opened.remove(f.id) } else { opened.insert(f.id) } } } label: {
                rowTitle(f, chevron: open ? "chevron.up" : "chevron.down")
            }.buttonStyle(.plain).accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 14) {
                NunaFitnessScale(value: value, valueText: f.valueText, unit: f.unit, reference: f.reference, referenceText: f.referenceText, range: f.range,
                                 higherIsBetter: f.higherIsBetter, low: f.lowText, high: f.highText, expanded: open)
                sideFigure(f)
            }
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    if let better = standing(f) {
                        Text(better > 0 ? "Outperforming" : (better < 0 ? "Underperforming" : "On par"))
                            .font(.nuna(size: 21, weight: .medium)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    }
                    Text(f.note).font(.nuna(size: 16.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NavigationLink(value: NunaTodayRoute.trend(f.trend)) {
                        HStack(spacing: 10) {
                            Text("View trend").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            Image(systemName: "arrow.right").font(.nuna(size: 16, weight: .regular))
                        }
                        .foregroundStyle(NunaPalette.recoveryBlue).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.top, 10).padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
        // An open row sits on a darker band than the rows around it.
        .background(open ? NunaPalette.canvas.opacity(0.45) : Color.clear)
    }

    /// An input with no data for the week: its name, an empty scale, a dash for the years, and what it needs. It is left out of the age.
    private func missingRow(_ f: Factor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowTitle(f, chevron: nil)
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 3) { ForEach(0..<10, id: \.self) { _ in Rectangle().fill(NunaPalette.textMuted.opacity(0.25)).frame(height: 5) } }.clipShape(Capsule())
                sideFigure(f)
            }
            Text("No data").font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(f.missing).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textCase(nil)
            if f.id == "vo2max", profile.waistCm <= 0 {
                Button { showWaist = true } label: {
                    HStack(spacing: 10) {
                        Text("Unlock VO₂max").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 16, weight: .regular))
                    }
                    .foregroundStyle(NunaPalette.recoveryBlue).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 14)
    }

    // MARK: Trends

    /// The calendar age on a day, in years and tenths from the date of birth, so the line beside the age rises as the weeks go.
    private func calendarAge(on day: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: profile.dateOfBirth, to: day).day ?? 0
        return Double(days) / 365.25
    }

    private var trends: some View {
        let ages: [(date: Date, value: Double)] = bodyAges.suffix(7).compactMap { r in date(r.day).map { (date: $0, value: r.value) } }
        var paces: [(date: Date, value: Double)] = []
        let all = readings
        if all.count >= PaceOfAging.minReadings {
            for i in max(PaceOfAging.minReadings - 1, all.count - 7)..<all.count {
                if let p = PaceOfAging.compute(Array(all.prefix(i + 1))) { paces.append((Date(timeIntervalSince1970: all[i].time), p.pace)) }
            }
        }
        return VStack(alignment: .leading, spacing: 14) {
            heading("Trend view")
            if ages.count >= 2 {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        trendHead("Body age trend", .fitnessAge)
                        HStack(spacing: 18) {
                            legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).frame(width: 14, height: 14), "Your Body age")
                            legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.textPrimary).frame(width: 14, height: 14), "Calendar age")
                        }
                        NunaLine2Chart(points: ages, color: tint, decimals: 1, reference: profile.age > 0 ? ages.map { (date: $0.date, value: calendarAge(on: $0.date)) } : [],
                                       referenceColor: NunaPalette.textPrimary, referenceDecimals: 1, lastValueOnly: true, weekdayAxis: false, height: 200)
                    }
                }
            }
            if paces.count >= 2 {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        trendHead("Pace of aging trend", .paceOfAging)
                        NunaLine2Chart(points: paces, color: NunaPalette.recoveryBlue, decimals: 1, reference: paces.map { (date: $0.date, value: 1.0) },
                                       referenceColor: NunaPalette.textPrimary, labelsReference: false, marksReference: false, lastValueOnly: true, weekdayAxis: false, height: 200)
                    }
                }
            }
        }
    }

    /// The title of a trend card, with the arrow that opens that reading's own Trend view.
    private func trendHead(_ title: LocalizedStringKey, _ page: NunaTrendPage) -> some View {
        NavigationLink(value: NunaTodayRoute.trend(page)) {
            HStack { cap(title); Spacer(minLength: 0); Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legend<S: View>(_ mark: S, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 7) { mark; Text(text).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary) }
    }

    // MARK: Not ready

    /// No age yet: fewer than three of the nine inputs have data (or the profile has no age). The inputs that do have data are still listed below.
    private var notReady: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not ready yet").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(profile.age > 0 ? "Body age needs at least 3 of its 9 inputs from the last 7 days. Wear your strap for a few more days."
                                     : "Body age needs your age in your profile and at least 3 of its 9 inputs from the last 7 days.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - The scale bar

/// A reading on a scale of ten blocks, as on the reference. Shut, the blocks are thin lines (amber at the unfavourable end, grey in the middle, green at the
/// favourable one) with the reading over a white marker, the break-even under a grey one, and the ends named under the bar. Open, each block is a tall dark
/// block with its bright line on top, the ends are named inside it, and the markers carry their names: the reading's caption and figure above, the break-even's figure and caption below.
private struct NunaFitnessScale: View {
    let value: Double
    let valueText: String
    let unit: String
    let reference: Double?
    let referenceText: String?
    let range: ClosedRange<Double>
    let higherIsBetter: Bool
    let low: String
    let high: String
    let expanded: Bool

    private func fraction(_ v: Double) -> CGFloat { CGFloat(min(max((v - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)) }

    /// Block i from the left, the favourable end at the right unless lower is better.
    private func color(_ i: Int) -> Color {
        let good = higherIsBetter ? i : 9 - i
        switch good {
        case 0...3: return NunaPalette.caution.opacity(1.0 - Double(3 - good) * 0.1)
        case 4...5: return NunaPalette.textMuted.opacity(0.6)
        default: return NunaPalette.charge.opacity(0.65 + Double(good - 6) * 0.12)
        }
    }

    private var height: CGFloat { expanded ? (reference != nil ? 190 : 124) : 90 }

    /// The figure with its unit smaller and grey after it.
    private func figure(_ text: String, _ unit: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: text).font(.nuna(size: size, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: size - 4, weight: .regular)).foregroundStyle(NunaPalette.textSecondary) }
        }
        .textCase(nil).fixedSize()
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = min(max(w * fraction(value), 0), w)
            let barTop: CGFloat = expanded ? 76 : 46
            ZStack(alignment: .topLeading) {
                if expanded {
                    Text("Last 7 days").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize()
                        .position(x: min(max(x, 56), max(w - 56, 56)), y: 10)
                    figure(valueText, unit, size: 22).position(x: min(max(x, 60), max(w - 60, 60)), y: 36)
                    Image(systemName: "arrowtriangle.down.fill").font(.nuna(size: 15)).foregroundStyle(NunaPalette.textPrimary).position(x: x, y: 62)
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { i in
                            Rectangle().fill(color(i).opacity(0.14)).frame(height: 36).overlay(alignment: .top) { Rectangle().fill(color(i)).frame(height: 3) }
                        }
                    }
                    .frame(width: w).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).offset(y: barTop)
                    HStack {
                        Text(verbatim: low).foregroundStyle(color(0))
                        Spacer()
                        Text(verbatim: high).foregroundStyle(color(9))
                    }
                    .font(.nuna(size: 14, weight: .bold)).textCase(nil)
                    .padding(.horizontal, 7).padding(.bottom, 6).frame(width: w, height: 36, alignment: .bottom).offset(y: barTop)
                    if let reference, let referenceText {
                        Image(systemName: "arrowtriangle.up.fill").font(.nuna(size: 13)).foregroundStyle(NunaPalette.textSecondary).position(x: w * fraction(reference), y: 126)
                        Text(verbatim: referenceText).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize()
                            .position(x: min(max(w * fraction(reference), 50), max(w - 50, 50)), y: 150)
                        Text("Break-even").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize()
                            .position(x: min(max(w * fraction(reference), 64), max(w - 64, 64)), y: 172)
                    }
                } else {
                    figure(valueText, unit, size: 19).position(x: min(max(x, 44), max(w - 44, 44)), y: 12)
                    Image(systemName: "arrowtriangle.down.fill").font(.nuna(size: 14)).foregroundStyle(NunaPalette.textPrimary).position(x: x, y: 34)
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { i in Rectangle().fill(color(i)).frame(height: 5) }
                    }
                    .frame(width: w).clipShape(Capsule()).offset(y: barTop)
                    if let reference {
                        Image(systemName: "arrowtriangle.up.fill").font(.nuna(size: 12)).foregroundStyle(NunaPalette.textSecondary).position(x: w * fraction(reference), y: 62)
                    }
                    HStack {
                        Text(verbatim: low).foregroundStyle(color(0))
                        Spacer()
                        Text(verbatim: high).foregroundStyle(color(9))
                    }
                    .font(.nuna(size: 14, weight: .bold)).textCase(nil).frame(width: w).offset(y: 70)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: valueText + " " + unit))
    }
}

// MARK: - The info page

/// What the orb's colour and the pace mean, one short page for each, and how the number is worked out.
private struct NunaFitnessAgeInfoSheet: View {
    let pace: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page { let tint: Color; let title: LocalizedStringKey; let text: LocalizedStringKey; let ruler: Double?; var shape = 0.12; var orb = true }

    private var pages: [Page] {
        [Page(tint: NunaPalette.caution, title: "An older Body age", text: "Your Body age is above your calendar age. Small, consistent habits can bring it down.", ruler: nil),
         Page(tint: NunaPalette.recoveryBlue, title: "On track", text: "Your Body age is close to your calendar age, a sign of balanced fitness. Keep up your current habits.", ruler: nil),
         Page(tint: NunaPalette.charge, title: "A younger Body age", text: "Your Body age is below your calendar age, reflecting healthy habits. Continue them.", ruler: nil),
         Page(tint: NunaPalette.textSecondary, title: "Your pace of aging", text: "Pace of aging shows how quickly your Body age is changing, so you can see how your recent habits shape it over time.", ruler: pace, shape: NunaFitnessAgeTone.irregularity(pace: pace)),
         Page(tint: NunaPalette.charge, title: "Trending slower", text: "Your pace is below 1.0x, or even negative. Your recent habits are lowering your Body age.", ruler: -1, shape: 0),
         Page(tint: NunaPalette.recoveryBlue, title: "Balanced", text: "Your pace is near 1.0x. Your Body age rises steadily, at the same rate as your calendar age.", ruler: 1, shape: 0.5),
         Page(tint: NunaPalette.caution, title: "Trending faster", text: "Your pace is above 1.0x. Your current habits may be pushing your Body age up. Small, healthy habits can shift the trend.", ruler: 3, shape: 1),
         Page(tint: NunaPalette.textSecondary, title: "How it's calculated",
              text: "Nine inputs from the last 7 days (resting heart rate, VO₂ max, hours and consistency of sleep, steps, time in heart-rate zones 1–3 and 4–5, strength training and lean body mass) are each read against a break-even point. The years each adds or takes away are added to your calendar age. The break-evens come from published mortality studies; lean body mass and a few others follow the WHOOP Healthspan page.",
              ruler: nil, orb: false)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 38)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(alignment: .leading, spacing: 18) {
                        if p.orb {
                            NunaFitnessOrb(tint: p.tint, size: 300, irregularity: p.shape) { EmptyView() }.frame(maxWidth: .infinity)
                            if i >= 3 { NunaPaceDial(value: p.ruler) } else { ageBar(i) }
                        } else {
                            Spacer(minLength: 60)
                        }
                        Text(p.title).font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Text(p.text).font(.nuna(size: 15.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 30)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Text("A wellness estimate, not a biological age or a medical assessment.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                .multilineTextAlignment(.center).padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 16).textCase(nil)
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    /// Younger at the left, older at the right, a marker where this page's case sits.
    private func ageBar(_ i: Int) -> some View {
        let f: CGFloat = i == 2 ? 0.08 : (i == 1 ? 0.5 : 0.92)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Capsule().fill(LinearGradient(colors: [NunaPalette.charge, NunaPalette.recoveryBlue, NunaPalette.caution], startPoint: .leading, endPoint: .trailing)).frame(height: 4).offset(y: 22)
                Image(systemName: "arrowtriangle.down.fill").font(.nuna(size: 14)).foregroundStyle(NunaPalette.textPrimary).position(x: geo.size.width * f, y: 10)
            }
        }
        .frame(height: 40)
    }
}
#endif
