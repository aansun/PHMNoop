#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Nutrition: what is left to eat today against the plan, the macros, and the diary by meal. Day by day, with a way back to earlier days.
struct NunaNutritionView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var today = NunaTodayModel()
    @StateObject private var csvKcal = NunaSeriesModel()
    @StateObject private var csvProtein = NunaSeriesModel()
    @StateObject private var csvCarbs = NunaSeriesModel()
    @StateObject private var csvFat = NunaSeriesModel()
    @ObservedObject private var caffeine = CaffeineLogStore.shared
    @ObservedObject private var changes = NunaDataChanges.shared
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false
    @AppStorage(NunaNutritionPrefs.targetKcal) private var targetKcal = 0.0
    @AppStorage(NunaNutritionPrefs.proteinPerKg) private var proteinPerKg = NunaNutritionPrefs.defaultProteinPerKg
    @AppStorage(NunaNutritionPrefs.fatShare) private var fatShare = NunaNutritionPrefs.defaultFatShare
    @AppStorage(NunaNutritionPrefs.paceKgPerWeek) private var pace = -0.5
    @AppStorage(NunaNutritionPrefs.lastCheckIn) private var lastCheckIn = ""
    @State private var offset = 0
    @State private var food = NunaFoodDay()
    @State private var addMeal: NunaMeal?
    @State private var deleting: FoodEntryRow?
    @State private var checkIn: NutritionMath.CheckIn?
    @State private var weightKg: Double?

    private var date: Date { Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date() }
    private var dayKey: String { Repository.localDayKey(date) }
    private var imported: (kcal: Double, p: Double?, c: Double?, f: Double?)? {
        guard let k = csvKcal.byDay[dayKey], k > 0 else { return nil }
        return (k, csvProtein.byDay[dayKey], csvCarbs.byDay[dayKey], csvFat.byDay[dayKey])
    }
    private var eaten: Double { food.entries.isEmpty ? (imported?.kcal ?? 0) : food.kcal }
    private var eatenMacros: (p: Double, c: Double, f: Double) {
        food.entries.isEmpty ? (imported?.p ?? 0, imported?.c ?? 0, imported?.f ?? 0) : (food.proteinG, food.carbsG, food.fatG)
    }
    private var target: Double? { hasPlan && targetKcal > 0 ? targetKcal : nil }
    private var macroTargets: NutritionMath.Macros? {
        guard let target else { return nil }
        return NutritionMath.macroTargets(kcal: target, weightKg: weightKg ?? (profile.weightKg > 0 ? profile.weightKg : 70), proteinPerKg: proteinPerKg, fatShare: fatShare)
    }
    private var checkInDue: Bool {
        guard checkIn != nil, offset == 0 else { return false }
        guard let last = NutritionMath.dayIndex(lastCheckIn), let now = NutritionMath.dayIndex(Repository.localDayKey(Date())) else { return true }
        return now - last >= 6
    }

    var body: some View {
        NunaDetailScreen("Nutrition") {
            dayStepper
            hero
            macroRow
            if checkInDue, let checkIn { checkInCard(checkIn) }
            ForEach(NunaMeal.allCases) { mealCard($0) }
            if food.entries.isEmpty, let imported { importedCard(imported) }
            addButton
            planLink
            importCard
            caffeineCard
        }
        .sheet(item: $addMeal) { m in NunaFoodAddSheet(day: dayKey, meal: m).nunaSheetChrome(detents: [.large]) }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let e = deleting { Task { await NunaFoodStore.delete(id: e.id, repo: repo) } }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { await load() }
        .task(id: dayKey) { food = await NunaFoodStore.day(dayKey, repo: repo) }
    }

    private func load() async {
        food = await NunaFoodStore.day(dayKey, repo: repo)
        await today.load(repo: repo, profile: profile)
        await csvKcal.load(repo: repo, key: "calories_in", source: "nutrition-csv", days: 120)
        await csvProtein.load(repo: repo, key: "protein_g", source: "nutrition-csv", days: 120)
        await csvCarbs.load(repo: repo, key: "carbs_g", source: "nutrition-csv", days: 120)
        await csvFat.load(repo: repo, key: "fat_g", source: "nutrition-csv", days: 120)
        let weights = await NunaFoodStore.weights(days: 120, repo: repo)
        weightKg = NutritionMath.trend(weights).last?.kg
        if hasPlan, target != nil {
            checkIn = NutritionMath.checkIn(trend: NutritionMath.trend(weights), intake: await NunaFoodStore.intakeByDay(days: 30, repo: repo), endDay: Repository.localDayKey(Date()),
                                            plannedKgPerWeek: pace, currentTarget: targetKcal)
        } else { checkIn = nil }
    }

    // MARK: Day

    private var dayStepper: some View {
        HStack(spacing: 18) {
            Button { offset += 1 } label: { Image(systemName: "chevron.left").font(.nuna(size: 15, weight: .bold)).frame(width: 40, height: 40) }.accessibilityLabel(Text("Earlier period"))
            Text(verbatim: dayTitle).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 18).frame(height: 38).background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
            Button { offset = max(0, offset - 1) } label: { Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .bold)).frame(width: 40, height: 40) }
                .disabled(offset == 0).opacity(offset == 0 ? 0.3 : 1).accessibilityLabel(Text("Later period"))
        }
        .foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    private var dayTitle: String {
        if offset == 0 { return String(localized: "Today") }
        if offset == 1 { return String(localized: "Yesterday") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 8) {
            if let target {
                let left = target - eaten
                nunaTrendsCap(left >= 0 ? "Left to eat" : "Over the target")
                Text(verbatim: nutFmt(abs(left))).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64))
                    .foregroundStyle(left >= 0 ? NunaPalette.textPrimary : NunaPalette.warning).minimumScaleFactor(0.6).lineLimit(1)
                Text(verbatim: String(localized: "kcal · target \(nutFmt(target))")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                NunaProgressBar(fraction: eaten / target, color: left >= 0 ? NunaPalette.charge : NunaPalette.warning).padding(.top, 6)
                HStack {
                    Text(verbatim: String(localized: "Eaten \(nutFmt(eaten))"))
                    Spacer()
                    if offset == 0, let a = today.calories, a > 0 { Text(verbatim: String(localized: "Active burn \(nutFmt(a))")) }
                }
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            } else {
                nunaTrendsCap("Eaten")
                Text(verbatim: nutFmt(eaten)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                Text("kcal").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    // MARK: Macros

    private var macroRow: some View {
        let m = eatenMacros
        let t = macroTargets
        return HStack(spacing: 10) {
            macroTile("Protein", eaten: m.p, goal: t?.proteinG, color: NunaPalette.charge)
            macroTile("Carbs", eaten: m.c, goal: t?.carbsG, color: NunaPalette.effort)
            macroTile("Fat", eaten: m.f, goal: t?.fatG, color: NunaPalette.warning)
        }
    }

    private func macroTile(_ label: LocalizedStringKey, eaten g: Double, goal: Double?, color: Color) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)) {
            VStack(spacing: 8) {
                NunaRingGauge(fraction: goal.map { $0 > 0 ? g / $0 : 0 } ?? 0, color: color, size: 62, lineWidth: 7) { EmptyView() }
                if let goal {
                    let left = goal - g
                    Text(verbatim: "\(nutFmt(abs(left))) g").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(left >= 0 ? NunaPalette.textPrimary : NunaPalette.warning).lineLimit(1).minimumScaleFactor(0.7)
                    Text(left >= 0 ? "left" : "over").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text(verbatim: "\(nutFmt(g)) g").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Check-in

    private func checkInCard(_ c: NutritionMath.CheckIn) -> some View {
        NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Weekly check-in")
                Text(verbatim: checkInText(c)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Text(verbatim: "\(nutFmt(targetKcal)) → \(nutFmt(c.newTarget)) kcal").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                HStack(spacing: 10) {
                    Button { targetKcal = c.newTarget; lastCheckIn = Repository.localDayKey(Date()); checkIn = nil } label: {
                        Text("Apply").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { lastCheckIn = Repository.localDayKey(Date()); checkIn = nil } label: {
                        Text(verbatim: String(localized: "Keep \(nutFmt(targetKcal))")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Text("A suggestion from your own numbers, not medical advice. You decide.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private func checkInText(_ c: NutritionMath.CheckIn) -> String {
        let actual = nutFmt(abs(c.actualKgPerWeek), 2), planned = nutFmt(abs(c.plannedKgPerWeek), 2)
        let verb = c.actualKgPerWeek < -0.005 ? String(localized: "lost") : (c.actualKgPerWeek > 0.005 ? String(localized: "gained") : String(localized: "held"))
        return String(localized: "Your trend weight \(verb) \(actual) kg a week, against the \(planned) kg you planned. A change of \(nutFmt(abs(c.changeKcal))) kcal a day would bring you back to the plan.")
    }

    // MARK: Diary

    private func mealCard(_ meal: NunaMeal) -> some View {
        let list = food.entries(meal)
        let total = list.reduce(0) { $0 + $1.kcal }
        return NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8)) {
            VStack(spacing: 0) {
                HStack {
                    Text(meal.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if !list.isEmpty { Text(verbatim: "\(nutFmt(total)) kcal").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
                    Button { addMeal = meal } label: { Image(systemName: "plus").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 40, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel(Text("Add food"))
                }
                ForEach(list, id: \.id) { e in
                    NunaDivider()
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: e.name).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).textCase(nil)
                            let macros = [e.proteinG.map { "P \(Int($0.rounded()))" }, e.carbsG.map { "C \(Int($0.rounded()))" }, e.fatG.map { "F \(Int($0.rounded()))" }].compactMap { $0 }
                            if !macros.isEmpty || e.source == "anya" {
                                Text(verbatim: (macros + (e.source == "anya" ? [String(localized: "estimate")] : [])).joined(separator: " · ")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(verbatim: nutFmt(e.kcal)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                        Menu {
                            Button { Task { await NunaFoodStore.keep(name: e.name, kcal: e.kcal, proteinG: e.proteinG, carbsG: e.carbsG, fatG: e.fatG, repo: repo) } } label: { Label("Save as a food", systemImage: "bookmark") }
                            Button(role: .destructive) { deleting = e } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted).frame(width: 36, height: 40) }
                    }
                    .padding(.vertical, 8)
                }
                if list.isEmpty {
                    Text("Nothing yet").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
                }
            }
        }
    }

    private func importedCard(_ i: (kcal: Double, p: Double?, c: Double?, f: Double?)) -> some View {
        NunaCard(small: true) {
            NunaListRow(LocalizedStringKey("Imported day: \(nutFmt(i.kcal)) kcal"), subtitle: "From your CSV import. Add food to log it meal by meal.", systemImage: "tray.and.arrow.down")
        }
    }

    private var addButton: some View {
        Button { addMeal = NunaMeal.suggested() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                Text("Add food").font(.nuna(size: 17, weight: .bold))
            }
            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var planLink: some View {
        NavigationLink { NunaNutritionPlanView() } label: {
            NunaCard(small: true) {
                NunaListRow("Strategy", subtitle: hasPlan ? LocalizedStringKey("Your plan, targets and weekly check-in") : LocalizedStringKey("Set a pace and get a daily target"), systemImage: "target", showsChevron: true)
            }
        }.buttonStyle(.plain)
    }

    private var importCard: some View {
        NavigationLink(value: TabRoute.dataSources) {
            NunaCard(small: true) {
                NunaListRow("Import CSV", subtitle: "From Cronometer or MacroFactor, processed on this phone", systemImage: "square.and.arrow.down", showsChevron: true)
            }
        }.buttonStyle(.plain)
    }

    private var caffeineCard: some View {
        let est = caffeine.estimate()
        return NunaCard(small: true) {
            NunaListRow(est.hasActive ? (est.totalRemainingMg.map { LocalizedStringKey("Caffeine \(Int($0.rounded())) mg active") } ?? "Caffeine active") : "No caffeine active",
                        subtitle: est.hoursSinceMostRecentActive.map { LocalizedStringKey("Last one about \(Int($0.rounded())) h ago") } ?? "Logged caffeine fades with a 5.5 hour half-life",
                        systemImage: "bolt")
        }
    }
}
#endif
