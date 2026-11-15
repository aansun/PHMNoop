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

/// Reads the week through `VitalityWeekReader` (the reader the weekly job that stores `body_age` and the Health screen use too) and runs it through `VitalityEngine`, so
/// the figures here are the stored ones.
enum NunaHealthspan {
    @MainActor static func compute(days: [DailyMetric], vo2: Double?, repo: Repository, profile: ProfileStore) async -> NunaHealthspanResult? {
        let rhrDays = days.compactMap { $0.restingHr }.count
        // The same gate as the fitness age: a week the strap was hardly worn says nothing.
        guard profile.age > 0, rhrDays >= FitnessAgeEngine.minCoverageDays else { return nil }
        let week = await VitalityWeekReader.read(repo: repo, days: days, age: profile.age, sex: profile.sex, waistCm: profile.waistCm, vo2Estimate: vo2)
        let inputs = VitalityEngine.weeklyInputs(week)
        guard let result = VitalityEngine.compute(inputs) else { return nil }

        func text(_ key: String) -> String {
            let f = AppLanguage.activeLocale
            switch key {
            case "rhr": return String(format: "%.0f bpm", locale: f, inputs.restingHR ?? 0)
            case "vo2max": return String(format: "%.0f", locale: f, inputs.vo2max ?? 0)
            case "sleep": return String(format: "%.1f h", locale: f, inputs.sleepHours ?? 0)
            case "consistency": return String(format: "%.0f%%", locale: f, (inputs.sleepConsistency ?? 0) * 100)
            case "steps": return String(format: "%.0f", locale: f, inputs.steps ?? 0)
            case "zonesLow": return String(format: "%.0f ", locale: f, inputs.zonesLowMin ?? 0) + String(localized: "min/wk")
            case "zonesHigh": return String(format: "%.0f ", locale: f, inputs.zonesHighMin ?? 0) + String(localized: "min/wk")
            case "strength": return String(format: "%.0f ", locale: f, inputs.strengthMin ?? 0) + String(localized: "min/wk")
            case "leanMass": return String(format: "%.1f%%", locale: f, inputs.leanMassPct ?? 0)
            default: return ""
            }
        }
        let rows = result.contributions.map { NunaHealthspanResult.Row(key: $0.key, label: $0.label, value: text($0.key), years: VitalityEngine.years(of: $0)) }
        return NunaHealthspanResult(bodyAge: result.bodyAge, rows: rows)
    }
}
#endif
