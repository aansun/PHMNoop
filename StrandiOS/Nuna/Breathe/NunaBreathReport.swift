#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The report after a session: what the body did while the wearer breathed, in the strap's own numbers, with a short reading of it.
struct NunaBreathReportView: View {
    let record: NunaBreathRecord
    var readOnly = false
    let onDone: () -> Void
    var onAgain: (() -> Void)?
    @State private var showAnya = false

    private var template: BreathTemplate? { record.templateId.flatMap(BreathTemplates.template(id:)) }
    private var title: String {
        template?.title ?? BreathProtocolCatalog.protocolById(record.protocolId).map { String(localized: String.LocalizationValue($0.title)) } ?? record.protocolId
    }
    private var goal: BreathGoal { BreathGoal(rawValue: record.goal) ?? .calm }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(readOnly ? "Session" : "Session complete").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: title).font(.nuna(size: NunaTypeSize.h1, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: dateText).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    Button(action: onDone) {
                        Text(readOnly ? "Close" : "Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                verdictCard
                HStack(spacing: 10) {
                    stat("Time", clock(record.seconds), "")
                    stat("Breaths", "\(record.breaths)", "")
                    stat("Pace", pace, "br/min")
                }
                metricCard("Heart rate", series: record.hrSeries, color: NunaPalette.alertText, unit: "bpm",
                           lines: [("Start", record.hrStart), ("End", record.hrEnd), ("Average", record.hrAvg)])
                metricCard("HRV (RMSSD)", series: record.rmssdSeries, color: NunaPalette.restLight, unit: "ms",
                           lines: [("Start", record.rmssdStart), ("Average", record.rmssdAvg), ("Peak", record.rmssdPeak)])
                if !record.haptics {
                    Text("This session ran without strap haptics, so the pace was followed by sight only.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Button { showAnya = true } label: {
                    HStack(spacing: 12) { AnyaIconTile(); NunaListRow("Ask Anya about this session", description: "She remembers your sessions in Breathing", showsChevron: true) }
                }.buttonStyle(.plain)
                if let onAgain {
                    Button(action: onAgain) {
                        HStack(spacing: 8) { Image(systemName: "arrow.clockwise").font(.nuna(size: 15, weight: .bold)); Text("Breathe again").font(.nuna(size: 17, weight: .bold)) }
                            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Text("An estimate for relaxation, not a medical reading.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .sheet(isPresented: $showAnya) { NunaAnyaSheet(context: "Breathing") }
    }

    // MARK: Parts

    private var verdictCard: some View {
        let v = Self.verdict(record)
        return NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AnyaMark(size: 18).foregroundStyle(NunaPalette.textSecondary)
                    Text("Anya's reading").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let p = record.rmssdChangePct { NunaChip(verbatim: String(format: "%+.0f%% HRV", locale: AppLanguage.activeLocale, p), color: p >= 5 ? NunaPalette.charge : nil) }
                }
                Text(verbatim: v.headline).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let d = v.detail { Text(verbatim: d).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
            }
        }
    }

    /// A reading worked out from this session's own numbers.
    static func verdict(_ r: NunaBreathRecord) -> (headline: String, detail: String?) {
        var detail: [String] = []
        if let a = r.hrStart, let b = r.hrEnd, a - b >= 3 {
            detail.append(String(localized: "Heart rate came down from \(Int(a.rounded())) to \(Int(b.rounded())) bpm."))
        } else if let a = r.hrStart, let b = r.hrEnd, b - a >= 3 {
            detail.append(String(localized: "Heart rate rose from \(Int(a.rounded())) to \(Int(b.rounded())) bpm, which is normal for energising or focus breathing."))
        }
        guard let p = r.rmssdChangePct else {
            return (String(localized: "No HRV was recorded this time"),
                    ([String(localized: "Wear the strap snug and sit still so it can pick up your beats.")] + detail).joined(separator: " "))
        }
        if p >= 10 { return (String(localized: "Your HRV rose \(Int(p.rounded()))% while you breathed. Your body settled."), detail.joined(separator: " ").nilIfEmpty) }
        if p <= -10 { return (String(localized: "Your HRV was \(Int(abs(p).rounded()))% lower than at the start."),
                              ([String(localized: "That can happen with focus or energising techniques, or when you were already calm. A longer exhale tends to lift it.")] + detail).joined(separator: " ")) }
        return (String(localized: "Your HRV stayed close to where it began."),
                ([String(localized: "Short sessions often change little. Try ten minutes at a slower pace.")] + detail).joined(separator: " "))
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
                }
            }
        }
    }

    private func metricCard(_ title: LocalizedStringKey, series: [Double], color: Color, unit: String, lines: [(LocalizedStringKey, Double?)]) -> some View {
        let vals = series.filter { $0 > 0 }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if vals.count >= 3 {
                    NunaSpark(values: vals, color: color).frame(height: 70)
                    HStack {
                        Text(verbatim: "0:00"); Spacer(); Text(verbatim: clock(record.seconds))
                    }.font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    NunaDivider()
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l.0).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                                Text(verbatim: l.1.map { String(format: "%.0f", $0) } ?? "–").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text("Not enough readings from the strap in this session.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    private var pace: String {
        record.seconds > 0 && record.breaths > 0 ? String(format: "%.1f", locale: AppLanguage.activeLocale, Double(record.breaths) / (Double(record.seconds) / 60)) : "–"
    }
    private var dateText: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: record.date) + " · " + goal.shortTitle
    }
    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

/// Every session, newest first, with the week at a glance.
struct NunaBreathHistoryView: View {
    let onClose: () -> Void
    @State private var records = NunaBreathLog.all()
    @State private var opened: NunaBreathRecord?

    private var week: [NunaBreathRecord] { records.filter { $0.startTs >= Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                HStack {
                    Text("Breathing history").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                if records.isEmpty {
                    NunaCard { Text("No sessions yet. Finish one and it appears here with its report.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                } else {
                    HStack(spacing: 10) {
                        tile("Last 7 days", "\(week.count)", String(localized: "sessions"))
                        tile("Time", "\(week.reduce(0) { $0 + $1.seconds } / 60)", "min")
                        let moves = week.compactMap(\.rmssdChangePct)
                        tile("HRV move", moves.isEmpty ? "–" : String(format: "%+.0f", moves.reduce(0, +) / Double(moves.count)), "%")
                    }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { NunaDivider() }
                                Button { opened = r } label: { row(r) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .sheet(item: $opened) { r in
            NunaBreathReportView(record: r, readOnly: true, onDone: { opened = nil }).nunaSheetChrome(detents: [.large])
        }
    }

    private func tile(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
            }
        }
    }

    private func row(_ r: NunaBreathRecord) -> some View {
        let goal = BreathGoal(rawValue: r.goal) ?? .calm
        let name = r.templateId.flatMap { BreathTemplates.template(id: $0)?.title } ?? r.protocolId
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; f.timeStyle = .short
        return HStack(spacing: 12) {
            NunaIconTile(goal.icon, tint: goal.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(f.string(from: r.date)) · \(r.durationText)").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 6)
            if let p = r.rmssdChangePct {
                NunaChip(verbatim: String(format: "%+.0f%%", locale: AppLanguage.activeLocale, p), color: p >= 5 ? NunaPalette.charge : nil)
            }
            Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
#endif
