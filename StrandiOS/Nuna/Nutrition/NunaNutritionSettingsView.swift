#if os(iOS)
import SwiftUI
import StrandDesign

/// The gear on the Nutrition page: the plan, importing a CSV and whether Anya speaks up unprompted.
struct NunaNutritionSettingsView: View {
    @AppStorage(NunaNutritionPrefs.nudges) private var nudges = true
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false

    var body: some View {
        NunaDetailScreen("Nutrition settings") {
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12)) {
                VStack(spacing: 0) {
                    NavigationLink { NunaNutritionPlanView() } label: {
                        NunaListRow("Strategy", subtitle: hasPlan ? LocalizedStringKey("Your plan, targets and weekly check-in") : LocalizedStringKey("Set a pace and get a daily target"), systemImage: "target", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: TabRoute.dataSources) {
                        NunaListRow("Import CSV", subtitle: "From Cronometer or MacroFactor, processed on this phone", systemImage: "square.and.arrow.down", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12)) {
                NunaToggleRow("Anya speaks up", subtitle: "Tells you when the day runs over or short of your target", systemImage: "sparkles", isOn: $nudges)
            }
        }
    }
}
#endif
