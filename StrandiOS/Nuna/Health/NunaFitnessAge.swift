#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Weekly fitness comparison (docs/FITNESS_AGE.md): a number with a plus or minus 5 year band, against the
/// real age. It is a comparison, not a biological age. Reads the stored weekly series and the last 7 days.
struct NunaFitnessAgeView: View {
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var series: [(day: String, value: Double)] = []
    @State private var vo2: Double?
    @State private var loaded = false
    @State private var showWaist = false

    private func cap(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    private func short(_ day: String) -> String { date(day).map { nunaAxisDate($0) } ?? day }

    /// Inputs the weekly model uses, rebuilt from the last 7 days (the same rules as the weekly job).
    private var last7: ArraySlice<DailyMetric> { repo.days.suffix(7) }
    private var rhrValues: [Double] { last7.compactMap { $0.restingHr }.map(Double.init) }
    private var medianRHR: Double? {
        let v = rhrValues.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }
    private var activeStrains: [Double] { last7.compactMap { $0.strain }.filter { $0 >= 30 } }
    private var paIndex: Double {
        let m = activeStrains.isEmpty ? 0 : activeStrains.reduce(0, +) / Double(activeStrains.count)
        return FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: activeStrains.count, meanActiveStrain: m)
    }

    var body: some View {
        NunaDetailScreen("Fitness age") {
            if let latest = series.last {
                hero(latest)
                paceCard
                trendCard
                components
                dataCard
                history
                vo2Card
                lowerCard
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loaded ? "Not ready yet" : " ").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Fitness age needs your age, your sex and resting heart rate from at least 4 nights. It updates once a week.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted)
                    Text("This is a fitness comparison in years, not a biological age or a medical assessment. The model uses no exercise test, so watch the direction rather than the exact number.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Non-exercise model (Nes 2011, HUNT), updated every Saturday", systemImage: "sparkles",
                          text: "Your age, sex, the median resting heart rate of the last 7 days and a physical activity index built from your recent training are compared with an average person of your age. The gap is turned into years.")
        }
        .task(id: repo.refreshSeq) {
            series = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 200)
            vo2 = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: 60).last?.value
            loaded = true
        }
        .sheet(isPresented: $showWaist) { NunaWaistSheet() }
    }

    private func hero(_ latest: (day: String, value: Double)) -> some View {
        let age = Double(profile.age)
        let diff = age > 0 ? Int((age - latest.value).rounded()) : nil
        let tint: Color = (diff ?? 0) > 0 ? NunaPalette.charge : ((diff ?? 0) < 0 ? NunaPalette.warning : NunaPalette.textSecondary)
        let updated: String = date(latest.day).map {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMMM"); return f.string(from: $0)
        } ?? latest.day
        // The change since the previous weekly reading, from the stored series.
        let weekly: Int? = series.count >= 2 ? Int((series[series.count - 1].value - series[series.count - 2].value).rounded()) : nil
        return NunaCard(padding: EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18)) {
            VStack(spacing: 18) {
                Text("Health").font(.nuna(size: 13, weight: .heavy)).tracking(2).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                NunaFitnessOrb(tint: tint) {
                    VStack(spacing: 6) {
                        Text(verbatim: String(format: "%.0f", locale: AppLanguage.activeLocale, latest.value))
                            .font(.nuna(size: 64, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(1.6).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        if let diff, diff != 0 {
                            Text(diff > 0 ? LocalizedStringKey("\(diff) years younger") : LocalizedStringKey("\(-diff) years older"))
                                .font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint)
                        } else if diff == 0 {
                            Text("About your age").font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint)
                        }
                    }
                }
                if let weekly, weekly != 0 {
                    HStack(spacing: 6) {
                        Image(systemName: weekly < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.nuna(size: 10))
                        Text(verbatim: weekly < 0 ? String(localized: "\(-weekly) yr younger than last week") : String(localized: "\(weekly) yr older than last week"))
                            .font(.nuna(size: 13, weight: .bold))
                    }
                    .foregroundStyle(weekly < 0 ? NunaPalette.charge : NunaPalette.warning)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background((weekly < 0 ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: Capsule())
                } else if weekly == 0 {
                    Text("Steady since last week").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Text(verbatim: updated).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted)
                if let diff {
                    Text(verbatim: diff == 0 ? String(localized: "Your heart and lung fitness is about the same as your age.")
                         : String(localized: "Your heart and lung fitness matches someone aged \(Int(latest.value.rounded())), while you are \(profile.age)."))
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                    NunaAgeSlider(fitness: latest.value, age: age)
                    HStack(spacing: 16) {
                        legend(Capsule().fill(NunaPalette.charge.opacity(0.3)).frame(width: 14, height: 10), "Range ±5 yr")
                        legend(Circle().strokeBorder(NunaPalette.ink, lineWidth: 2).frame(width: 10, height: 10), "Actual age")
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pace of aging

    private var paceReadings: [PaceOfAging.Reading] {
        series.compactMap { r in date(r.day).map { PaceOfAging.Reading(time: $0.timeIntervalSince1970, fitnessAge: r.value) } }
    }

    /// Pace of aging from the stored weekly series (`PaceOfAging`), against the same pace one week earlier.
    private var paceCard: some View {
        let all = paceReadings
        let now = PaceOfAging.compute(all)
        let before = PaceOfAging.compute(Array(all.dropLast()))
        let move: Double? = now.flatMap { n in before.map { n.pace - $0.pace } }
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
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
                        .background((move < 0 ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: Capsule())
                    }
                }
                if let now {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: String(format: "%.1fx", locale: AppLanguage.activeLocale, now.pace))
                            .font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        NunaChip(now.band == .slow ? "Slow" : (now.band == .fast ? "Fast" : "Normal"),
                                 color: now.band == .slow ? NunaPalette.charge : (now.band == .fast ? NunaPalette.warning : nil))
                    }
                    NunaPaceDial(value: now.pace)
                    Text(paceText(now)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Text(now.confidence == .solid ? "Based on about six months of weekly readings."
                         : (now.confidence == .building ? "Still building: the pace firms up as weeks of readings add up."
                            : "Early estimate: too few weeks to move far from 1.0x yet."))
                        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
                } else {
                    let weeks = all.count
                    Text(verbatim: weeks == 0 ? String(localized: "Pace of aging appears after 6 weekly readings.")
                         : String(localized: "Pace of aging appears after 6 weekly readings. You have \(weeks) so far."))
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    NunaPaceDial(value: nil)
                }
            }
        }
    }

    private func paceText(_ r: PaceOfAging.Result) -> LocalizedStringKey {
        switch r.band {
        case .slow: return "Your fitness age is rising slower than the calendar, so you are ageing more slowly than time passes."
        case .fast: return "Your fitness age is rising faster than the calendar. Better sleep, activity and resting heart rate can bring it back."
        case .normal: return "1.0x means your fitness age moves at the same speed as the calendar. 0.0x means it holds still, and below that you are getting fitter."
        }
    }

    private func legend<S: View>(_ mark: S, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { mark; Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
    }

    private var trendCard: some View {
        let recent = Array(series.suffix(5))
        let delta: Double? = recent.count >= 2 ? (recent.last!.value - recent.first!.value).rounded() : nil
        let pts = recent.compactMap { r in date(r.day).map { ($0, r.value) } }
        return NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cap("4-week direction")
                    Spacer()
                    if let delta, abs(delta) >= 1 {
                        Text(verbatim: (delta < 0 ? "▼ " : "▲ ") + String(localized: "\(Int(abs(delta))) yr"))
                            .font(.nuna(size: 14, weight: .heavy)).foregroundStyle(delta < 0 ? NunaPalette.charge : NunaPalette.warning)
                    }
                }
                if let delta {
                    Text(delta <= -1 ? "You are getting fitter. Look at the direction over several weeks, not one number."
                         : (delta >= 1 ? "Fitness slipped a little. Look at the direction over several weeks, not one number."
                            : "Steady. Look at the direction over several weeks, not one number."))
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                NunaLine2Chart(points: pts, color: NunaPalette.charge, decimals: 0, height: 130)
            }
        }
    }

    private func componentRow(icon: String, title: LocalizedStringKey, reference: String, value: String, unit: String, years: Double) -> some View {
        let n = Int(abs(years).rounded())
        let younger = years < 0
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    NunaIconTile(icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: reference).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Text(verbatim: n == 0 ? "±0" : ((younger ? "−" : "+") + String(localized: "\(n) yr")))
                            .font(.nuna(size: 13, weight: .heavy)).foregroundStyle(n == 0 ? NunaPalette.textSecondary : (younger ? NunaPalette.charge : NunaPalette.warning))
                    }
                }
                GeometryReader { geo in
                    let w = geo.size.width, half = w / 2
                    let span = half * CGFloat(min(abs(years) / 6, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(NunaPalette.ink.opacity(0.09)).frame(height: 8)
                        Capsule().fill(younger ? NunaPalette.charge : NunaPalette.warning).frame(width: span, height: 8)
                            .offset(x: younger ? half - span : half)
                        Rectangle().fill(NunaPalette.ink.opacity(0.6)).frame(width: 2, height: 16).offset(x: half - 1)
                    }
                }
                .frame(height: 16)
                HStack {
                    Text("Younger"); Spacer(); Text("Reference"); Spacer(); Text("Older")
                }
                .font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    @ViewBuilder private var components: some View {
        let age = Double(profile.age)
        if age > 0, let rhr = medianRHR {
            let rhrYears = FitnessAgeEngine.fitnessAge(age: age, sex: profile.sex, restingHR: rhr, paIndex: FitnessAgeEngine.paiReference) - age
            let paYears = FitnessAgeEngine.fitnessAge(age: age, sex: profile.sex, restingHR: FitnessAgeEngine.restingHRReference, paIndex: paIndex) - age
            NunaTitleRow(title: "What shapes it") { EmptyView() }
            Text("Two signals compared with an average person of your age. Median of 7 days.")
                .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            componentRow(icon: "heart", title: "Resting HR",
                         reference: String(localized: "Reference \(Int(FitnessAgeEngine.restingHRReference)) bpm"),
                         value: String(format: "%.0f", rhr), unit: "bpm", years: rhrYears)
            componentRow(icon: "flame", title: "Physical activity",
                         reference: String(localized: "Reference \(String(format: "%.1f", locale: AppLanguage.activeLocale, FitnessAgeEngine.paiReference)) · from your training"),
                         value: String(format: "%.1f", locale: AppLanguage.activeLocale, paIndex), unit: "/ 15", years: paYears)
        }
    }

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
        let rows = Array(series.suffix(6).reversed())
        if rows.count >= 2 {
            NunaTitleRow(title: "Weekly history") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 12) {
                            Text(verbatim: short(r.day)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 56, alignment: .leading)
                            NunaProgressBar(fraction: min(max(1 - (r.value - 20) / 60, 0.05), 1), color: i == 0 ? NunaPalette.charge : NunaPalette.rest)
                            Text(verbatim: String(format: "%.0f", r.value)).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                                .foregroundStyle(NunaPalette.textPrimary).frame(width: 40, alignment: .trailing)
                        }
                        .frame(minHeight: 50)
                    }
                }
            }
        }
    }

    @ViewBuilder private var vo2Card: some View {
        if let vo2 {
            let female = profile.sex.lowercased() == "female"
            let see = female ? FitnessAgeEngine.seeWomen : FitnessAgeEngine.seeMen
            NunaTitleRow(title: "VO₂max estimate") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: String(format: "%.0f", vo2)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("ml/kg/min").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        NunaChip(profile.waistCm > 0 ? "Waist-based" : "Estimated")
                    }
                    Text(verbatim: profile.waistCm > 0
                         ? String(localized: "Range ±\(String(format: "%.1f", locale: AppLanguage.activeLocale, see)). Unlocked because your waist, \(Int(profile.waistCm)) cm, is set.")
                         : String(localized: "A rougher estimate from heart rate. Add your waist for the sharper one."))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ZStack(alignment: .leading) {
                        NunaProportionBar(parts: [(2, NunaPalette.zoneBase), (2, NunaPalette.zoneBase), (2, NunaPalette.rest), (2, NunaPalette.charge), (2, NunaPalette.charge)], height: 12)
                        GeometryReader { geo in
                            let f = CGFloat(min(max((vo2 - 20) / 40, 0), 1))
                            Capsule().fill(NunaPalette.ink).frame(width: 6, height: 20).shadow(color: NunaPalette.ink.opacity(0.2), radius: 3)
                                .offset(x: min(max(geo.size.width * f - 3, 0), geo.size.width - 6), y: -4)
                        }
                        .frame(height: 12)
                    }
                    HStack { Text("Fair"); Spacer(); Text("Superior") }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            Button { showWaist = true } label: {
                NunaCard(small: true) {
                    NunaListRow("Unlock VO₂max", subtitle: "Weight, height and waist. Does not change the fitness age.", systemImage: "ruler", showsChevron: true)
                }
            }.buttonStyle(.plain)
        }
    }

    private var lowerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "How to lower it") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaListRow("Zone 2 runs", subtitle: "3× per week, 30 minutes", systemImage: "figure.run")
                    NunaDivider()
                    NunaListRow("Short intervals", subtitle: "1× per week, 4 × 4 minutes", systemImage: "bolt")
                    NunaDivider()
                    NunaListRow("Enough sleep", subtitle: "Resting heart rate falls when Rest is high", systemImage: "moon")
                }
            }
        }
    }
}
#endif
