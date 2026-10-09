#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Achievements (Me › Personalize): how long the data has run and where the best and worst of it sit. Level and streaks count only days
/// the strap really scored; nothing is filled in. Everything is worked out on this phone from the stored days and saved workouts.
struct NunaAchievementsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var workouts: [WorkoutRow] = []
    @State private var allTime = false
    @State private var showAllActivities = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Charge at or above this is a green day; Rest at or above this a good night; Effort from this up counts as a working day (10 of 21).
    private static let greenCharge = 67.0
    private static let goodRest = 70.0
    private static let workingEffort = 10.0 / 21.0 * 100

    // MARK: Days in view

    private var cal: Calendar { Calendar.current }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private func date(_ key: String) -> Date? { Self.dayFormat.date(from: key) }

    /// Every stored day, oldest first.
    private var allDays: [DailyMetric] { repo.days.sorted { $0.day < $1.day } }

    private var daysInView: [DailyMetric] {
        guard !allTime else { return allDays }
        let from = Repository.localDayKey(cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date())) ?? Date())
        return allDays.filter { $0.day >= from }
    }

    private var workoutsInView: [WorkoutRow] {
        guard !allTime else { return workouts }
        let from = Int((cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date())) ?? Date()).timeIntervalSince1970)
        return workouts.filter { $0.startTs >= from }
    }

    // MARK: Level

    private var recoveries: Int { allDays.filter { $0.recovery != nil }.count }
    private static let perLevel = 30
    private var level: Int { 1 + recoveries / Self.perLevel }
    private var levelProgress: Double { Double(recoveries % Self.perLevel) / Double(Self.perLevel) }
    private var tier: LocalizedStringKey { level >= 10 ? "Gold" : (level >= 5 ? "Silver" : "Bronze") }
    private var tierColor: Color { level >= 10 ? NunaPalette.scoreMid : (level >= 5 ? NunaPalette.textSecondary : NunaPalette.warning) }

    /// Days in a row, counted back from today (or yesterday while today has nothing yet), that carry any reading.
    private var dataStreak: Int {
        let keys = Set(allDays.map(\.day))
        var day = cal.startOfDay(for: Date())
        if !keys.contains(Repository.localDayKey(day)) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while keys.contains(Repository.localDayKey(day)) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    private var memberSince: String? {
        guard let first = allDays.first, let d = date(first.day) else { return nil }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f.string(from: d)
    }

    // MARK: Streaks and extremes

    /// The longest run of consecutive calendar days in view for which `test` holds.
    private func longestRun(_ test: (DailyMetric) -> Bool) -> Int {
        var best = 0, run = 0
        var previous: Date?
        for d in daysInView {
            guard let when = date(d.day) else { continue }
            if test(d) {
                if let p = previous, cal.dateComponents([.day], from: p, to: when).day == 1, run > 0 { run += 1 } else { run = 1 }
                previous = when
                best = max(best, run)
            } else { run = 0; previous = nil }
        }
        return best
    }

    private func spread(_ values: [Double]) -> (low: Double, high: Double, median: Double)? {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let s = values.sorted()
        let mid = s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        return (lo, hi, mid)
    }

    // MARK: Body

    var body: some View {
        NunaDetailScreen("Achievements") {
            header
            NunaSegmented([(value: false, title: "Last 30 days"), (value: true, title: "All time")], selection: $allTime)
            figures
            activities
            spreads
            streaks
            extremes
            nunaFootnote("Level counts the days your strap scored Charge, 30 for each level. Streaks and extremes only use days with a reading.")
        }
        .task(id: repo.refreshSeq) { workouts = await repo.workoutRows() }
    }

    // MARK: Level and streak

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                NunaRingGauge(fraction: levelProgress, color: tierColor, size: 84, lineWidth: 6) {
                    Text(verbatim: "\(level)").font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(tier).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tierColor)
                Text(verbatim: String(localized: "Level \(level)")).font(.nuna(size: 20, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(verbatim: String(localized: "\(recoveries) Charge days")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 10) {
                stat("Data streak", String(localized: "\(dataStreak) days"))
                if let memberSince { stat("Member since", memberSince) }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(NunaPalette.hairline).frame(width: 1) }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
        }
    }

    // MARK: Number of activities, max heart rate, peak Effort

    private var figures: some View {
        let ws = workoutsInView
        let maxHr = ws.compactMap(\.maxHr).max()
        let peak = daysInView.compactMap(\.strain).max()
        return HStack(alignment: .top, spacing: 0) {
            figure(icon: "dumbbell", value: "\(ws.count)", unit: "×", label: "Number of activities")
            Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 64)
            figure(icon: "heart", value: maxHr.map(String.init) ?? "–", unit: "", label: "Max heart rate")
            Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 64)
            VStack(spacing: 8) {
                NunaRingGauge(fraction: (peak ?? 0) / 100, color: peak.map(nunaEffortColor) ?? NunaPalette.effortModerate,
                              gradient: peak.map(nunaEffortRingColors), size: 52, lineWidth: 5) {
                    Text(verbatim: peak.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–")
                        .font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                }
                caption("Peak day Effort")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { NunaDivider() }
        .overlay(alignment: .bottom) { NunaDivider() }
    }

    private func figure(icon: String, value: String, unit: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(height: 24)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: value).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty && value != "–" { Text(verbatim: unit).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            caption(label)
        }
        .frame(maxWidth: .infinity)
    }

    private func caption(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Activities

    private struct SportRow: Identifiable {
        let id: String; let count: Int; let peak: Double?
    }

    private var sports: [SportRow] {
        Dictionary(grouping: workoutsInView) { WorkoutSource.displaySport($0.sport) }
            .map { SportRow(id: $0.key, count: $0.value.count, peak: $0.value.compactMap(\.strain).max()) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }

    private func sportIcon(_ name: String) -> String {
        let s = name.lowercased()
        if s.contains("run") || s.contains("jog") { return "figure.run" }
        if s.contains("walk") { return "figure.walk" }
        if s.contains("hik") || s.contains("ruck") { return "figure.hiking" }
        if s.contains("cycl") || s.contains("spin") || s.contains("bike") || s.contains("biking") { return "figure.outdoor.cycle" }
        if s.contains("swim") { return "figure.pool.swim" }
        if s.contains("yoga") { return "figure.yoga" }
        if NunaWorkoutKind.isStrengthName(name) { return "dumbbell" }
        return "figure.mixed.cardio"
    }

    @ViewBuilder private var activities: some View {
        let list = sports
        if !list.isEmpty {
            let shown = showAllActivities ? list : Array(list.prefix(6))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    caption("Activities")
                    Spacer()
                    caption("Peak Effort")
                }
                NunaPlainList {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 14) {
                            Text(verbatim: "\(s.count)×").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .frame(width: 44, alignment: .trailing)
                            Image(systemName: sportIcon(s.id)).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                            Text(verbatim: s.id).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 8)
                            Text(verbatim: s.peak.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–")
                                .font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        .padding(.vertical, 14)
                    }
                }
                if list.count > 6 {
                    Button { withAnimation { showAllActivities.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAllActivities ? "chevron.up" : "chevron.down").font(.nuna(size: 11, weight: .bold))
                            Text(showAllActivities ? "Fewer activities" : "More activities").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: HRV and resting heart rate

    @ViewBuilder private var spreads: some View {
        let hrv = spread(daysInView.compactMap(\.avgHrv))
        let rhr = spread(daysInView.compactMap { $0.restingHr.map(Double.init) })
        if hrv != nil || rhr != nil {
            HStack(alignment: .top, spacing: 0) {
                if let hrv { spreadColumn("HRV", "ms", hrv) }
                if hrv != nil && rhr != nil { Rectangle().fill(NunaPalette.hairline).frame(width: 1) }
                if let rhr { spreadColumn("Resting HR", "bpm", rhr) }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .top) { NunaDivider() }
            .overlay(alignment: .bottom) { NunaDivider() }
        }
    }

    /// Two bars, the lowest and the highest reading in view, with a dashed line at the median.
    private func spreadColumn(_ title: LocalizedStringKey, _ unit: String, _ s: (low: Double, high: Double, median: Double)) -> some View {
        let top = max(s.high, 1)
        let height: CGFloat = 120
        func h(_ v: Double) -> CGFloat { max(8, height * CGFloat(v / top)) }
        return VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 26) {
                    bar(s.low, h(s.low), "Low")
                    bar(s.high, h(s.high), "High")
                }
                .frame(maxWidth: .infinity)
                // The median across both bars.
                HStack(spacing: 6) {
                    NunaTargetLine().frame(height: 1.5)
                    Text("Median").font(.nuna(size: 9.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 6).frame(height: 18)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.bottom, h(s.median))
            }
            .frame(height: height + 34, alignment: .bottom)
            HStack(spacing: 4) {
                Text(title).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(verbatim: "(\(unit))").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func bar(_ value: Double, _ height: CGFloat, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(Int(value.rounded()))").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NunaPalette.textSecondary.opacity(0.55)).frame(width: 46, height: height)
                .overlay(alignment: .top) { Rectangle().fill(NunaPalette.textPrimary).frame(height: 2) }
            caption(label)
        }
    }

    // MARK: Streaks

    private var streaks: some View {
        let working = Int(UnitFormatter.effortValue(Self.workingEffort, scale: scale).rounded())
        return HStack(alignment: .top, spacing: 0) {
            streak("dumbbell", longestRun { ($0.strain ?? 0) >= Self.workingEffort }, NunaPalette.effortModerate, LocalizedStringKey("Effort \(working)+ streak"))
            streak("leaf", longestRun { ($0.recovery ?? 0) >= Self.greenCharge }, NunaPalette.scoreHigh, "Green Charge streak")
            streak("moon", longestRun { restScore($0) >= Self.goodRest }, NunaPalette.restText, "Rest 70%+ streak")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { NunaDivider() }
    }

    /// The Rest score of a day, from the stored daily totals (the same composite the Rest ring shows), or 0 without sleep.
    private func restScore(_ d: DailyMetric) -> Double { AnalyticsEngine.Rest.composite(daily: d) ?? 0 }

    private func streak(_ icon: String, _ n: Int, _ tint: Color, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(n)").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(tint)
                    Text(verbatim: "×").font(.nuna(size: 13, weight: .bold)).foregroundStyle(tint)
                }
            }
            caption(label)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Lowest Charge, longest sleep

    private var extremes: some View {
        let lowest = daysInView.compactMap(\.recovery).min()
        let longest = daysInView.compactMap(\.totalSleepMin).max()
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "bolt.slash").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: lowest.map { "\(Int($0.rounded()))%" } ?? "–").font(.nuna(size: 26, weight: .bold, design: NunaType.design))
                        .foregroundStyle(lowest.map(nunaChargeColor) ?? NunaPalette.textPrimary)
                }
                caption("Lowest Charge")
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "moon").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: longest.map { NunaSleepFormat.duration($0) } ?? "–").font(.nuna(size: 26, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.restText)
                }
                caption("Longest sleep")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }
}
#endif
