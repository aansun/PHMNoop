#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The "+" sheet: six shortcuts, Ask Anya and today's water, as in the Quick actions mockup.
struct NunaQuickSheet: View {
    let hydrationEnabled: Bool
    let coachEnabled: Bool
    let onAddActivity: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var waterML = 0
    @State private var goalML = 2500

    @AppStorage(NunaQuickActions.storageKey) private var actionsRaw = ""
    @State private var editing = false
    @State private var todayPanel: NunaTodayRoute?
    @State private var mePanel: NunaMeRoute?
    @State private var workoutPanel: NunaWorkoutRoute?
    @State private var breathing = false

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
                    Image(systemName: "slider.horizontal.3").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Customize quick actions"))
            }
            .padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(actions) { a in tile(LocalizedStringKey(a.title), a.icon, nil) { run(a) } }
            }
            if coachEnabled {
                Button { go(.coach) } label: {
                    NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                .frame(width: 40, height: 40).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask Anya").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text("About today, by voice or text").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if hydrationEnabled { waterRow }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.card.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await reloadWater() }
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
        case .metric(let key):
            if let m = MetricCatalog.metric(key: key, source: "my-whoop") { todayPanel = .metric(m) }
        }
    }

    private var waterRow: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 12) {
                NunaIconTile("drop", tint: NunaPalette.effortText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water today").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "\(liters(waterML)) of \(liters(goalML)) L"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Spacer(minLength: 4)
                Button { Task { await undoWater() } } label: {
                    Image(systemName: "minus").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Remove last drink"))
                Button { Task { await addWater(250) } } label: { Text("+250") }
                    .buttonStyle(.nuna(.primary, height: 44)).fixedSize()
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
                Image(systemName: icon).font(.nuna(size: 22, weight: .semibold))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 60, height: 60)
                    .background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
#endif
