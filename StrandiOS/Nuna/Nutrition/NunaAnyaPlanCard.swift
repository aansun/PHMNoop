#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// A nutrition plan Anya worked out from the person's data. It shows the numbers next to what is set now, the data each rests on and anything to take to a
/// clinician; nothing changes until the person taps Apply. Used in the Anya chat and on the Strategy screen.
struct NunaAnyaPlanCard: View {
    let spec: AnyaPlanSpec
    /// Called when the person discards the suggestion; the screen drops it so nothing is left behind.
    var onDiscard: (() -> Void)?
    @State private var discarded = false
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false
    @AppStorage(NunaNutritionPrefs.targetKcal) private var targetKcal = 0.0
    @AppStorage(NunaNutritionPrefs.paceKgPerWeek) private var pace = -0.5
    @AppStorage(NunaNutritionPrefs.proteinPerKg) private var proteinPerKg = NunaNutritionPrefs.defaultProteinPerKg
    @AppStorage(NunaNutritionPrefs.fatShare) private var fatShare = NunaNutritionPrefs.defaultFatShare
    @AppStorage(NunaNutritionPrefs.lastCheckIn) private var lastCheckIn = ""
    @State private var applied = false
    @State private var labCautions: [String] = []
    @State private var showNutrition = false

    /// What the model flagged, then every Lab Book value that sits outside the range from the person's own report, worked out here rather than left to the model.
    private var allCautions: [String] { spec.cautions + labCautions }

    private var newPace: Double { spec.paceKgPerWeek ?? pace }
    private var newProtein: Double { spec.proteinPerKg ?? proteinPerKg }
    private var newFat: Double { spec.fatShare ?? fatShare }
    private var macros: NutritionMath.Macros {
        NutritionMath.macroTargets(kcal: spec.targetKcal, weightKg: profile.weightKg > 0 ? profile.weightKg : 70, proteinPerKg: newProtein, fatShare: newFat)
    }

    var body: some View {
        if !discarded { card }
    }

    private var card: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    NunaIconTile("target")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan from Anya").font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Text("Worked out from your own data").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    line("Daily target", "\(nutFmt(spec.targetKcal)) kcal", was: hasPlan && targetKcal > 0 && abs(targetKcal - spec.targetKcal) >= 1 ? "\(nutFmt(targetKcal))" : nil)
                    NunaDivider()
                    line("Pace", paceText(newPace), was: nil)
                    NunaDivider()
                    line("Protein", "\(nutFmt(newProtein, 1)) g/kg · \(nutFmt(macros.proteinG)) g", was: nil)
                    NunaDivider()
                    line("Fat", "\(Int((newFat * 100).rounded()))% · \(nutFmt(macros.fatG)) g", was: nil)
                    NunaDivider()
                    line("Carbs", String(localized: "the rest · \(nutFmt(macros.carbsG)) g"), was: nil)
                }
                if let explanation = spec.explanation {
                    VStack(alignment: .leading, spacing: 6) {
                        nunaTrendsCap("How Anya got here")
                        Text(verbatim: explanation).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
                if !spec.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        nunaTrendsCap("Based on")
                        ForEach(spec.reasons, id: \.self) { r in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(NunaPalette.textMuted).padding(.top, 7)
                                Text(verbatim: r).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                    }
                }
                whoSection
                if !allCautions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(allCautions, id: \.self) { c in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.warning).padding(.top, 2)
                                Text(verbatim: c).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                    }
                }
                if applied {
                    HStack(spacing: 10) {
                        Label(String(localized: "Plan applied"), systemImage: "checkmark.circle.fill").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Spacer()
                        Button { showNutrition = true } label: { Text("Open Nutrition").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button { apply() } label: {
                            Text("Apply this plan").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                        Button { discarded = true; onDiscard?() } label: {
                            Text("Discard").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 20).frame(height: 46)
                                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    Text("A suggestion from your own numbers, not medical advice. Nothing changes until you apply it.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        .sheet(isPresented: $showNutrition) { NunaQuickPanel(route: NunaTodayRoute.nutrition) }
        .task {
            let markers = NunaLabGrouping.markers(await NunaLabStore.load(repo))
            labCautions = markers.compactMap { m -> String? in
                guard m.category != .bodyMeasurement, let latest = m.latest, let s = m.latestStatus, s != .within, let r = m.ownRange else { return nil }
                return String(localized: "\(m.name) \(m.text(latest)) \(m.unit) is \(s == .above ? String(localized: "above") : String(localized: "below")) the range on your own report (\(r.label(key: m.key))). Talk to your clinician before changing how you eat because of it.")
            }
        }
    }

    // MARK: WHO references

    private struct WhoLine: Identifiable { let id = UUID(); let text: String; let fits: Bool? }

    /// The plan against the WHO references for healthy adults, worked out here from the numbers on the card: BMI and healthy weight at the profile height,
    /// protein per kg, and the shares of energy from fat and carbohydrate.
    private var whoLines: [WhoLine] {
        var out: [WhoLine] = []
        let kg = profile.weightKg, cm = profile.heightCm
        if kg > 20, let r = WhoBodyReference.weightRangeKg(heightCm: cm) {
            let bmi = kg / pow(cm / 100, 2)
            let word: String
            switch WhoNutritionReference.bmiClass(bmi) {
            case .underweight: word = String(localized: "below the WHO healthy range")
            case .normal: word = String(localized: "in the WHO healthy range")
            case .overweight: word = String(localized: "above the WHO healthy range (overweight)")
            case .obese: word = String(localized: "above the WHO healthy range (obesity)")
            }
            out.append(WhoLine(text: String(localized: "BMI \(nutFmt(bmi, 1)) is \(word) of 18.5 to 24.9, which is \(nutFmt(r.low, 1)) to \(nutFmt(r.high, 1)) kg at your height."), fits: WhoNutritionReference.bmiClass(bmi) == .normal))
        }
        let protein = newProtein
        out.append(WhoLine(text: protein >= WhoNutritionReference.proteinSafeGPerKg
                           ? String(localized: "Protein \(nutFmt(protein, 1)) g/kg is above the WHO safe level of intake, 0.83 g/kg a day.")
                           : String(localized: "Protein \(nutFmt(protein, 1)) g/kg is under the WHO safe level of intake, 0.83 g/kg a day."), fits: protein >= WhoNutritionReference.proteinSafeGPerKg))
        if let s = WhoNutritionReference.shares(proteinG: macros.proteinG, carbsG: macros.carbsG, fatG: macros.fatG) {
            out.append(WhoLine(text: String(localized: "Fat is \(Int((s.fat * 100).rounded()))% of the energy; WHO suggests 20 to 35%."), fits: WhoNutritionReference.fatShareRange.contains(s.fat)))
            out.append(WhoLine(text: String(localized: "Carbohydrate is \(Int((s.carbs * 100).rounded()))% of the energy; WHO suggests 55 to 75%."), fits: WhoNutritionReference.carbShareRange.contains(s.carbs)))
        }
        return out
    }

    @ViewBuilder private var whoSection: some View {
        let lines = whoLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                nunaTrendsCap("Against WHO references")
                ForEach(lines) { l in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: l.fits == true ? "checkmark.circle.fill" : "info.circle.fill").font(.nuna(size: 14, weight: .bold))
                            .foregroundStyle(l.fits == true ? NunaPalette.charge : NunaPalette.textSecondary).padding(.top, 2)
                        Text(verbatim: l.text).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
                Text("General references for healthy adults. Your own situation can reasonably differ; this is not medical advice.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    private func line(_ label: LocalizedStringKey, _ value: String, was: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 8)
            if let was { Text(verbatim: was).font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted).strikethrough() }
            Text(verbatim: value).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
        }.padding(.vertical, 10)
    }

    private func paceText(_ p: Double) -> String {
        if p == 0 { return String(localized: "Maintain weight") }
        let amount = nutFmt(abs(p), 2).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return p < 0 ? String(localized: "Lose \(amount) kg a week") : String(localized: "Gain \(amount) kg a week")
    }

    private func apply() {
        pace = newPace; proteinPerKg = newProtein; fatShare = newFat
        targetKcal = spec.targetKcal; hasPlan = true; lastCheckIn = Repository.localDayKey(Date())
        NunaDataChanges.shared.bump()
        applied = true
    }
}
#endif
