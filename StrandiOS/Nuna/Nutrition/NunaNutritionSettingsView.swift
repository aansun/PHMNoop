#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The gear on the Nutrition page: the plan, importing a CSV and whether Anya speaks up unprompted.
struct NunaNutritionSettingsView: View {
    @AppStorage(NunaNutritionPrefs.nudges) private var nudges = true
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false
    @State private var learned: [LearnedFood] = []

    var body: some View {
        NunaDetailScreen("Nutrition settings") {
            NunaSettingsSection("Your plan") {
                NunaSettingsCard {
                    NavigationLink { NunaNutritionPlanView() } label: {
                        NunaListRow("Strategy", subtitle: hasPlan ? LocalizedStringKey("Your plan, targets and weekly check-in") : LocalizedStringKey("Set a pace and get a daily target"), systemImage: "target", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("Import") {
                NunaSettingsCard {
                    NavigationLink(value: TabRoute.dataSources) {
                        NunaListRow("Import CSV", subtitle: "From Cronometer or MacroFactor, processed on this phone", systemImage: "square.and.arrow.down", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("Anya") {
                NunaSettingsSwitch("Anya speaks up", subtitle: "Tells you when the day runs over or short of your target", systemImage: "sparkles", isOn: $nudges)
            }
            NunaSettingsSection("Your food figures") { learnedFoods }
        }
        .onAppear { learned = NunaFoodMemoryStore.load() }
    }

    /// What was learned from corrections, each with a way to forget it.
    private var learnedFoods: some View {
        NunaSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                if learned.isEmpty {
                    Text("Nothing yet. Change a figure with the pencil on an estimate and it is remembered here.").font(.nuna(size: 13.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.vertical, 12)
                }
                ForEach(Array(learned.enumerated()), id: \.element.id) { i, food in
                    if i > 0 { NunaDivider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: food.name).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                            Text(verbatim: [food.amount, String(localized: "\(Int(food.kcal.rounded())) kcal")].compactMap { $0 }.joined(separator: " · "))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 6)
                        Button { NunaFoodMemoryStore.forget(id: food.id); learned = NunaFoodMemoryStore.load() } label: {
                            Image(systemName: "trash").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 36)
                        }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
}
#endif
