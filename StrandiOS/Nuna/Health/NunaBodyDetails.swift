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
                .frame(width: 64, height: 64).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
        }.buttonStyle(.plain)
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m }
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
    @AppStorage("nuna.weightTarget") private var target = 0.0
    @State private var range = 30
    @State private var page = 0
    @State private var showAdd = false
    @State private var showTarget = false

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
            HStack(spacing: 10) {
                NunaStatTile(label: "Body fat", value: nbFmt(fatS.latest?.value, 1), unit: fatS.latest == nil ? "" : "%")
                NunaStatTile(label: "Lean mass", value: nbFmt(leanS.latest?.value, 1), unit: leanS.latest == nil ? "" : "kg")
                NunaStatTile(label: "BMI", value: nbFmt(bmi, 1))
            }
            if let bmi { bmiCard(bmi) }
            Button { showAdd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                    Text("Add a measurement").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                Button { showTarget = true } label: {
                    NunaListRow("Weight target", subtitle: LocalizedStringKey(target > 0 ? "\(nbFmt(target, 1)) kg" : String(localized: "Not set")),
                                systemImage: "scalemass", showsChevron: true)
                }.buttonStyle(.plain)
            }
            NunaCard(small: true) {
                NunaListRow("Read from Apple Health", subtitle: "Read only. Manage it in Me › Apple Health. A weight you type in is kept on this phone and also used for calorie and VO₂max estimates.",
                            systemImage: "heart.text.square")
            }
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
    }

    private func bmiCard(_ bmi: Double) -> some View {
        // Scale in thirds: under 18.5, 18.5 to 25, 25 to 30, over 30 (WHO adult bands).
        func pos(_ b: Double) -> Double {
            if b < 18.5 { return max(0, (b - 14) / 4.5) * (2.0 / 12) }
            if b < 25 { return 2.0 / 12 + (b - 18.5) / 6.5 * (5.0 / 12) }
            if b < 30 { return 7.0 / 12 + (b - 25) / 5 * (2.0 / 12) }
            return 9.0 / 12 + min((b - 30) / 10, 1) * (3.0 / 12)
        }
        let label: LocalizedStringKey = bmi < 18.5 ? "Under" : (bmi < 25 ? "Normal" : (bmi < 30 ? "Over" : "High"))
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaCap("BMI"); Spacer(); NunaChip(label, color: bmi >= 18.5 && bmi < 25 ? NunaPalette.charge : NunaPalette.warning) }
                NunaScaleBar(parts: [(2, NunaPalette.zoneBase), (5, NunaPalette.charge), (2, NunaPalette.warning), (3, NunaPalette.alert)], position: pos(bmi))
                HStack { Text(verbatim: "18,5"); Spacer(); Text(verbatim: "25"); Spacer(); Text(verbatim: "30") }
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                HStack { Text("Under"); Spacer(); Text("Normal").foregroundStyle(NunaPalette.charge).fontWeight(.heavy); Spacer(); Text("Over") }
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
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

// MARK: - Waist

struct NunaWaistView: View {
    @EnvironmentObject private var profile: ProfileStore
    @State private var showAdd = false

    var body: some View {
        let waist = profile.waistCm
        let ratio: Double? = (waist > 0 && profile.heightCm > 0) ? waist / profile.heightCm : nil
        NunaDetailScreen("Waist") {
            NunaCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { nunaCap("Latest"); Spacer(); NunaChip("Profile") }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: waist > 0 ? nbFmt(waist) : "–").font(.nuna(size: 68, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(68)).foregroundStyle(NunaPalette.textPrimary)
                        if waist > 0 { Text("cm").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    Text(waist > 0 ? "Read from Apple Health when it has one, or typed in here" : "Not set yet")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            if let ratio {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            nunaCap("Waist to height ratio")
                            Spacer()
                            NunaChip(ratio < 0.5 ? "Healthy" : (ratio < 0.6 ? "Above" : "High"), color: ratio < 0.5 ? NunaPalette.charge : NunaPalette.warning)
                        }
                        Text(verbatim: nbFmt(ratio, 2)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                        NunaScaleBar(parts: [(3, NunaPalette.rest), (3, NunaPalette.charge), (2, NunaPalette.warning), (3, NunaPalette.alert)],
                                     position: min(max((ratio - 0.35) / 0.3, 0), 1))
                        HStack { Text(verbatim: "0,4"); Spacer(); Text(verbatim: "0,6") }
                            .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: String(localized: "Below 0.5 is generally considered healthy for a height of \(Int(profile.heightCm.rounded())) cm."))
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            NavigationLink(value: NunaTodayRoute.fitnessAge) {
                NunaCard(small: true) { NunaListRow("Used for VO₂max", subtitle: "Opens the fitness age screen", systemImage: "waveform.path.ecg", showsChevron: true) }
            }.buttonStyle(.plain)
            Button { showAdd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                    Text("Add a manual measurement").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            NunaCard(small: true) {
                NunaListRow("Fill the profile from Apple Health", subtitle: "The latest value is read automatically. Manage it in Me › Apple Health.", systemImage: "heart.text.square")
            }
        }
        .sheet(isPresented: $showAdd) {
            NunaNumberSheet(title: "Waist", unit: "cm", initial: waist > 0 ? waist : 80, range: 50...180, step: 1, decimals: 0) { v in profile.waistCm = v }
        }
    }
}

// MARK: - Nutrition

struct NunaNutritionView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var kcalS = NunaSeriesModel()
    @StateObject private var proteinS = NunaSeriesModel()
    @StateObject private var carbsS = NunaSeriesModel()
    @StateObject private var fatS = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    @ObservedObject private var caffeine = CaffeineLogStore.shared

    var body: some View {
        let kin = kcalS.latest
        let out = day.calories
        NunaDetailScreen("Nutrition") {
            if let kin {
                NunaCard {
                    HStack(spacing: 18) {
                        NunaRingGauge(fraction: out.map { $0 > 0 ? kin.value / $0 : 0 } ?? 0, color: NunaPalette.charge, size: 116, lineWidth: 11) {
                            VStack(spacing: 0) {
                                Text(verbatim: nbFmt(kin.value)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                Text("kcal in").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if let out {
                                row("Out", nbFmt(out))
                                let diff = kin.value - out
                                row("Difference", (diff >= 0 ? "+" : "−") + nbFmt(abs(diff)), color: diff < 0 ? NunaPalette.charge : nil)
                                NunaChip(abs(diff) < 100 ? "Balanced" : (diff < 0 ? "Mild deficit" : "Surplus"), color: abs(diff) < 100 || diff < 0 ? NunaPalette.charge : NunaPalette.warning)
                            }
                            Text(verbatim: kin.day).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 0)
                    }
                }
                macrosCard(kin.value)
            } else {
                NunaCard {
                    Text("No nutrition imported yet. Import a CSV from Cronometer or MacroFactor, processed on this phone.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            importCard
            caffeineCard
        }
        .task(id: repo.refreshSeq) {
            await day.load(repo: repo, profile: profile)
            await kcalS.load(repo: repo, key: "calories_in", source: "nutrition-csv", days: 60)
            await proteinS.load(repo: repo, key: "protein_g", source: "nutrition-csv", days: 60)
            await carbsS.load(repo: repo, key: "carbs_g", source: "nutrition-csv", days: 60)
            await fatS.load(repo: repo, key: "fat_g", source: "nutrition-csv", days: 60)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String, color: Color? = nil) -> some View {
        HStack(spacing: 18) {
            Text(label).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(color ?? NunaPalette.textPrimary)
        }
    }

    private func macrosCard(_ kcal: Double) -> some View {
        let macros: [(LocalizedStringKey, Double?, Double, Color)] = [
            ("Protein", proteinS.latest?.value, 4, NunaPalette.charge), ("Carbs", carbsS.latest?.value, 4, NunaPalette.effort), ("Fat", fatS.latest?.value, 9, NunaPalette.warning),
        ]
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaCap("Macros")
                ForEach(0..<macros.count, id: \.self) { i in
                    if let g = macros[i].1 {
                        VStack(spacing: 8) {
                            HStack {
                                Text(macros[i].0).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: "\(nbFmt(g)) g").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }
                            NunaProgressBar(fraction: kcal > 0 ? g * macros[i].2 / kcal : 0, color: macros[i].3)
                        }
                    }
                }
                Text("Bars show each macro's share of calories").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    private var importCard: some View {
        NavigationLink(value: TabRoute.dataSources) {
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        NunaIconTile("plus")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import CSV").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("From Cronometer or MacroFactor").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(spacing: 8) { NunaChip("Cronometer"); NunaChip("MacroFactor") }
                    Text("Processed on this phone. Never uploaded.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }.buttonStyle(.plain)
    }

    private var caffeineCard: some View {
        let est = caffeine.estimate()
        return NunaCard(small: true) {
            NunaListRow(est.hasActive ? (est.totalRemainingMg.map { LocalizedStringKey("Caffeine \(Int($0.rounded())) mg active") } ?? "Caffeine active") : "No caffeine active",
                        subtitle: est.hoursSinceMostRecentActive.map { LocalizedStringKey("Last one about \(Int($0.rounded())) h ago") } ?? "Logged caffeine fades with a 5.5 hour half-life",
                        systemImage: "bolt")
        }
    }
}

// MARK: - Lab Book

struct NunaLabBookView: View {
    @EnvironmentObject private var repo: Repository
    @State private var markers: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var showEditor = false
    @State private var detailKey: String?
    @State private var showNote = false

    private struct KeyID: Identifiable { let id: String }

    private var keys: [String] {
        let latest = Dictionary(grouping: markers, by: \.markerKey).mapValues { $0.map(\.takenAt).max() ?? 0 }
        return latest.keys.sorted { (latest[$0] ?? 0) > (latest[$1] ?? 0) }
    }

    var body: some View {
        NunaDetailScreen("Lab Book") {
            if let last = markers.map(\.takenAt).max() {
                NunaCard(small: true) {
                    NunaListRow("Last test", subtitle: LocalizedStringKey(LabBookFormat.day(last)), systemImage: "clock")
                }
            }
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 120)
            } else if markers.isEmpty {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your own logbook").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Keep the numbers you get from your doctor or pharmacy, next to your wearable signals. Everything stays on this phone.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(keys, id: \.self) { markerCard($0) }
            }
            Button { showEditor = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.nuna(size: 14, weight: .bold))
                    Text("Add a result").font(.nuna(size: 17, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            Text("Saved on this phone. Not a medical diagnosis. NOOP does not read results for you.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity, alignment: .leading)
            Button("Read the full note") { showNote = true }
                .font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showEditor) { MarkerEditorView { drafts in await save(drafts) }.preferredColorScheme(NunaTheme.colorScheme) }
        .sheet(item: Binding(get: { detailKey.map(KeyID.init) }, set: { detailKey = $0?.id })) { k in
            MarkerDetailView(markerKey: k.id, readings: markers.filter { $0.markerKey == k.id }, onDelete: { id in await delete(id) }).preferredColorScheme(NunaTheme.colorScheme)
        }
        .sheet(isPresented: $showNote) { LabBookDisclaimerView().preferredColorScheme(NunaTheme.colorScheme) }
    }

    /// The range the user typed from their own report, when it reads as "low–high".
    private func parsedRange(_ text: String?) -> (Double, Double)? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        let nums = cleaned.split(whereSeparator: { !("0123456789.".contains($0)) }).compactMap { Double($0) }
        guard nums.count >= 2, nums[0] < nums[1] else { return nil }
        return (nums[0], nums[1])
    }

    private func markerCard(_ key: String) -> some View {
        let series = markers.filter { $0.markerKey == key }
        let latest = series.last
        let name = MarkerCatalog.definition(for: key)?.displayName ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        let range = parsedRange(latest?.referenceText)
        return Button { detailKey = key } label: {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verbatim: latest?.value.map { LabBookFormat.value($0, key: key) } ?? (latest?.valueText ?? "—"))
                                    .font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: latest?.unit ?? "").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                        Spacer()
                        if let v = latest?.value, let range {
                            let inside = v >= range.0 && v <= range.1
                            NunaChip(inside ? "Within your range" : "Outside your range", color: inside ? NunaPalette.charge : NunaPalette.warning)
                        }
                    }
                    if let v = latest?.value, let range {
                        let span = range.1 - range.0
                        let pos: Double = v < range.0 ? max(0.02, 0.2 - 0.18 * min((range.0 - v) / (span * 0.5), 1))
                            : (v > range.1 ? min(0.98, 0.8 + 0.18 * min((v - range.1) / (span * 0.5), 1)) : 0.2 + 0.6 * (v - range.0) / span)
                        NunaScaleBar(parts: [(2, NunaPalette.zoneBase), (6, NunaPalette.charge), (2, NunaPalette.zoneBase)], position: pos)
                        HStack {
                            Text(verbatim: LabBookFormat.value(range.0, key: key)); Spacer(); Text(verbatim: LabBookFormat.value(range.1, key: key))
                        }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    HStack {
                        Text(verbatim: latest.map { String(localized: "last taken \(LabBookFormat.day($0.takenAt))") } ?? "")
                            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        var all: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            all.append(contentsOf: (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? [])
        }
        markers = all.sorted { $0.takenAt < $1.takenAt }
        loaded = true
    }

    private func save(_ drafts: [LabMarkerRow]) async {
        guard !drafts.isEmpty, let store = await repo.storeHandle() else { return }
        try? await store.upsertLabMarkers(drafts)
        await repo.refresh()
        await load()
    }

    private func delete(_ id: String) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLabMarker(id: id)
        await repo.refresh()
        await load()
    }
}

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
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
                NunaListRow("Track my cycle", subtitle: "Optional, only on this phone") {
                    Toggle("", isOn: $tracking).labelsHidden().tint(NunaPalette.charge)
                        .onChange(of: tracking) { _, _ in Task { await model.refreshV5Signals() } }
                }
                NunaDivider()
                NunaListRow("Effect on Charge", subtitle: "HRV baseline adjusted per phase") {
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
