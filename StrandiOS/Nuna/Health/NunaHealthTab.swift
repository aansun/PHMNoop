#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The Health tab: fitness age, the health monitor (the five vital signs against their usual range) and the stress monitor, one under the other.
struct NunaHealthTabView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var day = NunaTodayModel()

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                Text("Health").font(.nuna(size: NunaTypeSize.h1, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                NunaFitnessAgeSummary()
                NunaHealthMonitorCard(hrv: day.hrv, restingHr: day.restingHr, spo2: day.spo2, respiratory: day.respiratory, skinTemp: day.extras["skin_temp"])
                if day.stress != nil || day.stressCurve != nil {
                    NunaStressCard(score: day.stress, curve: day.stressCurve, baseline: day.stressBaseline, isToday: day.isToday, workouts: day.workouts)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .nunaTodayDestinations()
        .task(id: repo.refreshSeq) { await day.load(repo: repo, profile: profile) }
    }
}

/// Fitness age as the orb, how far it is from the calendar age and from last week, and the way into the full page.
struct NunaFitnessAgeSummary: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var series: [(day: String, value: Double)] = []
    @State private var loaded = false

    var body: some View {
        NunaCard(padding: EdgeInsets(top: 22, leading: 18, bottom: 18, trailing: 18)) {
            VStack(spacing: 16) {
                if let latest = series.last { content(latest) } else { empty }
                NavigationLink(value: NunaTodayRoute.fitnessAge) {
                    Text("Go to fitness age").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: repo.refreshSeq) {
            series = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 200)
            loaded = true
        }
    }

    private func content(_ latest: (day: String, value: Double)) -> some View {
        let age = Double(profile.age)
        let diff = age > 0 ? Int((age - latest.value).rounded()) : nil
        let tint: Color = (diff ?? 0) > 0 ? NunaPalette.charge : ((diff ?? 0) < 0 ? NunaPalette.warning : NunaPalette.textSecondary)
        let weekly: Int? = series.count >= 2 ? Int((series[series.count - 1].value - series[series.count - 2].value).rounded()) : nil
        return VStack(spacing: 16) {
            Text("Fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            NunaFitnessOrb(tint: tint, size: 240) {
                VStack(spacing: 6) {
                    Text(verbatim: String(format: "%.0f", locale: AppLanguage.activeLocale, latest.value))
                        .font(.nuna(size: 60, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(60)).foregroundStyle(NunaPalette.textPrimary)
                    if let diff, diff != 0 {
                        Text(diff > 0 ? LocalizedStringKey("\(diff) years younger") : LocalizedStringKey("\(-diff) years older"))
                            .font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint)
                    } else if diff == 0 {
                        Text("About your age").font(.nuna(size: 15, weight: .bold)).foregroundStyle(tint)
                    }
                }
            }
            if let weekly, weekly != 0 {
                let good = weekly < 0
                HStack(spacing: 6) {
                    Image(systemName: good ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.nuna(size: 10))
                    Text(verbatim: good ? String(localized: "\(-weekly) yr younger than last week") : String(localized: "\(weekly) yr older than last week"))
                        .font(.nuna(size: 13, weight: .bold))
                }
                .foregroundStyle(good ? NunaPalette.charge : NunaPalette.warning)
                .padding(.horizontal, 14).frame(height: 32)
                .background((good ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            } else if weekly == 0 {
                Text("Steady since last week").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Text(loaded ? "Not ready yet" : " ").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Text("Fitness age needs your age, your sex and resting heart rate from at least 4 nights. It updates once a week.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The five vital signs side by side, each with a mark for in range, out of range or no reading, and a line with how many are in range.
struct NunaHealthMonitorCard: View {
    let hrv: Double?
    let restingHr: Double?
    let spo2: Double?
    let respiratory: Double?
    let skinTemp: Double?

    @EnvironmentObject private var repo: Repository
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()

    private struct Vital: Identifiable {
        let id: String
        let icon: String
        let label: String
        /// nil with no reading, otherwise whether it sits in its usual range.
        let ok: Bool?
    }

    private var vitals: [Vital] {
        [
            Vital(id: "resp", icon: "lungs", label: "RESP", ok: respiratory.flatMap { v in respS.band.map { abs(v - $0.mean) <= max($0.sd, 0.3) } }),
            Vital(id: "spo2", icon: "drop", label: "SpO₂", ok: spo2.map { $0 >= 95 }),
            Vital(id: "rhr", icon: "heart", label: "RHR", ok: restingHr.flatMap { v in rhrS.band.map { abs(v - $0.mean) <= max($0.sd, 1) } }),
            Vital(id: "hrv", icon: "waveform.path.ecg", label: "HRV", ok: hrv.flatMap { v in hrvS.band.map { abs(v - $0.mean) <= max($0.sd, 1) } }),
            Vital(id: "temp", icon: "thermometer.medium", label: "TEMP", ok: skinTemp.map { abs($0) < 0.5 }),
        ]
    }

    var body: some View {
        let all = vitals
        let known = all.filter { $0.ok != nil }.count
        let within = all.filter { $0.ok == true }.count
        NavigationLink(value: NunaTodayRoute.vitalSigns) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Health monitor").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(all.enumerated()), id: \.element.id) { idx, v in
                            if idx > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 70) }
                            column(v)
                        }
                    }
                    summary(within: within, known: known)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: repo.refreshSeq) {
            await hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
            await rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
            await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
        }
    }

    private func column(_ v: Vital) -> some View {
        let tint = v.ok == nil ? NunaPalette.textMuted : (v.ok == true ? NunaPalette.charge : NunaPalette.warning)
        return VStack(spacing: 8) {
            Image(systemName: v.icon).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(height: 26)
            Text(verbatim: v.label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).foregroundStyle(NunaPalette.textPrimary)
            badge(tint: tint, symbol: v.ok == nil ? "minus" : (v.ok == true ? "checkmark" : "exclamationmark"))
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(tint: Color, symbol: String) -> some View {
        Image(systemName: symbol).font(.nuna(size: 11, weight: .heavy)).foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func summary(within: Int, known: Int) -> some View {
        let allIn = known > 0 && within == known
        let tint = known == 0 ? NunaPalette.textMuted : (allIn ? NunaPalette.charge : NunaPalette.warning)
        return HStack(spacing: 12) {
            badge(tint: tint, symbol: known == 0 ? "minus" : (allIn ? "checkmark" : "exclamationmark"))
            Text(verbatim: known == 0 ? String(localized: "No data") : String(localized: "\(within)/5 metrics within range"))
                .font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).frame(height: 44)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif
