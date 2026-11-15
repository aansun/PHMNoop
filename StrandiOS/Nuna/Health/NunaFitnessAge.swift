#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// How far the page has been scrolled, read from the content's own position.
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
/// activity, each in years against an average person of the same age) and one that does not (the VO₂max estimate, shown as information).
/// A week is the Sunday to Saturday the stored reading belongs to; the arrows at the top step through the weeks that were stored.
struct NunaFitnessAgeView: View {
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
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

    private var gap: Int? {
        guard let current, profile.age > 0 else { return nil }
        return Int((Double(profile.age) - current.value).rounded())
    }
    private var tint: Color { (gap ?? 0) > 0 ? NunaPalette.charge : ((gap ?? 0) < 0 ? NunaPalette.warning : NunaPalette.textSecondary) }

    private var readings: [PaceOfAging.Reading] {
        series.compactMap { r in date(r.day).map { PaceOfAging.Reading(time: $0.timeIntervalSince1970, fitnessAge: r.value) } }
    }
    /// The pace as it stood at the week on show, from the readings up to and including it.
    private var pace: PaceOfAging.Result? { PaceOfAging.compute(Array(readings.prefix(index + 1))) }
    private var paceBefore: PaceOfAging.Result? { index >= 1 ? PaceOfAging.compute(Array(readings.prefix(index))) : nil }

    // MARK: Body

    /// How much of the page's own header has taken over from the big one: 0 at the top, 1 once the big figure has scrolled away.
    private var collapse: Double { min(max(Double((scrollY - 190) / 150), 0), 1) }

    var body: some View {
        ZStack(alignment: .top) {
            NunaBackdrop()
            ScrollView {
                ZStack(alignment: .top) {
                // Zero height, at the very top of the content: its place in the scroll view's own space is how far the page has gone up.
                GeometryReader { g in Color.clear.preference(key: NunaFitnessScrollKey.self, value: g.frame(in: .global).minY) }.frame(height: 0)
                VStack(spacing: NunaSpacing.section) {
                    if current != nil {
                        hero
                        paceSection
                        factors
                        trends
                        history
                        lowerCard
                    } else {
                        notReady
                    }
                    footer
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 62).padding(.bottom, 120)
                }
            }
            .modifier(NunaFitnessScrollOffset(offset: $scrollY))
            .onPreferenceChange(NunaFitnessScrollKey.self) { y in
                // The first reading is the page at rest; the page has gone up by how much it has fallen since.
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
        .sheet(isPresented: $showInfo) { NunaFitnessAgeInfoSheet(age: profile.age, pace: pace?.pace).nunaSheetChrome(detents: [.large]) }
    }

    // MARK: Header

    private func cap(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
    }

    /// The way back, the page's name with when it updates next, and the info page.
    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Fitness age").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if current != nil {
                    Text(nextUpdate).font(.nuna(size: 11, weight: .bold)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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
                        .frame(width: 34, height: 34).overlay(Circle().strokeBorder(NunaPalette.textPrimary.opacity(0.6), lineWidth: 1.5)).frame(width: 44, height: 44).contentShape(Rectangle())
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
            VStack(spacing: 2) {
                Text(verbatim: gap.map { String(abs($0)) } ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(tint)
                Text(gapCaption).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
            // Drawn larger than the room it takes, so its glow is not cut off at the edge of the drawing.
            orb(size: 210, number: 30, caption: false).frame(width: 150, height: 150)
            VStack(spacing: 2) {
                Text(verbatim: pace.map { String(format: "%.1fx", locale: AppLanguage.activeLocale, $0.pace) } ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Pace of aging").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 46).frame(height: 190, alignment: .top)
        // Solid behind the figures, so nothing of the page shows through them, and fading out only at the foot.
        .background(LinearGradient(stops: [.init(color: NunaPalette.canvas, location: 0), .init(color: NunaPalette.canvas, location: 0.8),
                                           .init(color: NunaPalette.canvas.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private var gapCaption: LocalizedStringKey { (gap ?? 0) > 0 ? "years younger" : ((gap ?? 0) < 0 ? "years older" : "about your age") }

    // MARK: Hero

    private func orb(size: CGFloat, number: CGFloat, caption: Bool) -> some View {
        NunaFitnessOrb(tint: tint, size: size) {
            VStack(spacing: 6) {
                Text(verbatim: current.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0.value) } ?? "–")
                    .font(.nuna(size: number, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(number)).foregroundStyle(NunaPalette.textPrimary)
                if caption {
                    Text("Fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    if let gap, gap != 0 { Text(nunaYearsGap(gap)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint) }
                    else if gap == 0 { Text("About your age").font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint) }
                }
            }
        }
    }

    private var weekRange: String {
        guard let current, let end = date(current.day), let start = Calendar.current.date(byAdding: .day, value: -6, to: end) else { return "" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: start) + " – " + f.string(from: end)
    }

    private func arrow(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            HStack {
                arrow("chevron.left", enabled: index > 0) { picked = index - 1 }.accessibilityLabel(Text("Earlier week"))
                Spacer()
                Text(verbatim: weekRange).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                arrow("chevron.right", enabled: !isLatest) { picked = index + 1 }.accessibilityLabel(Text("Later week"))
            }
            orb(size: 330, number: 64, caption: true)
            weeklyMove
            Text(verbatim: gap == nil ? "" : (gap == 0 ? String(localized: "Your heart and lung fitness is about the same as your age.")
                 : String(localized: "Your heart and lung fitness matches someone aged \(Int((current?.value ?? 0).rounded())), while you are \(profile.age).")))
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    /// The change since the reading before it: a pill, or "steady".
    @ViewBuilder private var weeklyMove: some View {
        if index >= 1 {
            let weekly = Int((series[index].value - series[index - 1].value).rounded())
            if weekly != 0 {
                HStack(spacing: 6) {
                    Image(systemName: weekly < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.nuna(size: 10))
                    Text(verbatim: weekly < 0 ? String(localized: "\(-weekly) yr younger than last week") : String(localized: "\(weekly) yr older than last week"))
                        .font(.nuna(size: 13, weight: .bold))
                }
                .foregroundStyle(weekly < 0 ? NunaPalette.charge : NunaPalette.warning)
                .padding(.horizontal, 14).frame(height: 32)
                .background((weekly < 0 ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            } else {
                Text("Steady since last week").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    // MARK: Pace of aging

    private var paceSection: some View {
        let move: Double? = pace.flatMap { n in paceBefore.map { n.pace - $0.pace } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                cap("Pace of aging")
                Spacer()
                if let move, abs(move) >= 0.05 {
                    HStack(spacing: 5) {
                        Image(systemName: move < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.nuna(size: 9))
                        Text(move < 0 ? "slower vs last week" : "faster vs last week").font(.nuna(size: 12, weight: .bold))
                    }
                    .foregroundStyle(move < 0 ? NunaPalette.charge : NunaPalette.warning)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background((move < 0 ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
            }
            if let pace {
                NunaPaceDial(value: pace.pace, showsValue: true)
                Text(paceText(pace)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Text(pace.confidence == .solid ? "Based on about six months of weekly readings."
                     : (pace.confidence == .building ? "Still building: the pace firms up as weeks of readings add up."
                        : "Early estimate: too few weeks to move far from 1.0x yet."))
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            } else {
                let weeks = index + 1
                Text(verbatim: weeks <= 0 ? String(localized: "Pace of aging appears after 6 weekly readings.")
                     : String(localized: "Pace of aging appears after 6 weekly readings. You have \(weeks) so far."))
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                NunaPaceDial(value: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paceText(_ r: PaceOfAging.Result) -> LocalizedStringKey {
        switch r.band {
        case .slow: return "Your fitness age is rising slower than the calendar, so you are ageing more slowly than time passes."
        case .fast: return "Your fitness age is rising faster than the calendar. Better sleep, activity and resting heart rate can bring it back."
        case .normal: return "1.0x means your fitness age moves at the same speed as the calendar. 0.0x means it holds still, and below that you are getting fitter."
        }
    }

    // MARK: What it is made of

    /// One thing on the page that is read against a scale: where it is, where an average person of the same age is, and what it adds to the age.
    private struct Factor: Identifiable {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let value: Double
        let valueText: String
        let unit: String
        let range: ClosedRange<Double>
        let reference: Double?
        let higherIsBetter: Bool
        /// Years it adds (older, positive) or takes away (younger, negative); nil for a figure the age does not use.
        let years: Double?
        let lowText: String
        let highText: String
        let note: LocalizedStringKey
        var extras: [(label: LocalizedStringKey, value: String)] = []
    }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private var restingFactor: Factor? {
        guard let rhr = medianRHR, let rawYears = rhrYears else { return nil }
        let years: Double? = yearsAgree ? rawYears : nil
        return Factor(id: "rhr", icon: "met:resting-heart-rate", title: "Resting HR", value: rhr, valueText: String(format: "%.0f", rhr), unit: "bpm", range: 40...80,
                      reference: FitnessAgeEngine.restingHRReference, higherIsBetter: false, years: years, lowText: "40 bpm", highText: "80 bpm",
                      note: "The median of your resting heart rate over these 7 days, against 65 bpm for an average person of your age. A lower resting heart rate is the sign of a fitter heart.",
                      extras: [("Nights read", "\(rhrValues.count) / 7")])
    }

    private var activityFactor: Factor? {
        guard medianRHR != nil, let rawYears = activityYears else { return nil }
        let years: Double? = yearsAgree ? rawYears : nil
        let scaled = UnitFormatter.effortDisplay(meanActiveStrain, scale: effortScale)
        return Factor(id: "activity", icon: "flame", title: "Physical activity", value: paIndex, valueText: String(format: "%.1f", locale: AppLanguage.activeLocale, paIndex), unit: "/ 15",
                      range: 0...15, reference: FitnessAgeEngine.paiReference, higherIsBetter: true, years: years, lowText: "0", highText: "15",
                      note: "An index from 0 to 15 built from how many days you trained this week and how hard. An average person of your age sits near 5.",
                      extras: [("Active days", "\(activeStrains.count) / 7"), ("Average Strain", activeStrains.isEmpty ? "–" : scaled)])
    }

    /// The VO₂max the weekly job stored for the week on show, or the latest before it.
    private var vo2: Double? {
        guard let day = current?.day else { return nil }
        return vo2Series.last(where: { $0.day <= day })?.value
    }

    private var vo2Factor: Factor? {
        guard let vo2 else { return nil }
        let female = profile.sex.lowercased() == "female"
        let see = female ? FitnessAgeEngine.seeWomen : FitnessAgeEngine.seeMen
        return Factor(id: "vo2", icon: "lungs", title: "VO₂max", value: vo2, valueText: String(format: "%.0f", vo2), unit: "ml/kg/min", range: 15...70, reference: nil, higherIsBetter: true,
                      years: nil, lowText: "15", highText: "70",
                      note: profile.waistCm > 0 ? "Worked out from your age, resting heart rate, activity and waist. It is shown for reference and does not change your fitness age."
                                                 : "A rougher estimate from your heart rate. Add your waist for a sharper one. It is shown for reference and does not change your fitness age.",
                      extras: [(profile.waistCm > 0 ? "Range" : "Method", profile.waistCm > 0 ? "±\(String(format: "%.1f", locale: AppLanguage.activeLocale, see))" : String(localized: "Estimated"))])
    }

    @ViewBuilder private var factors: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What shapes it").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer()
                legendMark("arrowtriangle.down.fill", "This week")
                legendMark("arrowtriangle.up.fill", "Average person")
            }
            if let rhr = restingFactor, let activity = activityFactor {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        factorRow(rhr)
                        NunaDivider()
                        factorRow(activity)
                        if yearsAgree, let a = rhrYears, let b = activityYears {
                            NunaDivider()
                            togetherRow(a + b)
                        }
                    }
                }
                if !yearsAgree {
                    Text("The years are left out: the days stored now do not add up to the reading of this week.")
                        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            } else {
                dataCard
            }
            if let v = vo2Factor {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { factorRow(v) }
                if profile.waistCm <= 0 {
                    Button { showWaist = true } label: {
                        NunaCard(small: true) { NunaListRow("Unlock VO₂max", description: "Weight, height and waist. Does not change the fitness age.", systemImage: "ruler", showsChevron: true) }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func legendMark(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.nuna(size: 9))
            Text(text).font(.nuna(size: 11.5, weight: .semibold)).textCase(nil)
        }.foregroundStyle(NunaPalette.textSecondary)
    }

    private func yearsText(_ y: Double) -> String {
        abs(y) < 0.05 ? "±0.0" : String(format: "%+.1f", locale: AppLanguage.activeLocale, y)
    }
    private func yearsColor(_ y: Double) -> Color { y > 0.05 ? NunaPalette.warning : (y < -0.05 ? NunaPalette.charge : NunaPalette.textSecondary) }

    private func factorRow(_ f: Factor) -> some View {
        let open = opened.contains(f.id)
        return VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { if open { opened.remove(f.id) } else { opened.insert(f.id) } } } label: {
                HStack(spacing: 10) {
                    NunaIcon(name: f.icon, size: 16).foregroundStyle(NunaPalette.textSecondary)
                    Text(f.title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 16) {
                NunaFitnessScale(value: f.value, reference: f.reference, range: f.range, higherIsBetter: f.higherIsBetter,
                             label: f.valueText + (f.unit.isEmpty ? "" : " " + f.unit), low: f.lowText, high: f.highText)
                VStack(spacing: 2) {
                    if let y = f.years {
                        Text(verbatim: yearsText(y)).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(yearsColor(y)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("years").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else if f.id == "vo2" {
                        Text("Not in the age").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center).textCase(nil)
                    }
                }
                .frame(width: 70)
            }
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    if let y = f.years {
                        Text(y < -0.05 ? "Outperforming" : (y > 0.05 ? "Underperforming" : "On par"))
                            .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    }
                    Text(f.note).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    HStack(spacing: 10) {
                        ForEach(Array(f.extras.enumerated()), id: \.offset) { _, e in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                                Text(verbatim: e.value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 12)
    }

    /// The two rows added up: how far the age is from the calendar. The headline can differ a little at the ends of the scale, where it stops at 20 and 80.
    private func togetherRow(_ total: Double) -> some View {
        HStack {
            Text("Together").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: yearsText(total)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(yearsColor(total))
            Text("years").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(minHeight: 56)
    }

    // MARK: Trends

    private var trends: some View {
        let fitness: [(Date, Double)] = series.suffix(26).compactMap { r in date(r.day).map { ($0, r.value) } }
        var paces: [(date: Date, value: Double)] = []
        let all = readings
        if all.count >= PaceOfAging.minReadings {
            for i in max(PaceOfAging.minReadings - 1, all.count - 26)..<all.count {
                if let p = PaceOfAging.compute(Array(all.prefix(i + 1))) { paces.append((Date(timeIntervalSince1970: all[i].time), p.pace)) }
            }
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Trend view").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    cap("Fitness age trend")
                    HStack(spacing: 18) {
                        legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).frame(width: 12, height: 12), "Your fitness age")
                        legend(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.textPrimary).frame(width: 12, height: 12), "Calendar age")
                    }
                    NunaLine2Chart(points: fitness.map { (date: $0.0, value: $0.1) }, color: tint, decimals: 0, baseline: profile.age > 0 ? Double(profile.age) : nil, baselineInRange: true, height: 190)
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    cap("Pace of aging trend")
                    if paces.count >= 2 {
                        NunaLine2Chart(points: paces, color: NunaPalette.textPrimary, decimals: 1, baseline: 1.0, height: 190)
                    } else {
                        Text("The trend appears once the pace has a few weeks behind it.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }
    }

    private func legend<S: View>(_ mark: S, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { mark; Text(text).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary) }
    }

    // MARK: Data, history, tips

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

    @ViewBuilder private var history: some View {
        let rows = Array(series.prefix(index + 1).suffix(6).reversed())
        if rows.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                NunaTitleRow(title: "Weekly history") { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { NunaDivider() }
                            HStack(spacing: 12) {
                                Text(verbatim: date(r.day).map { nunaAxisDate($0) } ?? r.day).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(width: 56, alignment: .leading)
                                NunaProgressBar(fraction: min(max(1 - (r.value - 20) / 60, 0.05), 1), color: i == 0 ? tint : NunaPalette.rest)
                                Text(verbatim: String(format: "%.0f", r.value)).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                                    .foregroundStyle(NunaPalette.textPrimary).frame(width: 40, alignment: .trailing)
                            }
                            .frame(minHeight: 50)
                        }
                    }
                }
            }
        }
    }

    private var lowerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "How to lower it") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaListRow("Zone 2 runs", description: "3× per week, 30 minutes", systemImage: "figure.run")
                    NunaDivider()
                    NunaListRow("Short intervals", description: "1× per week, 4 × 4 minutes", systemImage: "bolt")
                    NunaDivider()
                    NunaListRow("Enough sleep", description: "Resting heart rate falls when Sleep is high", systemImage: NunaIcons.sleep)
                }
            }
        }
    }

    private var notReady: some View {
        VStack(spacing: NunaSpacing.section) {
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

    private var footer: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted)
                    Text("This is a fitness comparison in years, not a biological age or a medical assessment. The model uses no exercise test, so watch the direction rather than the exact number.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Non-exercise model (Nes 2011, HUNT), updated every Saturday", systemImage: "sparkles",
                          text: "Your age, sex, the median resting heart rate of the last 7 days and a physical activity index built from your recent training are compared with an average person of your age. The gap is turned into years.")
        }
    }
}

// MARK: - The scale bar

/// A reading on a scale of ten segments that run from the unfavourable end (amber) to the favourable one (green): the reading as a white marker above the bar with its
/// value over it, the average person as a grey marker below it, and the ends of the scale named under the bar.
private struct NunaFitnessScale: View {
    let value: Double
    let reference: Double?
    let range: ClosedRange<Double>
    let higherIsBetter: Bool
    let label: String
    let low: String
    let high: String

    private func fraction(_ v: Double) -> CGFloat { CGFloat(min(max((v - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)) }

    /// Segment i from the left, with the favourable end at the right unless lower is better.
    private func segmentColor(_ i: Int) -> Color {
        let good = higherIsBetter ? i : 9 - i
        switch good {
        case 0...3: return NunaPalette.warning.opacity(1.0 - Double(3 - good) * 0.12)
        case 4...5: return NunaPalette.textMuted.opacity(0.45)
        default: return NunaPalette.charge.opacity(0.55 + Double(good - 6) * 0.15)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = min(max(w * fraction(value), 0), w)
                ZStack(alignment: .topLeading) {
                    Text(verbatim: label).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize()
                        .position(x: min(max(x, 40), max(w - 40, 40)), y: 8)
                    Image(systemName: "arrowtriangle.down.fill").font(.nuna(size: 13)).foregroundStyle(NunaPalette.textPrimary).position(x: x, y: 30)
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { i in RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(segmentColor(i)).frame(height: 6) }
                    }
                    .frame(width: w).offset(y: 40)
                    if let reference {
                        Image(systemName: "arrowtriangle.up.fill").font(.nuna(size: 12)).foregroundStyle(NunaPalette.textMuted).position(x: w * fraction(reference), y: 58)
                    }
                }
            }
            .frame(height: 66)
            HStack {
                Text(verbatim: low); Spacer(); Text(verbatim: high)
            }
            .font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

// MARK: - The info page

/// What the orb's colour and the pace mean, one short page for each, the way the first time through would say it.
private struct NunaFitnessAgeInfoSheet: View {
    let age: Int
    let pace: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page { let tint: Color; let title: LocalizedStringKey; let text: LocalizedStringKey; let ruler: Double? }

    private var pages: [Page] {
        [Page(tint: NunaPalette.warning, title: "An older fitness age", text: "Your fitness age is above your calendar age. Small, consistent habits can bring it down.", ruler: nil),
         Page(tint: NunaPalette.insightBlue, title: "On track", text: "Your fitness age is close to your calendar age, a sign of balanced fitness. Keep up your current habits.", ruler: nil),
         Page(tint: NunaPalette.charge, title: "A younger fitness age", text: "Your fitness age is below your calendar age, reflecting good heart and lung fitness. Continue your healthy habits.", ruler: nil),
         Page(tint: NunaPalette.textSecondary, title: "Your pace of aging", text: "Pace of aging shows how quickly your fitness age is changing, so you can see how your recent habits shape it over time.", ruler: pace),
         Page(tint: NunaPalette.charge, title: "Trending slower", text: "Your pace is below 1.0x, or even negative. Your recent habits are lowering your fitness age.", ruler: -1),
         Page(tint: NunaPalette.insightBlue, title: "Balanced", text: "Your pace is near 1.0x. Your fitness age rises steadily, at the same rate as your calendar age.", ruler: 1),
         Page(tint: NunaPalette.warning, title: "Trending faster", text: "Your pace is above 1.0x. Your current habits may be pushing your fitness age up. Small, healthy habits can shift the trend.", ruler: 3)]
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
                        NunaFitnessOrb(tint: p.tint, size: 280) { EmptyView() }.frame(maxWidth: .infinity)
                        if i >= 3 { NunaPaceDial(value: p.ruler) } else { ageBar(i) }
                        Text(p.title).font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Text(p.text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textCase(nil)
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
                Capsule().fill(LinearGradient(colors: [NunaPalette.charge, NunaPalette.insightBlue, NunaPalette.warning], startPoint: .leading, endPoint: .trailing)).frame(height: 5).offset(y: 22)
                Image(systemName: "arrowtriangle.down.fill").font(.nuna(size: 14)).foregroundStyle(NunaPalette.textPrimary).position(x: geo.size.width * f, y: 10)
            }
        }
        .frame(height: 40)
    }
}
#endif
