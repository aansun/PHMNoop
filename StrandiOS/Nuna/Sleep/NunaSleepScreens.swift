#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Loads `NunaSleepModel` once per screen and hands it to the content. Pushed screens each own a model
/// (a few cached reads) and start on the night the caller was looking at.
struct NunaSleepHost<Content: View>: View {
    let title: LocalizedStringKey
    let startIndex: Int
    @ViewBuilder let content: (NunaSleepModel) -> Content

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()

    var body: some View {
        NunaScreen(title) {
            if !model.loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else if model.night == nil {
                NunaCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No sleep data yet").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Wear your strap overnight and your first night will show up here.")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content(model)
            }
        }
        .task(id: repo.refreshSeq) {
            await model.load(repo: repo)
            if model.loaded, startIndex < model.nights.count, startIndex > 0, model.index == 0 { model.index = startIndex }
        }
    }
}

private func whole(_ v: Double?) -> String {
    v.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

// MARK: - Summary

struct NunaSleepView: View {
    var startIndex = 0
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var showCoach = false

    var body: some View {
        NunaSleepHost(title: "Sleep", startIndex: startIndex) { model in
            if let night = model.night {
                NunaNightPicker(model: model)
                hero(model, night)
                stagesCard(model, night)
                if !night.naps.isEmpty { napCard(night) }
                tiles(model, night)
                if let typ = model.typical() { usualCard(model, night, typ) }
                vitalsCard(night)
                needCard(model, night)
                if let d = night.daily?.disturbances, d > 0 {
                    NunaCard(small: true) {
                        NunaListRow("Woke up \(d) times", subtitle: "Brief awakenings during the night", systemImage: "moon.fill", tint: NunaPalette.restText)
                    }
                }
                bodyClockCard
                if coachEnabled { NunaAnyaCard(title: "How can I sleep better tonight?") { showCoach = true } }
            }
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "sleep") }
    }

    @EnvironmentObject private var appModel: AppModel

    /// Body clock: the lowest point and whether last night sat in the ideal window.
    @ViewBuilder private var bodyClockCard: some View {
        NavigationLink(value: NunaTodayRoute.bodyClock) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("timer", tint: NunaPalette.restText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body clock").font(.system(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        if let est = appModel.circadianPhase, est.confidence != .unreadable {
                            Text(verbatim: String(localized: "Lowest point \(NunaClockHour.text(est.tempMinHour))"))
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        } else {
                            Text("Still learning").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("Needs about a week of heart-rate data").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func hero(_ model: NunaSleepModel, _ night: NunaNight) -> some View {
        let rest = model.value("sleep_performance")
        let eff = model.efficiency(night)
        return NunaCard {
            HStack(spacing: 18) {
                NunaRingGauge(fraction: (rest ?? 0) / 100, color: NunaPalette.rest, size: 112, lineWidth: 10) {
                    VStack(spacing: 0) {
                        Text(verbatim: rest.map { "\(Int($0.rounded()))%" } ?? "–")
                            .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Rest").font(.system(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: NunaSleepFormat.duration(night.asleepMin))
                        .font(.system(size: NunaTypeSize.numberL - 6, weight: .bold, design: .rounded))
                        .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    Text(verbatim: "\(NunaSleepFormat.clock(night.onset)) – \(NunaSleepFormat.clock(night.wake))")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    HStack(spacing: 6) {
                        if let eff { NunaChip(verbatim: String(localized: "Efficiency \(Int(eff.rounded()))%"), color: NunaPalette.restText) }
                        if let nap = night.naps.first {
                            NavigationLink(value: NunaTodayRoute.sleepNaps(model.index)) {
                                NunaChip(verbatim: String(localized: "Nap \(Int(nap.asleepMin.rounded()))m"), systemImage: "plus")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func stagesCard(_ model: NunaSleepModel, _ night: NunaNight) -> some View {
        NavigationLink(value: NunaTodayRoute.sleepStages(model.index)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sleep stages").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    if night.intervals.isEmpty {
                        NunaStageSplitBar(stages: night.stages)
                    } else {
                        NunaHypnogramStrip(intervals: night.intervals)
                        NunaTimeAxis(start: night.onset, end: night.wake)
                    }
                    NunaStageLegend()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func napCard(_ night: NunaNight) -> some View {
        let nap = night.naps[0]
        return NavigationLink(value: NunaTodayRoute.sleepNaps(0)) {
            NunaCard(small: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nap").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: NunaSleepFormat.duration(nap.asleepMin))
                            .font(.system(size: NunaTypeSize.numberM, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: "\(NunaSleepFormat.clock(nap.start)) – \(NunaSleepFormat.clock(nap.end))")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    NunaChip("Detected automatically", color: NunaPalette.charge)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func tiles(_ model: NunaSleepModel, _ night: NunaNight) -> some View {
        let hvn = model.hoursVsNeeded(night)
        let eff = model.efficiency(night)
        let cons = model.consistency(night)
        let rest = model.restorative(night)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Performance", hvn, model)
            tile("Efficiency", eff, model)
            tile("Consistency", cons, model)
            tile("Restorative", rest, model)
        }
    }

    private func tile(_ label: LocalizedStringKey, _ value: Double?, _ model: NunaSleepModel) -> some View {
        NavigationLink(value: NunaTodayRoute.sleepPerformance(model.index)) {
            NunaStatTile(label: label, value: whole(value), unit: value == nil ? "" : "%", fraction: value.map { $0 / 100 })
        }
        .buttonStyle(.plain)
    }

    private func usualCard(_ model: NunaSleepModel, _ night: NunaNight, _ typ: Stages) -> some View {
        NavigationLink(value: NunaTodayRoute.sleepStages(model.index)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Compared to usual").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    stageRow(.deep, night.stages.deep, typ.deep, night.stages.total)
                    stageRow(.rem, night.stages.rem, typ.rem, night.stages.total)
                    stageRow(.light, night.stages.light, typ.light, night.stages.total)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stageRow(_ stage: SleepStage, _ minutes: Double, _ typical: Double, _ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stage.nunaName).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: "\(NunaSleepFormat.duration(minutes)) · \(total > 0 ? Int((minutes / total * 100).rounded()) : 0)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
            }
            NunaProgressBar(fraction: total > 0 ? minutes / total * 2 : 0, color: stage.nunaColor)
            Text(verbatim: String(localized: "Usually \(NunaSleepFormat.duration(typical))"))
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func vitalsCard(_ night: NunaNight) -> some View {
        NavigationLink(value: NunaTodayRoute.sleepVitals(0)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Overnight vitals").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    HStack {
                        mini("HRV", whole(night.daily?.avgHrv))
                        mini("Heart rate", whole(night.daily?.restingHr.map(Double.init)))
                        mini("SpO₂", night.daily?.spo2Pct.map { "\(Int($0.rounded()))%" } ?? "–")
                        mini("Breathing", night.daily?.respRateBpm.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func mini(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func needCard(_ model: NunaSleepModel, _ night: NunaNight) -> some View {
        let need: Double? = model.need(night)
        let debt = model.debtMin
        return NavigationLink(value: NunaTodayRoute.sleepPerformance(model.index)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Need and debt").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    HStack {
                        Text(verbatim: need.map { NunaSleepFormat.duration($0) } ?? "–")
                            .font(.system(size: NunaTypeSize.numberM, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Text("needed").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        if let debt, debt > 0 { NunaChip(verbatim: String(localized: "Debt \(Int(debt.rounded())) min"), color: NunaPalette.warning) }
                    }
                    if let need, need > 0 { NunaProgressBar(fraction: night.asleepMin / need) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stages

struct NunaSleepStagesView: View {
    var startIndex = 0
    var body: some View {
        NunaSleepHost(title: "Sleep stages", startIndex: startIndex) { model in
            if let night = model.night {
                NunaNightPicker(model: model)
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: NunaSleepFormat.duration(night.asleepMin))
                                .font(.system(size: NunaTypeSize.numberL, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Text("asleep").font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                        }
                        Text(verbatim: String(localized: "In bed \(NunaSleepFormat.duration(night.inBedMin))"))
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        if night.intervals.isEmpty {
                            NunaStageSplitBar(stages: night.stages)
                            Text("The order of stages is not available for this night. The split below comes from the daily totals.")
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        } else {
                            NunaHypnogramStrip(intervals: night.intervals, height: 140)
                            NunaTimeAxis(start: night.onset, end: night.wake)
                        }
                        NunaStageLegend()
                    }
                }
                let typ = model.typical()
                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        row(.deep, night.stages.deep, typ?.deep, night.stages.total)
                        NunaDivider()
                        row(.rem, night.stages.rem, typ?.rem, night.stages.total)
                        NunaDivider()
                        row(.light, night.stages.light, typ?.light, night.stages.total)
                        NunaDivider()
                        row(.awake, night.stages.awake, typ?.awake, night.stages.total)
                    }
                }
                Text("Stages are estimated from heart rate and movement. They are not a medical sleep study.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    private func row(_ stage: SleepStage, _ minutes: Double, _ typical: Double?, _ total: Double) -> some View {
        HStack(spacing: 12) {
            Circle().fill(stage.nunaColor).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.nunaName).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                if let typical {
                    Text(verbatim: String(localized: "Usually \(NunaSleepFormat.duration(typical))"))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: NunaSleepFormat.duration(minutes)).font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(total > 0 ? Int((minutes / total * 100).rounded()) : 0)%")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(minHeight: 62)
    }
}

// MARK: - Vitals

struct NunaSleepVitalsView: View {
    var startIndex = 0
    var body: some View {
        NunaSleepHost(title: "Overnight vitals", startIndex: startIndex) { model in
            if let night = model.night {
                NunaNightPicker(model: model)
                let others = model.nights.dropFirst(model.index + 1).prefix(14).compactMap(\.daily)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    vital("HRV", "hrv", night.daily?.avgHrv, others.compactMap(\.avgHrv), "ms", 0)
                    vital("Resting HR", "rhr", night.daily?.restingHr.map(Double.init), others.compactMap { $0.restingHr.map(Double.init) }, "bpm", 0)
                    vital("Blood Oxygen", "spo2", night.daily?.spo2Pct, others.compactMap(\.spo2Pct), "%", 0)
                    vital("Respiratory", "resp_rate", night.daily?.respRateBpm, others.compactMap(\.respRateBpm), "/min", 1)
                    vital("Skin Temp", "skin_temp", night.daily?.skinTempDevC, others.compactMap(\.skinTempDevC), "°C", 1)
                }
                Text("Compared with your average of the previous nights. Tap a vital to see its history.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    @ViewBuilder private func vital(_ label: LocalizedStringKey, _ key: String, _ value: Double?, _ prior: [Double],
                                    _ unit: String, _ decimals: Int) -> some View {
        let avg = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
        let tile = NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.system(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value.map { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                        .font(.system(size: NunaTypeSize.numberM, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: unit).font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                if let value, let avg {
                    let d = value - avg
                    Text(verbatim: (d >= 0 ? "+" : "−") + String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, abs(d)) + String(localized: " vs average"))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }
}

// MARK: - Performance, need and debt

struct NunaSleepPerformanceView: View {
    var startIndex = 0
    var body: some View {
        NunaSleepHost(title: "Sleep performance", startIndex: startIndex) { model in
            if let night = model.night {
                NunaNightPicker(model: model)
                let hvn = model.hoursVsNeeded(night)
                let need: Double? = model.need(night)
                let debt = model.debtMin
                NunaCard {
                    HStack(spacing: 18) {
                        NunaRingGauge(fraction: (hvn ?? 0) / 100, color: NunaPalette.rest, size: 112, lineWidth: 10) {
                            Text(verbatim: hvn.map { "\(Int($0.rounded()))%" } ?? "–")
                                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hours vs needed").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: "\(NunaSleepFormat.duration(night.asleepMin)) / \(need.map { NunaSleepFormat.duration($0) } ?? "–")")
                                .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            if let debt, debt > 0 { NunaChip(verbatim: String(localized: "Debt \(Int(debt.rounded())) min"), color: NunaPalette.warning) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                trend("Hours vs needed, last 14 nights", model.recent { model.hoursVsNeeded($0) }, NunaPalette.rest)
                trend("Consistency, last 14 nights", model.recent { model.consistency($0) }, NunaPalette.restText)
                trend("Efficiency, last 14 nights", model.recent { model.efficiency($0) }, NunaPalette.restLight)
            }
        }
    }

    @ViewBuilder private func trend(_ title: LocalizedStringKey, _ values: [Double?], _ color: Color) -> some View {
        if values.contains(where: { $0 != nil }) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    NunaBars(values: values, color: color, average: nil).frame(height: 110)
                }
            }
        }
    }
}

// MARK: - Naps

struct NunaNapView: View {
    var startIndex = 0
    var body: some View {
        NunaSleepHost(title: "Naps", startIndex: startIndex) { model in
            let recent = model.nights.prefix(14).flatMap { n in n.naps.map { (n, $0) } }
            NunaCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Naps are detected automatically").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("A nap is any sleep that is not your main night. Naps add to your daily sleep, they do not replace it.")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if recent.isEmpty {
                NunaCard(small: true) {
                    NunaListRow("No naps in the last 14 days", systemImage: "zzz", tint: NunaPalette.restText)
                }
            } else {
                NunaSectionHeader("Last 14 days")
                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { idx, pair in
                            if idx > 0 { NunaDivider() }
                            napRow(pair.0, pair.1)
                        }
                    }
                }
            }
        }
    }

    private func napRow(_ night: NunaNight, _ nap: NunaNap) -> some View {
        HStack(spacing: 12) {
            NunaIconTile("zzz", tint: NunaPalette.restText)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NunaSleepFormat.nightTitle(nap.start)).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(NunaSleepFormat.clock(nap.start)) – \(NunaSleepFormat.clock(nap.end))")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer()
            Text(verbatim: NunaSleepFormat.duration(nap.asleepMin)).font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(minHeight: 62)
    }
}
#endif
