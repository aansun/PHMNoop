#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The "+" sheet: six shortcuts and today's water, as in the Quick actions mockup.
struct NunaQuickSheet: View {
    let hydrationEnabled: Bool
    let onAddActivity: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var waterML = 0
    @State private var goalML = 2500

    @AppStorage(NunaQuickActions.storageKey) private var actionsRaw = ""
    @AppStorage(NunaQuickActions.waterAmountKey) private var waterAdd = NunaQuickActions.waterAmountDefault
    @State private var editing = false
    @State private var todayPanel: NunaTodayRoute?
    @State private var mePanel: NunaMeRoute?
    @State private var workoutPanel: NunaWorkoutRoute?
    @State private var breathing = false
    @State private var addingFood = false
    @State private var foodToday = NunaFoodDay()
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false
    @AppStorage(NunaNutritionPrefs.targetKcal) private var targetKcal = 0.0

    /// The width of the button at the end of the food row and of the pair at the end of the water row.
    private static let controlWidth: CGFloat = 176

    private var actions: [NunaQuickAction] {
        let ids = NunaQuickActions.decode(actionsRaw.isEmpty ? NunaQuickActions.encode(NunaQuickActions.defaultIDs) : actionsRaw)
        return ids.compactMap(NunaQuickActions.action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick actions")
                    .font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Button { editing = true } label: {
                    NunaBareIcon("slider.horizontal.3", target: 40)
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Customize quick actions"))
            }
            .padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(actions) { a in tile(LocalizedStringKey(a.title), a.icon, nil) { run(a) } }
            }
            foodRow
            if hydrationEnabled { waterRow }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await reloadWater(); foodToday = await NunaFoodStore.day(Repository.localDayKey(Date()), repo: repo) }
        .sheet(isPresented: $addingFood, onDismiss: { Task { foodToday = await NunaFoodStore.day(Repository.localDayKey(Date()), repo: repo) } }) {
            NunaFoodAddSheet(day: Repository.localDayKey(Date()), meal: NunaMeal.suggested()).nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $editing) { NunaQuickActionsEditor(raw: $actionsRaw).nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $breathing) {
            NavigationStack { NunaBreathView().toolbar(.hidden, for: .navigationBar) }
                .preferredColorScheme(NunaTheme.colorScheme)
        }
        .sheet(item: $todayPanel) { NunaQuickPanel(route: $0) }
        .sheet(item: $mePanel) { NunaQuickPanel(route: $0) }
        .sheet(item: $workoutPanel) { NunaQuickPanel(route: $0) }
    }

    private func run(_ a: NunaQuickAction) {
        switch a.kind {
        case .addActivity: dismiss(); onAddActivity()
        case .route(let d): go(d)
        case .breathing: breathing = true
        case .today(let r): todayPanel = r
        case .me(let r): mePanel = r
        case .workout(let r): workoutPanel = r
        case .foodAdd: addingFood = true
        case .metric(let key):
            if let m = MetricCatalog.metric(key: key, source: "my-whoop") { todayPanel = .metric(m) }
        }
    }

    /// Today's food next to the water: what has been eaten against the target, and a button that opens Add food.
    private var foodRow: some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            HStack(spacing: 12) {
                NunaIconTile("fork.knife", tint: NunaPalette.charge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Food today").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: hasPlan && targetKcal > 0 ? String(localized: "\(nutFmt(foodToday.kcal)) of \(nutFmt(targetKcal)) kcal") : String(localized: "\(nutFmt(foodToday.kcal)) kcal"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 4)
                // The same width as the + button of the water row below it, so the two line up down the right edge.
                Button { addingFood = true } label: { Text("+Log").lineLimit(1) }
                    .buttonStyle(.nuna(.primary, height: 44, fullWidth: true)).frame(width: Self.controlWidth - 52)
            }
        }
    }

    private var waterRow: some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            HStack(spacing: 12) {
                NunaIconTile("drop", tint: NunaPalette.effortText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water today").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "\(liters(waterML)) of \(liters(goalML)) L"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Button { Task { await undoWater() } } label: {
                        Image(systemName: "minus").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Remove last drink"))
                    Button { Task { await addWater(waterAdd) } } label: { Text(verbatim: "+\(waterAdd)") }
                        .buttonStyle(.nuna(.primary, height: 44, fullWidth: true))
                }
                .frame(width: Self.controlWidth)
            }
        }
    }

    private func liters(_ ml: Int) -> String {
        String(format: "%.1f", locale: AppLanguage.activeLocale, Double(ml) / 1000)
    }

    private func reloadWater() async {
        guard hydrationEnabled else { return }
        waterML = Int(await repo.hydrationTotal(day: Repository.localDayKey(Date())))
        goalML = repo.hydrationGoalML(profileSex: profile.sex)
    }

    private func addWater(_ ml: Int) async {
        _ = await repo.logHydration(amountMl: ml)
        repo.noteHydrationChanged()
        await reloadWater()
    }

    private func undoWater() async {
        if let last = repo.hydrationEntries().last {
            _ = await repo.deleteHydrationEntry(id: last.id)
            repo.noteHydrationChanged()
            await reloadWater()
        }
    }

    private func go(_ dest: NavRouter.Destination) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.requestedDestination = dest }
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, _ tint: Color?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                NunaGlyph(icon, pointSize: 22, weight: .semibold)
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 60, height: 60)
                Text(title).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
#endif
