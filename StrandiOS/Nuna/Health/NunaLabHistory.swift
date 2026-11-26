#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// The tests behind the Lab Book: every set of results as one entry (a test), the page that lists them, and the page of every reading of one marker.

// MARK: - Tests

/// One set of results: the readings that were collected together. A test added by hand has its name in the note of its readings; a file's readings
/// are one test per day and file.
struct NunaLabTest: Identifiable {
    let id: String
    let name: String
    let takenAt: Int
    let rows: [LabMarkerRow]
    /// Readings, with a blood-pressure pair counted once.
    var count: Int { rows.filter { $0.markerKey != LabBookProjection.bpDiastolicKey }.count }
}

enum NunaLabTests {
    /// What makes two readings one test: for a result typed in, the moment it was taken (the flow gives all of a test's readings the same one);
    /// for a file, the day and the file's kind.
    static func key(_ r: LabMarkerRow) -> String { r.source == "manual" ? "manual-\(r.takenAt)" : "\(r.source)-\(r.day)" }

    static func name(_ rows: [LabMarkerRow]) -> String {
        // A blood pressure reading keeps its position and cuff place there, shown in the person's language.
        if let note = rows.compactMap(\.note).first(where: { !$0.isEmpty }), rows.first?.source == "manual" { return NunaBPContext.display(note) ?? note }
        switch rows.first?.source ?? "" {
        case "manual": return String(localized: "Lab result")
        case WhoopBiomarkerExportParser.sourceId: return String(localized: "WHOOP biomarker export")
        case LabFhirImport.sourceId: return String(localized: "FHIR file")
        case LabMarkerCsvImport.sourceId: return String(localized: "CSV file")
        default: return String(localized: "Lab result")
        }
    }

    /// Newest first.
    static func group(_ rows: [LabMarkerRow]) -> [NunaLabTest] {
        Dictionary(grouping: rows, by: key).map { id, list in
            NunaLabTest(id: id, name: name(list), takenAt: list.map(\.takenAt).max() ?? 0, rows: list)
        }
        .sorted { $0.takenAt > $1.takenAt }
    }
}

/// A test as a row: a note icon, its name with the number of readings, its date.
struct NunaLabTestRow: View {
    let test: NunaLabTest
    var body: some View {
        NavigationLink { NunaLabSummaryPage(title: LocalizedStringKey(test.name), testId: test.id) } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.clipboard").font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).frame(width: 32)
                Text(verbatim: "\(test.name) (\(test.count))").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: LabBookFormat.day(test.takenAt)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            .padding(.horizontal, 16).frame(height: 62).contentShape(Rectangle())
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        }.buttonStyle(.plain)
    }
}

// MARK: - Lab history

/// Every test, newest first and by year, with the way to add another.
struct NunaLabHistoryView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var adding = false

    var body: some View {
        let tests = NunaLabTests.group(rows)
        let years = Dictionary(grouping: tests) { Calendar.current.component(.year, from: Date(timeIntervalSince1970: TimeInterval($0.takenAt))) }
        NunaDetailScreen("Lab history", trailing: AnyView(
            Button { adding = true } label: {
                Image(systemName: "plus").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("Add results"))
        )) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lab history").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Every set of results you added, by hand or from a file.").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if loaded {
                ForEach(years.keys.sorted(by: >), id: \.self) { year in
                    VStack(alignment: .leading, spacing: 12) {
                        NunaRuledHeader(LocalizedStringKey(String(year)))
                        ForEach(years[year] ?? []) { NunaLabTestRow(test: $0) }
                    }
                }
                otherLabs
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(isPresented: $adding) {
            NunaLabTestFlow { rows = await NunaLabStore.load(repo) }.nunaSheetChrome(detents: [.large])
        }
    }

    private var otherLabs: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.clipboard").font(.nuna(size: 46, weight: .light)).foregroundStyle(NunaPalette.textMuted).padding(.top, 8)
            VStack(spacing: 6) {
                Text("Have other labs?").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Add results from past doctor visits to follow them over time.").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Button { adding = true } label: {
                Text("Add results").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(20).frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 2))
    }
}

// MARK: - All recordings

/// Every reading of one marker, by month, newest first. A reading can be removed from its menu.
struct NunaLabRecordingsView: View {
    let markerKey: String
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var removing: LabMarkerRow?

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); return f
    }()
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d, HH:mm"); return f
    }()

    private var mine: [LabMarkerRow] { rows.filter { $0.markerKey == markerKey }.sorted { $0.takenAt > $1.takenAt } }
    private var name: String { NunaLabGrouping.markerName(markerKey) }

    var body: some View {
        let months = Dictionary(grouping: mine) { Self.monthFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.takenAt))) }
        let order = mine.reduce(into: [String]()) { acc, r in
            let m = Self.monthFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(r.takenAt)))
            if !acc.contains(m) { acc.append(m) }
        }
        NunaDetailScreen("All recordings") {
            VStack(alignment: .leading, spacing: 6) {
                Text("All recorded data").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(verbatim: String(localized: "View all of your \(name) data.")).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ForEach(order, id: \.self) { month in
                VStack(alignment: .leading, spacing: 12) {
                    NunaRuledHeader(LocalizedStringKey(month))
                    ForEach(months[month] ?? [], id: \.id) { r in recording(r) }
                }
            }
            if loaded && mine.isEmpty {
                Text("No readings for this marker.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
        .nunaDialog("Remove this reading?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            NunaDialogButton("Remove", role: .destructive) {
                if let r = removing {
                    var ids = [r.id]
                    // A blood-pressure reading goes with its diastolic half.
                    if r.markerKey == LabBookProjection.bpSystolicKey, let d = rows.first(where: { $0.markerKey == LabBookProjection.bpDiastolicKey && $0.takenAt == r.takenAt }) { ids.append(d.id) }
                    Task { await NunaLabStore.delete(ids: ids, repo: repo) }
                }
                removing = nil
            }
            NunaDialogButton("Cancel", role: .cancel) { removing = nil }
        }
    }

    private func recording(_ r: LabMarkerRow) -> some View {
        let diastolic = r.markerKey == LabBookProjection.bpSystolicKey ? rows.first { $0.markerKey == LabBookProjection.bpDiastolicKey && $0.takenAt == r.takenAt }?.value : nil
        var text = r.value.map { LabBookFormat.value($0, key: r.markerKey) } ?? (r.valueText ?? "—")
        if let d = diastolic { text += "/" + LabBookFormat.value(d, key: LabBookProjection.bpDiastolicKey) }
        return HStack(spacing: 14) {
            Image(systemName: r.source == "manual" ? "square.and.pencil" : "doc.text").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: text).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: r.unit).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                // How a typed blood-pressure reading was taken, when that was filled in.
                if let how = NunaBPContext.display(r.note) {
                    Text(verbatim: how).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: Self.momentFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(r.takenAt)))).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 62)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        .nunaLongPressMenu { NunaMenuItem("Remove", icon: "trash", role: .destructive) { removing = r } }
    }
}

extension MarkerDefinition: @retroactive Identifiable { public var id: String { key } }
#endif
