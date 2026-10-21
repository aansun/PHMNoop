#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What Anya reads on one screen, worked out on the phone from numbers that are already stored: a line that always cites
/// its figures, an optional second line, the names of the signals it came from and the questions worth asking next.
/// No provider is involved, so the card and the top of the sheet work without a connection. When there are no figures to
/// cite the read is nil and nothing is shown (a card without numbers is not drawn).
struct NunaAnyaRead: Equatable {
    var headline: String
    var detail: String?
    /// Plain names of the signals behind the line ("Charge", "HRV", …); shown as "Read:" chips.
    var read: [String]
    var module: NunaAnyaModule
    var questions: [NunaAnyaQuestion]
    /// What the weather and air mean for training, when they are on. Kept apart from the detail so a screen that already shows them
    /// does not say them twice.
    var outdoor: String? = nil
}

struct NunaAnyaQuestion: Equatable, Identifiable {
    enum Kind: Equatable { case ask, plan }
    var id: String { title }
    let title: String
    let prompt: String
    var kind: Kind = .ask
}

/// The modules Anya appears in (docs/nuna/mockups/AnyaMap.dc.html).
enum NunaAnyaModule: String, Equatable {
    case today, health, trends, sleep, workouts, nutrition, device, breathing

    init(context: String) {
        let c = context.lowercased()
        if c.contains("breath") { self = .breathing }
        else if c.contains("sleep") || c.contains("nap") || c.contains("body clock") || c.contains("rest") { self = .sleep }
        else if c.contains("trend") { self = .trends }
        else if c.contains("workout") || c.contains("effort") || c.contains("training") { self = .workouts }
        else if c.contains("health") || c.contains("stress") || c.contains("warning") || c.contains("hrv") || c.contains("heart") || c.contains("oxygen") || c.contains("respir") || c.contains("weight") || c.contains("body") { self = .health }
        else if c.contains("nutrition") || c.contains("water") || c.contains("calor") { self = .nutrition }
        else if c.contains("device") || c.contains("battery") || c.contains("strap") { self = .device }
        else { self = .today }
    }

    var title: LocalizedStringKey {
        switch self {
        case .today: return "Today"; case .health: return "Health"; case .trends: return "Trends"; case .sleep: return "Sleep"
        case .workouts: return "Workouts"; case .nutrition: return "Nutrition"; case .device: return "Devices"; case .breathing: return "Breathing"
        }
    }
}

/// The one metric a detail screen is about, so the sheet reads that and not the whole module.
struct NunaAnyaMetric: Equatable {
    let key: String
    let source: String
    let title: String
    let unit: String
    let decimals: Int
    let higherIsBetter: Bool?
}

@MainActor
enum NunaAnyaReader {
    static func read(context: String, metric: NunaAnyaMetric? = nil, repo: Repository, profile: ProfileStore, scale: EffortScale) async -> NunaAnyaRead? {
        if let metric { return await metricRead(metric, repo: repo, profile: profile) }
        if context.lowercased() == "body" { return await body(repo: repo, profile: profile, scale: scale) }
        let module = NunaAnyaModule(context: context)
        switch module {
        case .nutrition: return await nutrition(repo: repo, profile: profile)
        case .today, .device: return await today(module, repo: repo, profile: profile, scale: scale)
        case .sleep: return await sleep(repo: repo, profile: profile)
        case .health: return await health(repo: repo, profile: profile)
        case .trends: return trends(repo: repo)
        case .workouts: return await workouts(repo: repo, scale: scale)
        case .breathing: return await breathing(repo: repo, profile: profile)
        }
    }

    /// Writes this module's note for the day and adds what moved since the last day it noted to the read's detail.
    private static func remembering(_ read: NunaAnyaRead, values: [String: Double]) -> NunaAnyaRead {
        var r = read
        let note = r.headline + (r.detail.map { " " + $0 } ?? "")
        if let moved = NunaAnyaMemory.snapshot(r.module, headline: note, values: values) {
            r.detail = [r.detail, moved].compactMap { $0 }.joined(separator: " ")
        }
        return r
    }

    // MARK: Today

    private static func today(_ module: NunaAnyaModule, repo: Repository, profile: ProfileStore, scale: EffortScale) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        guard let charge = m.charge.pct else { return nil }
        let c = Int(charge.rounded())
        let level = m.readiness?.level
        let tail: String
        switch level {
        case .primed: tail = String(localized: "ready for a hard session")
        case .balanced: tail = String(localized: "ready for a moderate load")
        case .strained, .rundown: tail = String(localized: "take it easy today")
        default: tail = String(localized: "still learning your baseline")
        }
        var bits: [String] = []
        if let d = m.restingHrDelta, abs(d) >= 1 {
            let n = Int(abs(d).rounded())
            bits.append(d < 0 ? String(localized: "Resting heart rate down \(n) bpm") : String(localized: "Resting heart rate up \(n) bpm"))
        }
        if let d = m.hrvDelta, abs(d) >= 1 {
            let n = Int(abs(d).rounded())
            bits.append(d > 0 ? String(localized: "HRV up \(n) ms") : String(localized: "HRV down \(n) ms"))
        }
        var read = ["Charge"]
        if m.restingHr != nil { read.append("Resting HR") }
        if m.hrv != nil { read.append("HRV") }
        if let e = m.effort { read.append("Effort"); bits.append(String(localized: "Effort so far \(UnitFormatter.effortDisplay(e, scale: scale))")) }
        if m.rest != nil { read.append("Rest") }
        var vals: [String: Double] = ["charge": charge]
        if let v = m.effort { vals["effort"] = Double(UnitFormatter.effortDisplay(v, scale: scale)) ?? v }
        if let v = m.rest { vals["rest"] = v }
        if let v = m.hrv { vals["hrv"] = v }
        if let v = m.restingHr { vals["rhr"] = v }
        var out = remembering(NunaAnyaRead(headline: String(localized: "Charge \(c)%, \(tail)"),
                                           detail: bits.isEmpty ? nil : bits.joined(separator: ". ") + ".",
                                           read: read, module: module, questions: questions(.today)), values: vals)
        // The weather and air, when they are on: what they mean for training today, in plain words (the memory above keeps only the figures).
        let environment = EnvironmentStore.shared
        if environment.isActive, let s = environment.snapshot, Date().timeIntervalSince1970 - Double(s.ts) < 3 * 3600, let a = environment.advice {
            out.outdoor = NunaMark.plain(NunaInsightText.environment(a, s, maxReasons: 1))
            out.read.append("Weather and air")
        }
        return out
    }

    // MARK: Sleep

    private static func sleep(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        guard let rest = m.rest else { return nil }
        // What carried or held the night back and what to do tonight, in place of the figures the screen already shows.
        let sleepModel = NunaSleepModel()
        await sleepModel.load(repo: repo)
        if let night = sleepModel.night, let read = SleepRead.analyze(sleepModel.sleepFacts(night, debtMin: sleepModel.debtMin)) {
            let restSeries = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            let context = await NunaSleepFactorContext.load(repo: repo, restByWakeDay: Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l }))
            let parts = NunaInsightText.sleepParts(read, factors: context, wakeDay: night.dayKey)
            var vals: [String: Double] = ["rest": rest]
            if let v = m.sleepMinutes { vals["sleepMin"] = v }
            return remembering(NunaAnyaRead(headline: parts.why, detail: parts.action, read: ["Rest", "Sleep duration", "Sleep stages"],
                                            module: .sleep, questions: questions(.sleep)), values: vals)
        }
        let hours = m.sleepMinutes.map { NunaAnyaReader.hm($0) }
        var bits: [String] = []
        if let e = m.day?.efficiency { bits.append(String(localized: "Sleep efficiency \(Int(e.rounded()))%")) }
        if let d = m.day?.deepMin, d > 0 { bits.append(String(localized: "Deep sleep \(hm(d))")) }
        if let n = m.day?.disturbances { bits.append(String(localized: "\(n) wake-ups")) }
        var read = ["Rest"]; if hours != nil { read.append("Sleep duration") }
        let head = hours.map { String(localized: "Rest \(Int(rest.rounded()))% after \($0) of sleep") } ?? String(localized: "Rest \(Int(rest.rounded()))%")
        var vals: [String: Double] = ["rest": rest]
        if let v = m.sleepMinutes { vals["sleepMin"] = v }
        if let v = m.day?.efficiency { vals["efficiency"] = v }
        if let v = m.day?.deepMin, v > 0 { vals["deepMin"] = v }
        return remembering(NunaAnyaRead(headline: head, detail: bits.isEmpty ? nil : bits.joined(separator: ". ") + ".",
                                        read: read, module: .sleep, questions: questions(.sleep)), values: vals)
    }

    // MARK: Health

    private static func health(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        // Against the person's own 30 days: what the two overnight signals say together, not the two figures.
        func history(_ pick: (DailyMetric) -> Double?) -> [Double] { repo.days.dropLast().suffix(30).compactMap(pick) }
        if let h = m.hrv, let r = m.restingHr,
           let hrv = VitalRead.analyze(latest: h, history: history { $0.avgHrv }),
           let rhr = VitalRead.analyze(latest: r, history: history { $0.restingHr.map(Double.init) }) {
            var vals: [String: Double] = ["hrv": h, "rhr": r]
            if let v = m.spo2 { vals["spo2"] = v }
            if let v = m.respiratory { vals["resp"] = v }
            var read = ["HRV", "Resting HR"]
            if m.spo2 != nil { read.append("Blood Oxygen") }
            if m.respiratory != nil { read.append("Respiratory") }
            let text = NunaInsightText.health(hrv: hrv, rhr: rhr)
            return remembering(NunaAnyaRead(headline: text.headline, detail: text.detail, read: read, module: .health,
                                            questions: questions(.health)), values: vals)
        }
        var parts: [String] = [], read: [String] = []
        if let v = m.hrv { parts.append("HRV \(Int(v.rounded())) ms"); read.append("HRV") }
        if let v = m.restingHr { parts.append(String(localized: "resting heart rate \(Int(v.rounded())) bpm")); read.append("Resting HR") }
        guard !parts.isEmpty else { return nil }
        var more: [String] = []
        if let v = m.spo2 { more.append("SpO₂ \(Int(v.rounded()))%"); read.append("Blood Oxygen") }
        if let v = m.respiratory { more.append(String(localized: "breathing \(String(format: "%.1f", locale: AppLanguage.activeLocale, v)) per minute")); read.append("Respiratory") }
        let head = parts.joined(separator: ", ")
        var vals: [String: Double] = [:]
        if let v = m.hrv { vals["hrv"] = v }
        if let v = m.restingHr { vals["rhr"] = v }
        if let v = m.spo2 { vals["spo2"] = v }
        if let v = m.respiratory { vals["resp"] = v }
        return remembering(NunaAnyaRead(headline: String(head.prefix(1)).uppercased() + String(head.dropFirst()), detail: more.isEmpty ? nil : more.joined(separator: ", ") + ".",
                                        read: read, module: .health, questions: questions(.health)), values: vals)
    }

    // MARK: Body

    /// The Health > Body tab as one read: body health (BMI, waist ratio, weight), the week of training and its load, and nutrition.
    /// Each part is left out when there is nothing behind it.
    private static func body(repo: Repository, profile: ProfileStore, scale: EffortScale) async -> NunaAnyaRead? {
        func f(_ v: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", locale: AppLanguage.activeLocale, v) }
        let weightS = NunaSeriesModel(), fatS = NunaSeriesModel(), leanS = NunaSeriesModel(), kcalS = NunaSeriesModel(), proteinS = NunaSeriesModel()
        await weightS.load(repo: repo, key: "weight", source: "apple-health", days: 60, also: nunaManualSource)
        await fatS.load(repo: repo, key: "body_fat", source: "apple-health", days: 60)
        await leanS.load(repo: repo, key: "lean_mass", source: "apple-health", days: 60)
        await kcalS.load(repo: repo, key: "calories_in", source: "nutrition-csv", days: 30)
        await proteinS.load(repo: repo, key: "protein_g", source: "nutrition-csv", days: 30)
        let training = NunaWorkoutsModel()
        await training.load(repo: repo)

        var head: [String] = [], detail: [String] = [], read: [String] = []
        var vals: [String: Double] = [:]

        let weight = weightS.latest?.value ?? (profile.weightKg > 0 ? profile.weightKg : nil)
        if let w = weight, profile.heightCm > 0 {
            let bmi = w / pow(profile.heightCm / 100, 2)
            let word = bmi < 18.5 ? String(localized: "under range") : (bmi < 25 ? String(localized: "in the normal range") : String(localized: "above the normal range"))
            head.append("BMI \(f(bmi)) (\(word))"); read.append("BMI"); vals["bmi"] = bmi
        }
        if profile.waistCm > 0, profile.heightCm > 0 {
            let r = profile.waistCm / profile.heightCm
            head.append(String(localized: "waist ratio \(f(r, 2))")); read.append("Waist ratio"); vals["waist"] = r
        }
        if let w = weight {
            read.append("Weight"); vals["weight"] = w
            let pts = weightS.readings(30)
            if pts.count >= 2 {
                let d = pts[pts.count - 1].value - pts[0].value
                if abs(d) >= 0.05 { detail.append(String(localized: "Weight \(f(w)) kg, \(d < 0 ? "down" : "up") \(f(abs(d))) kg over 30 days.")) }
                else { detail.append(String(localized: "Weight \(f(w)) kg, steady over 30 days.")) }
            } else { detail.append(String(localized: "Weight \(f(w)) kg.")) }
        }
        if let fat = fatS.latest?.value { read.append("Body fat"); detail.append(String(localized: "Body fat \(f(fat))%.")); vals["fat"] = fat }
        if let lean = leanS.latest?.value { read.append("Lean mass"); detail.append(String(localized: "Lean mass \(f(lean)) kg.")); vals["lean"] = lean }

        let week = training.recent(days: 7)
        if !week.isEmpty {
            let e = training.effort(week)
            head.append(String(localized: "\(week.count) sessions this week (Effort \(UnitFormatter.effortDisplay(e, scale: scale)))"))
            read.append("Training"); vals["weekEffort"] = Double(UnitFormatter.effortDisplay(e, scale: scale)) ?? e
        }
        if let ratio = TrendInsights.loadRatio(blocks: training.weeklyEffort(weeks: 6)) {
            let word: String
            switch TrendInsights.loadBand(ratio) {
            case .under: word = String(localized: "below your usual")
            case .optimal: word = String(localized: "in your usual range")
            case .high: word = String(localized: "above your usual")
            case .excessive: word = String(localized: "well above your usual")
            }
            detail.append(String(localized: "Training load ratio \(f(ratio, 2)), \(word)."))
            read.append("Training load"); vals["loadRatio"] = ratio
        }
        if let kcal = kcalS.latest?.value {
            var line = String(localized: "Nutrition: \(Int(kcal.rounded())) kcal in")
            if let p = proteinS.latest?.value { line += String(localized: ", \(Int(p.rounded())) g protein") }
            detail.append(line + "."); read.append("Nutrition"); vals["kcalIn"] = kcal
        }
        guard !head.isEmpty else { return nil }
        let h = head.joined(separator: ", ")
        return remembering(NunaAnyaRead(headline: String(h.prefix(1)).uppercased() + String(h.dropFirst()),
                                        detail: detail.isEmpty ? nil : detail.joined(separator: " "),
                                        read: read, module: .health, questions: bodyQuestions), values: vals)
    }

    private static var bodyQuestions: [NunaAnyaQuestion] {
        [NunaAnyaQuestion(title: String(localized: "Is my weight trend healthy?"), prompt: "Look at my weight, BMI and waist to height ratio and tell me neutrally what the trend says."),
         NunaAnyaQuestion(title: String(localized: "Review my training load"), prompt: "Review my training this week and my training load ratio. Am I doing too much or too little?"),
         NunaAnyaQuestion(title: String(localized: "What does my nutrition show?"), prompt: "Look at my nutrition and my training and tell me one thing to adjust.")]
    }

    // MARK: Nutrition

    /// Today's food read against the plan: calories and macros so far, the week, the weight trend and what the body spends. Every figure is stored data;
    /// parts without data are left out, and with nothing eaten and no plan there is no read.
    @MainActor private static func nutrition(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        func n(_ v: Double) -> String { String(format: "%.0f", locale: AppLanguage.activeLocale, v) }
        let d = UserDefaults.standard
        let today = Repository.localDayKey(Date())
        let food = await NunaFoodStore.day(today, repo: repo)
        let intake = await NunaFoodStore.intakeByDay(days: 14, repo: repo)
        var eaten = intake[today] ?? 0
        if !food.entries.isEmpty { eaten = food.kcal }
        let plan = d.bool(forKey: NunaNutritionPrefs.hasPlan) ? d.double(forKey: NunaNutritionPrefs.targetKcal) : 0
        var head: [String] = [], detail: [String] = [], read: [String] = [], vals: [String: Double] = [:]

        if plan > 0 {
            let weights = await NunaFoodStore.weights(days: 120, repo: repo)
            let kg = NutritionMath.trend(weights).last?.kg ?? (profile.weightKg > 0 ? profile.weightKg : 70)
            let m = NutritionMath.macroTargets(kcal: plan, weightKg: kg, proteinPerKg: d.object(forKey: NunaNutritionPrefs.proteinPerKg) as? Double ?? NunaNutritionPrefs.defaultProteinPerKg,
                                               fatShare: d.object(forKey: NunaNutritionPrefs.fatShare) as? Double ?? NunaNutritionPrefs.defaultFatShare)
            let left = plan - eaten
            head.append(left >= 0 ? String(localized: "\(n(eaten)) of \(n(plan)) kcal eaten, \(n(left)) left") : String(localized: "\(n(eaten)) of \(n(plan)) kcal eaten, \(n(-left)) over"))
            if !food.entries.isEmpty {
                detail.append(String(localized: "Protein \(n(food.proteinG)) of \(n(m.proteinG)) g, carbs \(n(food.carbsG)) of \(n(m.carbsG)) g, fat \(n(food.fatG)) of \(n(m.fatG)) g."))
                vals["protein"] = food.proteinG
            }
            read.append("Daily target"); vals["target"] = plan
        } else if eaten > 0 {
            head.append(String(localized: "\(n(eaten)) kcal eaten today"))
            if !food.entries.isEmpty { detail.append(String(localized: "Protein \(n(food.proteinG)) g, carbs \(n(food.carbsG)) g, fat \(n(food.fatG)) g. Set a plan in Strategy to get a daily target.")) }
        }
        guard !head.isEmpty else { return nil }
        vals["kcal"] = eaten; read.append("Food diary")

        let others = intake.filter { $0.key != today && $0.value > 0 }
        if others.count >= 3 {
            let avg = others.values.reduce(0, +) / Double(others.count)
            detail.append(String(localized: "On the \(others.count) earlier days logged in the last two weeks you averaged \(n(avg)) kcal."))
        }
        let weights = NutritionMath.trend(await NunaFoodStore.weights(days: 60, repo: repo))
        if let last = weights.last, let first = weights.first(where: { (NutritionMath.dayIndex(last.day) ?? 0) - (NutritionMath.dayIndex($0.day) ?? 0) <= 28 }),
           first.day != last.day {
            let diff = last.kg - first.kg
            detail.append(abs(diff) < 0.1 ? String(localized: "Trend weight \(String(format: "%.1f", locale: AppLanguage.activeLocale, last.kg)) kg, steady.")
                          : String(localized: "Trend weight \(String(format: "%.1f", locale: AppLanguage.activeLocale, last.kg)) kg, \(diff < 0 ? "down" : "up") \(String(format: "%.1f", locale: AppLanguage.activeLocale, abs(diff))) kg in four weeks."))
            read.append("Weight")
        }
        if let burn = NunaFoodStore.maintenance(intake: await NunaFoodStore.intakeByDay(days: 30, repo: repo), weights: await NunaFoodStore.weights(days: 120, repo: repo), profile: profile) {
            detail.append(burn.source == .foodAndWeight ? String(localized: "Your body spends about \(n(burn.kcal)) kcal a day, worked out from your food and weight.")
                          : String(localized: "Your body spends roughly \(n(burn.kcal)) kcal a day, a rough figure from your profile for now."))
        }
        return remembering(NunaAnyaRead(headline: String(head[0].prefix(1)).uppercased() + String(head[0].dropFirst()), detail: detail.isEmpty ? nil : detail.joined(separator: " "),
                                        read: read, module: .nutrition, questions: questions(.nutrition)), values: vals)
    }

    // MARK: Trends

    private static func trends(repo: Repository) -> NunaAnyaRead? {
        let vals = repo.days.compactMap { d in d.recovery.map { (d.day, $0) } }
        guard vals.count >= 14 else { return nil }
        let last7 = vals.suffix(7).map(\.1), prior = vals.dropLast(7).suffix(30).map(\.1)
        guard !prior.isEmpty else { return nil }
        let a = last7.reduce(0, +) / Double(last7.count), b = prior.reduce(0, +) / Double(prior.count)
        let diff = Int((a - b).rounded())
        let word = diff == 0 ? String(localized: "level with") : (diff > 0 ? String(localized: "\(diff) points above") : String(localized: "\(-diff) points below"))
        return remembering(NunaAnyaRead(headline: String(localized: "Charge averaged \(Int(a.rounded()))% this week, \(word) the month before"),
                                        detail: String(localized: "Compared with \(prior.count) earlier days (\(Int(b.rounded()))% on average)."),
                                        read: ["Charge", "30 days"], module: .trends, questions: questions(.trends)), values: ["week": a, "before": b])
    }

    // MARK: Breathing

    /// The Breathing module's read: the advisor's pick for right now, with the figures behind it and a note on the last session.
    private static func breathing(repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let s = await NunaBreathAdviceMaker.make(repo: repo, profile: profile)
        var detail = s.detail
        if let last = NunaBreathLog.all().first, let pct = last.rmssdChangePct {
            let note = String(localized: "Last session: HRV \(String(format: "%+.0f", locale: AppLanguage.activeLocale, pct))% over \(last.durationText).")
            detail = [detail, note].compactMap { $0 }.joined(separator: " ")
        }
        return NunaAnyaRead(headline: s.headline, detail: detail, read: s.read, module: .breathing, questions: questions(.breathing))
    }

    // MARK: Workouts

    private static func workouts(repo: Repository, scale: EffortScale) async -> NunaAnyaRead? {
        let rows = await repo.workoutRows()
        let from = Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
        let week = rows.filter { $0.startTs >= from }
        guard !week.isEmpty else { return nil }
        let effort = week.compactMap(\.strain).reduce(0, +)
        let minutes = Int(week.reduce(0.0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) } / 60)
        return remembering(NunaAnyaRead(headline: String(localized: "\(week.count) sessions this week, Effort \(UnitFormatter.effortDisplay(effort, scale: scale))"),
                                        detail: String(localized: "\(minutes) minutes of training in the last 7 days."),
                                        read: ["Workouts 7 days", "Effort"], module: .workouts, questions: questions(.workouts)),
                           values: ["sessions": Double(week.count), "minutes": Double(minutes), "weekEffort": Double(UnitFormatter.effortDisplay(effort, scale: scale)) ?? effort])
    }

    // MARK: One metric

    /// What Anya says on a single-metric screen: the latest reading, against yesterday and against the wearer's own 30 days, from the
    /// stored daily series of that metric and nothing else. Nil when there is no reading to cite.
    private static func metricRead(_ m: NunaAnyaMetric, repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        if m.key == "stress" { return await stressRead(m, repo: repo, profile: profile) }
        let series = await repo.exploreSeries(key: m.key, source: m.source, days: 60)
        guard let latest = series.last else { return nil }
        let earlier = series.dropLast().suffix(30).map(\.value)
        func f(_ v: Double) -> String { String(format: "%.\(m.decimals)f", locale: AppLanguage.activeLocale, v) }
        let unit = m.unit.isEmpty ? "" : (m.unit == "%" ? "%" : " " + m.unit)
        var head = "\(m.title) \(f(latest.value))\(unit)"
        var read = [m.title]
        if earlier.count >= 5 {
            let avg = earlier.reduce(0, +) / Double(earlier.count)
            let tol = max(abs(avg) * 0.03, m.decimals == 0 ? 0.5 : 0.05)
            let word = abs(latest.value - avg) <= tol ? String(localized: "in line with")
                : (latest.value > avg ? String(localized: "above") : String(localized: "below"))
            head += ", \(word) " + String(localized: "your \(earlier.count)-day average (\(f(avg)))")
            read.append(String(localized: "\(earlier.count) days"))
        }
        var detail: String?
        if series.count >= 2 {
            let prev = series[series.count - 2].value, d = latest.value - prev
            // "Down 0" is no news: a move too small to show at this precision counts as the same.
            let tiny = Double(f(abs(d))) == 0
            detail = tiny ? String(localized: "Same as the day before (\(f(prev))).")
                : (d > 0 ? String(localized: "Up \(f(abs(d))) from the day before (\(f(prev))).") : String(localized: "Down \(f(abs(d))) from the day before (\(f(prev))).")) 
        }
        return NunaAnyaRead(headline: head, detail: detail, read: read, module: .health, questions: metricQuestions(m))
    }

    private static func stressRead(_ m: NunaAnyaMetric, repo: Repository, profile: ProfileStore) async -> NunaAnyaRead? {
        let model = NunaTodayModel()
        await model.load(repo: repo, profile: profile)
        let level = model.stressCurve.flatMap { StressDayCurve.latestLevel($0) } ?? model.stress.map { min(max($0, 0), 3) }
        guard let level else { return nil }
        func f(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }
        var head = String(localized: "Stress \(f(level)) of 3")
        if let base = model.stressBaseline {
            let d = level - base
            head += ", " + (abs(d) < 0.05 ? String(localized: "at your baseline (\(f(base)))")
                            : (d < 0 ? String(localized: "calmer than your baseline (\(f(base)))") : String(localized: "tenser than your baseline (\(f(base)))")))
        }
        var detail: String?
        if let curve = model.stressCurve, curve.hours.contains(where: { $0.level != nil }) {
            detail = String(localized: "High stress for \(StressTrace.clock(minutes: StressDayCurve.highMinutes(curve))) hours so far. Moments when you were moving are left out.")
        }
        var read = ["Stress"]
        if model.hrv != nil { read.append("HRV") }
        if model.restingHr != nil { read.append("Resting HR") }
        return NunaAnyaRead(headline: head, detail: detail, read: read, module: .health, questions: metricQuestions(m))
    }

    /// Questions about this metric, in this metric's words.
    private static func metricQuestions(_ m: NunaAnyaMetric) -> [NunaAnyaQuestion] {
        let t = m.title
        return [NunaAnyaQuestion(title: String(localized: "Is my \(t) normal for me?"),
                                 prompt: "Is my \(t) normal for me? Compare my latest reading with my own recent days and say whether it is worth attention."),
                NunaAnyaQuestion(title: String(localized: "Why did \(t) change?"),
                                 prompt: "Why might my \(t) have changed compared with the days before? Look at my sleep, training and journal for triggers."),
                NunaAnyaQuestion(title: String(localized: "What affects \(t)?"),
                                 prompt: "What affects \(t) and what could I do to keep it in a good range, given my own numbers?")]
    }

    // MARK: Questions per module (AnyaSheet*.dc.html)

    static func questions(_ module: NunaAnyaModule) -> [NunaAnyaQuestion] {
        switch module {
        case .today:
            return [NunaAnyaQuestion(title: String(localized: "Build today's plan"), prompt: "", kind: .plan),
                    NunaAnyaQuestion(title: String(localized: "Why did Charge change?"), prompt: "Why did my Charge change compared with yesterday? Use my sleep, HRV and resting heart rate."),
                    NunaAnyaQuestion(title: String(localized: "Summarise my day"), prompt: "Summarise my day so far in a few sentences, using my numbers.")]
        case .health:
            return [NunaAnyaQuestion(title: String(localized: "Explain my HRV"), prompt: "Explain what my HRV is telling me today, compared with my own baseline."),
                    NunaAnyaQuestion(title: String(localized: "What is fitness age?"), prompt: "What is fitness age and how is mine worked out in this app?"),
                    NunaAnyaQuestion(title: String(localized: "Check my lab results"), prompt: "Look at my Lab Book markers and tell me neutrally what stands out.")]
        case .sleep:
            return [NunaAnyaQuestion(title: String(localized: "Why did I wake up?"), prompt: "Why might I have woken up several times last night? Use my sleep numbers."),
                    NunaAnyaQuestion(title: String(localized: "Compare with last week"), prompt: "Compare my sleep this week with last week."),
                    NunaAnyaQuestion(title: String(localized: "How can I sleep better tonight?"), prompt: "Give me one practical step to sleep better tonight, based on my recent nights.")]
        case .trends:
            return [NunaAnyaQuestion(title: String(localized: "Why did Charge move?"), prompt: "Why did my Charge move over the last month? Point to the behaviours in my data."),
                    NunaAnyaQuestion(title: String(localized: "My hardest day"), prompt: "Which day was hardest on my body this month and what followed it?"),
                    NunaAnyaQuestion(title: String(localized: "Plan next week"), prompt: "Suggest how to spread training across next week given my recent load and recovery.")]
        case .workouts:
            return [NunaAnyaQuestion(title: String(localized: "Today's recommendation"), prompt: "Recommend the best workout for today using my Charge, Effort, Rest and recent workouts."),
                    NunaAnyaQuestion(title: String(localized: "Plan this week"), prompt: "Plan my training for this week from my current load and recovery."),
                    NunaAnyaQuestion(title: String(localized: "Recover faster"), prompt: "What helps me recover faster after my recent sessions?")]
        case .nutrition:
            return [NunaAnyaQuestion(title: String(localized: "How is my day going?"), prompt: "Look at what I have eaten today against my target and macros and tell me what to do for the rest of the day."),
                    NunaAnyaQuestion(title: String(localized: "Dinner suggestion"), prompt: "Suggest what to eat tonight given what I have eaten today, my target and today's activity."),
                    NunaAnyaQuestion(title: String(localized: "How much protein do I need?"), prompt: "How much protein should I aim for, given my training and my weight?")]
        case .breathing:
            return [NunaAnyaQuestion(title: String(localized: "Which exercise fits me now?"), prompt: "Which breathing exercise fits me right now? Use my live heart rate, HRV, stress and Charge, and what worked in my earlier breathing sessions."),
                    NunaAnyaQuestion(title: String(localized: "How did my last sessions go?"), prompt: "How did my recent breathing sessions go? Look at the HRV and heart rate change in each and tell me what is working."),
                    NunaAnyaQuestion(title: String(localized: "How do I breathe better?"), prompt: "Give me one practical tip to get more from my breathing sessions, given how my body responded before.")]
        case .device:
            return [NunaAnyaQuestion(title: String(localized: "Why did the strap disconnect?"), prompt: "Why might my strap keep disconnecting from the phone?"),
                    NunaAnyaQuestion(title: String(localized: "How do I charge the battery?"), prompt: "How should I charge my strap and how long does the battery last?")]
        }
    }

    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
#endif
