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
    @State private var presented: Panel?
    @State private var waterML = 0
    @State private var goalML = 2500

    private enum Panel: String, Identifiable { case breathing, nap, weight; var id: String { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick actions")
                .font(.system(size: NunaTypeSize.h2, weight: .heavy, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
                .padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                tile("Add activity", "plus", nil) { dismiss(); onAddActivity() }
                tile("Start session", "play", NunaPalette.charge) { go(.activeWorkout) }
                tile("Journal", "bookmark", nil) { go(.journal) }
                tile("Breathing", "wind", NunaPalette.charge) { presented = .breathing }
                tile("Nap", "moon", nil) { presented = .nap }
                tile("Weight", "scalemass", NunaPalette.effortText) { presented = .weight }
            }
            if coachEnabled {
                Button { go(.coach) } label: {
                    NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                .frame(width: 40, height: 40).background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask Anya").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text("About today, by voice or text").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
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
        .preferredColorScheme(.dark)
        .task { await reloadWater() }
        .sheet(item: $presented) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .breathing: BreathingView()
                    case .nap: NunaNapView().nunaTodayDestinations()
                    case .weight:
                        if let m = MetricCatalog.metric(key: "weight", source: "apple-health") { NunaMetricDetailView(metric: m) }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { presented = nil } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var waterRow: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 12) {
                NunaIconTile("drop", tint: NunaPalette.effortText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water today").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "\(liters(waterML)) of \(liters(goalML)) L"))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Spacer(minLength: 4)
                Button { Task { await undoWater() } } label: {
                    Image(systemName: "minus").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
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
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint ?? NunaPalette.textPrimary)
                    .frame(width: 60, height: 60)
                    .background((tint.map { NunaPalette.tint($0) }) ?? Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(title).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
#endif
