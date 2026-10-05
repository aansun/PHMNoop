#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Today's plan (AnyaPlan.dc): a suggested session built on this iPhone from Charge, yesterday's Effort, the load band and
/// the wearer's own heart-rate zones. It needs no provider. Asking Anya to change it hands the plan to the conversation.
/// Today's suggested session worked out from the stored numbers. Shared by the plan screen and the Anya card on Today,
/// so both always show the same session.
struct NunaDayPlanResult {
    var plan: DayPlan.Plan
    var charge: Int
    var yesterdayEffort: Double?
    var band: TrendInsights.LoadBand?

    var title: String {
        switch plan.kind {
        case .recovery: return String(localized: "Easy movement, \(plan.totalMinutes) min")
        case .easy: return String(localized: "Easy zone 2, \(plan.totalMinutes) min")
        case .steady: return String(localized: "Steady zone 2, \(plan.totalMinutes) min")
        case .quality: return String(localized: "Tempo session, \(plan.totalMinutes) min")
        }
    }

    @MainActor static func load(repo: Repository, profile: ProfileStore) async -> NunaDayPlanResult? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        guard let c = m.charge.pct else { return nil }
        let days = repo.days
        let y = days.dropLast().last?.strain
        let efforts = days.compactMap(\.strain).filter { $0 > 0 }.suffix(30).sorted()
        let usual = efforts.isEmpty ? nil : efforts[efforts.count / 2]
        // Six 7-day blocks of daily Effort for the load band.
        let blocks: [Double] = (0..<6).reversed().map { w in
            let slice = days.suffix(7 * (w + 1)).prefix(7)
            return slice.compactMap(\.strain).reduce(0, +)
        }
        let b = TrendInsights.loadRatio(blocks: blocks).map(TrendInsights.loadBand)
        let rows = await repo.workoutRows()
        let from = Int(Date().addingTimeInterval(-60 * 86_400).timeIntervalSince1970)
        let perMinute = rows.filter { $0.startTs >= from }.compactMap { r -> Double? in
            guard let s = r.strain, s > 0, let d = r.durationS ?? Optional(Double(r.endTs - r.startTs)), d > 300 else { return nil }
            return s / (d / 60)
        }
        let plan = DayPlan.plan(charge: c, yesterdayEffort: y, usualEffort: usual, loadBand: b, effortPerMinute: perMinute)
        return NunaDayPlanResult(plan: plan, charge: Int(c.rounded()), yesterdayEffort: y, band: b)
    }
}

struct NunaAnyaPlanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var plan: DayPlan.Plan?
    @State private var charge: Int?
    @State private var yesterdayEffort: Double?
    @State private var band: TrendInsights.LoadBand?
    @State private var loaded = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var zones: HRZoneSet { profile.hrZoneSet }

    var body: some View {
        NunaDetailScreen("Today's plan") {
            if let plan, let charge {
                header(plan, charge)
                stepsCard(plan)
                zonesCard(plan)
                whyCard(plan, charge)
                actions(plan, charge)
            } else if loaded {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No plan yet").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Anya needs today's Charge to suggest a session. Wear the strap overnight and sync, then come back.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("A suggestion from your own numbers, not a prescription. Listen to how you feel and stop if something hurts.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    // MARK: Cards

    private func header(_ plan: DayPlan.Plan, _ charge: Int) -> some View {
        NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Planned for you")
                    Spacer()
                    NunaChip(verbatim: String(localized: "Charge \(charge)%"))
                }
                Text(verbatim: title(plan)).font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: blurb(plan.kind)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                NunaDivider()
                HStack {
                    tile("Duration", String(format: "%d:00", plan.totalMinutes), nil)
                    tile("Zone", "\(plan.mainZone)", nil)
                    tile("Effort", effortText(plan), effortText(plan) == "–" ? nil : String(localized: "estimated"))
                }
            }
        }
    }

    private func tile(_ l: LocalizedStringKey, _ v: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 21, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(verbatim: note).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepsCard(_ plan: DayPlan.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Steps") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, s in
                        if i > 0 { NunaDivider() }
                        HStack(alignment: .top, spacing: 14) {
                            Text(verbatim: "\(i + 1)").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30).background(NunaPalette.glassStrong, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(phaseName(s.phase)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer()
                                    Text(verbatim: String(localized: "\(s.minutes) min")).font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary) }
                                Text(verbatim: instruction(s, plan.kind)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private func zonesCard(_ plan: DayPlan.Plan) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaTrendsCap("Heart-rate zones"); Spacer(); Text(verbatim: String(localized: "Max \(Int(zones.maxHR)) bpm")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                HStack(spacing: 4) {
                    ForEach(zones.zones, id: \.number) { z in
                        RoundedRectangle(cornerRadius: 6).fill(z.number == plan.mainZone ? NunaPalette.accent : NunaPalette.ink.opacity(0.12)).frame(height: 14)
                    }
                }
                HStack { ForEach(zones.zones, id: \.number) { z in
                    Text(verbatim: "Z\(z.number)").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(z.number == plan.mainZone ? NunaPalette.textPrimary : NunaPalette.textSecondary).frame(maxWidth: .infinity)
                } }
                if let z = zones.zones.first(where: { $0.number == plan.mainZone }) {
                    Text(verbatim: String(localized: "Zone \(plan.mainZone): \(Int(z.lower.rounded()))–\(Int(z.upper.rounded())) bpm")).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
        }
    }

    private func whyCard(_ plan: DayPlan.Plan, _ charge: Int) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                nunaTrendsCap("Why this")
                Text(verbatim: reasons(plan, charge).joined(separator: " ")).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Read:").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    ForEach(readNames, id: \.self) { Text(verbatim: $0).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readNames: [String] {
        var out = ["Charge"]
        if yesterdayEffort != nil { out.append(String(localized: "Effort yesterday")) }
        if band != nil { out.append(String(localized: "Load 6 weeks")) }
        out.append(String(localized: "Heart-rate zones"))
        return out
    }

    private func actions(_ plan: DayPlan.Plan, _ charge: Int) -> some View {
        VStack(spacing: 12) {
            Button {
                router.plannedSession = .init(title: NunaDayPlanResult(plan: plan, charge: charge, yesterdayEffort: nil, band: nil).title, minutes: plan.totalMinutes, zone: plan.mainZone)
                router.requestedDestination = .activeWorkout
            } label: {
                Text("Start session").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: Capsule())
            }.buttonStyle(.plain)
            if coach.isConfigured {
                Button {
                    coach.pendingPrompt = "Here is the session you suggested for today: \(title(plan)), main zone \(plan.mainZone). My Charge is \(charge)%. Adjust it to fit my day and explain the change."
                    router.requestedDestination = .coach
                } label: {
                    Text("Ask Anya to change it").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Words

    private func title(_ p: DayPlan.Plan) -> String {
        switch p.kind {
        case .recovery: return String(localized: "Easy movement, \(p.totalMinutes) min")
        case .easy: return String(localized: "Easy zone 2, \(p.totalMinutes) min")
        case .steady: return String(localized: "Steady zone 2, \(p.totalMinutes) min")
        case .quality: return String(localized: "Tempo session, \(p.totalMinutes) min")
        }
    }

    private func blurb(_ k: DayPlan.Kind) -> String {
        switch k {
        case .recovery: return String(localized: "A light day that helps you recover. Keep it gentle.")
        case .easy: return String(localized: "Enough to keep moving without digging into tomorrow's Charge.")
        case .steady: return String(localized: "A calm, steady effort that builds fitness and protects tomorrow's Charge.")
        case .quality: return String(localized: "Your body is ready for harder work. A controlled tempo session fits.")
        }
    }

    private func phaseName(_ p: DayPlan.Step.Phase) -> LocalizedStringKey {
        switch p { case .warmup: return "Warm-up"; case .main: return "Main"; case .cooldown: return "Cool-down" }
    }

    private func bpm(_ zone: Int) -> String {
        guard let z = zones.zones.first(where: { $0.number == zone }) else { return "" }
        return "\(Int(z.lower.rounded()))–\(Int(z.upper.rounded())) bpm"
    }

    private func instruction(_ s: DayPlan.Step, _ k: DayPlan.Kind) -> String {
        switch s.phase {
        case .warmup:
            return k == .quality ? String(localized: "Easy jog, then three short pickups. Stay within \(bpm(2)).")
                                 : String(localized: "Brisk walk, then very easy movement. Build up slowly within \(bpm(s.zone)).")
        case .main:
            switch k {
            case .recovery: return String(localized: "Walk or gentle mobility. Breathe through the nose. Stay under \(bpm(1)).")
            case .easy, .steady: return String(localized: "Hold \(bpm(2)). You can still hold a conversation.")
            case .quality: return String(localized: "Three blocks of 6 minutes at \(bpm(4)), with 3 minutes easy between.")
            }
        case .cooldown:
            return String(localized: "Walk easy until your heart rate drops below \(Int(zones.zones.first?.upper.rounded() ?? 100)) bpm.")
        }
    }

    private func effortText(_ p: DayPlan.Plan) -> String {
        guard let lo = p.effortLow, let hi = p.effortHigh else { return "–" }
        return "+\(UnitFormatter.effortDisplay(lo, scale: scale))–\(UnitFormatter.effortDisplay(hi, scale: scale))"
    }

    private func reasons(_ p: DayPlan.Plan, _ charge: Int) -> [String] {
        var out = [String(localized: "Charge is \(charge)%.")]
        if let y = yesterdayEffort { out.append(String(localized: "Yesterday's Effort was \(UnitFormatter.effortDisplay(y, scale: scale)).")) }
        if let band {
            switch band {
            case .under: out.append(String(localized: "Your recent load is light, so there is room to add."))
            case .optimal: out.append(String(localized: "Your recent load is in the safe range."))
            case .high: out.append(String(localized: "Your recent load is high, so the plan stays controlled."))
            case .excessive: out.append(String(localized: "Your recent load is well above usual, so rest comes first."))
            }
        }
        return out
    }

    // MARK: Data

    private func load() async {
        defer { loaded = true }
        guard let r = await NunaDayPlanResult.load(repo: repo, profile: profile) else { plan = nil; return }
        charge = r.charge; yesterdayEffort = r.yesterdayEffort; band = r.band; plan = r.plan
    }
}
#endif
