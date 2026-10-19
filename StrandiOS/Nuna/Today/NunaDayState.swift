#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What the two chips under Today's rings mean right now: the Charge state (Solid, Last night, Calibrating, No data) and the readiness word
/// (Push, Maintain, Rest). The page is built from the same figures the chips are, so what it says follows the state the wearer is in.
struct NunaDayStateView: View {
    enum Kind: Hashable { case charge, readiness }
    let kind: Kind

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var day = NunaTodayModel()

    var body: some View {
        NunaDetailScreen(kind == .charge ? "Charge state" : "Readiness") {
            switch kind {
            case .charge: chargeContent
            case .readiness: readinessContent
            }
        }
        .task(id: repo.refreshSeq) { await day.load(repo: repo, profile: profile) }
    }

    // MARK: Charge state

    @ViewBuilder private var chargeContent: some View {
        let state = day.charge
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    NunaChip(verbatim: state.stateLabel, color: tone(for: state))
                    Spacer()
                    if let pct = state.pct {
                        Text(verbatim: "\(Int(pct.rounded()))%").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
                Text(verbatim: chargeHeadline(state)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
                Text(verbatim: chargeBody(state)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        nunaTrendsCap("What to do")
        NunaCard(small: true) {
            Text(verbatim: chargeAdvice(state)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
        }
        nunaTrendsCap("The colour of the dot")
        NunaCard(small: true) {
            let pct = state.pct
            VStack(alignment: .leading, spacing: 14) {
                legend("Green", "67% and above. You are well recovered: a hard session should land well.", current: (pct ?? -1) >= 67, color: NunaPalette.scoreHigh, plainTitle: true)
                legend("Yellow", "34% to 66%. Moderate recovery: train at a steady pace and watch how you feel.", current: pct.map { $0 >= 34 && $0 < 67 } ?? false, color: NunaPalette.scoreMid, plainTitle: true)
                legend("Red", "Below 34%. Recovery is low: keep the day easy and put sleep first.", current: pct.map { $0 < 34 } ?? false, color: NunaPalette.scoreLow, plainTitle: true)
                legend("Grey", "There is no Charge yet, so the dot has no colour to give.", current: pct == nil, color: NunaPalette.textMuted, plainTitle: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        nunaTrendsCap("The four states")
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 14) {
                legend("Solid", "Today's Charge is scored from last night's sleep, against a baseline that is trusted.", current: { if case .scored = state { return true }; return false }())
                legend("Last night", "Today has no score of its own yet, so the last scored night is shown.", current: { if case .carried = state { return true }; return false }())
                legend("Calibrating", "PHMN is still learning your baseline; the first nights give no score.", current: { if case .calibrating = state { return true }; return false }())
                legend("No data", "No scored night yet and not calibrating: nothing honest to show.", current: { if case .noData = state { return true }; return false }())
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        nunaFootnote("Charge is made from your HRV, resting heart rate, breathing and sleep, each against your own baseline. Not medical advice.")
    }

    private func tone(for state: LiquidTodayView.ChargeDisplay) -> Color? {
        state.pct.map(nunaChargeColor)
    }

    private func chargeHeadline(_ state: LiquidTodayView.ChargeDisplay) -> String {
        switch state {
        case .scored: return String(localized: "Today's Charge is scored.")
        case .carried: return String(localized: "Today has no score of its own yet.")
        case .calibrating(let nights): return String(localized: "Learning your baseline, \(nights) of \(Baselines.minNightsSeed) nights.")
        case .noData: return String(localized: "There is no Charge to show yet.")
        }
    }

    private func chargeBody(_ state: LiquidTodayView.ChargeDisplay) -> String {
        switch state {
        case .scored:
            return String(localized: "It comes from last night's sleep and is the number on the ring. Your baseline is established, so you can rely on it.")
        case .carried(_, let caption):
            return String(localized: "The ring shows the last scored night (\(caption)). Charge is worked out after a night's sleep is recorded and synced; none has been scored for today, so this is the last real number, not a new estimate. It becomes Solid once tonight's sleep is scored.")
        case .calibrating:
            var text = String(localized: "A score needs a few nights of your own HRV to compare against. Until then PHMN keeps the ring empty instead of guessing.")
            if let reason = state.calibrationReason(dayKeys: repo.days.map(\.day), nightlyHrv: repo.days.map(\.avgHrv), today: day.dayKey(repo: repo)) {
                text += "\n\n" + reason
            }
            return text
        case .noData:
            return String(localized: "There is no scored night in your history and the baseline is not being built, so the ring stays empty rather than show a made-up number.")
        }
    }

    private func chargeAdvice(_ state: LiquidTodayView.ChargeDisplay) -> String {
        switch state {
        case .scored: return String(localized: "Nothing to do. Plan today's load against the Effort target on Today.")
        case .carried: return String(localized: "Wear the strap tonight and let it sync in the morning. If you slept with it on and it still says Last night, open the Devices page and sync.")
        case .calibrating: return String(localized: "Keep wearing the strap while you sleep. Each night with an HRV reading counts toward the baseline.")
        case .noData: return String(localized: "Pair the strap, wear it overnight and sync. Charge appears once a night has been scored.")
        }
    }

    /// A line of a key. `color` is the dot of the thing it explains; without one the dot only marks the line that is true now.
    private func legend(_ title: String, _ text: String, current: Bool, color: Color? = nil, plainTitle: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color ?? (current ? NunaPalette.textPrimary : NunaPalette.hairline)).frame(width: 10, height: 10).padding(.top, 5)
                .opacity(color == nil || current ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(title)).font(.nuna(size: 14.5, weight: .heavy)).foregroundStyle(current ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    if current { NunaChip(verbatim: String(localized: "Now"), color: color) }
                }
                Text(LocalizedStringKey(text)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    // MARK: Readiness

    @ViewBuilder private var readinessContent: some View {
        if let r = day.readiness {
            let word = Self.word(r.level)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if let word { NunaChip(verbatim: word, systemImage: "bolt.fill", color: Self.tone(r.level)) }
                        Spacer()
                        NunaChip(verbatim: Self.confidence(r.confidence))
                    }
                    Text("The bolt chip on Today is your readiness for training: how ready your body looks today, worked out from your own signals. The word is what to do with it, and its colour shows how favourable it is.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: r.headline).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: r.summary).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !r.signals.isEmpty {
                nunaTrendsCap("What it is based on")
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(r.signals.enumerated()), id: \.offset) { i, s in
                            if i > 0 { NunaDivider() }
                            signalRow(s)
                        }
                    }
                }
                nunaFootnote("Dots: green helps, grey is neutral, amber is worth watching, red works against you.")
            }
            nunaTrendsCap("What the word means")
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    legend("Push", "Your signals line up and your recent load is supported: a hard session should land well.", current: r.level == .primed, color: NunaPalette.charge)
                    legend("Maintain", "Nothing stands out either way: a moderate, steady load suits today.", current: r.level == .balanced, color: NunaPalette.effortText)
                    legend("Rest", "One or more recovery signals are down, or the load has been high: keep it easy and sleep well.", current: r.level == .strained || r.level == .rundown, color: NunaPalette.warning)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            NunaCard {
                Text("Readiness appears once PHMN has a few nights of HRV and resting heart rate to compare against.")
                    .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        nunaFootnote("Readiness compares today's HRV, resting heart rate and breathing with your own 30-day baseline, and your last week's load with your last month's. A trend in your own data, not medical advice.")
    }

    private func signalRow(_ s: ReadinessEngine.Signal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Self.flagColor(s.flag)).frame(width: 9, height: 9).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: s.label).font(.nuna(size: 14.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 8)
                    if let e = s.evidence {
                        Text(verbatim: e).font(.nuna(size: 12.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
                Text(verbatim: s.detail).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
        .padding(.vertical, 12)
    }

    static func word(_ level: ReadinessEngine.Level) -> String? {
        switch level {
        case .primed: return "Push"
        case .balanced: return "Maintain"
        case .strained, .rundown: return "Rest"
        case .insufficient: return nil
        }
    }

    private static func tone(_ level: ReadinessEngine.Level) -> Color {
        level == .primed ? NunaPalette.charge : (level == .balanced ? NunaPalette.effortText : NunaPalette.warning)
    }

    private static func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good: return NunaPalette.charge
        case .neutral: return NunaPalette.textMuted
        case .watch: return NunaPalette.warning
        case .bad: return NunaPalette.alertText
        }
    }

    private static func confidence(_ c: ScoreConfidence) -> String {
        switch c {
        case .calibrating: return String(localized: "Calibrating")
        case .building: return String(localized: "Building")
        case .solid: return String(localized: "Solid")
        }
    }
}
#endif
