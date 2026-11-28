#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import StrandImport

/// An assistant reply drawn as prose plus native cards for the charts, programs and workouts it carries.
struct NunaAnyaReply: View {
    let text: String
    /// The type of the prose, for the sheets that set their own (the cards stay as they are).
    var font: Font = NunaAnyaType.reply
    var lineSpacing: CGFloat = NunaAnyaType.replySpacing
    var color: Color? = NunaPalette.textPrimary
    /// What the person asked. A question about a week draws a 7-day chart, whatever window the reply named.
    var question: String?
    /// The message the reply belongs to, so a card that writes something remembers it did when the conversation is opened again.
    var messageID: UUID?
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter

    /// The chart over the window the question asked for (a week is 7 days), with no title that could still name another window.
    private func windowed(_ c: AnyaChartSpec) -> AnyaChartSpec {
        guard let days = AnyaActions.requestedDays(in: question), days != c.days else { return c }
        var out = c
        out.days = days; out.title = nil
        return out
    }

    var body: some View {
        let blocks = AnyaActions.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { place, b in
                Group { switch b {
                case .text(let t):
                    Text(NunaAnyaSheet.markdown(t)).font(font).lineSpacing(lineSpacing).foregroundStyle(color ?? .primary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                case .chart(let c): NunaAnyaChartCard(spec: windowed(c))
                case .program(let p): NunaAnyaProgramCard(spec: p)
                case .workout(let w): NunaAnyaWorkoutCard(spec: w)
                case .lab(let l): NunaAnyaLabCard(spec: l)
                case .food(let f): NunaAnyaFoodCard(spec: f)
                case .plan(let p): NunaAnyaPlanCard(spec: p)
                case .breath(let b): NunaAnyaBreathCard(spec: b)
                } }
                .environment(\.nunaAnyaCardID, messageID.map { "\($0.uuidString)#\(place)" })
            }
        }
    }
}

// MARK: - What a card has already written

/// What a card in the chat wrote, with the choices it was made with, so the card reads the same when the conversation is opened again.
struct NunaAnyaCardUse: Codable, Equatable {
    var count: Int
    var excluded: [Int] = []
    var scale: [String: Double] = [:]
}

/// The cards already used, kept on the device by message and place in the reply; the newest 200.
enum NunaAnyaCardUses {
    static let key = "nuna.anya.cardsUsed"
    private struct Entry: Codable { var id: String; var use: NunaAnyaCardUse }

    private static var entries: [Entry] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static func use(_ id: String?) -> NunaAnyaCardUse? {
        guard let id else { return nil }
        return entries.first { $0.id == id }?.use
    }

    static func record(_ use: NunaAnyaCardUse, for id: String?) {
        guard let id else { return }
        let kept = Array(([Entry(id: id, use: use)] + entries.filter { $0.id != id }).prefix(200))
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: key) }
    }
}

private struct NunaAnyaCardIDKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Which card of which message a card is; nil for a card that is not part of a kept conversation.
    var nunaAnyaCardID: String? {
        get { self[NunaAnyaCardIDKey.self] }
        set { self[NunaAnyaCardIDKey.self] = newValue }
    }
}

// MARK: - Chart

/// A chart Anya asked for, drawn from the readings stored on the phone. Only the metric and the window come from the reply.
struct NunaAnyaChartCard: View {
    let spec: AnyaChartSpec
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = spec.title { Text(verbatim: t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary) }
            ForEach(spec.metrics, id: \.self) { NunaAnyaMetricChart(key: $0, days: spec.days) }
        }
    }
}

private struct NunaAnyaMetricChart: View {
    let key: String
    let days: Int
    @EnvironmentObject private var repo: Repository
    @StateObject private var series = NunaSeriesModel()

    private var metric: MetricDescriptor? {
        MetricCatalog.metric(key: key, source: key == "weight" ? "apple-health" : "my-whoop")
            ?? MetricCatalog.metric(key: key, source: "my-whoop")
    }

    var body: some View {
        let pts = series.readings(days)
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(verbatim: metric?.title ?? key).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    if let m = metric, let last = pts.last { Text(verbatim: m.format(last.value)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
                }
                if pts.count >= 2 {
                    NunaSegmentedChart(points: pts, color: color, decimals: metric?.decimals ?? 0, band: series.typicalRange,
                                       higherIsBetter: metric?.higherIsBetter ?? true, directional: metric?.higherIsBetter != nil, height: 190)
                } else {
                    Text(series.loaded ? "No data in this period" : " ").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .task(id: repo.refreshSeq) { if let m = metric { await series.load(repo: repo, key: m.key, source: m.source, days: max(days, 30) + 30) } }
    }

    private var color: Color {
        switch metric?.category {
        case "Strain": return NunaPalette.effort
        case "Sleep": return NunaPalette.rest
        default: return NunaPalette.charge
        }
    }
}

// MARK: - Program

/// A gym program Anya wrote. Each day can be saved as a program of its own (the gym log keeps one list of exercises per program).
struct NunaAnyaProgramCard: View {
    let spec: AnyaProgramSpec
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @State private var saved = false
    @State private var saving = false
    @State private var showGym = false
    @Environment(\.nunaAnyaCardID) private var cardID

    var body: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NunaIconTile("dumbbell")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: spec.name).font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        if let n = spec.note { Text(verbatim: n).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }
                    Spacer(minLength: 0)
                }
                ForEach(Array(spec.days.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: d.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        ForEach(Array(d.items.enumerated()), id: \.offset) { _, it in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: it.exercise).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer(minLength: 8)
                                Text(verbatim: target(it)).font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                    }
                }
                if saved {
                    HStack(spacing: 10) {
                        Label(String(localized: "Saved"), systemImage: "checkmark.circle.fill").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Spacer()
                        Button { showGym = true } label: { Text("Open in Strength Trainer").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                    }
                } else {
                    Button { Task { await save() } } label: {
                        Text(spec.days.count > 1 ? String(localized: "Save \(spec.days.count) programs") : String(localized: "Save as program"))
                            .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(saving).opacity(saving ? 0.5 : 1)
                }
            }
        }
        .sheet(isPresented: $showGym) { NunaQuickPanel(route: NunaWorkoutRoute.gym) }
        .onAppear { if NunaAnyaCardUses.use(cardID) != nil { saved = true } }
    }

    private func target(_ it: AnyaProgramItem) -> String {
        var s = ""
        if let sets = it.sets { s += "\(sets)×" }
        if let lo = it.repsLow { s += it.repsHigh.map { $0 == lo ? "\(lo)" : "\(lo)–\($0)" } ?? "\(lo)" }
        else if it.sets != nil { s += "–" }
        return s
    }

    private func save() async {
        guard NunaAnyaCardUses.use(cardID) == nil else { saved = true; return }
        guard let store = await repo.storeHandle() else { return }
        saving = true; defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        for (day, d) in spec.days.enumerated() {
            let id = UUID().uuidString
            let name = spec.days.count > 1 ? "\(spec.name) · \(d.title)" : spec.name
            // The list shows the newest first, so each later day is stamped a second older and the first day stays on top.
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: String(name.prefix(80)), note: spec.note,
                                                                    createdAt: now - day, updatedAt: now - day, archived: false)])
            let items = d.items.enumerated().map { i, it in
                LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: id, ord: i, exercise: it.exercise, targetSets: it.sets,
                                   targetRepsLow: it.repsLow, targetRepsHigh: it.repsHigh, targetRpe: nil, targetWeightKg: nil, restSec: it.restSec, note: it.note)
            }
            _ = try? await store.replaceLiftProgramItems(programId: id, items: items)
            // Anya's programs are kept together in the Gym tab.
            NunaAnyaPrograms.add(id)
            NunaProgramGroupsModel.shared.place(id, inGroupNamed: NunaProgramType.anya.name)
        }
        // The muscles of each exercise are remembered (the library's for an exercise it has, Anya's or the closest match's for one it has not), so the
        // weekly sets per muscle count them and the exercise has a page and a history from the first session.
        let known = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        var picks: [NunaPickedExercise] = []
        for d in spec.days {
            for it in d.items where !picks.contains(where: { $0.name == it.exercise }) {
                let lib = NunaExerciseLibrary.matchBundled(it.exercise)
                if let lib, !known.contains(where: { $0.name == it.exercise }) {
                    _ = try? await store.upsertLiftExercises([LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: it.exercise, primaryMuscle: lib.liftPrimary,
                                                                              secondaryMuscles: lib.liftSecondary, createdAt: now, lastUsedTs: nil)])
                }
                if lib == nil { picks.append(NunaPickedExercise(name: it.exercise, primary: nil, secondary: [])) }
            }
        }
        await NunaCustomExercises.remember(picks, repo: repo, coach: model.coach)
        await repo.refresh()
        NunaAnyaCardUses.record(NunaAnyaCardUse(count: spec.days.count), for: cardID)
        saved = true
    }
}

// MARK: - Workout

/// A session Anya planned. Start opens the workout start screen with its length and zone already chosen.
struct NunaAnyaWorkoutCard: View {
    let spec: AnyaWorkoutSpec
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                NunaIconTile(NunaSportPicker.symbol(for: spec.sport ?? spec.title))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: spec.title).font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: detail).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    if let n = spec.note { Text(verbatim: n).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
                }
                Spacer(minLength: 6)
                Button {
                    router.plannedSession = .init(title: spec.title, minutes: spec.minutes, zone: spec.zone ?? 2, sport: spec.sport)
                    router.requestedDestination = .activeWorkout
                } label: {
                    Text("Start").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 18).frame(height: 42)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let s = spec.sport { parts.append(s) }
        parts.append(String(localized: "\(spec.minutes) min"))
        if let z = spec.zone { parts.append(String(localized: "Zone \(z)")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Lab results

/// Lab results Anya read from what was typed or attached, or that a CSV or FHIR file held. Nothing is saved until the person taps Save, and each line can
/// be left out; values, units and ranges are shown exactly as read, and a name that matches the catalog joins that marker's history.
struct NunaAnyaLabCard: View {
    let spec: AnyaLabSpec
    @EnvironmentObject private var repo: Repository
    @State private var excluded: Set<Int> = []
    @State private var fallbackDay = Date()
    @State private var saving = false
    @State private var savedCount: Int?
    @State private var showLab = false
    @Environment(\.nunaAnyaCardID) private var cardID

    private var needsDay: Bool { spec.day == nil && spec.results.contains { $0.day == nil } }
    private var fallbackKey: String { Repository.localDayKey(fallbackDay) }

    private func made(_ r: AnyaLabResult) -> LabMarkerCsvRow? {
        LabMarkerCsvImport.makeRow(name: r.marker, value: r.value, unit: r.unit, day: r.day ?? spec.day ?? fallbackKey, referenceText: r.range, note: r.note)
    }

    private var chosen: [LabMarkerCsvRow] {
        spec.results.enumerated().compactMap { i, r in excluded.contains(i) ? nil : made(r) }
    }

    var body: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NunaIconTile("testtube.2")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: spec.title ?? String(localized: "Lab results")).font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Text(verbatim: String(localized: "\(spec.results.count) results to check")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 0)
                }
                if needsDay && savedCount == nil {
                    HStack {
                        Text("Taken on").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: $fallbackDay, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                }
                ForEach(Array(spec.results.enumerated()), id: \.offset) { i, r in line(i, r) }
                if let n = savedCount {
                    HStack(spacing: 10) {
                        Label(String(localized: "Saved \(n) results"), systemImage: "checkmark.circle.fill").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Spacer()
                        Button { showLab = true } label: { Text("Open Lab Book").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                    }
                } else {
                    Button { Task { await save() } } label: {
                        Text(String(localized: "Save \(chosen.count) to Lab Book")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(saving || chosen.isEmpty).opacity(saving || chosen.isEmpty ? 0.5 : 1)
                    Text("Nothing is saved until you tap Save. Check each value against your report.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .sheet(isPresented: $showLab) { NunaQuickPanel(route: NunaTodayRoute.labBook) }
        .onAppear { if let used = NunaAnyaCardUses.use(cardID) { savedCount = used.count; excluded = Set(used.excluded) } }
    }

    @ViewBuilder private func line(_ i: Int, _ r: AnyaLabResult) -> some View {
        let row = made(r)
        let on = row != nil && !excluded.contains(i)
        let range = NunaLabRange.parse(row?.referenceText)
        let status = row.flatMap { range?.status($0.value) }
        Button { if row != nil, savedCount == nil { if on { excluded.insert(i) } else { excluded.remove(i) } } } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.nuna(size: 20, weight: .semibold))
                    .foregroundStyle(on ? NunaPalette.charge : NunaPalette.textMuted).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: row.flatMap { MarkerCatalog.definition(for: $0.markerKey)?.displayName } ?? r.marker).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: detail(r, row)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    if status != nil || row?.isCustomMarker == true {
                        HStack(spacing: 6) {
                            if let status { NunaChip(NunaLabRange.word(status), color: NunaLabRange.tint(status)) }
                            if let row, row.isCustomMarker { NunaChip("New marker") }
                        }
                    }
                    if row == nil { Text("Can't be added. Give blood pressure as systolic and diastolic.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil) }
                }
                Spacer(minLength: 0)
            }
            .opacity(on || savedCount != nil ? 1 : 0.5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func detail(_ r: AnyaLabResult, _ row: LabMarkerCsvRow?) -> String {
        var parts = [LabBookFormat.value(r.value, key: row?.markerKey ?? "") + ((row?.unit ?? r.unit ?? "").isEmpty ? "" : " " + (row?.unit ?? r.unit ?? ""))]
        if let range = row?.referenceText { parts.append(String(localized: "range \(range)")) }
        if let day = row?.day { parts.append(LabBookFormat.dayFromKey(day)) }
        return parts.joined(separator: " · ")
    }

    private func save() async {
        if let used = NunaAnyaCardUses.use(cardID) { savedCount = used.count; return }
        let rows = chosen
        guard !rows.isEmpty else { return }
        saving = true; defer { saving = false }
        await NunaLabStore.save(NunaLabStore.storedRows(rows, source: "anya-lab", deviceId: repo.deviceId), repo: repo)
        NunaAnyaCardUses.record(NunaAnyaCardUse(count: rows.count, excluded: excluded.sorted()), for: cardID)
        savedCount = rows.count
    }
}
#endif
