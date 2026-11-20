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
    /// How many nights back the screen may go (nil: everything loaded).
    var maxNights: Int?
    @ViewBuilder let content: (NunaSleepModel) -> Content

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()
    @AppStorage(NunaNapPrefs.autoDetectKey) private var autoNaps = true

    var body: some View {
        NunaScreen(title) {
            if !model.loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else if model.night == nil {
                NunaCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No sleep data yet").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Wear your strap overnight and your first night will show up here.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content(model)
            }
        }
        .task(id: "\(repo.refreshSeq)-\(autoNaps)") {
            model.maxNights = maxNights
            await model.load(repo: repo)
            if model.loaded, startIndex < model.nights.count, startIndex > 0, model.index == 0 { model.index = startIndex }
        }
    }
}

private func whole(_ v: Double?) -> String {
    v.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

/// Everything the night had, from the stages to the body clock: the sleep stages card (with the pencil that edits the sleep times and an
/// undo for a deleted night), the comparison with other nights, naps, the overnight vitals, the sleep need and debt and the body
/// clock. Shared by the Rest screen (which is also the Sleep screen) and the pushed sleep sub-screens, so they show the same night the same way.
struct NunaSleepNightSections: View {
    let model: NunaSleepModel
    let night: NunaNight
    /// The four percentage tiles (performance, efficiency, consistency, restorative); the Rest screen already lists them as rows.
    var showsTiles = false
    /// The Need and debt card; the Rest screen draws a fuller one of its own.
    var showsNeed = true
    /// The Body clock card; the Rest screen draws it itself, after its weekly trends.
    var showsBodyClock = true
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @State private var edit: NunaSleepEditTarget?
    @State private var undo: SleepDeletionSnapshot?

    var body: some View {
        // One container: a modifier on a Group is applied to every child of it, which drew the "Sleep deleted" toast (and the editor sheet) once per card.
        VStack(spacing: NunaSpacing.section) {
            NunaSleepStageSection(model: model, night: night,
                                  onEdit: night.editTarget.map { block in { edit = NunaSleepEditTarget(block, isNap: false) } })
            if !night.naps.isEmpty { napCard(night) }
            if showsTiles { tiles(model, night) }
            if showsNeed { needCard(model, night) }
            if showsBodyClock { NunaBodyClockLink() }
        }
        .sheet(item: $edit) { NunaSleepTimeSheet(target: $0) { snap in await repo.refresh(); if let snap { undo = snap } } }
        .nunaSleepUndo($undo) { await repo.refresh() }
    }

    private func napCard(_ night: NunaNight) -> some View {
        let nap = night.naps[0]
        return NavigationLink(value: NunaTodayRoute.sleepNaps(0)) {
            NunaCard(small: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nap").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: NunaSleepFormat.duration(nap.asleepMin))
                            .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: "\(NunaSleepFormat.clock(nap.start)) – \(NunaSleepFormat.clock(nap.end))")
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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

    private func needCard(_ model: NunaSleepModel, _ night: NunaNight) -> some View {
        let need: Double? = model.need(night)
        let debt = model.debtMin
        return NavigationLink(value: NunaTodayRoute.sleepPerformance(model.index)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Need and debt").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    HStack {
                        Text(verbatim: need.map { NunaSleepFormat.duration($0) } ?? "–")
                            .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("needed").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
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
                                .font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(NunaTypeSize.numberL)).foregroundStyle(NunaPalette.textPrimary)
                            Text("asleep").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                        }
                        Text(verbatim: String(localized: "In bed \(NunaSleepFormat.duration(night.inBedMin))"))
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        if night.intervals.isEmpty {
                            NunaStageSplitBar(stages: night.stages)
                            Text("The order of stages is not available for this night. The split below comes from the daily totals.")
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private func row(_ stage: SleepStage, _ minutes: Double, _ typical: Double?, _ total: Double) -> some View {
        HStack(spacing: 12) {
            Circle().fill(stage.nunaColor).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.nunaName).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                if let typical {
                    Text(verbatim: String(localized: "Usually \(NunaSleepFormat.duration(typical))"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: NunaSleepFormat.duration(minutes)).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(total > 0 ? Int((minutes / total * 100).rounded()) : 0)%")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .frame(minHeight: 62)
    }
}

// MARK: - Vitals

struct NunaSleepVitalsView: View {
    var startIndex = 0
    @EnvironmentObject private var repo: Repository
    var body: some View {
        NunaSleepHost(title: "Overnight vitals", startIndex: startIndex) { model in
            if let night = model.night {
                NunaNightPicker(model: model)
                let others = model.nights.dropFirst(model.index + 1).prefix(14).compactMap(\.daily)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    vital("HRV", "hrv", night.daily?.avgHrv, others.compactMap(\.avgHrv), "ms", 0)
                    vital("Resting HR", "rhr", night.daily?.restingHr.map(Double.init), others.compactMap { $0.restingHr.map(Double.init) }, "bpm", 0)
                    vital("Blood Oxygen", "spo2", repo.spo2(for: night.daily), others.compactMap { repo.spo2(for: $0) }, "%", 0)
                    vital("Respiratory", "resp_rate", night.daily?.respRateBpm, others.compactMap(\.respRateBpm), "/min", 1)
                    skinVital(night.daily?.skinTempDevC, others.compactMap(\.skinTempDevC))
                }
                Text("Compared with your average of the previous nights. Tap a vital to see its history.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    /// The night's skin temperature as the rise from the usual level. A deviation is shown as it is, against the average of the nights before; an
    /// absolute temperature (an import) becomes its rise over the median of those nights, and then has nothing left to be compared with.
    @ViewBuilder private func skinVital(_ value: Double?, _ prior: [Double]) -> some View {
        if let value, abs(value) >= 20 {
            let level = prior.filter { abs($0) >= 20 }
            if level.count >= 3, let m = Repository.median(level) {
                vital("Skin Temp", "skin_temp", value - m, [], "°C", 1)
            } else {
                vital("Skin Temp", "skin_temp", nil, [], "°C", 1)
            }
        } else {
            vital("Skin Temp", "skin_temp", value, prior.filter { abs($0) < 20 }, "°C", 1)
        }
    }

    @ViewBuilder private func vital(_ label: LocalizedStringKey, _ key: String, _ value: Double?, _ prior: [Double],
                                    _ unit: String, _ decimals: Int) -> some View {
        let avg = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
        let tile = NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value.map { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                        .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                if let value, let avg {
                    let d = value - avg
                    Text(verbatim: (d >= 0 ? "+" : "−") + String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, abs(d)) + String(localized: " vs average"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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

// MARK: - Naps

struct NunaNapView: View {
    var startIndex = 0
    /// Open on a given nap: the day it belongs to and when it started (unix seconds).
    var dayKey: String?
    var napStart: Int?
    @EnvironmentObject private var repo: Repository
    @StateObject private var model = NunaSleepModel()
    @AppStorage(NunaNapPrefs.autoDetectKey) private var autoNaps = true
    /// The nap in view when the day has more than one; the one asked for, else the first.
    @State private var selectedStart: Int?
    @State private var showAdd = false
    @State private var edit: NunaSleepEditTarget?
    @State private var undo: SleepDeletionSnapshot?

    private var night: NunaNight? { model.night }
    private var naps: [NunaNap] { night?.naps ?? [] }
    private var isToday: Bool { night.map { Calendar.current.isDateInToday($0.wakeDate) } ?? false }
    /// The nap on show: the one asked for, else the first of the day.
    private var current: NunaNap? { naps.first(where: { Int($0.start.timeIntervalSince1970) == selectedStart }) ?? naps.first }

    var body: some View {
        // The same page as the Sleep one: the header with the title in the middle and its button at the right, then the cards, one under the other.
        NunaDetailScreen("Naps", trailing: AnyView(addButton), centersTitle: true) {
            if !model.loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else if let night {
                NunaNightPicker(model: model, date: night.wakeDate, showsCaption: false, compact: true)
                if let nap = current {
                    stagesCard(nap)
                    impact(night)
                } else {
                    noNap
                }
            } else {
                noNap
            }
        }
        .task(id: "\(repo.refreshSeq)-\(autoNaps)") {
            await model.load(repo: repo)
            if model.loaded, startIndex < model.nights.count, startIndex > 0, model.index == 0 { model.index = startIndex }
            if let dayKey, let i = model.nights.firstIndex(where: { $0.dayKey == dayKey }) { model.index = i }
            if let napStart { selectedStart = napStart }
        }
        .sheet(isPresented: $showAdd) { NunaAddNapSheet(day: night?.wakeDate ?? Date()) { await repo.refresh(); await model.load(repo: repo) } }
        .sheet(item: $edit) { NunaSleepTimeSheet(target: $0) { snap in await model.load(repo: repo); if let snap { undo = snap } } }
        .nunaSleepUndo($undo) { await model.load(repo: repo) }
        // Her line is about the nap on show; there is no analysis to fetch for a page about one nap.
        .nunaAnyaFloating(context: "nap", line: anyaLine, analyses: false)
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Add a nap by hand"))
    }

    private var noNap: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No nap this day").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("A nap is any sleep that is not your main night. It is detected automatically when you rest without moving for a while.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { showAdd = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.nuna(size: 17, weight: .bold))
                    Text("Add a nap by hand").font(.nuna(size: 15, weight: .heavy))
                }
                .foregroundStyle(NunaPalette.charge)
                .frame(maxWidth: .infinity, minHeight: 60)
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous)
                    .strokeBorder(NunaPalette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        }
    }

    /// Anya's line about the nap: how long it was against the 30 minutes that leave the night alone.
    private var anyaLine: String? {
        guard let nap = current else { return nil }
        let length = NunaSleepFormat.duration(nap.asleepMin)
        return nap.asleepMin <= 30
            ? String(localized: "Your \(length) nap stays under 30 minutes, the length that is safest for tonight's sleep.")
            : String(localized: "Your \(length) nap is longer than 30 minutes, which can make it harder to fall asleep tonight. Keep the next one under 30 minutes.")
    }

    /// The nap shaped as a night, so it is drawn by the very same Sleep stages card, in the layout of the night: the title and the pencil above the card,
    /// the hours of sleep, the chart, the stages and the restorative sleep.
    private func stagesCard(_ nap: NunaNap) -> some View {
        let night = NunaNight(dayKey: "nap-\(Int(nap.start.timeIntervalSince1970))", wakeDate: nap.end, onset: nap.start, wake: nap.end,
                              stages: Stages(awake: nap.minutes(.awake), light: nap.minutes(.light), deep: nap.minutes(.deep), rem: nap.minutes(.rem)),
                              intervals: nap.intervals, naps: [], daily: nil, proportional: nap.intervals.isEmpty, motion: nap.motion)
        let count = naps.count
        let number = (naps.firstIndex(where: { $0.id == nap.id }) ?? 0) + 1
        return NunaSleepStageSection(model: model, night: night,
                                     onEdit: nap.block.map { block in { edit = NunaSleepEditTarget(block, isNap: true) } },
                                     title: count > 1 ? LocalizedStringKey("Nap \(number) of \(count)") : "Nap", compareWithNights: false,
                                     rangeText: "\(NunaSleepFormat.clock(nap.start)) – \(NunaSleepFormat.clock(nap.end))",
                                     badge: nap.manual ? "Added by you" : "Detected automatically", badgeColor: nap.manual ? nil : NunaPalette.charge,
                                     edited: nap.manual, referenceLayout: true)
    }

    /// The very card the Sleep page draws for hours against need, with the day's sleep: the night and what its naps add. The need is worked out the
    /// way the Sleep page does it, so the two pages never give two needs for the same day.
    private func impact(_ night: NunaNight) -> some View {
        let napMin = naps.reduce(0) { $0 + $1.asleepMin }
        let asleep = (night.daily?.totalSleepMin ?? night.asleepMin) + napMin
        let healthy = SleepModel.debtNeedMin(days: repo.days)
        let debts = SleepDebt.debtSeries(series: model.nights.reversed().map { ($0.dayKey, $0.daily?.totalSleepMin ?? $0.asleepMin) },
                                         needHours: healthy / 60)
        let ledgerDebt = max(debts.first(where: { $0.day == night.dayKey })?.value ?? 0, 0)
        let stored = model.hasStoredNeed(night)
        let total = stored ? max(model.need(night), healthy) : healthy + ledgerDebt
        let debt = stored ? min(ledgerDebt, total - healthy) : ledgerDebt
        let strain = max(total - healthy - debt, 0)
        return NunaHoursVsNeededCard(asleepMin: asleep, healthyMin: healthy, strainMin: strain, debtMin: debt,
                                     percent: total > 0 ? min(asleep / total * 100, 100) : nil, usual: model.usual { model.hoursVsNeeded($0) })
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
            Text("Add a nap").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
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
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.medium])
        .onAppear {
            let cal = Calendar.current
            let base = cal.isDateInToday(day) ? Date() : (cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day)
            end = min(base, Date()); start = end.addingTimeInterval(-30 * 60)
        }
    }
}


/// Body clock: the lowest point and whether last night sat in the ideal window.
struct NunaBodyClockLink: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationLink(value: NunaTodayRoute.bodyClock) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("timer", tint: NunaPalette.restText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body clock").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        if let est = appModel.circadianPhase, est.confidence != .unreadable {
                            Text(verbatim: String(localized: "Lowest point \(NunaClockHour.text(est.tempMinHour))"))
                                .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        } else {
                            Text("Still learning").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("Needs about a week of heart-rate data").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
