#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// The card on the fitness age page that lists what moves the wearer's Body Age: nine inputs of `VitalityEngine` (resting heart rate, cardio fitness, sleep
/// duration and regularity, steps, time in heart-rate zones 1–3 and 4–5, strength training, lean body mass), each as the years it adds or takes away
/// against its break-even. Heart-rate variability, which the engine also reads, is left out here so the nine are the nine the WHOOP Healthspan page lists.
/// An input with no data for the week is left out, never counted as zero, and the card stays away when fewer than three are there. It is a wellness estimate
/// from published mortality studies and sits beside the fitness age without changing it.
struct NunaHealthspanCard: View {
    /// What `NunaHealthspan.compute` made for the week on show; nil draws nothing.
    let computed: NunaHealthspanResult?
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        if let computed { content(computed) }
    }

    private func content(_ computed: NunaHealthspanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
                Text("Healthspan factors").font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                NunaCard {
                    VStack(alignment: .leading, spacing: 18) {
                        header(computed)
                        VStack(spacing: 14) { ForEach(computed.rows) { row($0) } }
                        Text("\(computed.rows.count) of 9 inputs").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text("Each input is read against a break-even taken from published mortality studies. An input with no data is left out, not counted as zero. This is a wellness estimate, not a biological age, and it does not change your fitness age.")
                            .font(.nunaWords(size: 13)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
    }

    private func header(_ c: NunaHealthspanResult) -> some View {
        let delta = Double(profile.age) - c.bodyAge
        let years = String(format: "%.1f", locale: AppLanguage.activeLocale, abs(delta))
        let tint = abs(delta) < 0.5 ? NunaPalette.textPrimary : (delta > 0 ? NunaPalette.charge : NunaPalette.caution)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Body age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, c.bodyAge)).font(.nuna(size: 44, weight: .semibold, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary)
            Group {
                if abs(delta) < 0.5 { Text("About the same as your calendar age") }
                else if delta > 0 { Text("\(years) years younger than your calendar age") }
                else { Text("\(years) years older than your calendar age") }
            }
            .font(.nuna(size: 14, weight: .semibold)).textCase(nil).foregroundStyle(tint)
        }
    }

    private func row(_ r: NunaHealthspanResult.Row) -> some View {
        let tint = abs(r.years) < 0.05 ? NunaPalette.textSecondary : (r.years < 0 ? NunaPalette.charge : NunaPalette.caution)
        return VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(r.label)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                Text(verbatim: r.value).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Text(verbatim: String(format: "%+.1f", locale: AppLanguage.activeLocale, r.years).replacingOccurrences(of: "-", with: "−") + " " + String(localized: "yr"))
                    .font(.nuna(size: 13, weight: .heavy)).foregroundStyle(tint).textCase(nil).frame(minWidth: 62, alignment: .trailing)
            }
            // A bar out from the middle: older to the right, younger to the left, full at four years.
            GeometryReader { g in
                let half = g.size.width / 2
                let w = min(abs(r.years) / 4, 1) * half
                ZStack(alignment: .leading) {
                    Capsule().fill(NunaPalette.textMuted.opacity(0.18))
                    Capsule().fill(tint).frame(width: max(w, 2)).offset(x: r.years < 0 ? half - w : half)
                    Rectangle().fill(NunaPalette.textMuted.opacity(0.6)).frame(width: 1.5).offset(x: half - 0.75)
                }
            }
            .frame(height: 6)
        }
    }
}

/// The Body Age of the week on show and what each input adds or takes away.
struct NunaHealthspanResult {
    struct Row: Identifiable {
        let key: String
        let label: String
        let value: String
        let years: Double
        var id: String { key }
    }
    let bodyAge: Double
    let rows: [Row]
}

/// Reads the week's inputs from the stored days, series, heart-rate samples and workouts, and runs them through `VitalityEngine`.
enum NunaHealthspan {
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private static func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    private static func median(_ v: [Double]) -> Double? {
        let s = v.sorted()
        guard !s.isEmpty else { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    @MainActor static func compute(days: [DailyMetric], vo2: Double?, repo: Repository, profile: ProfileStore) async -> NunaHealthspanResult? {
        let age = profile.age
        let rhrs = days.compactMap { $0.restingHr }.map(Double.init)
        // The same gate as the fitness age: a week the strap was hardly worn says nothing.
        guard age > 0, rhrs.count >= FitnessAgeEngine.minCoverageDays else { return nil }

        let nights = days.compactMap { $0.totalSleepMin }.map { $0 / 60 }.filter { $0 > 0 }
        // Sleep regularity: the consistency the app stores from the timing of sleep when it has it, the spread of the nights' length when it does not.
        let storedConsistency = Dictionary((await repo.exploreSeries(key: "sleep_consistency", source: "my-whoop", days: 400)).map { ($0.day, $0.value) },
                                           uniquingKeysWith: { _, l in l })
        let weekConsistency = days.compactMap { storedConsistency[$0.day] }
        let consistency: Double? = weekConsistency.count >= 3 ? min(max((mean(weekConsistency) ?? 0) / 100, 0), 1) : VitalityEngine.sleepConsistency(nightlyHours: nights)

        let estimated = Dictionary((await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: 400)).map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        let steps = days.compactMap { d in d.steps.map(Double.init) ?? estimated[d.day] }

        // Heart-rate zones and strength time over the week. A week with no minutes in any zone has no heart-rate samples left to read, so those inputs are
        // left out then; a worn week always has some time in zone 1.
        let dates = days.compactMap { Self.dayParser.date(from: $0.day) }
        let zones = await NunaZoneMinutes.perDay(repo: repo, age: age, days: dates)
        let totalZones = zones.values.reduce(0.0) { $0 + $1.reduce(0, +) }
        let hasZones = totalZones > 0
        let low = zones.values.reduce(0.0) { $0 + $1[0] + $1[1] + $1[2] }
        let high = zones.values.reduce(0.0) { $0 + $1[3] + $1[4] }
        let cal = Calendar.current
        let from = Int((dates.first ?? Date()).timeIntervalSince1970)
        let to = Int((cal.date(byAdding: .day, value: 1, to: dates.last ?? Date()) ?? Date()).timeIntervalSince1970)
        let strength = await repo.workoutRows().filter { $0.startTs >= from && $0.startTs < to && NunaWorkoutKind.isStrength($0) }
            .reduce(0.0) { $0 + (($1.durationS ?? Double($1.endTs - $1.startTs)) / 60) }

        // Cardio fitness: a figure the wearer entered (the latest one up to the end of the week), or the estimate when it was worked out with their waist. The estimate
        // without a waist (15.3 × max heart rate ÷ resting heart rate) runs about 10 ml/kg/min high for a low resting heart rate and ignores sex, so it is not used here.
        let weekEnd = days.last?.day ?? ""
        let entered = await NunaVO2Manual.entries(repo: repo).first { $0.day <= weekEnd }?.value
        let cardio: Double? = entered ?? (profile.waistCm > 0 ? vo2 : nil)

        // Lean body mass: what the body fat of the last 30 days up to the week's end leaves of 100%, from Apple Health or a hand entry.
        let fat = NunaSeriesModel()
        await fat.load(repo: repo, key: "body_fat", source: "apple-health", days: 400, also: nunaManualSource)
        let lastDate = dates.last ?? Date()
        let fatFrom = Repository.localDayKey(cal.date(byAdding: .day, value: -29, to: lastDate) ?? lastDate)
        let recentFat = fat.byDay.filter { $0.key >= fatFrom && $0.key <= weekEnd }.map(\.value)
        let lean: Double? = recentFat.isEmpty ? nil : 100 - (mean(recentFat) ?? 0)

        let rhr = median(rhrs)
        let inputs = VitalityEngine.Inputs(
            chronoAge: Double(age), restingHR: rhr, vo2max: cardio,
            expectedVO2max: cardio == nil ? nil : VitalityEngine.expectedVO2max(age: Double(age), sex: profile.sex),
            sleepHours: mean(nights), sleepConsistency: consistency,
            steps: steps.count >= 3 ? mean(steps) : nil,
            zonesLowMin: hasZones ? low : nil, zonesHighMin: hasZones ? high : nil, strengthMin: hasZones || strength > 0 ? strength : nil,
            leanMassPct: lean)
        guard let result = VitalityEngine.compute(inputs) else { return nil }

        func text(_ key: String) -> String {
            let f = AppLanguage.activeLocale
            switch key {
            case "rhr": return String(format: "%.0f bpm", locale: f, rhr ?? 0)
            case "vo2max": return String(format: "%.0f", locale: f, cardio ?? 0)
            case "sleep": return String(format: "%.1f h", locale: f, mean(nights) ?? 0)
            case "consistency": return String(format: "%.0f%%", locale: f, (consistency ?? 0) * 100)
            case "leanMass": return String(format: "%.1f%%", locale: f, lean ?? 0)
            case "steps": return String(format: "%.0f", locale: f, mean(steps) ?? 0)
            case "zonesLow": return String(format: "%.0f ", locale: f, low) + String(localized: "min/wk")
            case "zonesHigh": return String(format: "%.0f ", locale: f, high) + String(localized: "min/wk")
            case "strength": return String(format: "%.0f ", locale: f, strength) + String(localized: "min/wk")
            default: return ""
            }
        }
        let rows = result.contributions.map { NunaHealthspanResult.Row(key: $0.key, label: $0.label, value: text($0.key), years: VitalityEngine.years(of: $0)) }
        return NunaHealthspanResult(bodyAge: result.bodyAge, rows: rows)
    }
}
#endif
