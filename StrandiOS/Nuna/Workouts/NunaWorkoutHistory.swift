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
    @State private var months = 3
    @State private var query = ""
    @State private var filter = "all"
    @State private var oldestFirst = false
    /// A day key ("yyyy-MM-dd") or a month key ("yyyy-MM"); the list below the calendar narrows to it.
    @State private var selected: String?

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }
    /// 3 and 6 months show a calendar of days; a year and five years show a calendar of months.
    private var dailyView: Bool { months <= 6 }

    private var startDate: Date {
        let today = cal.startOfDay(for: Date())
        let back = cal.date(byAdding: .month, value: -months, to: today) ?? today
        return back
    }

    private var topSports: [String] {
        Dictionary(grouping: m.rows, by: \.sport).sorted { $0.value.count > $1.value.count }.prefix(3).map(\.key)
    }

    private func matchesFilter(_ r: WorkoutRow) -> Bool {
        switch filter {
        case "all": return true
        case "cardio": return !NunaWorkoutKind.isStrength(r)
        case "strength": return NunaWorkoutKind.isStrength(r)
        default: return r.sport == filter
        }
    }

    /// Everything in the chosen range that matches the search and the filter; the calendar and the totals read this.
    private var inRange: [WorkoutRow] {
        let from = Int(startDate.timeIntervalSince1970)
        return m.rows.filter { $0.startTs >= from && matchesFilter($0) }
            .filter { query.isEmpty || WorkoutSource.displaySport($0.sport).localizedCaseInsensitiveContains(query) }
    }

    private func dayKey(_ ts: Int) -> String { m.dayKey(ts) }
    private func monthKey(_ ts: Int) -> String { String(m.dayKey(ts).prefix(7)) }

    private func weekStart(_ date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date }

    var body: some View {
        let list = inRange
        let shown = list.filter { r in
            guard let sel = selected else { return true }
            return sel.count > 7 ? dayKey(r.startTs) == sel : monthKey(r.startTs) == sel
        }
        NunaDetailScreen("All sessions") {
            NunaSegmented([(value: 3, title: "3 mo"), (value: 6, title: "6 mo"), (value: 12, title: "1 yr"), (value: 60, title: "5 yr")], selection: $months)
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
            overview(list)
            calendarCard(list)
            sessions(shown)
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo) }
        .onChange(of: months) { _ in selected = nil }
        .onChange(of: filter) { _ in selected = nil }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        Button { filter = id } label: {
            Text(verbatim: title).font(.system(size: 13.5, weight: .bold)).foregroundStyle(filter == id ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 36).background(filter == id ? NunaPalette.textPrimary : NunaPalette.glassStrong, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Overview: totals and a column per week, month or quarter

    private struct Bucket { let start: Date; var cardio = 0; var strength = 0 }

    /// Weeks for 3 and 6 months, months for a year, quarters for five years. Every bucket in the range is kept, even an empty one.
    private func buckets(_ list: [WorkoutRow]) -> [Bucket] {
        let today = Date()
        var out: [Bucket] = []
        var d: Date
        let step: (Date) -> Date
        switch months {
        case 3, 6:
            d = weekStart(startDate); step = { cal.date(byAdding: .day, value: 7, to: $0) ?? $0 }
        case 12:
            d = cal.dateInterval(of: .month, for: startDate)?.start ?? startDate; step = { cal.date(byAdding: .month, value: 1, to: $0) ?? $0 }
        default:
            let q = cal.dateInterval(of: .month, for: startDate)?.start ?? startDate
            let m0 = cal.component(.month, from: q)
            d = cal.date(byAdding: .month, value: -((m0 - 1) % 3), to: q) ?? q
            step = { cal.date(byAdding: .month, value: 3, to: $0) ?? $0 }
        }
        while d <= today { out.append(Bucket(start: d)); d = step(d) }
        for r in list {
            let t = Date(timeIntervalSince1970: TimeInterval(r.startTs))
            guard let i = out.lastIndex(where: { $0.start <= t }) else { continue }
            if NunaWorkoutKind.isStrength(r) { out[i].strength += 1 } else { out[i].cardio += 1 }
        }
        return out
    }

    /// Day and month, with the year once the range is a year or more.
    private func axisDate(_ d: Date) -> String {
        guard months >= 12 else { return nunaAxisDate(d) }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: d)
    }

    /// Weeks between the first session in the list (or the start of the range) and today, so a short history is not averaged over five years.
    private func perWeekSpan(_ list: [WorkoutRow]) -> Double {
        let first = list.map(\.startTs).min().map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? startDate
        return max(1, Date().timeIntervalSince(max(first, startDate)) / (7 * 86_400))
    }

    private func overview(_ list: [WorkoutRow]) -> some View {
        let bs = buckets(list)
        let top = max(bs.map { $0.cardio + $0.strength }.max() ?? 1, 1)
        let active = Set(list.map { dayKey($0.startTs) }).count
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Totals for this filter")
                    Spacer()
                    Text(verbatim: "\(axisDate(startDate)) – \(axisDate(Date()))").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack {
                    tile("Sessions", "\(list.count)"); tile("Duration", NunaWorkoutFormat.duration(m.minutes(list) * 60)); tile("Effort", UnitFormatter.effortDisplay(m.effort(list), scale: scale))
                }
                HStack {
                    tile("Active days", "\(active)"); tile("Per week", list.isEmpty ? "–" : String(format: "%.1f", locale: AppLanguage.activeLocale, Double(list.count) / perWeekSpan(list)))
                    tile("Longest session", NunaWorkoutFormat.duration(list.compactMap { $0.durationS ?? Double($0.endTs - $0.startTs) }.max()))
                }
                NunaDivider()
                HStack {
                    Text(months <= 6 ? "Sessions per week" : (months == 12 ? "Sessions per month" : "Sessions per quarter")).font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: String(localized: "Highest \(top)")).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack(alignment: .bottom, spacing: bs.count > 30 ? 2 : 4) {
                    ForEach(Array(bs.enumerated()), id: \.offset) { _, b in
                        VStack(spacing: 1) {
                            Spacer(minLength: 0)
                            if b.strength > 0 { RoundedRectangle(cornerRadius: 2).fill(NunaPalette.rest).frame(height: 110 * CGFloat(b.strength) / CGFloat(top)) }
                            if b.cardio > 0 { RoundedRectangle(cornerRadius: 2).fill(NunaPalette.effort).frame(height: 110 * CGFloat(b.cardio) / CGFloat(top)) }
                            if b.cardio + b.strength == 0 { RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 3) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 110)
                    }
                }
                HStack {
                    Text(verbatim: axisDate(bs.first?.start ?? startDate))
                    Spacer()
                    if bs.count > 4 { Text(verbatim: axisDate(bs[bs.count / 2].start)); Spacer() }
                    Text(verbatim: axisDate(bs.last?.start ?? Date()))
                }
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.effort, text: "Cardio", dot: true); NunaLegendItem(color: NunaPalette.rest, text: "Strength", dot: true) }
            }
        }
    }

    // MARK: Calendar: days for 3 and 6 months, months for a year and five years

    private func calendarCard(_ list: [WorkoutRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        nunaTrendsCap("Workout calendar")
                        Spacer()
                        if selected != nil {
                            Button { selected = nil } label: {
                                HStack(spacing: 4) { Text("Show all").font(.system(size: 13, weight: .bold)); Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                    .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 12).frame(height: 30).background(NunaPalette.glassStrong, in: Capsule())
                            }.buttonStyle(.plain)
                        } else {
                            Text(dailyView ? "Tap a day" : "Tap a month").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    if dailyView { dayHeat(list) } else { monthHeat(list) }
                    HStack(spacing: 14) {
                        NunaLegendItem(color: NunaPalette.effort, text: "Cardio", dot: true)
                        NunaLegendItem(color: NunaPalette.rest, text: "Strength", dot: true)
                        NunaLegendItem(color: NunaPalette.textPrimary, text: "Both", dot: true)
                    }
                }
            }
        }
    }

    private func kindColor(cardio: Bool, strength: Bool) -> Color {
        cardio && strength ? NunaPalette.textPrimary : (strength ? NunaPalette.rest : NunaPalette.effort)
    }

    /// One column per week (Monday to Sunday down), oldest on the left, with the month named above where it starts.
    private func dayHeat(_ list: [WorkoutRow]) -> some View {
        let today = cal.startOfDay(for: Date())
        let first = weekStart(startDate)
        let weeks = max(1, (cal.dateComponents([.day], from: first, to: weekStart(today)).day ?? 0) / 7 + 1)
        let byDay = Dictionary(grouping: list, by: { dayKey($0.startTs) })
        let gap: CGFloat = weeks > 16 ? 3 : 5
        let f = DateFormatter()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    let ws = cal.date(byAdding: .day, value: w * 7, to: first) ?? first
                    let prev = cal.component(.month, from: cal.date(byAdding: .day, value: -7, to: ws) ?? ws), next = cal.component(.month, from: cal.date(byAdding: .day, value: 7, to: ws) ?? ws)
                    // The first column only names its month when the month is not about to change at the next one.
                    let newMonth = w == 0 ? next == cal.component(.month, from: ws) : cal.component(.month, from: ws) != prev
                    Text(verbatim: newMonth ? monthShort(ws, f) : "").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize().frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                }
            }
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            let key = Repository.localDayKey(date)
                            let rs = byDay[key] ?? []
                            let future = date > today || date < cal.startOfDay(for: startDate)
                            let on = !rs.isEmpty
                            Button { if on { selected = selected == key ? nil : key } } label: {
                                RoundedRectangle(cornerRadius: weeks > 16 ? 3 : 6, style: .continuous)
                                    .fill(on ? kindColor(cardio: rs.contains { !NunaWorkoutKind.isStrength($0) }, strength: rs.contains(where: NunaWorkoutKind.isStrength)) : Color.white.opacity(future ? 0 : 0.07))
                                    .overlay(RoundedRectangle(cornerRadius: weeks > 16 ? 3 : 6, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: selected == key ? 2 : 0).padding(-2))
                                    .aspectRatio(1, contentMode: .fit)
                            }.buttonStyle(.plain).disabled(!on)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func monthShort(_ d: Date, _ f: DateFormatter) -> String {
        f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// One row per year, twelve months across. The shade follows how many sessions the month holds.
    private func monthHeat(_ list: [WorkoutRow]) -> some View {
        let byMonth = Dictionary(grouping: list, by: { monthKey($0.startTs) })
        let today = Date()
        let startYear = cal.component(.year, from: startDate), endYear = cal.component(.year, from: today)
        let peak = max(byMonth.values.map(\.count).max() ?? 1, 1)
        let f = DateFormatter()
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(verbatim: "").frame(width: 38)
                ForEach(1...12, id: \.self) { mo in
                    Text(verbatim: String(monthShort(cal.date(from: DateComponents(year: 2001, month: mo, day: 1)) ?? today, f).prefix(1))).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array((startYear...endYear).reversed()), id: \.self) { y in
                HStack(spacing: 4) {
                    Text(verbatim: String(y)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 38, alignment: .leading)
                    ForEach(1...12, id: \.self) { mo in
                        let key = String(format: "%04d-%02d", y, mo)
                        let rs = byMonth[key] ?? []
                        let monthStart = cal.date(from: DateComponents(year: y, month: mo, day: 1)) ?? today
                        let outside = monthStart > today || (cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart) <= cal.startOfDay(for: startDate)
                        let on = !rs.isEmpty
                        Button { if on { selected = selected == key ? nil : key } } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? kindColor(cardio: rs.contains { !NunaWorkoutKind.isStrength($0) }, strength: rs.contains(where: NunaWorkoutKind.isStrength)).opacity(0.3 + 0.7 * Double(rs.count) / Double(peak)) : Color.white.opacity(outside ? 0 : 0.07))
                                .overlay(Text(verbatim: on ? "\(rs.count)" : "").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Double(rs.count) / Double(peak) > 0.5 ? NunaPalette.onAccent : NunaPalette.textPrimary).minimumScaleFactor(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: selected == key ? 2 : 0).padding(-2))
                                .aspectRatio(1, contentMode: .fit)
                        }.buttonStyle(.plain).disabled(!on)
                    }
                }
            }
        }
    }

    // MARK: Sessions, grouped by week (3 and 6 months) or by month (a year, five years)

    @ViewBuilder private func sessions(_ list: [WorkoutRow]) -> some View {
        HStack {
            Text(sessionsTitle).font(.system(size: NunaTypeSize.h2, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Button { oldestFirst.toggle() } label: {
                HStack(spacing: 4) { Text(oldestFirst ? "Oldest" : "Newest").font(.system(size: 13, weight: .bold)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)) }
                    .foregroundStyle(NunaPalette.textPrimary)
            }.buttonStyle(.plain)
        }
        if list.isEmpty {
            NunaCard { Text(m.loaded ? "No sessions match." : " ").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
        }
        let groups = Dictionary(grouping: list, by: { r -> Date in
            let t = Date(timeIntervalSince1970: TimeInterval(r.startTs))
            return dailyView ? weekStart(t) : (cal.dateInterval(of: .month, for: t)?.start ?? t)
        }).sorted { oldestFirst ? $0.key < $1.key : $0.key > $1.key }
        LazyVStack(spacing: NunaSpacing.section) {
            ForEach(groups, id: \.key) { start, rs in
                let ordered = oldestFirst ? rs.sorted { $0.startTs < $1.startTs } : rs.sorted { $0.startTs > $1.startTs }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(verbatim: groupTitle(start)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Text(verbatim: String(localized: "\(rs.count) sessions · Effort \(UnitFormatter.effortDisplay(m.effort(rs), scale: scale))")).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(ordered.enumerated()), id: \.offset) { i, r in
                                if i > 0 { NunaDivider() }
                                NavigationLink(value: NunaWorkoutRoute.summary(m.key(r))) { NunaWorkoutRow(row: r, system: system, effortScale: scale) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sessionsTitle: LocalizedStringKey { selected == nil ? "Sessions" : "Selected" }

    private func groupTitle(_ start: Date) -> String {
        if let sel = selected {
            let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = sel.count > 7 ? "yyyy-MM-dd" : "yyyy-MM"
            if let d = parse.date(from: sel) {
                let f = DateFormatter(); f.locale = AppLanguage.activeLocale
                f.setLocalizedDateFormatFromTemplate(sel.count > 7 ? "EEEE d MMMM yyyy" : "MMMM yyyy")
                return f.string(from: d)
            }
        }
        if dailyView { return String(localized: "Week of \(nunaAxisDate(start))") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: start)
    }

    private func tile(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: v).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
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
    @State private var selected: String?
    @State private var page = 0
    @State private var showCoach = false
    private let weeks = 7

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    private func matches(_ r: WorkoutRow) -> Bool { kind == "all" || (kind == "cardio") != NunaWorkoutKind.isStrength(r) }

    var body: some View {
        let stats = NunaWorkoutStats(model: m, days: 35, filter: matches)
        let day = selected ?? ""
        let dayRows = m.rows.filter { m.dayKey($0.startTs) == day }.filter(matches)
        NunaDetailScreen("Workout calendar", trailing: AnyView(todayChip)) {
            NunaSegmented([(value: "all", title: "All"), (value: "cardio", title: "Cardio"), (value: "strength", title: "Strength")], selection: $kind)
            NunaCard {
                VStack(spacing: 14) {
                    HStack {
                        pageButton("chevron.left", enabled: true) { page += 1 }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(verbatim: rangeTitle).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: page == 0 ? String(localized: "Last \(weeks) weeks") : String(localized: "\(weeks) weeks")).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        pageButton("chevron.right", enabled: page > 0) { page -= 1 }
                    }
                    NunaWorkoutMonthGrid(model: m, weeks: weeks, selected: $selected, offset: page, filter: kind)
                }
            }
            if !day.isEmpty { dayCard(day, dayRows) }
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
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            if selected == nil { selected = m.rows.first.map { m.dayKey($0.startTs) } ?? m.todayKey }
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "workouts") }
    }

    private var todayChip: some View {
        Button { page = 0; selected = m.todayKey } label: {
            Text("Today").font(.system(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 38)
                .background(NunaPalette.glassStrong, in: Capsule()).overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func pageButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 40, height: 40).background(NunaPalette.glassStrong, in: Circle())
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private var rangeTitle: String {
        let first = NunaWorkoutMonthGrid.firstMonday(weeks: weeks, offset: page)
        let last = Calendar(identifier: .gregorian).date(byAdding: .day, value: weeks * 7 - 1, to: first) ?? first
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("MMMM"); let a = f.string(from: first)
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); let b = f.string(from: last)
        return a == String(b.split(separator: " ").first ?? "") ? b : a + " – " + b
    }

    private func dayCard(_ day: String, _ rows: [WorkoutRow]) -> some View {
        NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(verbatim: dayTitle(day)).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(verbatim: String(localized: "\(rows.count) sessions"))
                }
                if rows.isEmpty { Text("Rest day").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    NavigationLink(value: NunaWorkoutRoute.summary(m.key(r))) { NunaWorkoutRow(row: r, system: system, effortScale: scale) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func dayTitle(_ key: String) -> String {
        guard let d = NunaDayFormat.parse(key) else { return key }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMMM"); return f.string(from: d)
    }

    private var weekdayPattern: some View {
        let cutoff = TrendInsights.shift(m.todayKey, by: -83) ?? m.todayKey
        let counts = Dictionary(grouping: m.rows.filter { m.dayKey($0.startTs) >= cutoff }.filter(matches), by: { TrendInsights.weekday(m.dayKey($0.startTs)) ?? 0 }).mapValues { Set($0.map { m.dayKey($0.startTs) }).count }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let top = max(counts.values.max() ?? 1, 1)
        let lowest = order.min(by: { (counts[$0] ?? 0) < (counts[$1] ?? 0) })
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Weekly pattern") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(order, id: \.self) { wd in
                            let c = counts[wd] ?? 0
                            VStack(spacing: 6) {
                                Text(verbatim: "\(c)").font(.system(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                                ZStack(alignment: .bottom) {
                                    Color.clear
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.effort.opacity(wd == lowest ? 0.45 : 1))
                                        .frame(height: max(8, 64 * CGFloat(c) / CGFloat(top)))
                                }.frame(height: 64)
                                Text(verbatim: NunaTrendsFormat.weekdayShort(wd)).font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if let lowest, !m.rows.isEmpty {
                        Text(verbatim: String(localized: "Days with a session over the last 12 weeks. \(longDay(lowest)) is the one most often empty. A good day for full rest."))
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
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
