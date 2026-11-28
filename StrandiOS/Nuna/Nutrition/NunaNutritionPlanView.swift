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
    @State private var showPlan = false

    private static let paces: [Double] = [-1, -0.75, -0.5, -0.25, 0, 0.25, 0.5]
    private var weightKg: Double { NunaFoodStore.planWeightKg(weights: weights, profile: profile) ?? 70 }
    private var computedTarget: Double? { maintenance.map { NutritionMath.dailyTarget(maintenanceKcal: $0.kcal, weeklyChangeKg: pace) } }
    private var macros: NutritionMath.Macros? { hasPlan && targetKcal > 0 ? NutritionMath.macroTargets(kcal: targetKcal, weightKg: weightKg, proteinPerKg: proteinPerKg, fatShare: fatShare) : nil }
    private var checkIn: NutritionMath.CheckIn? {
        guard hasPlan, targetKcal > 0 else { return nil }
        return NutritionMath.checkIn(trend: NutritionMath.trend(weights), intake: intake, endDay: Repository.localDayKey(Date()), plannedKgPerWeek: pace, currentTarget: targetKcal)
    }

    var body: some View {
        NunaDetailScreen("Strategy", centersTitle: true) {
            hero
            planPanel
            if hasPlan, targetKcal > 0 { macroTiles }
            if !hasPlan { startButton }
            if coachEnabled { anyaAsk }
            if hasPlan, targetKcal > 0 { weekSection; checkInCard }
            NunaExpandRow(title: "How this is worked out", subtitle: "", systemImage: "function",
                          text: "Your trend weight smooths each weigh-in so water and salt swings don't read as fat. What your body spends is worked out from what you ate and how the trend moved, at 7,700 kcal per kg, once there are two weeks of both; until then it comes from your profile. The target is that figure plus your pace. Protein follows your body weight, fat is a share of the calories and carbs are the rest. Everything is an estimate from your own numbers, not medical advice.")
        }
        .sheet(isPresented: $showGoal) {
            NunaNumberSheet(title: "Goal weight", unit: "kg", initial: goalKg > 0 ? goalKg : weightKg, range: 25...250, step: 0.5, decimals: 1) { goalKg = $0 }
        }
        .sheet(isPresented: $showPlan) { NunaAnyaSheet(context: "nutrition", planRequest: true) }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { await load() }
    }

    private func load() async {
        intake = await NunaFoodStore.intakeByDay(days: 30, repo: repo)
        weights = await NunaFoodStore.weights(days: 120, repo: repo)
        maintenance = NunaFoodStore.maintenance(intake: intake, weights: weights, profile: profile)
    }

    // MARK: Plan

    /// The day's target in the ring, filled by how much of it has been eaten today. Before a plan is started the ring is empty and says so.
    private var hero: some View {
        let target = hasPlan && targetKcal > 0 ? targetKcal : computedTarget
        let eaten = intake[Repository.localDayKey(Date())] ?? 0
        let over = hasPlan && eaten > (target ?? .infinity)
        return NunaScoreHero(caption: "Daily target", fraction: target.map { hasPlan && $0 > 0 ? eaten / $0 : 0 } ?? 0, number: nutFmt(target),
                             suffix: hasPlan ? String(localized: "kcal · \(nutFmt(eaten)) eaten today") : String(localized: "kcal · not started yet"),
                             color: over ? NunaPalette.warning : NunaPalette.charge,
                             hasNote: false, showsCaptionRow: false, ringTitle: "Target", ringSize: 280) { EmptyView() }
            .padding(.top, 4)
    }

    /// What the target is made from, under the ring that shows it.
    private var planPanel: some View {
        NunaSignalPanel {
            Button { showGoal = true } label: {
                editable(NunaFigureRow(title: "Goal weight", icon: "scalemass", value: goalKg > 0 ? nutFmt(goalKg, 1) : String(localized: "Not set"), unit: goalKg > 0 ? "kg" : ""))
            }.buttonStyle(.plain)
            NunaDivider()
            NunaMenu {
                ForEach(Self.paces, id: \.self) { p in
                    NunaMenuItem(verbatim: paceLabel(p), selected: pace == p) { pace = p; recalculate() }
                }
            } label: { editable(NunaFigureRow(title: "Pace", icon: "speedometer", value: paceAmount(pace), unit: pace == 0 ? "" : String(localized: "kg/week"))) }
            NunaDivider()
            NunaFigureRow(title: "Daily burn", icon: "flame", value: maintenance.map { nutFmt($0.kcal) } ?? "–", unit: maintenance == nil ? "" : String(localized: "kcal"))
                .padding(.trailing, 22)
            note(maintenanceNote)
            if hasPlan, let c = computedTarget, abs(c - targetKcal) >= 10 {
                NunaDivider()
                Button { recalculate() } label: {
                    editable(NunaFigureRow(title: "Target from this pace", icon: "arrow.counterclockwise", value: nutFmt(c), unit: String(localized: "kcal")))
                }.buttonStyle(.plain)
                note(String(localized: "Your target is set to \(nutFmt(targetKcal)) kcal. Tap to use the figure from this pace."))
            }
            if let c = computedTarget, c <= NutritionMath.floorKcal + 0.5 {
                Text(verbatim: String(localized: "This pace would go under \(nutFmt(NutritionMath.floorKcal)) kcal, so the target stops there."))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        }
    }

    /// A row that can be changed carries a chevron.
    private func editable<Row: View>(_ row: Row) -> some View {
        HStack(spacing: 10) {
            row
            Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted).frame(width: 12)
        }
        .contentShape(Rectangle())
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 44).padding(.bottom, 8)
    }

    /// The three macros of the target, in the order and colours of the Nutrition page. Protein and fat are chosen here; carbs are what is left.
    private var macroTiles: some View {
        HStack(alignment: .top, spacing: 10) {
            macroTile("Carbs", grams: macros?.carbsG, kcalPerGram: 4, detail: String(localized: "the rest"), color: NunaPalette.effort, editable: false)
            NunaMenu {
                ForEach([1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4], id: \.self) { v in
                    NunaMenuItem(verbatim: "\(nutFmt(v, 1)) g/kg", selected: proteinPerKg == v) { proteinPerKg = v }
                }
            } label: { macroTile("Protein", grams: macros?.proteinG, kcalPerGram: 4, detail: "\(nutFmt(proteinPerKg, 1)) g/kg", color: NunaPalette.charge, editable: true) }
            NunaMenu {
                ForEach([0.20, 0.25, 0.28, 0.30, 0.35, 0.40], id: \.self) { v in
                    NunaMenuItem(verbatim: "\(Int(v * 100))%", selected: abs(fatShare - v) < 0.001) { fatShare = v }
                }
            } label: { macroTile("Fat", grams: macros?.fatG, kcalPerGram: 9, detail: String(localized: "\(Int((fatShare * 100).rounded()))% chosen"), color: NunaPalette.warning, editable: true) }
        }
    }

    private func macroTile(_ title: LocalizedStringKey, grams: Double?, kcalPerGram: Double, detail: String, color: Color, editable: Bool) -> some View {
        let share = targetKcal > 0 ? (grams ?? 0) * kcalPerGram / targetKcal : 0
        return NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(title).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if editable { Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: nutFmt(grams)).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: "g").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                NunaProgressBar(fraction: share, color: color)
                Text(verbatim: String(localized: "\(Int((share * 100).rounded()))% of energy")).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.6).textCase(nil)
                Text(verbatim: detail).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).lineLimit(1).minimumScaleFactor(0.6).textCase(nil)
            }
        }
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button { startPlan() } label: {
                Text("Start this plan").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 52)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(computedTarget == nil).opacity(computedTarget == nil ? 0.5 : 1)
            Text("A starting point from your own numbers. Not medical advice.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
    }

    // MARK: Anya

    private var anyaAsk: some View {
        VStack(spacing: 10) {
            Button { showPlan = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.nuna(size: 15, weight: .bold))
                    Text("Ask Anya for a plan").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!coach.isConfigured).opacity(coach.isConfigured ? 1 : 0.5)
            if !coach.isConfigured {
                Text("Connect Anya in More to use this.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private func paceLabel(_ p: Double) -> String {
        if p == 0 { return String(localized: "Maintain weight") }
        let amount = nutFmt(abs(p), 2).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return p < 0 ? String(localized: "Lose \(amount) kg a week") : String(localized: "Gain \(amount) kg a week")
    }

    /// The pace as a signed figure, or the word for holding still.
    private func paceAmount(_ p: Double) -> String {
        if p == 0 { return String(localized: "Maintain") }
        return (p < 0 ? "−" : "+") + nutFmt(abs(p), 2).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
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

    /// The last seven days of the diary, drawn as the app's other weekly cards are, with how many of them landed on the target.
    private var weekSection: some View {
        let today = Date()
        let keys = (0..<7).map { Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -$0, to: today) ?? today) }
        let target = targetKcal
        let hit: (Double) -> Bool = { $0 >= target * 0.9 && $0 <= target * 1.1 }
        let onTarget = keys.filter { intake[$0].map(hit) ?? false }.count
        return VStack(spacing: 10) {
            NunaWeeklyTrendCard(title: "Eaten this week", key: "diary_kcal", style: .bars, color: NunaPalette.charge,
                                barFill: { v, _ in hit(v) ? NunaPalette.charge : NunaPalette.warning },
                                labelFill: { v, _ in hit(v) ? NunaPalette.charge : NunaPalette.warning },
                                points: keys.compactMap { k in intake[k].map { (day: k, value: $0) } }, valueText: { nutFmt($0) }, autoScale: true)
            HStack(spacing: 10) {
                Text(verbatim: String(localized: "On target means within 10% of \(nutFmt(target)) kcal.")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
                Spacer(minLength: 6)
                NunaChip(LocalizedStringKey("\(onTarget) of 7 on target"), color: onTarget >= 5 ? NunaPalette.charge : nil)
            }
            .padding(.horizontal, 4)
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
