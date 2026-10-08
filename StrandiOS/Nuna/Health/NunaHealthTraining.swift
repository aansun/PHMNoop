#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Training part of Health › Body: what the last seven days of workouts add up to, how cardio and strength share them, whether the
/// load is in balance, and the way into Workouts and Training load. The figures are the ones the Workouts hub reads; this is the
/// body-side view of them, not another source. One card opens Workouts (Gym is a tab in there); the heading link opens the full list of sessions.
struct NunaHealthTraining: View {
    @ObservedObject var m: NunaWorkoutsModel
    let scale: EffortScale

    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaTitleRow(title: "Training") {
                NavigationLink(value: NunaWorkoutRoute.history) { NunaLinkLabel(text: "All sessions", chevron: true) }
            }
            if m.loaded {
                weekCard
                linksCard
            }
        }
    }

    // MARK: Last 7 days

    private var weekCard: some View {
        let week = m.recent(days: 7)
        let total = m.effort(week)
        let weekly = m.weeklyEffort(weeks: 7)
        let usualBlocks = weekly.dropLast().filter { $0 > 0 }
        let usual = usualBlocks.isEmpty ? nil : usualBlocks.reduce(0, +) / Double(usualBlocks.count)
        let cal = Calendar.current
        let days: [(Date, [WorkoutRow])] = (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date())) ?? Date()
            return (d, week.filter { cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), inSameDayAs: d) })
        }
        let top = max(days.map { m.effort($0.1) }.max() ?? 1, 1)
        let kcal = week.compactMap(\.energyKcal).reduce(0, +)
        let wd = DateFormatter(); wd.locale = AppLanguage.activeLocale; wd.setLocalizedDateFormatFromTemplate("EEE")
        let strengthMin = m.minutes(week.filter(NunaWorkoutKind.isStrength)), cardioMin = m.minutes(week.filter { !NunaWorkoutKind.isStrength($0) })
        let ratio = TrendInsights.loadRatio(blocks: m.weeklyEffort(weeks: 6))
        let band = ratio.map(TrendInsights.loadBand)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Last 7 days")
                    Spacer()
                    if let usual, usual > 0, !week.isEmpty { NunaChip(verbatim: String(localized: "\(Int((total / usual * 100).rounded()))% of your usual"), color: NunaPalette.effortText) }
                }
                if week.isEmpty {
                    Text("No workouts in the last 7 days. Start one from Workouts.").font(.nuna(size: 14, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: UnitFormatter.effortDisplay(total, scale: scale)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                        if let usual { Text(verbatim: "/ " + UnitFormatter.effortDisplay(usual, scale: scale)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                        Text("Effort").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    NunaColumns(items: days.map { d, rs in
                        let e = m.effort(rs)
                        return NunaColumns.Item(weekday: wd.string(from: d), date: d, fraction: e > 0 ? e / top : nil,
                                                valueText: e > 0 ? UnitFormatter.effortDisplay(e, scale: scale) : nil, highlight: cal.isDateInToday(d),
                                                color: rs.isEmpty ? nil : (rs.allSatisfy(NunaWorkoutKind.isStrength) ? NunaPalette.rest : NunaPalette.effort))
                    }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText, showsDates: false)
                    NunaDivider()
                    HStack {
                        stat("Sessions", "\(week.count)")
                        stat("Duration", NunaWorkoutFormat.duration(m.minutes(week) * 60))
                        stat("Calories", kcal > 0 ? NunaTrendsFormat.num(kcal) : "–")
                    }
                    if cardioMin + strengthMin > 0 {
                        NunaProportionBar(parts: [(cardioMin, NunaPalette.effort), (strengthMin, NunaPalette.rest)], height: 12)
                        HStack {
                            NunaLegendItem(color: NunaPalette.effort, text: "Cardio", dot: true)
                            Text(verbatim: NunaWorkoutFormat.duration(cardioMin * 60)).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                            NunaLegendItem(color: NunaPalette.rest, text: "Strength", dot: true)
                            Text(verbatim: NunaWorkoutFormat.duration(strengthMin * 60)).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                if let ratio, let band {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 34, height: 34).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(verbatim: String(localized: "Acute-to-chronic load ratio \(String(format: "%.2f", locale: AppLanguage.activeLocale, ratio)). \(bandSentence(band))"))
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func stat(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bandSentence(_ b: TrendInsights.LoadBand) -> String {
        switch b {
        case .under: return String(localized: "Below your usual load. There is room to add some.")
        case .optimal: return String(localized: "Within the safe range of 0.8 to 1.3. You can raise intensity a little.")
        case .high: return String(localized: "Above your usual load. Keep the next sessions easier.")
        case .excessive: return String(localized: "Well above your usual load. Take a rest day.")
        }
    }

    // MARK: Ways in

    private var linksCard: some View {
        let last = m.rows.first
        let lastText = last.map { WorkoutSource.displaySport($0.sport) + " · " + NunaWorkoutFormat.day($0.startTs) }
        return NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NavigationLink(value: NunaWorkoutRoute.hub(0)) {
                    NunaListRow("Workouts", subtitle: lastText.map { LocalizedStringKey($0) } ?? "Start a workout and see your history", systemImage: "figure.run", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaWorkoutRoute.load) {
                    NunaListRow("Training load", description: "Cardio and strength, week by week", systemImage: "chart.bar", showsChevron: true)
                }.buttonStyle(.plain)
            }
        }
    }
}
#endif
