#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - All sessions (WorkoutHistory)

struct NunaWorkoutHistoryView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""
    @StateObject private var m = NunaWorkoutsModel()
    @State private var query = ""
    @State private var filter = "all"
    @State private var oldestFirst = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    private var topSports: [String] {
        Dictionary(grouping: m.rows, by: \.sport).sorted { $0.value.count > $1.value.count }.prefix(3).map(\.key)
    }

    private var filtered: [WorkoutRow] {
        let base = m.rows.filter { r in
            switch filter {
            case "all": return true
            case "cardio": return !NunaWorkoutKind.isStrength(r)
            case "strength": return NunaWorkoutKind.isStrength(r)
            default: return r.sport == filter
            }
        }.filter { query.isEmpty || WorkoutSource.displaySport($0.sport).localizedCaseInsensitiveContains(query) }
        return oldestFirst ? base.reversed() : base
    }

    private func weekStart(_ ts: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: TimeInterval(ts)))?.start ?? Date()
    }

    var body: some View {
        let list = filtered
        let weeks = Dictionary(grouping: list, by: { weekStart($0.startTs) }).sorted { oldestFirst ? $0.key < $1.key : $0.key > $1.key }
        NunaDetailScreen("All sessions") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                TextField("", text: $query, prompt: Text("Search sessions").foregroundStyle(NunaPalette.textMuted)).font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 16).frame(height: 48).background(Color.black.opacity(0.28), in: Capsule()).overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("all", String(localized: "All")); chip("cardio", String(localized: "Cardio")); chip("strength", String(localized: "Strength"))
                    ForEach(topSports, id: \.self) { chip($0, WorkoutSource.displaySport($0)) }
                }
            }
            totals(list)
            if list.isEmpty {
                NunaCard { Text(m.loaded ? "No sessions match." : " ").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
            }
            ForEach(weeks, id: \.key) { start, rs in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(verbatim: String(localized: "Week of \(nunaAxisDate(start))")).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Text(verbatim: String(localized: "\(rs.count) sessions · Effort \(UnitFormatter.effortDisplay(m.effort(rs), scale: scale))")).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(rs.enumerated()), id: \.offset) { i, r in
                                if i > 0 { NunaDivider() }
                                NavigationLink(value: NunaWorkoutRoute.summary(m.key(r))) { NunaWorkoutRow(row: r, system: system, effortScale: scale) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        Button { filter = id } label: {
            Text(verbatim: title).font(.system(size: 13.5, weight: .bold)).foregroundStyle(filter == id ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 36).background(filter == id ? NunaPalette.textPrimary : NunaPalette.glassStrong, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func totals(_ list: [WorkoutRow]) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    nunaTrendsCap("Totals for this filter")
                    Spacer()
                    Button { oldestFirst.toggle() } label: {
                        HStack(spacing: 4) { Text(oldestFirst ? "Oldest" : "Newest").font(.system(size: 13, weight: .bold)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)) }
                            .foregroundStyle(NunaPalette.textPrimary)
                    }.buttonStyle(.plain)
                }
                if let last = list.last {
                    Text(verbatim: String(localized: "Since \(nunaAxisDate(Date(timeIntervalSince1970: TimeInterval(last.startTs))))")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack {
                    tile("Sessions", "\(list.count)"); tile("Duration", NunaWorkoutFormat.duration(m.minutes(list) * 60)); tile("Effort", UnitFormatter.effortDisplay(m.effort(list), scale: scale))
                }
            }
        }
    }

    private func tile(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Calendar (WorkoutCalendar)

struct NunaWorkoutCalendarView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""
    @StateObject private var m = NunaWorkoutsModel()
    @State private var kind = "all"
    @State private var selected: String? = Repository.localDayKey(Date())
    @State private var showCoach = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    var body: some View {
        let stats = NunaWorkoutStats(model: m, days: 35)
        let day = (selected ?? "")
        let dayRows = m.rows.filter { m.dayKey($0.startTs) == day }.filter { kind == "all" || (kind == "cardio") != NunaWorkoutKind.isStrength($0) }
        NunaDetailScreen("Workout calendar") {
            NunaSegmented([(value: "all", title: "All"), (value: "cardio", title: "Cardio"), (value: "strength", title: "Strength")], selection: $kind)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("Last 7 weeks"); Spacer() }
                    NunaWorkoutMonthGrid(model: m, weeks: 7, selected: $selected)
                }
            }
            if !day.isEmpty {
                NunaCard(highlight: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: dayTitle(day)).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: String(localized: "\(dayRows.count) sessions")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if dayRows.isEmpty { Text("Rest day").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        ForEach(Array(dayRows.enumerated()), id: \.offset) { _, r in
                            NavigationLink(value: NunaWorkoutRoute.summary(m.key(r))) { NunaWorkoutRow(row: r, system: system, effortScale: scale) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                NunaStatTile(label: "Active days", value: "\(stats.active)", unit: "/ 35")
                NunaStatTile(label: "Rest days", value: "\(stats.rest)")
            }
            HStack(spacing: 12) {
                NunaStatTile(label: "Current streak", value: "\(stats.streak)", unit: String(localized: "days"))
                NunaStatTile(label: "Longest gap", value: "\(stats.longestGap)", unit: String(localized: "days"))
            }
            weekdayPattern
            NunaAnyaCard(verbatim: anyaLine(stats.streak)) { showCoach = true }
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "workouts") }
    }

    private func dayTitle(_ key: String) -> String {
        guard let d = NunaDayFormat.parse(key) else { return key }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMMM"); return f.string(from: d)
    }

    private var weekdayPattern: some View {
        let cutoff = TrendInsights.shift(m.todayKey, by: -84) ?? m.todayKey
        let counts = Dictionary(grouping: m.rows.filter { m.dayKey($0.startTs) >= cutoff }, by: { TrendInsights.weekday(m.dayKey($0.startTs)) ?? 0 }).mapValues { Set($0.map { m.dayKey($0.startTs) }).count }
        let top = max(counts.values.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Weekly pattern") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    NunaColumns(items: [2, 3, 4, 5, 6, 7, 1].map { wd in
                        NunaColumns.Item(weekday: NunaTrendsFormat.weekdayShort(wd), date: Date(), fraction: Double(counts[wd] ?? 0) / Double(top), valueText: "\(counts[wd] ?? 0)", highlight: counts[wd] == counts.values.max())
                    }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText, showsDates: false)
                    if let lo = [2, 3, 4, 5, 6, 7, 1].min(by: { (counts[$0] ?? 0) < (counts[$1] ?? 0) }), !m.rows.isEmpty {
                        Text(verbatim: String(localized: "Days with a session over the last 12 weeks. \(longDay(lo)) is the one most often empty.")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func longDay(_ w: Int) -> String { let f = DateFormatter(); f.locale = AppLanguage.activeLocale; return f.weekdaySymbols[(w - 1) % 7] }

    private func anyaLine(_ streak: Int) -> String {
        streak >= 3 ? String(localized: "You have been active \(streak) days in a row. Make tomorrow an easy day.")
                    : String(localized: "Your calendar is built from your saved sessions. Keep logging to see your rhythm.")
    }
}
#endif
