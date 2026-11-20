#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Nuna "Kesehatan": a hub with Vital and Sleep tabs. Phase 2 of docs/nuna/IMPLEMENTATION_PLAN.md.
/// Display only. Values come from the same loader as Nuna Today; screens that already have a good
/// flow (Lab Book, Rhythm with its consent gate, Apple Health permissions, cycle, mood) open as before.
struct NunaHealthView: View {
    var initialTab = 0
    /// The vital signs page (opened from the monitor card on Today and from Me): the vital content on its own. Without it this is the
    /// sleep overview.
    var vitalsOnly = false

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var day = NunaTodayModel()
    @StateObject private var sleep = NunaSleepModel()
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var spo2S = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()
    @StateObject private var skinS = NunaSeriesModel()
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @State private var hrvRange = 30
    @State private var hrvPage = 0
    @State private var rhrRange = 30
    @State private var rhrPage = 0

    @State private var tab = 0
    @State private var didSetTab = false
    @State private var legacy: Legacy?
    @State private var showCoach = false
    @State private var showSleepCoach = false
    @State private var showReport = false

    private enum Legacy: String, Identifiable { case appleHealth, live, mood, cycle, breathing; var id: String { rawValue } }

    var body: some View {
        container
        .nunaTodayDestinations()
        .nunaWorkoutDestinations()
        .task(id: repo.refreshSeq) {
            if vitalsOnly {
                await day.load(repo: repo, profile: profile)
                await hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
                await rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
                await spo2S.load(repo: repo, key: "spo2", source: "my-whoop")
                await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
                await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop")
            } else {
                await sleep.load(repo: repo)
            }
        }
        .sheet(item: $legacy) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .appleHealth: AppleHealthView()
                    case .live: LiveView()
                    case .breathing: NunaBreathView().toolbar(.hidden, for: .navigationBar)
                    case .mood: ScrollView { MindSection().padding() }
                    case .cycle:
                        NunaWithApp { appModel in
                            if let cycle = appModel.cyclePhase { CycleTrackerView(result: cycle, curve: appModel.cycleCurve) }
                        }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { legacy = nil } } }
            }
            .environmentObject(repo)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "health") }
        .sheet(isPresented: $showSleepCoach) { NunaAnyaSheet(context: "sleep") }
        .sheet(isPresented: $showReport) { NunaHealthReportSheet().nunaSheetChrome(detents: [.medium, .large]) }
    }

    @ViewBuilder private var container: some View {
        if vitalsOnly {
            NunaDetailScreen("Health monitor", centersTitle: true) { vitalTab }
        } else {
            // The sleep overview: the last seven nights, need against actual, bedtime and stages. A page of its own now that Health
            // is no longer a tab.
            NunaDetailScreen("Sleep") { sleepTab }
        }
    }

    // MARK: Tabs
    // MARK: Vital

    private var vitalTab: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaLiveHRCard(monitor: true)
            rangeBanner
            vitalBento
            shareReport
        }
    }

    /// "Share your health report": the 30 and 180 day report as a PDF, with a line on who it is for.
    private var shareReport: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showReport = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 24, weight: .light)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
                    Text("Share your health report").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(height: 62).frame(maxWidth: .infinity)
                .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text("Printable report for sharing with your doctor, physical trainer, or anyone of your choosing.")
                .font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    /// Resting heart rate in the same one-card layout as every metric detail: the reading, the W / M / 6M switch and date stepper, and the chart.
    private var rhrHero: some View {
        let d = day.restingHrDelta
        return NunaTrendDetailCard(
            caption: "Resting HR", valueText: fmt(day.restingHr), unit: "bpm",
            chip: d.flatMap { abs($0.rounded()) >= 1 ? (text: LocalizedStringKey((($0 > 0 ? "+" : "−") + "\(Int(abs($0).rounded()))") + " " + String(localized: "vs yesterday")), color: $0 < 0 ? NunaPalette.charge : NunaPalette.warning) : nil },
            series: rhrS, lineColor: NunaPalette.charge, decimals: 0, higherIsBetter: false, range: $rhrRange, page: $rhrPage)
    }

    private func metricRoute(_ key: String) -> NunaTodayRoute {
        MetricCatalog.metric(key: key, source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private func linked(_ key: String, _ tile: some View) -> some View {
        NavigationLink(value: metricRoute(key)) { tile }.buttonStyle(.plain)
    }

    /// Nights with a sleep reading, which the range and its stages go by.
    private var rangePhase: VitalRange.Phase { VitalRange.phase(nights: max(hrvS.nights, rhrS.nights)) }

    /// The purple band over the tiles while the range is still being built: calibrating (no range yet, seven nights), then learning (a range
    /// that is still wide, fourteen nights). Gone once the range is final.
    @ViewBuilder private var rangeBanner: some View {
        switch rangePhase {
        case .calibrating(let n):
            let left = VitalRange.calibrationNights - n
            NunaCalibrationBanner(message: left == 1 ? "Wear your strap to sleep for 1 more night to calibrate."
                                  : "Wear your strap to sleep for \(left) more nights to calibrate.",
                                  nights: n, needed: VitalRange.calibrationNights)
        case .learning(let n):
            let left = VitalRange.trustedNights - n
            NunaCalibrationBanner(message: left == 1 ? "Your range is still sharpening: 1 more night to finish it."
                                  : "Your range is still sharpening: \(left) more nights to finish it.",
                                  nights: n, needed: VitalRange.trustedNights)
        case .trusted:
            EmptyView()
        }
    }

    /// Respiratory, blood oxygen, resting heart rate, HRV and skin temperature, each with a pill that says where it sits against the wearer's own
    /// range. Each opens its own chart. While the range is calibrating the readings show with a grey "Calibrating range" and no verdict.
    private var vitalBento: some View {
        let hasRange = rangePhase.hasRange
        typealias Chip = (text: String, color: Color, symbol: String?)
        let calibrating: Chip = (String(localized: "Calibrating range"), NunaPalette.textSecondary, nil)
        let ok = NunaPalette.charge, warn = NunaPalette.warning

        /// "within 60 - 62", "elevated > 80" or "low < 15.0" for a reading against a series' typical range. Above is only a warning when
        /// `aboveIsGood` is false, below only when `belowIsGood` is false.
        func ranged(_ v: Double?, _ series: NunaSeriesModel, decimals: Int, floor: Double, aboveIsGood: Bool = false, belowIsGood: Bool = false) -> Chip? {
            guard hasRange else { return calibrating }
            guard let v, let verdict = series.verdict(v, floor: floor), let r = series.typicalRange else { return nil }
            func f(_ x: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, x) }
            switch verdict {
            case .inRange: return (String(localized: "within \(f(r.lowerBound)) - \(f(r.upperBound))"), ok, "checkmark")
            case .above: return (String(localized: "elevated > \(f(r.upperBound))"), aboveIsGood ? ok : warn, aboveIsGood ? "checkmark" : "exclamationmark")
            case .below: return (String(localized: "low < \(f(r.lowerBound))"), belowIsGood ? ok : warn, belowIsGood ? "checkmark" : "exclamationmark")
            }
        }
        let respChip = ranged(day.respiratory, respS, decimals: 1, floor: VitalRange.respiratoryFloor, aboveIsGood: false, belowIsGood: true)
        let hrvChip = ranged(day.hrv, hrvS, decimals: 0, floor: 1, aboveIsGood: true, belowIsGood: false)
        // A resting heart rate below the usual is good news, so only a rise is marked.
        let rhrChip = ranged(day.restingHr, rhrS, decimals: 0, floor: 1, aboveIsGood: false, belowIsGood: true)
        let spo2 = day.spo2
        let spo2Chip: Chip? = hasRange ? spo2.map { $0 >= 95 ? (String(localized: "within 95% - 100%"), ok, "checkmark") : (String(localized: "low < 95%"), warn, "exclamationmark") } : calibrating
        let skin = day.extras["skin_temp"]
        let skinChip: Chip? = hasRange ? skin.flatMap { v -> Chip? in
            guard let verdict = skinS.skinVerdict(v), let r = skinS.skinRange else { return nil }
            func fs(_ x: Double) -> String { String(format: "%+.1f", locale: AppLanguage.activeLocale, x) }
            switch verdict {
            case .inRange: return (String(localized: "within \(fs(r.lowerBound)) to \(fs(r.upperBound))"), ok, "checkmark")
            case .above: return (String(localized: "elevated > \(fs(r.upperBound))"), warn, "exclamationmark")
            case .below: return (String(localized: "low < \(fs(r.lowerBound))"), warn, "exclamationmark")
            }
        } : calibrating
        // Only the rise or fall from the usual level, never the temperature itself.
        let skinText = skin.flatMap { skinS.skinDeviation($0) }.map { (($0 >= 0 ? "+" : "−") + String(format: "%.1f", locale: AppLanguage.activeLocale, abs($0))) } ?? "–"
        func tile(_ key: String, icon: String, label: LocalizedStringKey, value: String, unit: String, _ chip: Chip?) -> some View {
            linked(key, NunaVitalTile(icon: icon, label: label, value: value, unit: unit, chip: chip?.text, chipColor: chip?.color ?? ok, symbol: chip?.symbol))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("resp_rate", icon: "met:respiratory-rate", label: "Respiratory rate", value: fmt(day.respiratory, 1), unit: "rpm", respChip)
            tile("spo2", icon: "vital:spo2", label: "Blood oxygen (SpO₂)", value: fmt(spo2), unit: "%", spo2Chip)
            tile("rhr", icon: "met:resting-heart-rate", label: "RHR", value: fmt(day.restingHr), unit: "bpm", rhrChip)
            tile("hrv", icon: "met:heart-rate-variability", label: "HRV", value: fmt(day.hrv), unit: "ms", hrvChip)
            tile("skin_temp", icon: "vital:temp", label: "Skin temp (from baseline)", value: skinText, unit: "°C", skinChip)
        }
    }

    private var skinCaption: LocalizedStringKey? {
        guard let v = day.extras["skin_temp"] else { return nil }
        return skinS.skinVerdict(v) == .inRange ? "Small deviation" : "Larger deviation"
    }

    private var hrvHero: some View {
        let b = hrvS.band
        var chip: (text: LocalizedStringKey, color: Color)?
        if let v = day.hrv, let b {
            let inRange = abs(v - b.mean) <= max(b.sd, 1)
            chip = (text: inRange ? "In range" : (v > b.mean ? "Above range" : "Below range"), color: inRange ? NunaPalette.charge : NunaPalette.warning)
        }
        return NunaTrendDetailCard(
            caption: "HRV", valueText: fmt(day.hrv), unit: "ms", chip: chip,
            note: day.hrvDelta.flatMap { abs($0.rounded()) >= 1 ? (($0 > 0 ? "+" : "−") + "\(Int(abs($0).rounded()))" + " " + String(localized: "vs yesterday")) : nil },
            series: hrvS, lineColor: NunaPalette.charge, decimals: 0, range: $hrvRange, page: $hrvPage)
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private var stressCard: some View {
        let score = day.stress
        let level: (LocalizedStringKey, Color)? = score.map { $0 < 1 ? ("Low", NunaPalette.charge) : ($0 < 2 ? ("Medium", NunaPalette.warning) : ("High", NunaPalette.alert)) }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: stressRoute) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            cardTitle("Stress monitor")
                            Spacer()
                            if let level { NunaChip(level.0, color: level.1) }
                        }
                        NunaHalfGauge(value: score, maxValue: 3, color: level?.1 ?? NunaPalette.textSecondary)
                            .frame(height: 112)
                            .overlay(alignment: .bottom) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(verbatim: fmt(score, 1)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: "/ 3").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                            }
                        Text("Calculated from heart rate and HRV through the day, against your own baseline.")
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    Button { legacy = .breathing } label: {
                        HStack(spacing: 8) {
                            NunaActivityGlyph(name: "Breathwork", size: 20)
                            Text("Breathe 5 min").font(.nuna(size: 15, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                    NavigationLink(value: NunaTodayRoute.mood) {
                        Image(systemName: "face.smiling").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Mood check-in"))
                }
            }
        }
    }

    private var liveCard: some View { NunaLiveHRCard() }

    // MARK: Sleep

    private var sleepTab: some View {
        let recent = Array(sleep.nights.prefix(7).reversed())
        return VStack(spacing: NunaSpacing.section) {
            if recent.isEmpty {
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard { NunaListRow("Sleep", description: "No night recorded yet", systemImage: "moon.zzz.fill", showsChevron: true) }
                }.buttonStyle(.plain)
            } else {
                weekCard(recent)
                sleepRead(recent)
                needCard(recent)
                bedtimeCard(recent)
                stagesAverageCard(recent)
                napsWeekCard(recent)
                NunaSleepAlarmRows()
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard(small: true) { NunaListRow("See last night in detail", systemImage: "moon.zzz.fill", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }

    private func weekCard(_ nights: [NunaNight]) -> some View {
        let rest = nights.compactMap { sleep.value("sleep_performance", $0) }
        let avgRest = rest.isEmpty ? nil : rest.reduce(0, +) / Double(rest.count)
        let avgSleep = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let effs = nights.compactMap { sleep.efficiency($0) }
        let avgEff = effs.isEmpty ? nil : effs.reduce(0, +) / Double(effs.count)
        let wakes = nights.compactMap { $0.daily?.disturbances }.map(Double.init)
        let avgWakes = wakes.isEmpty ? nil : wakes.reduce(0, +) / Double(wakes.count)
        let top = max(nights.map(\.asleepMin).max() ?? 1, 1)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Last 7 nights").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let avgRest { NunaChip(verbatim: String(localized: "Average Sleep \(Int(avgRest.rounded()))%"), color: NunaPalette.restText) }
                }
                NunaColumns(items: nights.map { n in
                    NunaColumns.Item(weekday: weekday(n.wakeDate), date: n.wakeDate, fraction: n.asleepMin / top,
                                     valueText: NunaSleepFormat.duration(n.asleepMin), highlight: n.id == nights.last?.id)
                }, color: NunaPalette.rest, highlightColor: NunaPalette.restText)
                HStack(spacing: 0) {
                    miniStat("Duration", NunaSleepFormat.duration(avgSleep))
                    miniStat("Efficiency", avgEff.map { "\(Int($0.rounded()))%" } ?? "–")
                    miniStat("Wake-ups", avgWakes.map { String(format: "%.1f×", locale: AppLanguage.activeLocale, $0) } ?? "–")
                }
                .padding(.top, 4)
            }
        }
    }

    /// Anya's read of the last seven nights: how long and how well you slept on average, against what you need.
    @ViewBuilder private func sleepRead(_ nights: [NunaNight]) -> some View {
        if coachEnabled, !nights.isEmpty {
            let avg = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
            let need = nights.last.map { sleep.need($0) }
            let rest = nights.compactMap { sleep.value("sleep_performance", $0) }
            let line: String = {
                let dur = NunaSleepFormat.duration(avg)
                guard let need, need > 0 else { return String(localized: "You slept \(dur) a night over the last \(nights.count) nights.") }
                let gap = Int((avg - need).rounded())
                if abs(gap) < 10 { return String(localized: "You slept \(dur) a night over the last \(nights.count) nights, close to what you need.") }
                let diff = NunaSleepFormat.duration(abs(Double(gap)))
                return gap < 0 ? String(localized: "You slept \(dur) a night over the last \(nights.count) nights, \(diff) short of what you need.")
                               : String(localized: "You slept \(dur) a night over the last \(nights.count) nights, \(diff) more than you need.")
            }()
            let detail: String? = rest.isEmpty ? nil : String(localized: "Average Sleep \(Int((rest.reduce(0, +) / Double(rest.count)).rounded()))%")
            // The step that goes with the reading: to close the gap when the nights are short, to keep the routine when they are not.
            let step = NunaAnyaVerdict.sleep(averageMin: avg, needMin: need)?.advice
            NunaAnyaCard(verbatim: line, detail: [detail, step].compactMap { $0 }.joined(separator: " ")) { showSleepCoach = true }
        }
    }

    private func needCard(_ nights: [NunaNight]) -> some View {
        let avg = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let need = nights.last.map { sleep.need($0) } ?? 480
        let debt = max(0, need - avg)
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Need vs actual").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if debt >= 1 { NunaChip(verbatim: String(localized: "Sleep debt \(Int(debt.rounded())) min"), color: NunaPalette.warning) }
                }
                HStack(spacing: 0) {
                    miniStat("Need", NunaSleepFormat.duration(need)); miniStat("Average", NunaSleepFormat.duration(avg))
                }
                NunaProgressBar(fraction: avg / max(need, 1), color: NunaPalette.rest)
            }
        }
    }

    /// Bedtime to wake time for each of the 7 nights as a bar on one shared clock, and how far bedtimes spread.
    private func bedtimeCard(_ nights: [NunaNight]) -> some View {
        let cal = Calendar.current
        func hour(_ d: Date, evening: Bool) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            return evening && h < 12 ? h + 24 : (evening ? h : h + 24)
        }
        let starts = nights.map { hour($0.onset, evening: true) }
        let ends = nights.map { n -> Double in
            let h = hour(n.wake, evening: false)
            return h < 24 ? h + 24 : h
        }
        let mean = starts.reduce(0, +) / Double(max(starts.count, 1))
        let sd = (starts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(starts.count, 1))).squareRoot()
        // One shared clock: whole hours around the earliest bedtime and latest wake, five evenly spaced ticks.
        let lo = floor((starts.min() ?? 21) - 0.25), hi = ceil((ends.max() ?? 32) + 0.25)
        let span = max(hi - lo, 1)
        let ticks = (0...4).map { lo + span * Double($0) / 4 }
        func tickLabel(_ h: Double) -> String {
            let half = (h * 2).rounded() / 2
            let hh = Int(half) % 24, mm = half.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 30
            return String(format: "%02d:%02d", hh, mm)
        }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Bedtime consistency")
                    Spacer()
                    NunaChip(verbatim: String(localized: "Spread \(Int((sd * 60).rounded())) min"), color: NunaPalette.restText)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ForEach(nights.indices, id: \.self) { i in
                            Text(verbatim: weekday(nights[i].wakeDate)).font(.nuna(size: 12, weight: .semibold))
                                .foregroundStyle(NunaPalette.textSecondary).frame(width: 30, height: 34, alignment: .leading).textCase(nil)
                        }
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .topLeading) {
                            ForEach(1..<4, id: \.self) { t in
                                Rectangle().fill(NunaPalette.hairlineSoft).frame(width: 1, height: geo.size.height)
                                    .offset(x: w * CGFloat(t) / 4)
                            }
                            ForEach(nights.indices, id: \.self) { i in
                                let x0 = w * CGFloat((starts[i] - lo) / span)
                                let x1 = w * CGFloat((min(ends[i], hi) - lo) / span)
                                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.glass).frame(width: w, height: 16).offset(y: CGFloat(i) * 34 + 9)
                                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.rest).frame(width: max(8, x1 - x0), height: 16)
                                    .offset(x: x0, y: CGFloat(i) * 34 + 9)
                            }
                        }
                    }
                    .frame(height: CGFloat(nights.count) * 34)
                }
                HStack(spacing: 10) {
                    Color.clear.frame(width: 30, height: 1)
                    GeometryReader { geo in
                        ForEach(0..<ticks.count, id: \.self) { t in
                            let label = tickLabel(ticks[t])
                            Text(verbatim: label).font(.nuna(size: 11, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(NunaPalette.textSecondary).fixedSize()
                                .position(x: min(max(geo.size.width * CGFloat(t) / 4, 18), geo.size.width - 18), y: 8)
                        }
                    }
                    .frame(height: 16)
                }
            }
        }
    }

    private func stagesAverageCard(_ nights: [NunaNight]) -> some View {
        let n = Double(nights.count)
        let avg = Stages(awake: nights.map { $0.stages.awake }.reduce(0, +) / n, light: nights.map { $0.stages.light }.reduce(0, +) / n,
                         deep: nights.map { $0.stages.deep }.reduce(0, +) / n, rem: nights.map { $0.stages.rem }.reduce(0, +) / n)
        let typ = sleep.typical()
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Average stages").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("Marker = your usual").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                stageLine(.deep, avg.deep, typ?.deep, avg.total)
                stageLine(.rem, avg.rem, typ?.rem, avg.total)
                stageLine(.light, avg.light, typ?.light, avg.total)
            }
        }
    }

    private func napTitle(_ nap: NunaNap) -> String { weekday(nap.start) + " " + NunaSleepFormat.clock(nap.start) }

    private func stageLine(_ stage: SleepStage, _ minutes: Double, _ typical: Double?, _ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stage.nunaName).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: NunaSleepFormat.duration(minutes)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            NunaRangeBar(value: minutes, lo: 0, hi: max(total / 2, 1), mean: typical, color: stage.nunaColor, showsMarkerDot: false)
        }
    }

    private func napsWeekCard(_ nights: [NunaNight]) -> some View {
        let napItems: [(night: NunaNight, nap: NunaNap)] = nights.flatMap { n in n.naps.map { (n, $0) } }
        let naps = napItems.map(\.nap)
        return NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Naps").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(verbatim: String(localized: "This week · \(naps.count)")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .padding(.bottom, 6)
                if naps.isEmpty {
                    Text("No naps this week").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.vertical, 12)
                }
                ForEach(Array(napItems.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { NunaDivider() }
                    NavigationLink(value: NunaTodayRoute.nap(item.night.dayKey, Int(item.nap.start.timeIntervalSince1970))) {
                        NunaListRow(LocalizedStringKey(napTitle(item.nap)), subtitle: LocalizedStringKey(NunaSleepFormat.duration(item.nap.asleepMin)), systemImage: NunaIcons.nap, showsChevron: true) {
                            NunaChip(item.nap.manual ? "Manual" : "Auto")
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Pieces

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    @ViewBuilder private func tile(_ label: LocalizedStringKey, _ key: String, _ value: String, _ unit: String,
                                   source: String = "my-whoop", caption: LocalizedStringKey? = nil) -> some View {
        let t = NunaStatTile(label: label, value: value, unit: value == "–" ? "" : unit, caption: caption)
        if let m = MetricCatalog.metric(key: key, source: source) {
            NavigationLink(value: NunaTodayRoute.metric(m)) { t }.buttonStyle(.plain)
        } else { t }
    }

    private func link(_ route: NunaTodayRoute, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: route) { NunaListRow(title, description: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String,
                     _ tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { NunaListRow(title, description: subtitle, systemImage: icon, tint: tint, showsChevron: true) }
            .buttonStyle(.plain)
    }

    private func fmt(_ v: Double?, _ digits: Int = 0) -> String {
        v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
    }
}
#endif
