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
    /// Recovery scores drawn as bars on the right of the card (the earlier days in grey, the last one in its colour).
    var bars: [Double]?
    /// A picture on the right of the card.
    var art: Art?
    enum Art: Equatable { case dart }
    enum Action: Equatable { case breathe, windDown, outlook, journal, trend, plan }
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
    var effortTargetLow: Double?
    var effortTargetHighShown: String?
    /// "green", "yellow" or "red" when today's scored Recovery is the first of that colour the person has had.
    var firstColour: String?
    var effortTargetText: String?
    var effortShown: String?
    var stressNow: Double?
    var stressHighMin: Int?
    var illness: IllnessSignalEngine.Result?
    /// The baselines still being built, with the nights read so far.
    var calibrating: [NunaCalibrationStage] = []
    /// Baselines that finished today, by stage id.
    var calibrationDone: [String] = []
    /// Workouts that just ended or were added since Today was first opened, newest first.
    var workouts: [NunaHighlightWorkout] = []
    var dayStrainShown: String?
    /// Naps that just ended.
    var naps: [NunaHighlightNap] = []
    /// Last night's sleep, until the middle of the day.
    var sleepRecorded: (duration: String, score: Int?)?
    /// Yesterday's journal has no answers yet. It is filled in after waking, so the sleep highlight offers the way in.
    var journalYesterdayOpen = false
    /// Today's Recovery is red and the 30 days before had none: the five scores before it, then today's. Nil otherwise.
    var newlyRedBars: [Double]?
    /// Today's Strain has reached 20 on the 21-point scale.
    var pushingLimits = false
    /// The Daily Outlook just opened up and has not been looked at yet.
    var outlookFirst = false
    /// The share of the week's plan done so far, in the morning of a day with a plan; nil otherwise.
    var planCheckIn: Int?
}

struct NunaCalibrationStage: Equatable {
    /// "recovery" or "stress".
    let id: String
    let nights: Int
    let total: Int
}

struct NunaHighlightWorkout: Equatable {
    let id: String
    let sport: String
    let duration: String
    let strain: String?
    let manual: Bool
}

struct NunaHighlightNap: Equatable {
    let id: String
    let duration: String
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

        // 1a. The Weekly Plan Check-In, the morning after the night.
        if let p = i.planCheckIn {
            out.append(.init(id: "plan-checkin", title: String(localized: "Weekly Plan Check-In"),
                             message: String(localized: "You've completed \(p)% of your Weekly Plan so far."),
                             actionTitle: String(localized: "View my progress"), action: .plan, art: .dart))
        }

        // 1b. The first Daily Outlook, waiting to be opened.
        if i.outlookFirst {
            out.append(.init(id: "outlook-first", title: String(localized: "Your First Daily Outlook"),
                             message: String(localized: "Your personalized daily insights and recommendations are here! Track progress, spot trends, and make informed decisions."),
                             actionTitle: String(localized: "Get my outlook"), action: .outlook))
        }

        // 2. Baselines: still being built, or finished today.
        for stage in i.calibrating {
            if stage.id == "recovery" {
                out.append(.init(id: "calib-recovery", title: String(localized: "Calibrating Recovery"),
                                 message: String(localized: "\(stage.nights) of \(stage.total) nights recorded. Wear your strap to bed each night so Recovery can learn your normal.")))
            } else {
                out.append(.init(id: "calib-stress", title: String(localized: "Calibrating Stress monitor"),
                                 message: String(localized: "\(stage.nights) of \(stage.total) nights recorded. Stress readings start once your baseline is complete, so keep wearing your strap.")))
            }
        }
        for id in i.calibrationDone {
            out.append(.init(id: "calib-done-\(id)", title: String(localized: "Calibration complete"),
                             message: id == "recovery"
                                ? String(localized: "Your baseline is ready. Recovery now compares each night with your own usual, so scores are more accurate.")
                                : String(localized: "Your stress baseline is ready. The Stress monitor now judges each day against your own usual, so readings fit you.")))
        }

        // 3. A workout that just ended, or one added by hand.
        for w in i.workouts {
            if w.manual {
                let msg = w.strain.map { String(localized: "\(w.sport) was added to your day: \(w.duration), Strain \($0). Its Strain now counts toward today's total.") }
                    ?? String(localized: "\(w.sport) was added to your day: \(w.duration). Open it from today's activities to check or edit the details.")
                out.append(.init(id: w.id, title: String(localized: "Activity added"), message: msg))
            } else {
                let msg: String
                if let st = w.strain, let day = i.dayStrainShown {
                    msg = String(localized: "\(w.sport), \(w.duration). Added Strain \(st); the day is at Strain \(day). Give your body time to recover and refuel.")
                } else if let st = w.strain {
                    msg = String(localized: "\(w.sport), \(w.duration). It added Strain \(st). Give your body time to recover and refuel after the session.")
                } else {
                    msg = String(localized: "\(w.sport), \(w.duration). Give your body time to recover and refuel after the session.")
                }
                out.append(.init(id: w.id, title: String(localized: "Workout recorded"), message: msg))
            }
        }

        // 4. A nap that just ended, and last night's sleep in the morning.
        for n in i.naps {
            out.append(.init(id: n.id, title: String(localized: "Nap recorded"), message: String(localized: "A \(n.duration) nap was added to your day. Short naps can top up your energy; keep them early in the day.")))
        }
        if let sl = i.sleepRecorded {
            let msg = sl.score.map { String(localized: "You slept \(sl.duration) last night, a Sleep score of \($0)%. Open Sleep for stages and tonight's bedtime.") }
                ?? String(localized: "You slept \(sl.duration) last night. Open Sleep for your stages, consistency and tonight's recommended bedtime.")
            out.append(.init(id: "sleep-recorded", title: String(localized: "Sleep recorded"), message: msg,
                             actionTitle: i.journalYesterdayOpen ? String(localized: "Log yesterday's journal") : nil,
                             action: i.journalYesterdayOpen ? .journal : nil))
        }

        // 4b. Recovery: the first of a colour, and being inside today's Strain range.
        if let c = i.firstColour {
            switch c {
            case "green":
                out.append(.init(id: "first-green", title: String(localized: "Your First Green"),
                                 message: String(localized: "Green Recovery means your body is well recovered and ready for Strain. A good day to train towards your target.")))
            case "red":
                out.append(.init(id: "first-red", title: String(localized: "Your First Red"),
                                 message: String(localized: "Red Recovery means your body is asking for rest. Keep today light and prioritize sleep and hydration tonight.")))
            default:
                out.append(.init(id: "first-yellow", title: String(localized: "Your First Yellow"),
                                 message: String(localized: "Yellow Recovery is normal and means your body is maintaining. Train steadily rather than pushing hard today.")))
            }
        }
        if let bars = i.newlyRedBars, i.firstColour != "red" {
            out.append(.init(id: "newly-red", title: String(localized: "Newly Red"),
                             message: String(localized: "You haven't been in the red in the last 30 days! Don't worry, it's only temporary."),
                             actionTitle: String(localized: "View trend"), action: .trend, bars: bars))
        }
        if let e = i.effort, let lo = i.effortTargetLow, let hi = i.effortTargetHigh, let shown = i.effortTargetHighShown, e >= lo, e <= hi {
            out.append(.init(id: "optimal-strain", title: String(localized: "Reaching Optimal Strain"),
                             message: String(localized: "You've hit the optimal Strain range for your Recovery. Keep moving towards your target of \(shown) for more fitness gains.")))
        }

        // 5. Resting heart rate above its usual (not while the baseline is still being built).
        if i.calibrating.isEmpty, let rhr = i.restingHr, let avg = i.restingHrAverage, avg > 0 {
            let pct = Int(((rhr - avg) / avg * 100).rounded())
            if let word = recoveryWord, pct >= 2 {
                out.append(.init(id: "rhr", title: String(localized: "Elevated RHR"),
                                 message: String(localized: "Your RHR is \(pct)% above average, resulting in a \(word) Recovery. If you can, spend some time on recovery activities to boost your health.")))
            } else if pct >= 8 {
                out.append(.init(id: "rhr", title: String(localized: "Elevated RHR"),
                                 message: String(localized: "Your RHR is \(pct)% above average. If you can, ease off today and let your body recover. A calm day and an early night usually help.")))
            }
        }

        // 6. HRV below its usual.
        if i.calibrating.isEmpty, let hrv = i.hrv, let avg = i.hrvAverage, avg > 0 {
            let pct = Int(((avg - hrv) / avg * 100).rounded())
            if pct >= (i.charge.map { $0 < 67 } == true ? 10 : 20) {
                out.append(.init(id: "hrv", title: String(localized: "Low HRV"),
                                 message: String(localized: "Your HRV is \(pct)% below your average. Take it easy today and prioritize sleep tonight; hydration helps too.")))
            }
        }

        // 7. Sleep debt, building or simply there; or a short night when the debt has nothing to add.
        var debtShown = false
        if let debt = i.debtMin, debt >= 60 {
            if let before = i.debtBeforeMin, debt >= before + 10 {
                out.append(.init(id: "debt", title: String(localized: "Sleep Debt Building"),
                                 message: String(localized: "Your Sleep Debt rose to \(hm(debt)), which can affect your long term performance. If you can, try to prioritize sleep tonight."),
                                 actionTitle: String(localized: "Wind down"), action: .windDown))
                debtShown = true
            } else if debt >= 90 {
                out.append(.init(id: "debt", title: String(localized: "Sleep Debt"),
                                 message: String(localized: "You are carrying \(hm(debt)) of Sleep Debt. An earlier night will help pay it down; even 30 extra minutes makes a difference."),
                                 actionTitle: String(localized: "Wind down"), action: .windDown))
                debtShown = true
            }
        }
        if !debtShown, let slept = i.sleepMinutes, slept > 0, slept <= i.sleepNeedMin - 90 {
            out.append(.init(id: "short", title: String(localized: "Short night"),
                             message: String(localized: "You slept \(hm(slept)) against the \(hm(i.sleepNeedMin)) you need. Keep today easy and aim for an early night to catch up."),
                             actionTitle: String(localized: "Wind down"), action: .windDown))
        }

        // 8. Strain at 20 or more, then more Strain than today's Recovery supports.
        if i.pushingLimits {
            out.append(.init(id: "pushing-limits", title: String(localized: "Pushing Limits"),
                             message: String(localized: "You worked hard today and exceeded your Optimal Strain range. Overreaching will help you get fitter over time.")))
        } else if let e = i.effort, let hi = i.effortTargetHigh, e > hi * 1.15, let shown = i.effortShown, let band = i.effortTargetText {
            out.append(.init(id: "strain", title: String(localized: "Strain above your target"),
                             message: String(localized: "Strain \(shown) is above today's range for your Recovery (\(band)). More training now costs tomorrow's Recovery.")))
        }

        // 9. A long stretch of high stress.
        if (i.stressHighMin ?? 0) >= 180 || (i.stressNow ?? 0) >= 2.2 {
            let spent = StressTrace.clock(minutes: i.stressHighMin ?? 0)
            out.append(.init(id: "stress", title: String(localized: "High stress today"),
                             message: String(localized: "You have spent \(spent) in high stress today. A few minutes of slow breathing can bring it down; a short walk helps too."),
                             actionTitle: String(localized: "Breathe"), action: .breathe))
        }
        return out
    }

    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? String(localized: "\(m / 60) hr \(m % 60) min") : String(localized: "\(m) min")
    }
}

/// The highlights card on Today: one card at a time with what stands out about the day, a check at its side that puts it away (a swipe to
/// either side does the same), and the next one behind it. It takes the place Anya's card had; when nothing stands out it is not there.
/// Bars for the recent scores, as on the Newly Red card: grey for the days before, the last one in its own colour, each as tall as its score.
struct NunaHighlightBars: View {
    let values: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let last = i == values.count - 1
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(last ? NunaScoreStyle.chargeColor(v) : NunaPalette.textMuted.opacity(0.55))
                    .frame(width: 9, height: max(8, 72 * min(max(v, 0), 100) / 100))
            }
        }
        .frame(height: 72, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct NunaHighlightsCard: View {
    let charge: Double?
    /// Whether today's Recovery was scored on its own (not carried from an earlier night).
    let chargeScored: Bool
    let hrv: Double?
    let restingHr: Double?
    let sleepMinutes: Double?
    let effort: Double?
    let stressNow: Double?
    let stressHighMin: Int?
    let rest: Double?
    let workouts: [WorkoutRow]
    /// The baselines still being built, with the nights read so far.
    let calibrating: [NunaCalibrationStage]
    @ObservedObject var feed: NunaHighlightsFeed
    let onBreathe: () -> Void
    let onWindDown: () -> Void
    let onOutlook: () -> Void
    let onJournal: () -> Void
    let onTrend: () -> Void
    var onPlan: () -> Void = {}

    @StateObject private var planModel = NunaPlanModel()
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(NunaPlanStore.key) private var planRaw = ""
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(NunaHighlightPrefs.dismissedKey) private var dismissedRaw = ""
    @State private var dragX: CGFloat = 0
    /// Whether yesterday already has journal answers. Starts true so the link stays hidden until the check has run.
    @State private var yesterdayLogged = true

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
        // The stretch drawn on the Strain ring, so these words and the ring give the same range.
        let band = NunaScoreStyle.effortTarget(charge: charge)
        let hi = band.map { $0.upperBound * 100 }
        let lo = band.map { $0.lowerBound * 100 }
        func colour(_ v: Double) -> String { v >= 67 ? "green" : (v >= 34 ? "yellow" : "red") }
        var first: String?
        if chargeScored, let c = charge {
            let today = colour(c)
            let earlierColours = repo.days.filter { $0.day < ((repo.today?.day) ?? dayKey) }.compactMap { $0.recovery }.map(colour)
            if !earlierColours.isEmpty, !earlierColours.contains(today) { first = today }
        }
        // Newly red: red today, after a month (with enough scored days to say so) that had none.
        var newlyRed: [Double]?
        if chargeScored, let c = charge, c < 34 {
            let anchor = repo.today?.day ?? dayKey
            let monthAgo = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
            let recent = repo.days.filter { $0.day < anchor && $0.day >= monthAgo }.compactMap { $0.recovery }
            if recent.count >= 7, !recent.contains(where: { $0 < 34 }) { newlyRed = Array(recent.suffix(5)) + [c] }
        }
        let bandText = band.map { b -> String in
            let lo = Int(UnitFormatter.effortValue(b.lowerBound * 100, scale: scale).rounded())
            let up = Int(UnitFormatter.effortValue(b.upperBound * 100, scale: scale).rounded())
            return "\(lo)–\(up)"
        }
        let earlier = repo.days.filter { $0.day < ((repo.today?.day) ?? dayKey) }
        let nowDate = Date()
        let nowTs = Int(nowDate.timeIntervalSince1970)
        // A workout shows while it is fresh (ended within 90 minutes), and for as long as it was not there when Today was first opened
        // today (so one added later, by hand or by a sync, is announced too).
        let announced = workouts.filter { w in
            guard w.endTs <= nowTs + 60 else { return false }
            let isNew = feed.baseline.map { !$0.contains(w.startTs) } ?? false
            return nowTs - w.endTs <= 90 * 60 || isNew
        }.sorted { $0.endTs > $1.endTs }.prefix(3).map { w in
            NunaHighlightWorkout(id: "workout-\(w.startTs)", sport: WorkoutSource.displaySport(w.sport),
                                 duration: NunaWorkoutFormat.duration(w.durationS ?? Double(w.endTs - w.startTs)),
                                 strain: w.strain.map { UnitFormatter.effortDisplay($0, scale: scale) },
                                 manual: WorkoutSource.classify(w.source) == .manual)
        }
        let freshNaps = feed.naps.filter { $0.end <= nowDate && nowDate.timeIntervalSince($0.end) <= 3 * 3600 }.map {
            NunaHighlightNap(id: "nap-\(Int($0.start.timeIntervalSince1970))", duration: NunaHighlightEngine.hm($0.asleepMin))
        }
        let hour = Calendar.current.component(.hour, from: nowDate)
        let slept: (duration: String, score: Int?)? = (hour < 14 && (sleepMinutes ?? 0) >= 60)
            ? (NunaHighlightEngine.hm(sleepMinutes ?? 0), rest.map { Int($0.rounded()) }) : nil
        var result = NunaHighlightInputs(
            charge: charge, hrv: hrv, restingHr: restingHr,
            hrvAverage: mean(before.compactMap(\.avgHrv)),
            restingHrAverage: mean(before.compactMap { $0.restingHr.map(Double.init) }),
            sleepMinutes: sleepMinutes, sleepNeedMin: need,
            debtMin: debt(repo.days), debtBeforeMin: debt(earlier),
            effort: effort, effortTargetHigh: hi, effortTargetLow: lo,
            effortTargetHighShown: hi.map { UnitFormatter.effortDisplay($0, scale: scale) },
            firstColour: first, effortTargetText: bandText,
            effortShown: effort.map { UnitFormatter.effortDisplay($0, scale: scale) },
            stressNow: stressNow, stressHighMin: stressHighMin, illness: appModel.illnessSignal,
            calibrating: calibrating, calibrationDone: ["recovery", "stress"].filter { feed.doneStages.contains($0) },
            workouts: Array(announced), dayStrainShown: effort.map { UnitFormatter.effortDisplay($0, scale: scale) },
            naps: freshNaps, sleepRecorded: slept, journalYesterdayOpen: !yesterdayLogged, newlyRedBars: newlyRed,
            pushingLimits: (effort.map { $0 * UnitFormatter.effortScaleFactor } ?? 0) >= 20,
            outlookFirst: NunaOutlookGate.ready(repo.days) && !UserDefaults.standard.bool(forKey: NunaOutlookGate.openedKey),
            planCheckIn: NunaCheckInGate.visible(woke: (sleepMinutes ?? 0) >= 60, hasPlan: NunaPlanStore.hasPlan(NunaPlanStore.load(planRaw)), now: nowDate)
                ? Int((planModel.accomplished * 100).rounded()) : nil)
#if DEBUG
        Self.demo(&result)
#endif
        return result
    }

#if DEBUG
    /// `--demo-highlights=calibrating,done,workout,manual,nap,sleep,first,optimal` puts that situation into the inputs, since the demo data has none of them.
    private static func demo(_ i: inout NunaHighlightInputs) {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-highlights=") }) else { return }
        for kind in arg.dropFirst("--demo-highlights=".count).split(separator: ",") {
            switch kind {
            case "calibrating": i.calibrating = [.init(id: "recovery", nights: 2, total: 4), .init(id: "stress", nights: 5, total: 14)]
            case "done": i.calibrationDone = ["recovery"]
            case "workout":
                i.workouts.append(.init(id: "demo-w", sport: "Running", duration: "42 min", strain: "9.4", manual: false)); i.dayStrainShown = "12.1"
            case "manual": i.workouts.append(.init(id: "demo-m", sport: "Padel", duration: "1h 0m", strain: "7.2", manual: true))
            case "nap": i.naps.append(.init(id: "demo-n", duration: "25 min"))
            case "sleep": i.sleepRecorded = ("7 hr 12 min", 82); i.journalYesterdayOpen = true
            case "pushing": i.pushingLimits = true
            case "newlyred": i.newlyRedBars = [62, 48, 55, 71, 66, 12]
            case "first": i.firstColour = "yellow"
            case "optimal": i.effort = 11; i.effortTargetLow = 10; i.effortTargetHigh = 14; i.effortTargetHighShown = "14.0"
            default: break
            }
        }
    }
#endif

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
            NunaCard(padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: h.art != nil ? 160 : (h.bars == nil ? 46 : 140))) {
                // A card with a picture is the compact one: smaller words, no three-line floor, 138 pt tall with its words centred.
                let compact = h.art != nil
                VStack(alignment: .leading, spacing: compact ? 8 : 6) {
                    Text(verbatim: h.title).font(.nunaWords(size: compact ? 13.5 : 14.5, semibold: true)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    // Always at least three lines tall (a hidden three-line stand-in sets the floor), so every card is four lines with its title.
                    ZStack(alignment: .topLeading) {
                        if !compact { Text(verbatim: "A\nA\nA").font(.nunaWords(size: 15)).tracking(0).lineSpacing(2).hidden().accessibilityHidden(true) }
                        Text(verbatim: h.message).font(.nunaWords(size: compact ? 12 : 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                    if let t = h.actionTitle, let a = h.action {
                        Button { perform(a) } label: {
                            if a == .outlook || a == .trend || a == .plan {
                                // The Outlook's own call to action: gradient letters and an arrow, no pill.
                                HStack(spacing: 10) {
                                    Text(verbatim: t).font(.nuna(size: compact ? 12 : 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    Image(systemName: "arrow.right").font(.system(size: compact ? 14 : 16, weight: .regular))
                                }
                                .foregroundStyle(a == .trend || a == .plan ? AnyShapeStyle(Color(red: 0.29, green: 0.56, blue: 0.89)) : AnyShapeStyle(Self.outlookGradient)).frame(minHeight: compact ? 20 : 32)
                            } else {
                                Text(verbatim: t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    .foregroundStyle(NunaPalette.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(NunaPalette.cardHighlight))
                            }
                        }
                        .buttonStyle(.plain).padding(.top, compact ? 2 : 4)
                    }
                }
                .frame(minHeight: compact ? 102 : nil, alignment: .leading)
            }
            .overlay {
                // The first Outlook is framed in the Outlook's violet to sky blue.
                if h.id == "outlook-first" {
                    RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(Self.outlookGradient, lineWidth: 2)
                }
            }
            .overlay(alignment: .trailing) {
                if let b = h.bars { NunaHighlightBars(values: b).padding(.trailing, 40) }
                if h.art == .dart { NunaDartBoard().padding(.trailing, 52) }
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
        .task(id: "\(repo.refreshSeq)-\(dayKey)") { await checkYesterdayJournal() }
        .task(id: "\(planRaw)-\(repo.refreshSeq)") { await planModel.load(repo: repo, age: profile.age, weekOffset: 0) }
    }

    /// Yesterday's journal is written the morning after, so the sleep highlight offers it until it has answers.
    private func checkYesterdayJournal() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let key = Repository.localDayKey(yesterday)
        let logged = await repo.nativeJournalDays(from: key, to: key)
        yesterdayLogged = logged.contains(key)
    }

    private static let outlookGradient = LinearGradient(colors: [Color(red: 0.62, green: 0.40, blue: 0.96), Color(red: 0.25, green: 0.72, blue: 0.98)],
                                                        startPoint: .leading, endPoint: .trailing)

    private func perform(_ a: NunaHighlight.Action) {
        switch a {
        case .breathe: onBreathe()
        case .windDown: onWindDown()
        case .outlook: onOutlook()
        case .journal: onJournal()
        case .trend: onTrend()
        case .plan: onPlan()
        }
    }

    private func put(away id: String) {
        // Put away unopened, the first Outlook is not announced again; the card under "My Day" stays.
        if id == "outlook-first" { UserDefaults.standard.set(true, forKey: NunaOutlookGate.openedKey) }
        var entries = dismissedRaw.split(separator: ",").map(String.init).filter { $0.hasPrefix(dayKey + "|") }
        entries.append("\(dayKey)|\(id)")
        withAnimation(.easeInOut(duration: 0.25)) { dismissedRaw = entries.joined(separator: ",") }
    }
}

/// Where the highlights keep what was put away.
enum NunaHighlightPrefs {
    static let dismissedKey = "nuna.highlights.dismissed"
}
/// What the highlights need beyond the day's figures: today's naps, the workouts that were already there when Today was first opened, and
/// which baselines finished today. It keeps the last two in `UserDefaults`, so a relaunch neither re-announces old workouts nor loses a
/// finished calibration before it was seen.
@MainActor
final class NunaHighlightsFeed: ObservableObject {
    @Published private(set) var naps: [NunaNap] = []
    /// Start times of today's workouts at the first look today; nil until there was one.
    @Published private(set) var baseline: Set<Int>?
    /// Baselines ("recovery", "stress") that finished today.
    @Published private(set) var doneStages: Set<String> = []

    private static let baselineKey = "nuna.highlights.baseline"
    private static func stageKey(_ id: String) -> String { "nuna.highlights.calib.\(id)" }
    private let defaults = UserDefaults.standard

    init() {
        let today = Repository.localDayKey(Date())
        if let raw = defaults.string(forKey: Self.baselineKey) {
            let p = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if p.count == 2, String(p[0]) == today { baseline = Set(p[1].split(separator: ",").compactMap { Int($0) }) }
        }
        for id in ["recovery", "stress"] where defaults.string(forKey: Self.stageKey(id)) == "done:\(today)" { doneStages.insert(id) }
    }

    func update(repo: Repository, loaded: Bool, workouts: [WorkoutRow], calibrating: [String]) async {
        guard loaded else { return }
        let today = Repository.localDayKey(Date())
        if baseline == nil {
            let set = Set(workouts.map(\.startTs))
            baseline = set
            defaults.set("\(today)|" + set.sorted().map(String.init).joined(separator: ","), forKey: Self.baselineKey)
        }
        for id in ["recovery", "stress"] {
            let key = Self.stageKey(id)
            let cur = defaults.string(forKey: key)
            if calibrating.contains(id) {
                if cur != "pending" { defaults.set("pending", forKey: key) }
                doneStages.remove(id)
            } else if cur == "pending" {
                defaults.set("done:\(today)", forKey: key)
                doneStages.insert(id)
            }
        }
        let start = Calendar.current.startOfDay(for: Date())
        let found = await NunaSleepModel.naps(from: start, to: start.addingTimeInterval(86_400), repo: repo).map(\.nap)
        if found.map(\.id) != naps.map(\.id) { naps = found }
    }
}

/// Keeps the feed current. It draws nothing, and sits where the screen always has a view (the score rings), because the card itself is not
/// there while nothing stands out.
struct NunaHighlightsTracker: View {
    @ObservedObject var feed: NunaHighlightsFeed
    let loaded: Bool
    let workouts: [WorkoutRow]
    let calibrating: [NunaCalibrationStage]
    @EnvironmentObject private var repo: Repository

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: "\(repo.refreshSeq)-\(loaded)-\(workouts.count)-\(calibrating.map(\.id).joined())") {
                await feed.update(repo: repo, loaded: loaded, workouts: workouts, calibrating: calibrating.map(\.id))
            }
    }
}
#endif
