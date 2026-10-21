#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

private func nunaCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

private func nbFmt(_ v: Double?, _ digits: Int = 0) -> String {
    v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

/// Source id for values typed in by hand. Imports and Apple Health keep their own ids, so neither can overwrite these.
let nunaManualSource = "noop-manual"

/// A big number with minus and plus buttons, for adding a measurement or setting a target.
struct NunaNumberSheet: View {
    let title: LocalizedStringKey
    let unit: String
    let initial: Double
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Text(title).font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, value))
                    .font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: unit).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            HStack(spacing: 16) {
                stepButton("minus") { value = max(range.lowerBound, (value - step).rounded(toPlaces: decimals)) }
                stepButton("plus") { value = min(range.upperBound, (value + step).rounded(toPlaces: decimals)) }
            }
            Button { onSave(value); dismiss() } label: {
                Text("Save").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .onAppear { value = min(max(initial, range.lowerBound), range.upperBound) }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 64, height: 64)
        }.buttonStyle(.plain)
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m }
}

/// Body health in one card: BMI and the waist to height ratio side by side, each with its word and its place on a scale. Opens the weight page.
/// Both read from Apple Health and the profile; nothing is typed in here.
struct NunaBodyHealthCard: View {
    let weightKg: Double?
    let bmi: Double?
    let waistCm: Double
    let heightCm: Double
    /// The arrow that says the card opens the weight page; left out on the weight page itself.
    var showsChevron = true

    private var ratio: Double? { (waistCm > 0 && heightCm > 0) ? waistCm / heightCm : nil }

    /// Where a BMI sits on the scale in thirds: under 18.5, 18.5 to 25, 25 to 30, over 30 (WHO adult bands).
    private func bmiPosition(_ b: Double) -> Double {
        if b < 18.5 { return max(0, (b - 14) / 4.5) * (2.0 / 12) }
        if b < 25 { return 2.0 / 12 + (b - 18.5) / 6.5 * (5.0 / 12) }
        if b < 30 { return 7.0 / 12 + (b - 25) / 5 * (2.0 / 12) }
        return 9.0 / 12 + min((b - 30) / 10, 1) * (3.0 / 12)
    }

    private func word(_ text: LocalizedStringKey, good: Bool) -> some View {
        Text(text).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            .nunaStatusChip(good ? NunaPalette.charge : NunaPalette.warning)
    }

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    nunaCap("Body health")
                    Spacer()
                    if let weightKg {
                        Text(verbatim: nbFmt(weightKg, 1) + " kg").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
                HStack(alignment: .top, spacing: 22) {
                    // BMI
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BMI").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: bmi.map { nbFmt($0, 1) } ?? "–").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        if let bmi { word(bmi < 18.5 ? "Under" : (bmi < 25 ? "Normal" : (bmi < 30 ? "Over" : "High")), good: bmi >= 18.5 && bmi < 25) }
                        else { Text("Add height and weight").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
                        if let bmi {
                            NunaScaleBar(parts: [(2, NunaPalette.zoneBase), (5, NunaPalette.charge), (2, NunaPalette.warning), (3, NunaPalette.alert)], position: bmiPosition(bmi))
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Waist to height
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Waist ratio").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: ratio.map { nbFmt($0, 2) } ?? "–").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        if let ratio { word(ratio < 0.5 ? "Healthy" : (ratio < 0.6 ? "Above" : "High"), good: ratio < 0.5) }
                        else { Text("Waiting for Apple Health").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
                        if let ratio {
                            NunaScaleBar(parts: [(3, NunaPalette.rest), (3, NunaPalette.charge), (2, NunaPalette.warning), (3, NunaPalette.alert)],
                                         position: min(max((ratio - 0.35) / 0.3, 0), 1))
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if ratio != nil, waistCm > 0 {
                    Text(verbatim: String(localized: "Waist \(Int(waistCm.rounded())) cm · below 0.5 is generally considered healthy"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A coloured scale bar with a white marker. `parts` are (weight, colour); `position` is 0...1.
struct NunaScaleBar: View {
    let parts: [(Double, Color)]
    let position: Double
    var body: some View {
        ZStack(alignment: .topLeading) {
            NunaProportionBar(parts: parts, height: 12)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink).frame(width: 6, height: 20).shadow(color: NunaPalette.ink.opacity(0.25), radius: 3)
                    .offset(x: min(max(geo.size.width * CGFloat(position) - 3, 0), geo.size.width - 6), y: -4)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Weight

struct NunaWeightView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var weightS = NunaSeriesModel()
    @StateObject private var fatS = NunaSeriesModel()
    @StateObject private var leanS = NunaSeriesModel()
    /// The same target as Me › Targets, so the two cannot disagree.
    @AppStorage(NunaGoals.targetWeightKg) private var target = 0.0
    @State private var range = 30
    @State private var page = 0
    @State private var showAdd = false
    @State private var showTarget = false
    @State private var showCoach = false
    @AppStorage("noop.coachEnabled") private var coachEnabled = true

    /// Anya's line: the latest weight and how it moved over the range in view.
    private func anyaLine(delta: Double?) -> String? {
        guard let latest else { return nil }
        var line = String(localized: "Weight") + " " + nbFmt(latest, 1) + " kg"
        if let delta, abs(delta) >= 0.05 { line += " · " + (delta < 0 ? "−" : "+") + nbFmt(abs(delta), 1) + " kg" }
        return line
    }

    private var latest: Double? { weightS.latest?.value ?? (profile.weightKg > 0 ? profile.weightKg : nil) }

    /// "Target 70,0 kg · 5,9 kg to go".
    private var targetNote: String? {
        guard target > 0, let latest else { return nil }
        let left = abs(latest - target)
        return left < 0.05 ? String(localized: "Target \(nbFmt(target, 1)) kg · reached")
            : String(localized: "Target \(nbFmt(target, 1)) kg · \(nbFmt(left, 1)) kg to go")
    }

    var body: some View {
        let pts = weightS.readings(range, endingDaysAgo: page * range)
        let delta: Double? = pts.count >= 2 ? pts.last!.value - pts.first!.value : nil
        let bmi: Double? = (latest != nil && profile.heightCm > 0) ? latest! / pow(profile.heightCm / 100, 2) : nil
        NunaDetailScreen("Weight") {
            NunaTrendDetailCard(
                caption: "Latest", valueText: nbFmt(latest, 1), unit: "kg",
                chip: delta.map { d in (text: LocalizedStringKey((d <= 0 ? "−" : "+") + nbFmt(abs(d), 1) + " kg"), color: NunaPalette.textPrimary) },
                note: targetNote,
                series: weightS, showsBand: false, reference: target > 0 ? target : nil, lineColor: NunaPalette.charge, decimals: 1,
                directional: false, range: $range, page: $page)
            if coachEnabled, let line = anyaLine(delta: delta) { NunaAnyaCard(verbatim: line) { showCoach = true } }
            NunaBodyHealthCard(weightKg: latest, bmi: bmi, waistCm: profile.waistCm, heightCm: profile.heightCm, showsChevron: false)
            NunaBodyCompositionCard(weightKg: latest, fatPct: fatS.latest?.value, leanKg: leanS.latest?.value, bmi: bmi)
            NunaExpandRow(title: "About body composition", subtitle: "From a smart scale via Apple Health", systemImage: "sparkles",
                          text: "Body fat and lean mass appear only when Apple Health has them, for example from a smart scale. NOOP never estimates them.")
        }
        .sheet(isPresented: $showAdd) {
            NunaNumberSheet(title: "Add a measurement", unit: "kg", initial: latest ?? 70, range: 25...250, step: 0.1, decimals: 1) { v in
                Task { await saveWeight(v) }
            }
        }
        .sheet(isPresented: $showTarget) {
            NunaNumberSheet(title: "Weight target", unit: "kg", initial: target > 0 ? target : (latest ?? 70), range: 25...250, step: 0.5, decimals: 1) { v in target = v }
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showCoach) {
            NunaAnyaSheet(context: "Weight", metric: NunaAnyaMetric(key: "weight", source: "apple-health", title: String(localized: "Weight"), unit: "kg", decimals: 1, higherIsBetter: nil))
        }
    }

    private func saveWeight(_ v: Double) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.upsertMetricSeries([MetricPoint(day: Repository.localDayKey(Date()), key: "weight", value: v)], deviceId: nunaManualSource)
        profile.weightKg = v
        await load()
    }

    private func load() async {
        await weightS.load(repo: repo, key: "weight", source: "apple-health", days: 400, also: nunaManualSource)
        await fatS.load(repo: repo, key: "body_fat", source: "apple-health", days: 400)
        await leanS.load(repo: repo, key: "lean_mass", source: "apple-health", days: 400)
    }
}

// MARK: - Body composition

/// Fat, lean mass and BMI in one card: the split as a bar when both are known, then the three figures. Fat and lean mass appear only when
/// Apple Health has them; nothing is estimated here.
struct NunaBodyCompositionCard: View {
    let weightKg: Double?
    let fatPct: Double?
    let leanKg: Double?
    let bmi: Double?

    private func fmt(_ v: Double?, _ d: Int = 1) -> String { v.map { String(format: "%.\(d)f", locale: AppLanguage.activeLocale, $0) } ?? "–" }

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaCap("Body composition")
                if let fat = fatPct, let lean = leanKg, let w = weightKg, w > 0 {
                    let fatShare = max(0, min(100, fat)), leanShare = max(0, min(100 - fatShare, lean / w * 100))
                    NunaProportionBar(parts: [(fatShare, NunaPalette.warning), (leanShare, NunaPalette.charge), (max(0, 100 - fatShare - leanShare), NunaPalette.zoneBase)], height: 16)
                }
                HStack(alignment: .top, spacing: 0) {
                    figure("Body fat", fmt(fatPct), fatPct == nil ? "" : "%")
                    figure("Lean mass", fmt(leanKg), leanKg == nil ? "" : "kg")
                    figure("BMI", fmt(bmi), "")
                }
            }
        }
    }

    private func figure(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Waist

// MARK: - Nutrition

// MARK: - Cycle

struct NunaCycleView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppModel.cycleAwarenessKey) private var tracking = false
    @State private var starts: [String] = []
    @State private var confirmDelete = false

    private var phaseTitle: LocalizedStringKey {
        switch model.cyclePhase?.phase {
        case .follicular: return "Follicular phase"
        case .periOvulatory: return "Around ovulation"
        case .luteal: return "Luteal phase"
        case .learning: return "Still learning"
        default: return "No clear pattern yet"
        }
    }

    var body: some View {
        NunaDetailScreen("Menstrual cycle") {
            if tracking, let r = model.cyclePhase { statusCard(r) }
            weekCard
            logCard
            settingsCard
            if !starts.isEmpty { historyCard }
            NunaCard(small: true) {
                NunaListRow("Cycle data never leaves this iPhone", subtitle: "For awareness only. Not a medical device and not contraception.", systemImage: "lock")
            }
        }
        .task(id: repo.cycleTrackingSeq) { starts = await repo.periodStarts() }
        .confirmationDialog("Delete all logged period starts?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all period history", role: .destructive) {
                Task { await repo.deleteAllPeriodStarts(); await model.refreshV5Signals() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes the on-device period-start history. Sensor history is not changed.") }
    }

    private func statusCard(_ r: CyclePhaseEngine.Result) -> some View {
        let day = r.cycleDayLow ?? 0
        let length = r.cycleLengthDays ?? 28
        return NunaCard {
            HStack(spacing: 18) {
                NunaRingGauge(fraction: length > 0 ? Double(day) / Double(length) : 0, color: NunaPalette.rest, size: 124, lineWidth: 11) {
                    VStack(spacing: 0) {
                        Text(verbatim: day > 0 ? (r.cycleDayHigh != nil && r.cycleDayHigh != r.cycleDayLow ? "~\(day)" : "\(day)") : "–")
                            .font(.nuna(size: 32, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("day").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(phaseTitle).font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if let w = r.nextPeriodWindow {
                        Text(verbatim: String(localized: "Next period around \(w.earliestDay) to \(w.latestDay)"))
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    if let l = r.cycleLengthDays { NunaChip(verbatim: String(localized: "\(l)-day cycle")) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var weekCard: some View {
        let cal = Calendar.current
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0 - 3, to: Date()) ?? Date() }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaCap("This week")
                HStack {
                    ForEach(0..<7, id: \.self) { i in
                        let d = days[i]
                        let isToday = cal.isDateInToday(d)
                        let logged = starts.contains(Repository.localDayKey(d))
                        VStack(spacing: 6) {
                            Text(verbatim: f.string(from: d)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Text(verbatim: "\(cal.component(.day, from: d))").font(.nuna(size: 13, weight: .bold, design: NunaType.design))
                                .foregroundStyle(isToday ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(isToday ? NunaPalette.accent : (logged ? NunaPalette.alert.opacity(0.9) : NunaPalette.ink.opacity(0.07)), in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(NunaPalette.alert).frame(width: 10, height: 10)
                    Text("Period start").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    private var logCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaCap("Log today")
                let today = Repository.localDayKey(Date())
                let logged = starts.contains(today)
                Button {
                    Task { await repo.logPeriodStart(day: today); await model.refreshV5Signals() }
                } label: {
                    Text(logged ? "Period start logged today" : "Period started today").font(.nuna(size: 15, weight: .bold))
                        .foregroundStyle(logged ? NunaPalette.textSecondary : NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(logged ? NunaPalette.glassStrong : NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(logged)
            }
        }
    }

    private var settingsCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("Track my cycle", description: "Optional, only on this phone") {
                    Toggle("", isOn: $tracking).labelsHidden().tint(NunaPalette.charge)
                        .onChange(of: tracking) { _, _ in Task { await model.refreshV5Signals() } }
                }
                NunaDivider()
                NunaListRow("Effect on Charge", description: "HRV baseline adjusted per phase") {
                    NunaChip(tracking ? "On" : "Off", color: tracking ? NunaPalette.charge : nil)
                }
            }
        }
    }

    private var historyCard: some View {
        let rows = Array(starts.sorted(by: >).prefix(6))
        return NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                nunaCap("Period starts").padding(.bottom, 6)
                ForEach(0..<rows.count, id: \.self) { i in
                    if i > 0 { NunaDivider() }
                    NunaListRow(LocalizedStringKey(LabBookFormat.dayFromKey(rows[i])))
                }
                NunaDivider()
                Button { confirmDelete = true } label: {
                    Text("Delete all period history").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }
}
#endif
