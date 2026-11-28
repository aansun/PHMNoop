#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// Runs Anya's lookups (`AnyaTools`) against what is on this phone. Journal answers, blood pressure and lab results are given only when the
/// person shares patterns and the Lab Book.
@MainActor
enum NunaAnyaTools {
    static func install(on coach: AICoachEngine, repo: Repository, profile: ProfileStore) {
        coach.lookUp = { [weak coach] name, input in
            await run(name, input, repo: repo, profile: profile, sharesRecords: coach?.includeOnDeviceSignals ?? false)
        }
    }

    /// What the screen says while Anya waits: which of the person's data she is reading, so a lookup is never silent.
    static func activity(_ name: String?) -> String {
        switch name.flatMap(AnyaTools.Name.init(rawValue:)) {
        case .dailyMetrics: return String(localized: "Reading your daily figures…")
        case .sleepNights: return String(localized: "Reading your nights…")
        case .workouts: return String(localized: "Reading your workouts…")
        case .bodyTrend: return String(localized: "Reading your body trend…")
        case .foodDiary: return String(localized: "Reading your food diary…")
        case .healthLog: return String(localized: "Reading your health log…")
        case .profile: return String(localized: "Reading your profile…")
        case .saveAboutYou: return String(localized: "Making a note…")
        case nil: return String(localized: "Anya is thinking…")
        }
    }

    /// The short name of what a lookup read, for the line under a reply.
    static func readName(_ name: String) -> String? {
        switch AnyaTools.Name(rawValue: name) {
        case .dailyMetrics: return String(localized: "Daily figures")
        case .sleepNights: return String(localized: "Nights")
        case .workouts: return String(localized: "Workouts")
        case .bodyTrend: return String(localized: "Body trend")
        case .foodDiary: return String(localized: "Food diary")
        case .healthLog: return String(localized: "Health log")
        case .profile: return String(localized: "Profile")
        case .saveAboutYou, nil: return nil
        }
    }

    static func run(_ name: String, _ input: [String: Any], repo: Repository, profile: ProfileStore, sharesRecords: Bool, now: Date = Date()) async -> (text: String, failed: Bool) {
        guard let tool = AnyaTools.Name(rawValue: name) else { return ("There is no tool called \(name).", true) }
        let today = Repository.localDayKey(now)
        let text: String
        switch tool {
        case .dailyMetrics: text = await daily(input, repo: repo, today: today)
        case .sleepNights: text = await nights(input, repo: repo, today: today)
        case .workouts: text = await workouts(input, repo: repo, today: today)
        case .bodyTrend: text = await body(input, repo: repo)
        case .foodDiary: text = await food(input, repo: repo, today: today)
        case .healthLog: text = await healthLog(input, repo: repo, shares: sharesRecords, now: now)
        case .profile: text = await person(profile, repo: repo)
        case .saveAboutYou: return note(input)
        }
        return (AnyaTools.capped(text), false)
    }

    private static func note(_ input: [String: Any]) -> (text: String, failed: Bool) {
        guard let field = (input["field"] as? String).flatMap(AnyaAboutYou.Field.init(rawValue:)), let text = input["text"] as? String else {
            return ("field and text are needed; field is one of: " + AnyaAboutYou.Field.allCases.map(\.rawValue).joined(separator: ", ") + ".", true)
        }
        var about = AnyaAboutYou.load()
        guard about.note(field, text, replacing: input["replace"] as? Bool ?? false) else {
            return ("Not saved: nothing to save, or that line is full. To rewrite it, send the whole new text with replace true.", true)
        }
        about.save()
        return ("Saved. \(field.title) is now: \(about[field])", false)
    }

    private static func daily(_ input: [String: Any], repo: Repository, today: String) async -> String {
        let wanted = ((input["metrics"] as? [Any])?.compactMap { $0 as? String } ?? []).filter(AnyaTools.metrics.contains)
        guard !wanted.isEmpty else { return "Name at least one of: " + AnyaTools.metrics.joined(separator: ", ") + "." }
        let r = AnyaTools.range(input, today: today, standard: 30, most: 730)
        let days = repo.days.filter { $0.day >= r.from && $0.day <= r.to }
        var steps: [String: Double] = [:]
        if wanted.contains("steps") {
            for p in await repo.exploreSeries(key: "steps", source: MetricCatalog.combinedStepsSource, days: 800) { steps[p.day] = p.value }
        }
        let scale = AICoachEngine.strainScale()
        func value(_ metric: String, _ d: DailyMetric) -> Double? {
            switch metric {
            case "recovery": return d.recovery
            case "strain": return d.strain.map { UnitFormatter.effortValue($0, scale: scale) }
            case "sleep_hours": return d.totalSleepMin.map { $0 / 60 }
            case "deep_hours": return d.deepMin.map { $0 / 60 }
            case "rem_hours": return d.remMin.map { $0 / 60 }
            case "sleep_efficiency": return d.efficiency.map { $0 > 1.5 ? $0 : $0 * 100 }
            case "hrv": return d.avgHrv
            case "resting_hr": return d.restingHr.map(Double.init)
            case "respiratory_rate": return d.respRateBpm
            case "spo2": return d.spo2Pct
            case "skin_temp_change": return d.skinTempDevC
            case "steps": return steps[d.day] ?? d.steps.map(Double.init)
            case "energy_burned_kcal": return d.activeKcalEst
            default: return nil
            }
        }
        let units = "Units: recovery 0-100, strain 0-\(UnitFormatter.effortScaleMax(scale)), hours, efficiency %, HRV ms, resting HR bpm, breaths a minute, SpO2 %, skin temperature change °C, energy burned in kcal for the whole day with resting energy included."
        return "\(r.from) to \(r.to). \(units)\n"
            + AnyaTools.table(columns: wanted, rows: days.map { d in (d.day, wanted.map { value($0, d) }) }, group: AnyaTools.group(input, days: r.days))
    }

    private static func stamp(_ ts: Int, _ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private static func nights(_ input: [String: Any], repo: Repository, today: String) async -> String {
        let r = AnyaTools.range(input, today: today, standard: 7, most: 60)
        let sessions = await repo.allSleepSessions(days: 800)
        let byDay = Dictionary(grouping: sessions) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) }
        let metrics = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, l in l })
        var lines: [String] = []
        for day in byDay.keys.filter({ $0 >= r.from && $0 <= r.to }).sorted() {
            let list = (byDay[day] ?? []).sorted { ($0.endTs - $0.effectiveStartTs) > ($1.endTs - $1.effectiveStartTs) }
            guard let main = list.first else { continue }
            var parts = ["woke \(day): in bed \(stamp(main.effectiveStartTs, "HH:mm")) to \(stamp(main.endTs, "HH:mm"))"]
            if let d = metrics[day] {
                if let m = d.totalSleepMin { parts.append(String(format: "asleep %.1fh", m / 60)) }
                if let m = d.deepMin { parts.append(String(format: "deep %.1fh", m / 60)) }
                if let m = d.remMin { parts.append(String(format: "REM %.1fh", m / 60)) }
                if let m = d.lightMin { parts.append(String(format: "light %.1fh", m / 60)) }
            }
            if var e = main.efficiency, e > 0 { if e <= 1.5 { e *= 100 }; parts.append("efficiency \(Int(e.rounded()))%") }
            if let h = main.restingHr { parts.append("resting HR \(h)") }
            if let v = main.avgHrv { parts.append("HRV \(Int(v.rounded()))ms") }
            let naps = list.dropFirst().map { "\(stamp($0.effectiveStartTs, "HH:mm"))-\(stamp($0.endTs, "HH:mm"))" }
            if !naps.isEmpty { parts.append("also slept " + naps.joined(separator: ", ")) }
            lines.append(parts.joined(separator: ", "))
        }
        return lines.isEmpty ? "No sleep recorded from \(r.from) to \(r.to)." : "Nights from \(r.from) to \(r.to):\n" + lines.joined(separator: "\n")
    }

    private static func workouts(_ input: [String: Any], repo: Repository, today: String) async -> String {
        let r = AnyaTools.range(input, today: today, standard: 30, most: 365)
        let sport = (input["sport"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let distance = UnitPrefs.resolveDistance(system: system, override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        let rows = await repo.workoutRows(days: 800).filter {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs)))
            return day >= r.from && day <= r.to && (sport.isEmpty || $0.sport.lowercased().contains(sport))
        }.sorted { $0.startTs < $1.startTs }
        guard !rows.isEmpty else { return "No \(sport.isEmpty ? "" : "\(sport) ")workouts from \(r.from) to \(r.to)." }
        let lines = rows.map { w -> String in
            var parts = ["\(stamp(w.startTs, "yyyy-MM-dd HH:mm")) \(w.sport)"]
            if let s = w.durationS { parts.append("\(Int((s / 60).rounded())) min") }
            if let s = w.strain { parts.append("strain \(AICoachEngine.strainText(s))") }
            if let h = w.avgHr { parts.append("avg HR \(h)") }
            if let h = w.maxHr { parts.append("max HR \(h)") }
            if let k = w.energyKcal { parts.append("\(Int(k.rounded())) kcal") }
            if let m = w.distanceM, m > 0 { parts.append(UnitFormatter.distanceFromMeters(m, system: distance)) }
            if let z = AICoachEngine.zoneShareText(w.zonesJSON) { parts.append(z) }
            return parts.joined(separator: ", ")
        }
        return "Workouts from \(r.from) to \(r.to):\n" + AnyaTools.sessionTotals(rows.map { ($0.sport, $0.durationS.map { $0 / 60 }) }) + "\n" + lines.joined(separator: "\n")
    }

    private static func body(_ input: [String: Any], repo: Repository) async -> String {
        let series = input["series"] as? String ?? ""
        let days = AnyaTools.days(input, standard: 90, most: 730)
        let points: [(day: String, value: Double)]
        let name: String
        switch series {
        case "weight":
            points = await NunaFoodStore.weights(days: days, repo: repo).map { ($0.day, $0.kg) }; name = "weight kg"
        case "body_age":
            points = await repo.exploreSeries(key: "body_age", source: "my-whoop", days: days); name = "Body age in years (one reading a week)"
        case "vo2max":
            points = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: days); name = "VO2 max estimate"
        default:
            return "series must be one of: " + AnyaTools.bodySeries.joined(separator: ", ") + "."
        }
        let group: AnyaTools.Group = points.count > 60 ? .week : .day
        return AnyaTools.table(columns: [name], rows: points.map { ($0.day, [$0.value]) }, group: group)
    }

    private static func food(_ input: [String: Any], repo: Repository, today: String) async -> String {
        let r = AnyaTools.range(input, today: today, standard: 7, most: 60)
        guard let store = await repo.storeHandle() else { return "The food diary could not be read." }
        let rows = (try? await store.foodEntries(deviceId: repo.deviceId, fromDay: r.from, toDay: r.to)) ?? []
        guard !rows.isEmpty else { return "Nothing logged in the food diary from \(r.from) to \(r.to)." }
        let lines = Dictionary(grouping: rows, by: \.day).sorted { $0.key < $1.key }.map { day, list -> String in
            let d = NunaFoodDay(entries: list)
            let items = list.map { "\($0.meal): \($0.name) \(Int($0.kcal.rounded())) kcal" }.joined(separator: "; ")
            return "\(day): \(Int(d.kcal.rounded())) kcal, protein \(Int(d.proteinG.rounded())) g (\(items))"
        }
        return "Food diary from \(r.from) to \(r.to) (a day with nothing logged is missing, not fasting):\n" + lines.joined(separator: "\n")
    }

    private static func healthLog(_ input: [String: Any], repo: Repository, shares: Bool, now: Date) async -> String {
        guard shares else {
            return "Not shared with you. The person can turn on \"Share patterns and Lab Book\" in Anya settings if they want you to read their journal, blood pressure or lab results."
        }
        let days = AnyaTools.days(input, standard: 30, most: 730)
        let from = Repository.localDayKey(now.addingTimeInterval(-Double(days - 1) * 86_400))
        switch input["kind"] as? String {
        case "journal":
            let entries = await repo.journalEntries(days: days).filter { $0.day >= from }
            guard !entries.isEmpty else { return "No journal answers since \(from)." }
            let lines = Dictionary(grouping: entries, by: \.day).sorted { $0.key < $1.key }.map { day, list -> String in
                func name(_ e: JournalEntry) -> String {
                    e.question + (e.numericValue.map { String(format: " (%g)", $0) } ?? "") + ((e.notes?.isEmpty == false) ? " [\(e.notes!)]" : "")
                }
                let yes = list.filter(\.answeredYes).map(name), no = list.filter { !$0.answeredYes }.map(\.question)
                return "\(day): yes: \(yes.isEmpty ? "-" : yes.joined(separator: ", ")); no: \(no.isEmpty ? "-" : no.joined(separator: ", "))"
            }
            return "Journal since \(from):\n" + lines.joined(separator: "\n")
        case "blood_pressure":
            let start = Int(now.timeIntervalSince1970) - days * 86_400
            let readings = await NunaBP.load(repo).filter { $0.takenAt >= start }
            guard !readings.isEmpty else { return "No blood pressure readings since \(from)." }
            let lines = readings.map { "\(stamp($0.takenAt, "yyyy-MM-dd HH:mm")): \($0.text) mmHg" + ($0.note.map { " (\($0))" } ?? "") }
            return NunaAnyaReader.bloodPressureGuardrail + "\nBlood pressure since \(from):\n" + lines.joined(separator: "\n")
        case "lab_results":
            let markers = NunaLabGrouping.markers(await NunaLabStore.load(repo))
            let lines = markers.compactMap { m -> String? in
                guard let latest = m.latest else { return nil }
                var line = "\(m.name): \(m.text(latest)) \(m.unit) on \(LabBookFormat.dayFromKey(latest.day))"
                if let range = m.ownRange { line += " (range on their own report \(range.label(key: m.key)) \(m.unit))" }
                return line
            }
            return lines.isEmpty ? "No lab results saved." : "Latest of each saved result. Say where a value sits against the range on their own report; never call it normal or abnormal yourself.\n" + lines.joined(separator: "\n")
        default:
            return "kind must be one of: " + AnyaTools.logKinds.joined(separator: ", ") + "."
        }
    }

    private static func person(_ profile: ProfileStore, repo: Repository) async -> String {
        let d = UserDefaults.standard
        var lines = ["Age \(profile.age), sex \(profile.sex), height \(Int(profile.heightCm.rounded())) cm"]
        if let w = await NunaFoodStore.weights(days: 120, repo: repo).last { lines.append(String(format: "Weight %.1f kg on %@", w.kg, w.day)) }
        else if profile.weightKg > 0 { lines.append(String(format: "Weight %.1f kg (from the profile)", profile.weightKg)) }
        if profile.waistCm > 0 { lines.append(String(format: "Waist %.0f cm", profile.waistCm)) }
        if profile.hrMaxOverride > 0 { lines.append("Maximum heart rate set to \(profile.hrMaxOverride)") }
        var goals: [String] = []
        if d.double(forKey: NunaGoals.targetWeightKg) > 0 { goals.append("target weight \(d.double(forKey: NunaGoals.targetWeightKg)) kg") }
        if d.double(forKey: "nuna.goal.weeklyEffort") > 0 { goals.append("weekly Strain \(Int(d.double(forKey: "nuna.goal.weeklyEffort")))") }
        if d.integer(forKey: "nuna.goal.sleepMinutes") > 0 { goals.append("sleep \(d.integer(forKey: "nuna.goal.sleepMinutes")) minutes") }
        if d.integer(forKey: "nuna.goal.steps") > 0 { goals.append("\(d.integer(forKey: "nuna.goal.steps")) steps a day") }
        lines.append("Goals set: " + (goals.isEmpty ? "none" : goals.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }
}
#endif
