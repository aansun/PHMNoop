#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import StrandImport

/// An assistant reply drawn as prose plus native cards for the charts, programs and workouts it carries.
struct NunaAnyaReply: View {
    let text: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        let blocks = AnyaActions.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .text(let t):
                    Text(NunaAnyaSheet.markdown(t)).font(.nuna(size: 15.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                case .chart(let c): NunaAnyaChartCard(spec: c)
                case .program(let p): NunaAnyaProgramCard(spec: p)
                case .workout(let w): NunaAnyaWorkoutCard(spec: w)
                case .lab(let l): NunaAnyaLabCard(spec: l)
                case .food(let f): NunaAnyaFoodCard(spec: f)
                case .plan(let p): NunaAnyaPlanCard(spec: p)
                }
            }
        }
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
                    NunaSegmentedChart(points: pts, color: color, decimals: metric?.decimals ?? 0, band: series.band.map { $0.lo...$0.hi },
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
        case "Effort": return NunaPalette.effort
        case "Rest": return NunaPalette.rest
        default: return NunaPalette.charge
        }
    }
}

// MARK: - Program

/// A gym program Anya wrote. Each day can be saved as a program of its own (the gym log keeps one list of exercises per program).
struct NunaAnyaProgramCard: View {
    let spec: AnyaProgramSpec
    @EnvironmentObject private var repo: Repository
    @State private var saved = false
    @State private var saving = false
    @State private var showGym = false

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
                        Button { showGym = true } label: { Text("Open in Gym").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
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
    }

    private func target(_ it: AnyaProgramItem) -> String {
        var s = ""
        if let sets = it.sets { s += "\(sets)×" }
        if let lo = it.repsLow { s += it.repsHigh.map { $0 == lo ? "\(lo)" : "\(lo)–\($0)" } ?? "\(lo)" }
        else if it.sets != nil { s += "–" }
        return s
    }

    private func save() async {
        guard let store = await repo.storeHandle() else { return }
        saving = true; defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        for d in spec.days {
            let id = UUID().uuidString
            let name = spec.days.count > 1 ? "\(spec.name) · \(d.title)" : spec.name
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: String(name.prefix(80)), note: spec.note,
                                                                    createdAt: now, updatedAt: now, archived: false)])
            let items = d.items.enumerated().map { i, it in
                LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: id, ord: i, exercise: it.exercise, targetSets: it.sets,
                                   targetRepsLow: it.repsLow, targetRepsHigh: it.repsHigh, targetRpe: nil, targetWeightKg: nil, restSec: it.restSec, note: it.note)
            }
            _ = try? await store.replaceLiftProgramItems(programId: id, items: items)
        }
        await repo.refresh()
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
        let rows = chosen
        guard !rows.isEmpty else { return }
        saving = true; defer { saving = false }
        await NunaLabStore.save(NunaLabStore.storedRows(rows, source: "anya-lab", deviceId: repo.deviceId), repo: repo)
        savedCount = rows.count
    }
}
#endif
