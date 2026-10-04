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
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "sleep") }
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
                        if night.motion.count >= 10 {
                            NunaMotionStrip(epochs: night.motion, total: night.wake.timeIntervalSince(night.onset))
                        }
                        NunaTimeAxis(start: night.onset, end: night.wake)
                    }
                    NunaStageLegend(showsMovement: night.motion.count >= 10 && !night.intervals.isEmpty)
                    if !night.intervals.isEmpty { NunaMovementStats(night: night) }
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
                    NunaChip(nap.manual ? "Added by you" : "Detected automatically", color: nap.manual ? nil : NunaPalette.charge)
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
                            if night.motion.count >= 10 {
                                NunaMotionStrip(epochs: night.motion, total: night.wake.timeIntervalSince(night.onset), height: 40)
                            }
                            NunaTimeAxis(start: night.onset, end: night.wake)
                        }
                        NunaStageLegend(showsMovement: night.motion.count >= 10 && !night.intervals.isEmpty)
                        if !night.intervals.isEmpty { NunaMovementStats(night: night) }
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
                Text("Stages are estimated from heart rate and movement. Movement counts are relative to this strap and are not a medical sleep study.")
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
                trend("Hours vs needed, last 14 nights", model.recentPoints { model.hoursVsNeeded($0) })
                trend("Consistency, last 14 nights", model.recentPoints { model.consistency($0) })
                trend("Efficiency, last 14 nights", model.recentPoints { model.efficiency($0) })
            }
        }
    }

    @ViewBuilder private func trend(_ title: LocalizedStringKey, _ points: [(date: Date, value: Double)]) -> some View {
        if !points.isEmpty {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    NunaLine2Chart(points: points, color: .white, decimals: 0, height: 170)
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
            NunaNapContent(model: model)
        }
    }
}

private struct NunaNapContent: View {
    @ObservedObject var model: NunaSleepModel
    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var showAdd = false
    @State private var showCoach = false

    private var night: NunaNight? { model.night }
    private var naps: [NunaNap] { night?.naps ?? [] }
    private var isToday: Bool { night.map { Calendar.current.isDateInToday($0.wakeDate) } ?? false }

    var body: some View {
        Group { content }
            .sheet(isPresented: $showAdd) { NunaAddNapSheet(day: night?.wakeDate ?? Date()) { await repo.refresh(); await model.load(repo: repo) } }
            .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "nap") }
    }

    @ViewBuilder private var content: some View {
        if let night {
            NunaNightPicker(model: model, caption: isToday ? "Today" : "Earlier day", date: night.wakeDate)
            if let nap = naps.first {
                hero(nap, count: naps.count)
                tiles(nap)
                impact(night)
                if coachEnabled { NunaAnyaCard(title: "A nap under 30 minutes is safest for your night's sleep", highlight: false) { showCoach = true } }
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No nap this day").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("A nap is any sleep that is not your main night. It is detected automatically when you rest without moving for a while.")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button { showAdd = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                    Text("Add a nap by hand").font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(NunaPalette.charge)
                .frame(maxWidth: .infinity, minHeight: 60)
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
            history
        }
    }

    private func hero(_ nap: NunaNap, count: Int) -> some View {
        let total = max(nap.end.timeIntervalSince(nap.start), 1)
        return NunaCard(padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(count > 1 ? "First nap" : "Nap").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(nap.manual ? "Added by you" : "Detected automatically", color: nap.manual ? nil : NunaPalette.charge)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(Int(nap.asleepMin.rounded()))").font(.system(size: 60, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    Text("min").font(.system(size: 22, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Text(verbatim: "\(NunaSleepFormat.clock(nap.start)) – \(NunaSleepFormat.clock(nap.end))")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                if !nap.intervals.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(["Awake", "REM", "Light", "Deep"], id: \.self) { l in
                                Text(LocalizedStringKey(l)).font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: 48, height: 110, alignment: .leading)
                        VStack(spacing: 6) {
                            NunaHypnogramStrip(intervals: nap.intervals, height: 110)
                            if nap.motion.count >= 4 { NunaMotionStrip(epochs: nap.motion, total: total, height: 30) }
                        }
                    }
                    .padding(.top, 8)
                    HStack {
                        Spacer().frame(width: 58)
                        Text(verbatim: NunaSleepFormat.clock(nap.start)); Spacer()
                        Text(verbatim: NunaSleepFormat.clock(nap.start.addingTimeInterval(total / 2))); Spacer()
                        Text(verbatim: NunaSleepFormat.clock(nap.end))
                    }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    NunaStageLegend(showsMovement: nap.motion.count >= 4)
                } else {
                    Text("The order of stages is not available for this nap.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func tiles(_ nap: NunaNap) -> some View {
        let moves = NunaMovementSummary(nap.motion, hours: max(nap.spanMin / 60, 0.05))?.movements
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NunaStatTile(label: "Light", value: "\(Int(nap.minutes(.light).rounded()))", unit: "min")
            NunaStatTile(label: "Deep", value: "\(Int(nap.minutes(.deep).rounded()))", unit: "min")
            NunaStatTile(label: "REM", value: "\(Int(nap.minutes(.rem).rounded()))", unit: "min")
            NunaStatTile(label: "Movement", value: moves.map(String.init) ?? "–", unit: moves == nil ? "" : "×")
        }
    }

    private func impact(_ night: NunaNight) -> some View {
        let napMin = naps.reduce(0) { $0 + $1.asleepMin }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Effect on tonight").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                line("Total sleep this day", NunaSleepFormat.duration(night.asleepMin + napMin))
                line("Counted toward your need", "+" + NunaSleepFormat.duration(napMin))
                line("Tonight's need", NunaSleepFormat.duration(model.need(night)))
                Text("A nap counts toward your sleep need but does not change last night's Rest score.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private func line(_ l: LocalizedStringKey, _ v: String) -> some View {
        HStack {
            Text(l).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: v).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private var history: some View {
        let recent = model.nights.prefix(14).flatMap { n in n.naps.map { (n, $0) } }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Nap history") { EmptyView() }
            if recent.isEmpty {
                NunaCard(small: true) { NunaListRow("No naps in the last 14 days", systemImage: "zzz", tint: NunaPalette.restText) }
            } else {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { idx, pair in
                            if idx > 0 { NunaDivider() }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: weekday(pair.1.start)).font(.system(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: "\(NunaSleepFormat.clock(pair.1.start)) – \(NunaSleepFormat.clock(pair.1.end))")
                                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                                Spacer()
                                Text(verbatim: "\(Int(pair.1.asleepMin.rounded()))m").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                                NunaChip(pair.1.manual ? "Manual" : "Auto", color: pair.1.manual ? nil : NunaPalette.charge)
                            }
                            .frame(minHeight: 56)
                        }
                    }
                }
            }
        }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: d)
    }
}

/// Add a nap by hand: pick the day and the start and end. Staged from the strap's raw data when there is any.
private struct NunaAddNapSheet: View {
    let day: Date
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a nap").font(.system(size: NunaTypeSize.h2, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    DatePicker("Start", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).tint(NunaPalette.charge)
                        .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 52)
                    NunaDivider()
                    DatePicker("End", selection: $end, in: start...Date(), displayedComponents: [.date, .hourAndMinute]).tint(NunaPalette.charge)
                        .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 52)
                }
            }
            Text("The nap is staged from your strap's heart rate and movement when it has data for that time.")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            Button {
                Task {
                    await repo.addManualNap(startTs: Int(start.timeIntervalSince1970), endTs: Int(end.timeIntervalSince1970))
                    await onSaved(); dismiss()
                }
            } label: { Text("Save nap") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
                .disabled(end.timeIntervalSince(start) < 5 * 60)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .nunaSheetChrome(detents: [.medium])
        .onAppear {
            let cal = Calendar.current
            let base = cal.isDateInToday(day) ? Date() : (cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day)
            end = min(base, Date()); start = end.addingTimeInterval(-30 * 60)
        }
    }
}

#endif
