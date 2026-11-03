#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One thing about today worth a look: a short title, a sentence with the figures behind it, and optionally one thing to do about it.
struct NunaHighlight: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: Action?
    enum Action: Equatable { case breathe, windDown }
}

/// What the highlights are worked out from. Plain numbers, so the rules can be read (and tested) without the app around them.
struct NunaHighlightInputs {
    var charge: Double?
    var hrv: Double?
    var restingHr: Double?
    /// The averages over the nights before today.
    var hrvAverage: Double?
    var restingHrAverage: Double?
    var sleepMinutes: Double?
    var sleepNeedMin: Double
    var debtMin: Double?
    /// The debt as it stood before last night, to tell whether it is building.
    var debtBeforeMin: Double?
    var effort: Double?
    var effortTargetHigh: Double?
    var effortTargetText: String?
    var effortShown: String?
    var stressNow: Double?
    var stressHighMin: Int?
    var illness: IllnessSignalEngine.Result?
}

enum NunaHighlightEngine {
    /// The highlights for today, most important first. Empty when nothing stands out: the card then does not appear at all.
    static func build(_ i: NunaHighlightInputs) -> [NunaHighlight] {
        var out: [NunaHighlight] = []
        let recoveryWord: String? = i.charge.flatMap { c in c < 34 ? String(localized: "red") : (c < 67 ? String(localized: "yellow") : nil) }

        // 1. The early warning, when it has something to say.
        if let r = i.illness, r.level != .quiet {
            out.append(.init(id: "illness", title: String(localized: "Early warning"), message: localizedIllnessCopy(r)))
        }

        // 2. Resting heart rate above its usual.
        if let rhr = i.restingHr, let avg = i.restingHrAverage, avg > 0 {
            let pct = Int(((rhr - avg) / avg * 100).rounded())
            if let word = recoveryWord, pct >= 2 {
                out.append(.init(id: "rhr", title: String(localized: "Elevated RHR"),
                                 message: String(localized: "Your RHR is \(pct)% above average, resulting in a \(word) Recovery. If you can, spend some time on recovery activities to boost your health.")))
            } else if pct >= 8 {
                out.append(.init(id: "rhr", title: String(localized: "Elevated RHR"),
                                 message: String(localized: "Your RHR is \(pct)% above average. If you can, ease off today and let your body recover.")))
            }
        }

        // 3. HRV below its usual.
        if let hrv = i.hrv, let avg = i.hrvAverage, avg > 0 {
            let pct = Int(((avg - hrv) / avg * 100).rounded())
            if pct >= (i.charge.map { $0 < 67 } == true ? 10 : 20) {
                out.append(.init(id: "hrv", title: String(localized: "Low HRV"),
                                 message: String(localized: "Your HRV is \(pct)% below your average. Take it easy today and prioritize sleep tonight.")))
            }
        }

        // 4. Sleep debt, building or simply there; or a short night when the debt has nothing to add.
        var debtShown = false
        if let debt = i.debtMin, debt >= 60 {
            if let before = i.debtBeforeMin, debt >= before + 10 {
                out.append(.init(id: "debt", title: String(localized: "Sleep Debt Building"),
                                 message: String(localized: "Your Sleep Debt rose to \(hm(debt)), which can affect your long term performance. If you can, try to prioritize sleep tonight."),
                                 actionTitle: String(localized: "Wind down"), action: .windDown))
                debtShown = true
            } else if debt >= 90 {
                out.append(.init(id: "debt", title: String(localized: "Sleep Debt"),
                                 message: String(localized: "You are carrying \(hm(debt)) of Sleep Debt. An earlier night will help pay it down."),
                                 actionTitle: String(localized: "Wind down"), action: .windDown))
                debtShown = true
            }
        }
        if !debtShown, let slept = i.sleepMinutes, slept > 0, slept <= i.sleepNeedMin - 90 {
            out.append(.init(id: "short", title: String(localized: "Short night"),
                             message: String(localized: "You slept \(hm(slept)) against the \(hm(i.sleepNeedMin)) you need. Keep today easy and go to bed early."),
                             actionTitle: String(localized: "Wind down"), action: .windDown))
        }

        // 5. More Strain than today's Recovery supports.
        if let e = i.effort, let hi = i.effortTargetHigh, e > hi * 1.15, let shown = i.effortShown, let band = i.effortTargetText {
            out.append(.init(id: "strain", title: String(localized: "Strain above your target"),
                             message: String(localized: "Strain \(shown) is above today's range for your Recovery (\(band)). More training now costs tomorrow's Recovery.")))
        }

        // 6. A long stretch of high stress.
        if (i.stressHighMin ?? 0) >= 180 || (i.stressNow ?? 0) >= 2.2 {
            let spent = StressTrace.clock(minutes: i.stressHighMin ?? 0)
            out.append(.init(id: "stress", title: String(localized: "High stress today"),
                             message: String(localized: "You have spent \(spent) in high stress today. A few minutes of slow breathing can bring it down."),
                             actionTitle: String(localized: "Breathe"), action: .breathe))
        }
        return out
    }

    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? String(localized: "\(m / 60) hr \(m % 60) min") : String(localized: "\(m) min")
    }
}

/// The highlights card on Today: one card at a time with what stands out about the day, a check at its side that puts it away (a swipe to
/// either side does the same), and the next one behind it. It takes the place Anya's card had; when nothing stands out it is not there.
struct NunaHighlightsCard: View {
    let charge: Double?
    let hrv: Double?
    let restingHr: Double?
    let sleepMinutes: Double?
    let effort: Double?
    let stressNow: Double?
    let stressHighMin: Int?
    let onBreathe: () -> Void
    let onWindDown: () -> Void

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(NunaHighlightPrefs.dismissedKey) private var dismissedRaw = ""
    @State private var dragX: CGFloat = 0

    private var dayKey: String { Repository.localDayKey(Date()) }
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Highlights put away today, stored as "day|id" and read back for today only, so tomorrow starts clean.
    private var dismissed: Set<String> {
        Set(dismissedRaw.split(separator: ",").compactMap { entry -> String? in
            let p = entry.split(separator: "|", maxSplits: 1)
            return p.count == 2 && String(p[0]) == dayKey ? String(p[1]) : nil
        })
    }

    private var inputs: NunaHighlightInputs {
        let before = repo.days.filter { $0.day < dayKey }.suffix(14)
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let need = SleepModel.debtNeedMin(days: repo.days)
        func debt(_ days: [DailyMetric]) -> Double? {
            let l = SleepDebt.ledger(series: days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: need / 60)
            return l.nightCount > 0 ? l.magnitudeMin : nil
        }
        let band = CoupledView.optimalStrainRange(recovery: charge)
        let hi = band.map { Double($0.upperBound) / UnitFormatter.effortScaleFactor }
        let bandText = band.map { b -> String in
            let lo = Int(UnitFormatter.effortValue(Double(b.lowerBound) / UnitFormatter.effortScaleFactor, scale: scale).rounded())
            let up = Int(UnitFormatter.effortValue(Double(b.upperBound) / UnitFormatter.effortScaleFactor, scale: scale).rounded())
            return "\(lo)–\(up)"
        }
        let earlier = repo.days.filter { $0.day < ((repo.today?.day) ?? dayKey) }
        return NunaHighlightInputs(
            charge: charge, hrv: hrv, restingHr: restingHr,
            hrvAverage: mean(before.compactMap(\.avgHrv)),
            restingHrAverage: mean(before.compactMap { $0.restingHr.map(Double.init) }),
            sleepMinutes: sleepMinutes, sleepNeedMin: need,
            debtMin: debt(repo.days), debtBeforeMin: debt(earlier),
            effort: effort, effortTargetHigh: hi, effortTargetText: bandText,
            effortShown: effort.map { UnitFormatter.effortDisplay($0, scale: scale) },
            stressNow: stressNow, stressHighMin: stressHighMin, illness: appModel.illnessSignal)
    }

    /// What stands out today and has not been put away.
    private func liveHighlights() -> [NunaHighlight] {
        var found = NunaHighlightEngine.build(inputs)
#if DEBUG
        // `--demo-highlights` shows two sample highlights, since the demo data has nothing that stands out.
        if CommandLine.arguments.contains("--demo-highlights") {
            found = [
                .init(id: "demo1", title: String(localized: "Sleep Debt Building"),
                      message: String(localized: "Your Sleep Debt rose to \(String(localized: "1 hr 33 min")), which can affect your long term performance. If you can, try to prioritize sleep tonight."),
                      actionTitle: String(localized: "Wind down"), action: .windDown),
                .init(id: "demo2", title: String(localized: "Elevated RHR"),
                      message: String(localized: "Your RHR is \(2)% above average, resulting in a \(String(localized: "yellow")) Recovery. If you can, spend some time on recovery activities to boost your health.")),
            ]
        }
#endif
        return found.filter { !dismissed.contains($0.id) }
    }

    var body: some View {
        let live = liveHighlights()
        if let top = live.first {
            card(top, remaining: live.count)
                .id(top.id)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        }
    }

    private func card(_ h: NunaHighlight, remaining: Int) -> some View {
        ZStack(alignment: .top) {
            // The next one, showing only as an edge under this one.
            if remaining > 1 {
                RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
                    .fill(NunaPalette.cardSurface.opacity(0.75))
                    .frame(height: 40).padding(.horizontal, 16)
                    .mask(alignment: .bottom) { Rectangle().frame(height: 12) }
                    .frame(maxHeight: .infinity, alignment: .bottom).offset(y: 12)
            }
            NunaCard(padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 46)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: h.title).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Text(verbatim: h.message).font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if let t = h.actionTitle, let a = h.action {
                        Button { perform(a) } label: {
                            Text(verbatim: t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(NunaPalette.cardHighlight))
                        }
                        .buttonStyle(.plain).padding(.top, 4)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { put(away: h.id) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(remaining)").font(.nuna(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 28, height: 46)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(NunaPalette.cardHighlight))
                }
                .buttonStyle(.plain).padding(8)
                .accessibilityLabel(Text("Dismiss highlight"))
            }
            .offset(x: dragX).opacity(1 - Double(min(abs(dragX) / 320, 0.8)))
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        dragX = v.translation.width
                    }
                    .onEnded { v in
                        if abs(v.translation.width) > 90, abs(v.translation.width) > abs(v.translation.height) {
                            let way: CGFloat = v.translation.width > 0 ? 1 : -1
                            withAnimation(.easeIn(duration: 0.18)) { dragX = way * 420 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { put(away: h.id); dragX = 0 }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
                        }
                    }
            )
            .accessibilityAction(named: Text("Dismiss highlight")) { put(away: h.id) }
        }
        .padding(.bottom, remaining > 1 ? 12 : 0)
    }

    private func perform(_ a: NunaHighlight.Action) {
        switch a {
        case .breathe: onBreathe()
        case .windDown: onWindDown()
        }
    }

    private func put(away id: String) {
        var entries = dismissedRaw.split(separator: ",").map(String.init).filter { $0.hasPrefix(dayKey + "|") }
        entries.append("\(dayKey)|\(id)")
        withAnimation(.easeInOut(duration: 0.25)) { dismissedRaw = entries.joined(separator: ",") }
    }
}

/// Where the highlights keep what was put away.
enum NunaHighlightPrefs {
    static let dismissedKey = "nuna.highlights.dismissed"
}
#endif
