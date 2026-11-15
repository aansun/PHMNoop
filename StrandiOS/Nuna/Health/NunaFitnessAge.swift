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

/// The fitness age page (docs/FITNESS_AGE.md): the number with its gap to the real age, the pace of aging, what the number is made of, and how it moved.
///
/// It is a comparison, not a biological age, and it says only what the model uses. The model has four inputs: age, sex, the median resting heart rate of the
/// last 7 days and a physical activity index built from the week's training. So the page has two things that move the number (resting heart rate and
/// activity, each in years against an average person of the same age) and one that does not (the VO₂max estimate, shown for reference).
/// A week is the Sunday to Saturday the stored reading belongs to; the arrows at the top step through the weeks that were stored.
struct NunaFitnessAgeView: View {
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var series: [(day: String, value: Double)] = []
    @State private var vo2Series: [(day: String, value: Double)] = []
    @State private var loaded = false
    /// The stored week on show; nil is the latest.
    @State private var picked: Int?
    @State private var scrollY: CGFloat = 0
    @State private var restY: CGFloat?
    @State private var opened: Set<String> = []
    @State private var showInfo = false
    @State private var showWaist = false

    // MARK: Weeks

    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    private var index: Int { series.isEmpty ? 0 : min(max(picked ?? series.count - 1, 0), series.count - 1) }
    private var current: (day: String, value: Double)? { series.isEmpty ? nil : series[index] }
    private var isLatest: Bool { index == series.count - 1 }

    /// The 7 days that end on the Saturday the reading is stored under.
    private func window(endingOn day: String) -> [DailyMetric] {
        guard let end = date(day), let start = Calendar.current.date(byAdding: .day, value: -6, to: end) else { return [] }
        let from = Self.dayParser.string(from: start)
        return repo.days.filter { $0.day >= from && $0.day <= day }
    }

    private var days: [DailyMetric] { current.map { window(endingOn: $0.day) } ?? [] }
    private var rhrValues: [Double] { days.compactMap { $0.restingHr }.map(Double.init) }
    private var medianRHR: Double? {
        let v = rhrValues.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }
    private var activeStrains: [Double] { days.compactMap { $0.strain }.filter { $0 >= 30 } }
    private var meanActiveStrain: Double { activeStrains.isEmpty ? 0 : activeStrains.reduce(0, +) / Double(activeStrains.count) }
    private var paIndex: Double {
        FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: activeStrains.count, meanActiveStrain: meanActiveStrain)
    }

    /// Years of fitness age that resting heart rate adds (older, positive) or takes away (younger, negative), against an average person of the same age.
    private var rhrYears: Double? {
        guard profile.age > 0, let rhr = medianRHR else { return nil }
        return FitnessAgeEngine.fitnessAge(age: Double(profile.age), sex: profile.sex, restingHR: rhr, paIndex: FitnessAgeEngine.paiReference) - Double(profile.age)
    }
    private var activityYears: Double? {
        guard profile.age > 0, medianRHR != nil else { return nil }
        return FitnessAgeEngine.fitnessAge(age: Double(profile.age), sex: profile.sex, restingHR: FitnessAgeEngine.restingHRReference, paIndex: paIndex) - Double(profile.age)
    }

    /// Resting heart rate and activity add up to the distance between the fitness age and the calendar age, apart from the ends of the scale (20 and 80) and
    /// rounding. When the days stored now give a different sum than the reading stored for that week (the week was read from other data, or the history was
    /// rescored since), the years are left out rather than set beside a headline they contradict.
    private var yearsAgree: Bool {
        guard let current, profile.age > 0, let a = rhrYears, let b = activityYears else { return false }
        return abs((a + b) - (current.value - Double(profile.age))) <= 1.5
    }

    /// Calendar age minus fitness age in whole years; positive is younger.
    private var gap: Int? {
        guard let current, profile.age > 0 else { return nil }
        return Int((Double(profile.age) - current.value).rounded())
    }
    private var tint: Color { NunaFitnessAgeTone.tint(gap: gap) }
    /// The outline of the orb follows the pace of aging: a ring when it is slow, an amoeba when it is fast.
    private var orbShape: Double { NunaFitnessAgeTone.irregularity(pace: pace?.pace) }

    private var readings: [PaceOfAging.Reading] {
        series.compactMap { r in date(r.day).map { PaceOfAging.Reading(time: $0.timeIntervalSince1970, fitnessAge: r.value) } }
    }
    /// The pace as it stood at the week on show, from the readings up to and including it.
    private var pace: PaceOfAging.Result? { PaceOfAging.compute(Array(readings.prefix(index + 1))) }

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
                        if current != nil {
                            hero
                            paceSection
                            factors
                            trends
                        } else {
                            notReady
                        }
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 60).padding(.bottom, 120)
                }
            }
            .modifier(NunaFitnessScrollOffset(offset: $scrollY))
            .onPreferenceChange(NunaFitnessScrollKey.self) { y in
                if restY == nil { restY = y }
                if #unavailable(iOS 18.0) { scrollY = (restY ?? y) - y }
            }
            .scrollIndicators(.hidden)
            if current != nil { compactHeader.opacity(collapse).allowsHitTesting(false) }
            topBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) {
            series = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 400)
            vo2Series = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: 400)
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

    /// The way back, the page's name with when it updates next, and the info page.
    private var topBar: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("Fitness age").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if current != nil {
                    Text(nextUpdate).font(.nuna(size: 11.5, weight: .semibold)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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
                }.buttonStyle(.plain).accessibilityLabel(Text("About fitness age"))
            }
        }
        .padding(.horizontal, 12).frame(height: 56)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0.95), NunaPalette.canvas.opacity(0.95 * collapse)], startPoint: .top, endPoint: .bottom))
    }

    /// "Next update in 3 days": the reading is stored on Saturday and refines through the week.
    private var nextUpdate: String {
        let weekday = Calendar.current.component(.weekday, from: Date())   // Sunday 1 ... Saturday 7
        let left = (7 - weekday + 7) % 7
        return left == 0 ? String(localized: "Updates today") : (left == 1 ? String(localized: "Next update in 1 day") : String(localized: "Next update in \(left) days"))
    }

    /// The figure and the two statements, small, once the big one has scrolled off: the gap at the left, the pace at the right.
    private var compactHeader: some View {
        HStack(alignment: .center) {
            VStack(spacing: 3) {
                Text(verbatim: gap.map { String(abs($0)) } ?? "–").font(.nuna(size: 32, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restLight).textCase(nil)
                Text(gapCaption).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
            // Drawn larger than the room it takes, so its glow is not cut off at the edge of the drawing.
            NunaFitnessOrb(tint: tint, size: 170, irregularity: orbShape) { NunaFitnessOrbCenter(value: current?.value, gap: nil, numberSize: 30, captionSize: 10.5, showsGap: false) }
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

    private var weekRange: String {
        guard let current, let end = date(current.day), let start = Calendar.current.date(byAdding: .day, value: -6, to: end) else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: start) + " - " + f.string(from: end)
    }

    private func arrow(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                arrow("chevron.left", enabled: index > 0) { picked = index - 1 }.accessibilityLabel(Text("Earlier week"))
                Text(verbatim: weekRange).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                arrow("chevron.right", enabled: !isLatest) { picked = index + 1 }.accessibilityLabel(Text("Later week"))
                Spacer()
            }
            // Drawn over a room as wide as the page, so an orb a little wider than the page does not widen the page.
            Color.clear.frame(maxWidth: .infinity).frame(height: 350)
                .overlay { NunaFitnessOrb(tint: tint, size: 380, irregularity: orbShape) { NunaFitnessOrbCenter(value: current?.value, gap: gap, numberSize: 48) } }
                .padding(.top, 4)
        }
    }

    // MARK: Pace of aging

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            cap("Pace of aging")
            if let pace {
                NunaPaceDial(value: pace.pace, showsValue: true)
            } else {
                Text(verbatim: String(localized: "Pace of aging appears after 6 weekly readings. You have \(index + 1) so far."))
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                NunaPaceDial(value: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: What it is made of

    /// One thing on the page that is read against a scale: where it is, where an average person of the same age is, and what it adds to the age.
    private struct Factor: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let value: Double
        /// The figure and its unit, set apart because the unit is smaller and grey.
        let valueText: String
        let unit: String
        let range: ClosedRange<Double>
        let reference: Double?
        let referenceText: String?
        let higherIsBetter: Bool
        /// Years it adds (older, positive) or takes away (younger, negative); nil for a figure the age does not use, or when the years would contradict the headline.
        let years: Double?
        let lowText: String
        let highText: String
        let note: LocalizedStringKey
        /// The stored metric whose trend "View trend" opens, when there is one.
        var metricKey: String?
        /// Decimals of the difference from the average person, which stands where the years would when they cannot be said.
        var deltaDecimals = 0
    }

    private var restingFactor: Factor? {
        guard let rhr = medianRHR, let rawYears = rhrYears else { return nil }
        return Factor(id: "rhr", title: "Resting HR", value: rhr, valueText: String(format: "%.0f", rhr), unit: "bpm", range: 40...80,
                      reference: FitnessAgeEngine.restingHRReference, referenceText: String(format: "%.0f bpm", FitnessAgeEngine.restingHRReference), higherIsBetter: false,
                      years: yearsAgree ? rawYears : nil, lowText: "40bpm", highText: "80bpm",
                      note: "The median of your resting heart rate over these 7 days, against 65 bpm for an average person of your age. A lower resting heart rate is the sign of a fitter heart.",
                      metricKey: "rhr", deltaDecimals: 0)
    }

    private var activityFactor: Factor? {
        guard medianRHR != nil, let rawYears = activityYears else { return nil }
        return Factor(id: "activity", title: "Physical activity", value: paIndex, valueText: String(format: "%.1f", locale: AppLanguage.activeLocale, paIndex), unit: "", range: 0...15,
                      reference: FitnessAgeEngine.paiReference, referenceText: String(format: "%.1f", locale: AppLanguage.activeLocale, FitnessAgeEngine.paiReference), higherIsBetter: true,
                      years: yearsAgree ? rawYears : nil, lowText: "0", highText: "15",
                      note: "An index from 0 to 15 built from how many days you trained this week and how hard. An average person of your age sits near 5.",
                      deltaDecimals: 1)
    }

    /// The VO₂max the weekly job stored for the week on show, or the latest before it.
    private var vo2: Double? {
        guard let day = current?.day else { return nil }
        return vo2Series.last(where: { $0.day <= day })?.value
    }

    private var vo2Factor: Factor? {
        guard let vo2 else { return nil }
        return Factor(id: "vo2", title: "VO₂max", value: vo2, valueText: String(format: "%.0f", vo2), unit: "ml/kg/min", range: 15...70, reference: nil, referenceText: nil, higherIsBetter: true,
                      years: nil, lowText: "15", highText: "70",
                      note: profile.waistCm > 0 ? "Worked out from your age, resting heart rate, activity and waist. It is shown for reference and does not change your fitness age."
                                                 : "A rougher estimate from your heart rate. Add your waist for a sharper one. It is shown for reference and does not change your fitness age.",
                      metricKey: "vo2max_est")
    }

    @ViewBuilder private var factors: some View {
        if let rhr = restingFactor, let activity = activityFactor {
            VStack(alignment: .leading, spacing: 14) {
                sectionHead("Fitness")
                card {
                    factorRow(rhr)
                    if let v = vo2Factor { NunaDivider().padding(.horizontal, 18); factorRow(v) }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                sectionHead("Activity")
                card { factorRow(activity) }
            }
        } else {
            dataCard
        }
    }

    /// A section's name large, and at its right what the two markers on the bars mean.
    private func sectionHead(_ t: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            heading(t)
            Spacer(minLength: 4)
            legendMark("arrowtriangle.down.fill", "This week")
            Rectangle().fill(NunaPalette.textMuted.opacity(0.5)).frame(width: 1, height: 18)
            legendMark("arrowtriangle.up.fill", "Average person")
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

    /// Better (1), worse (-1) or level (0) than an average person: from the years when they are said, otherwise from how far the reading is from the average
    /// person's. nil for a figure with neither (VO₂max).
    private func standing(_ f: Factor) -> Int? {
        if let y = f.years { return y < -0.05 ? 1 : (y > 0.05 ? -1 : 0) }
        guard let r = f.reference else { return nil }
        let d = (f.value - r) * (f.higherIsBetter ? 1 : -1)
        let level = (f.range.upperBound - f.range.lowerBound) * 0.03
        return d > level ? 1 : (d < -level ? -1 : 0)
    }

    /// What stands at the right of the bar: the years the row adds to or takes off the fitness age, as on the reference. When those years do not add up to the week's
    /// reading (see `yearsAgree`) it is how far the reading is from the average person's instead, so the right is never empty where there is something true to say. A
    /// figure the age does not use has neither, and its bar takes the whole width.
    @ViewBuilder private func sideFigure(_ f: Factor) -> some View {
        if let y = f.years {
            VStack(spacing: 2) {
                Text(verbatim: yearsText(y)).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(yearsColor(y)).lineLimit(1).minimumScaleFactor(0.7).textCase(nil)
                Text("years").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            .frame(width: 66)
        } else if let r = f.reference, let better = standing(f) {
            VStack(spacing: 2) {
                Text(verbatim: abs(f.value - r) < 0.05 ? "0" : String(format: "%+.\(f.deltaDecimals)f", locale: AppLanguage.activeLocale, f.value - r))
                    .font(.nuna(size: 26, weight: .bold, design: NunaType.design)).lineLimit(1).minimumScaleFactor(0.7).textCase(nil)
                    .foregroundStyle(better > 0 ? NunaPalette.charge : (better < 0 ? NunaPalette.caution : NunaPalette.textSecondary))
                Text("vs average").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 66)
        }
    }

    /// Shut, a row is its name, the reading on a thin bar and the years. Open, the bar becomes tall blocks with the reading and the average person named at their
    /// markers, and under it come what it means for the age and the way to its trend.
    private func factorRow(_ f: Factor) -> some View {
        let open = opened.contains(f.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.22)) { if open { opened.remove(f.id) } else { opened.insert(f.id) } } } label: {
                HStack {
                    Text(f.title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(minHeight: 50).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 14) {
                NunaFitnessScale(value: f.value, valueText: f.valueText, unit: f.unit, reference: f.reference, referenceText: f.referenceText, range: f.range,
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
                    if let key = f.metricKey, let metric = MetricCatalog.metric(key: key, source: "my-whoop") {
                        NavigationLink(value: NunaTodayRoute.metric(metric)) {
                            HStack(spacing: 10) {
                                Text("View trend").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                Image(systemName: "arrow.right").font(.nuna(size: 16, weight: .regular))
                            }
                            .foregroundStyle(NunaPalette.recoveryBlue).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if f.id == "vo2", profile.waistCm <= 0 {
                        Button { showWaist = true } label: {
                            HStack(spacing: 10) {
                                Text("Unlock VO₂max").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                Image(systemName: "arrow.right").font(.nuna(size: 16, weight: .regular))
                            }
                            .foregroundStyle(NunaPalette.recoveryBlue).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 10).padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
        // An open row sits on a darker band than the rows around it.
        .background(open ? NunaPalette.canvas.opacity(0.45) : Color.clear)
    }

    // MARK: Trends

    /// The calendar age on a day, in years and tenths from the date of birth, so the line beside the fitness age rises as the weeks go.
    private func calendarAge(on day: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: profile.dateOfBirth, to: day).day ?? 0
        return Double(days) / 365.25
    }

    private var trends: some View {
        let fitness: [(date: Date, value: Double)] = series.suffix(7).compactMap { r in date(r.day).map { (date: $0, value: r.value) } }
        var paces: [(date: Date, value: Double)] = []
        let all = readings
        if all.count >= PaceOfAging.minReadings {
            for i in max(PaceOfAging.minReadings - 1, all.count - 7)..<all.count {
                if let p = PaceOfAging.compute(Array(all.prefix(i + 1))) { paces.append((Date(timeIntervalSince1970: all[i].time), p.pace)) }
            }
        }
        return VStack(alignment: .leading, spacing: 14) {
            heading("Trend view")
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    trendHead("Fitness age trend", .fitnessAge)
                    HStack(spacing: 18) {
                        legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).frame(width: 14, height: 14), "Your fitness age")
                        legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.textPrimary).frame(width: 14, height: 14), "Calendar age")
                    }
                    NunaLine2Chart(points: fitness, color: tint, decimals: 1, reference: profile.age > 0 ? fitness.map { (date: $0.date, value: calendarAge(on: $0.date)) } : [],
                                   referenceColor: NunaPalette.textPrimary, referenceDecimals: 1, lastValueOnly: true, weekdayAxis: false, height: 200)
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

    private var dataCard: some View {
        let nights = rhrValues.count
        let ok = nights >= FitnessAgeEngine.minCoverageDays
        return NunaCard(small: true) {
            NunaListRow(ok ? "Enough data" : "Not enough data yet", subtitle: LocalizedStringKey(String(localized: "\(nights) of 7 nights read. Minimum \(FitnessAgeEngine.minCoverageDays).")),
                        systemImage: ok ? "checkmark" : "hourglass") {
                NunaChip(ok ? "Ready" : "Waiting", color: ok ? NunaPalette.charge : NunaPalette.warning)
            }
        }
    }

    private var notReady: some View {
        VStack(spacing: 20) {
            NunaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loaded ? "Not ready yet" : " ").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Fitness age needs your age, your sex and resting heart rate from at least 4 nights. It updates once a week.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if loaded { dataCard }
        }
    }
}

// MARK: - The scale bar

/// A reading on a scale of ten blocks, as on the reference. Shut, the blocks are thin lines (amber at the unfavourable end, grey in the middle, green at the
/// favourable one) with the reading over a white marker, the average person under a grey one, and the ends named under the bar. Open, each block is a tall dark
/// block with its bright line on top, the ends are named inside it, and the markers carry their names: the reading's caption and figure above, the average
/// person's figure and caption below.
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
                    Text("This week").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize()
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
                        Text("Average person").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize()
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
        [Page(tint: NunaPalette.caution, title: "An older fitness age", text: "Your fitness age is above your calendar age. Small, consistent habits can bring it down.", ruler: nil),
         Page(tint: NunaPalette.recoveryBlue, title: "On track", text: "Your fitness age is close to your calendar age, a sign of balanced fitness. Keep up your current habits.", ruler: nil),
         Page(tint: NunaPalette.charge, title: "A younger fitness age", text: "Your fitness age is below your calendar age, reflecting good heart and lung fitness. Continue your healthy habits.", ruler: nil),
         Page(tint: NunaPalette.textSecondary, title: "Your pace of aging", text: "Pace of aging shows how quickly your fitness age is changing, so you can see how your recent habits shape it over time.", ruler: pace, shape: NunaFitnessAgeTone.irregularity(pace: pace)),
         Page(tint: NunaPalette.charge, title: "Trending slower", text: "Your pace is below 1.0x, or even negative. Your recent habits are lowering your fitness age.", ruler: -1, shape: 0),
         Page(tint: NunaPalette.recoveryBlue, title: "Balanced", text: "Your pace is near 1.0x. Your fitness age rises steadily, at the same rate as your calendar age.", ruler: 1, shape: 0.5),
         Page(tint: NunaPalette.caution, title: "Trending faster", text: "Your pace is above 1.0x. Your current habits may be pushing your fitness age up. Small, healthy habits can shift the trend.", ruler: 3, shape: 1),
         Page(tint: NunaPalette.textSecondary, title: "How it's calculated",
              text: "Your age, sex, the median resting heart rate of the last 7 days and a physical activity index built from your recent training are compared with an average person of your age. The gap is turned into years. Non-exercise model (Nes 2011, HUNT), updated every Saturday.",
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
            Text("A fitness comparison, not a biological age or a medical assessment.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
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
