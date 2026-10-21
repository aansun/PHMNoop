#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Strategy: the pace the person wants, the daily target and macros that follow from it, how the week went and the weekly check-in.
struct NunaNutritionPlanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @AppStorage(NunaNutritionPrefs.hasPlan) private var hasPlan = false
    @AppStorage(NunaNutritionPrefs.targetKcal) private var targetKcal = 0.0
    @AppStorage(NunaNutritionPrefs.paceKgPerWeek) private var pace = -0.5
    @AppStorage(NunaNutritionPrefs.proteinPerKg) private var proteinPerKg = NunaNutritionPrefs.defaultProteinPerKg
    @AppStorage(NunaNutritionPrefs.fatShare) private var fatShare = NunaNutritionPrefs.defaultFatShare
    @AppStorage(NunaNutritionPrefs.lastCheckIn) private var lastCheckIn = ""
    @AppStorage(NunaGoals.targetWeightKg) private var goalKg = 0.0
    @State private var intake: [String: Double] = [:]
    @State private var weights: [NutritionMath.WeightPoint] = []
    @State private var maintenance: (kcal: Double, source: NunaFoodStore.MaintenanceSource)?
    @State private var showGoal = false
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var asking = false
    @State private var suggestion: AnyaPlanSpec?
    @State private var askError: String?

    private static let paces: [Double] = [-1, -0.75, -0.5, -0.25, 0, 0.25, 0.5]
    private var trendKg: Double? { NutritionMath.trend(weights).last?.kg }
    private var weightKg: Double { trendKg ?? (profile.weightKg > 0 ? profile.weightKg : 70) }
    private var computedTarget: Double? { maintenance.map { NutritionMath.dailyTarget(maintenanceKcal: $0.kcal, weeklyChangeKg: pace) } }
    private var macros: NutritionMath.Macros? { hasPlan && targetKcal > 0 ? NutritionMath.macroTargets(kcal: targetKcal, weightKg: weightKg, proteinPerKg: proteinPerKg, fatShare: fatShare) : nil }
    private var checkIn: NutritionMath.CheckIn? {
        guard hasPlan, targetKcal > 0 else { return nil }
        return NutritionMath.checkIn(trend: NutritionMath.trend(weights), intake: intake, endDay: Repository.localDayKey(Date()), plannedKgPerWeek: pace, currentTarget: targetKcal)
    }

    var body: some View {
        NunaDetailScreen("Strategy") {
            planCard
            if coachEnabled { anyaAsk }
            if hasPlan, targetKcal > 0 { weekCard; checkInCard }
            NunaExpandRow(title: "How this is worked out", subtitle: "", systemImage: "function",
                          text: "Your trend weight smooths each weigh-in so water and salt swings don't read as fat. What your body spends is worked out from what you ate and how the trend moved, at 7,700 kcal per kg, once there are two weeks of both; until then it comes from your profile. The target is that figure plus your pace. Protein follows your body weight, fat is a share of the calories and carbs are the rest. Everything is an estimate from your own numbers, not medical advice.")
        }
        .sheet(isPresented: $showGoal) {
            NunaNumberSheet(title: "Goal weight", unit: "kg", initial: goalKg > 0 ? goalKg : weightKg, range: 25...250, step: 0.5, decimals: 1) { goalKg = $0 }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { await load() }
    }

    private func load() async {
        intake = await NunaFoodStore.intakeByDay(days: 30, repo: repo)
        weights = await NunaFoodStore.weights(days: 120, repo: repo)
        maintenance = NunaFoodStore.maintenance(intake: intake, weights: weights, profile: profile)
    }

    // MARK: Plan

    private var planCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    nunaTrendsCap("Your plan")
                    Spacer()
                    if hasPlan { Button { hasPlan = false; targetKcal = 0 } label: { Text("Remove").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain) }
                }.padding(.bottom, 6)
                row("Goal weight") {
                    Button { showGoal = true } label: { value(goalKg > 0 ? "\(nutFmt(goalKg, 1)) kg" : String(localized: "Not set")) }.buttonStyle(.plain)
                }
                NunaDivider()
                row("Pace") {
                    Menu {
                        ForEach(Self.paces, id: \.self) { p in
                            Button { pace = p; recalculate() } label: { if pace == p { Label(paceLabel(p), systemImage: "checkmark") } else { Text(verbatim: paceLabel(p)) } }
                        }
                    } label: { value(paceLabel(pace)) }
                }
                NunaDivider()
                row("Daily burn") {
                    VStack(alignment: .trailing, spacing: 2) {
                        value(maintenance.map { "\(nutFmt($0.kcal)) kcal" } ?? "–")
                        Text(maintenanceNote).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                }
                NunaDivider()
                row("Daily target") {
                    VStack(alignment: .trailing, spacing: 2) {
                        value(hasPlan && targetKcal > 0 ? "\(nutFmt(targetKcal)) kcal" : (computedTarget.map { "\(nutFmt($0)) kcal" } ?? "–"))
                        if hasPlan, let c = computedTarget, abs(c - targetKcal) >= 10 {
                            Button { recalculate() } label: { Text(verbatim: String(localized: "Reset to \(nutFmt(c))")).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain)
                        }
                    }
                }
                if let c = computedTarget, c <= NutritionMath.floorKcal + 0.5 {
                    Text(verbatim: String(localized: "This pace would go under \(nutFmt(NutritionMath.floorKcal)) kcal, so the target stops there.")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil).padding(.top, 8)
                }
                if hasPlan {
                    NunaDivider()
                    row("Protein") {
                        Menu {
                            ForEach([1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4], id: \.self) { v in
                                Button { proteinPerKg = v } label: { if proteinPerKg == v { Label("\(nutFmt(v, 1)) g/kg", systemImage: "checkmark") } else { Text(verbatim: "\(nutFmt(v, 1)) g/kg") } }
                            }
                        } label: { value("\(nutFmt(proteinPerKg, 1)) g/kg · \(nutFmt(macros?.proteinG)) g") }
                    }
                    NunaDivider()
                    row("Fat") {
                        Menu {
                            ForEach([0.20, 0.25, 0.28, 0.30, 0.35, 0.40], id: \.self) { v in
                                Button { fatShare = v } label: { if abs(fatShare - v) < 0.001 { Label("\(Int(v * 100))%", systemImage: "checkmark") } else { Text(verbatim: "\(Int(v * 100))%") } }
                            }
                        } label: { value("\(Int((fatShare * 100).rounded()))% · \(nutFmt(macros?.fatG)) g") }
                    }
                    NunaDivider()
                    row("Carbs") { value(String(localized: "the rest · \(nutFmt(macros?.carbsG)) g")) }
                }
                if !hasPlan {
                    Button { startPlan() } label: {
                        Text("Start this plan").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 50)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(computedTarget == nil).opacity(computedTarget == nil ? 0.5 : 1).padding(.top, 14)
                    Text("A starting point from your own numbers. Not medical advice.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(.top, 8)
                }
            }
        }
    }

    // MARK: Anya

    private var anyaAsk: some View {
        VStack(spacing: 10) {
            Button { Task { await askAnya() } } label: {
                HStack(spacing: 8) {
                    if asking { ProgressView().tint(NunaPalette.textPrimary) } else { Image(systemName: "sparkles").font(.nuna(size: 15, weight: .bold)) }
                    Text(asking ? "Working it out…" : "Ask Anya for a plan").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(asking || !coach.isConfigured).opacity(asking || !coach.isConfigured ? 0.5 : 1)
            if !coach.isConfigured {
                Text("Connect Anya in More to use this.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            if let askError { Text(verbatim: askError).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
            if let suggestion { NunaAnyaPlanCard(spec: suggestion, onDiscard: { self.suggestion = nil }).id(suggestion.targetKcal) }
        }
    }

    private func askAnya() async {
        asking = true; suggestion = nil; askError = nil
        defer { asking = false }
        let snapshot = await NunaNutritionSnapshot.build(repo: repo, profile: profile, includeLabBook: coach.includeOnDeviceSignals)
        guard let reply = await coach.suggestNutritionPlan(snapshot: snapshot) else {
            askError = String(localized: "Anya couldn't answer. Check her connection in More, then try again."); return
        }
        if let spec = AnyaActions.parse(reply).compactMap({ b -> AnyaPlanSpec? in if case .plan(let p) = b { return p } else { return nil } }).first { suggestion = spec }
        else { askError = String(localized: "Anya didn't return a plan this time. Try again.") }
    }

    private func row<T: View>(_ label: LocalizedStringKey, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center) {
            Text(label).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 10)
            trailing()
        }.padding(.vertical, 12)
    }

    private func value(_ text: String) -> some View {
        Text(verbatim: text).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.trailing).textCase(nil)
    }

    private func paceLabel(_ p: Double) -> String {
        if p == 0 { return String(localized: "Maintain weight") }
        let amount = nutFmt(abs(p), 2).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return p < 0 ? String(localized: "Lose \(amount) kg a week") : String(localized: "Gain \(amount) kg a week")
    }

    private var maintenanceNote: String {
        switch maintenance?.source {
        case .foodAndWeight: return String(localized: "From your food and weight")
        case .profile: return String(localized: "From your profile for now")
        case nil: return String(localized: "Add your height and weight")
        }
    }

    private func startPlan() {
        guard let c = computedTarget else { return }
        targetKcal = c; hasPlan = true; lastCheckIn = Repository.localDayKey(Date())
    }

    private func recalculate() {
        if hasPlan, let c = computedTarget { targetKcal = c }
    }

    // MARK: Week

    private var weekCard: some View {
        let today = Date()
        let days: [(key: String, label: String)] = (0..<7).reversed().map { back in
            let d = Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEEE")
            return (Repository.localDayKey(d), f.string(from: d))
        }
        let ceiling = max(targetKcal * 1.35, days.compactMap { intake[$0.key] }.max() ?? 0)
        let onTarget = days.filter { d in intake[d.key].map { $0 >= targetKcal * 0.9 && $0 <= targetKcal * 1.1 } ?? false }.count
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("This week")
                    Spacer()
                    NunaChip(LocalizedStringKey("\(onTarget) of 7 on target"), color: onTarget >= 5 ? NunaPalette.charge : nil)
                }
                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(days, id: \.key) { d in
                                let v = intake[d.key]
                                let ok = v.map { $0 >= targetKcal * 0.9 && $0 <= targetKcal * 1.1 } ?? false
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(v == nil ? NunaPalette.tile : (ok ? NunaPalette.charge : NunaPalette.warning))
                                    .frame(height: max(6, geo.size.height * CGFloat((v ?? ceiling * 0.06) / max(ceiling, 1))))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Rectangle().fill(NunaPalette.textMuted).frame(height: 1)
                            .offset(y: -geo.size.height * CGFloat(targetKcal / max(ceiling, 1)))
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
                }.frame(height: 110)
                HStack(spacing: 10) { ForEach(days, id: \.key) { d in Text(verbatim: d.label).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity) } }
                Text("The line is your target. On target means within 10% of it.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    // MARK: Check-in

    @ViewBuilder private var checkInCard: some View {
        NunaCard(highlight: checkIn != nil) {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Weekly check-in")
                if let c = checkIn {
                    Text(verbatim: String(localized: "Your trend weight moved \(nutFmt(c.actualKgPerWeek, 2)) kg a week, against the \(nutFmt(c.plannedKgPerWeek, 2)) kg you planned. A change of \(nutFmt(abs(c.changeKcal))) kcal a day would bring you back to the plan."))
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: "\(nutFmt(targetKcal)) → \(nutFmt(c.newTarget)) kcal").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    HStack(spacing: 10) {
                        Button { targetKcal = c.newTarget; lastCheckIn = Repository.localDayKey(Date()) } label: {
                            Text("Apply").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                        Button { lastCheckIn = Repository.localDayKey(Date()) } label: {
                            Text(verbatim: String(localized: "Keep \(nutFmt(targetKcal))")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    Text("A suggestion from your own numbers, not medical advice. You decide.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                } else {
                    Text("Nothing to change. A check-in needs at least 5 days of food logged this week and weigh-ins across a week; when your trend drifts from your pace, a suggestion shows up here and on the Nutrition page.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }
}
#endif
