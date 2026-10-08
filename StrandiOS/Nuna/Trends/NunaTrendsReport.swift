#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Export the trends as a PDF: pick the range, look through the pages, share. The document itself is `TrendsReportDocument`.
struct NunaTrendsReportSheet: View {
    let days: [DailyMetric]
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var range: ReportRange = .days90
    @State private var stressByDay: [String: Double] = [:]
    @State private var exporting = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var document: TrendsReportDocument {
        TrendsReportData.document(
            range: range, days: days, stressByDay: stressByDay,
            units: TrendsReportData.units(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw, effortScaleRaw: effortScaleRaw))
    }

    private static let previewScale: CGFloat = 0.5

    var body: some View {
        let doc = document
        let pages = doc.pages()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Export report").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
                Text("A readable PDF of your trends: a summary table, a chart for each metric and a day-by-day table of every reading, so you can analyse it further. It is made on this iPhone and nothing leaves it until you share it.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)

                NunaSegmented(ReportRange.allCases.map { (value: $0, title: LocalizedStringKey($0.label)) }, selection: $range)
                Text(verbatim: range.longName + " · " + String(localized: "\(doc.pageCount) pages"))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(pages.indices, id: \.self) { i in
                            pages[i]
                                .scaleEffect(Self.previewScale, anchor: .topLeading)
                                .frame(width: TrendsReportDocument.pageSize.width * Self.previewScale,
                                       height: TrendsReportDocument.pageSize.height * Self.previewScale, alignment: .topLeading)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: TrendsReportDocument.pageSize.height * Self.previewScale + 2)

                Button { export(doc) } label: { Text(exporting ? "Preparing…" : "Export PDF") }
                    .buttonStyle(.nuna(.primary, fullWidth: true))
                    .disabled(exporting)
                Text("The share sheet can save the PDF to Files, AirDrop it, or send it on.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.large])
        .task {
            let pts = await repo.series(key: "stress", source: "my-whoop")
            stressByDay = Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
    }

    @MainActor
    private func export(_ doc: TrendsReportDocument) {
        guard !exporting else { return }
        exporting = true
        let name = "PHMN-trends-\(doc.report.start)_to_\(doc.report.end).pdf"
        TrendsReportRenderer.exportPDF(pages: doc.pages(), size: TrendsReportDocument.pageSize, suggestedName: name)
        exporting = false
        // The share sheet sits on top of this one; dismissing here would take it down with it (#455).
    }
}
#endif
