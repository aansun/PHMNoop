#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The report after a session, laid out like a workout's log: the technique and when it ran in the header (the actions behind the three dots), the HRV
/// move and the time as the two big figures, an Anya line that reads the session, the key statistics together (each against the wearer's 30-day average of
/// the same technique), then the heart-rate and HRV curves in the strap's own numbers.
struct NunaBreathReportView: View {
    let record: NunaBreathRecord
    var readOnly = false
    let onDone: () -> Void
    var onAgain: (() -> Void)?
    @State private var showAnya = false
    @State private var confirmDelete = false
    /// The two halves of the detail: the key statistics, and the strap's curves.
    @State private var tab = Tab.stats
    private enum Tab: Hashable { case stats, curves }

    private var title: String { record.displayTitle }
    private var goal: BreathGoal { BreathGoal(rawValue: record.goal) ?? .calm }
    private var end: Int { record.startTs + record.seconds }

    var body: some View {
        let averages = NunaBreathAverages(for: record, in: NunaBreathLog.all())
        NunaDetailScreen(LocalizedStringKey(title), titleSymbol: "lungs.fill", subtitle: NunaWorkoutFormat.span(record.startTs, end), titleActivity: goal.activity,
                         trailing: AnyView(actionsMenu), onBack: onDone) {
            figures(averages)
            let v = Self.verdict(record)
            NunaAnyaCard(verbatim: v.headline, detail: v.detail) { showAnya = true }
            if hasCurves {
                NunaCapsuleTabs(options: [(value: Tab.stats, title: "Key statistics"), (value: Tab.curves, title: "Heart rate")], selection: $tab)
                if tab == .stats { keyStatistics(averages) } else { charts }
            } else {
                keyStatistics(averages)
                charts
            }
            if !record.haptics {
                Text("This session ran without strap haptics, so the pace was followed by sight only.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            if let onAgain {
                Button(action: onAgain) {
                    HStack(spacing: 8) { Image(systemName: "arrow.clockwise").font(.nuna(size: 15, weight: .bold)); Text("Breathe again").font(.nuna(size: 17, weight: .bold)) }
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
            }
            Text("An estimate for relaxation, not a medical reading.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .sheet(isPresented: $showAnya) { NunaAnyaSheet(context: "Breathing") }
        .nunaDialog("Delete this session?", isPresented: $confirmDelete) {
            NunaDialogButton("Delete", role: .destructive) { NunaBreathLog.delete(record.id); onDone() }
            NunaDialogButton("Cancel", role: .cancel) {}
        }
    }

    // MARK: Parts

    private var actionsMenu: some View {
        NunaActionsButton(items: [
            NunaActionItem(title: "Ask Anya about this session", symbol: "sparkles") { showAnya = true },
            NunaActionItem(title: "Delete", symbol: "trash", destructive: true) { confirmDelete = true },
        ])
    }

    /// The two figures the report opens with: how far HRV moved and how long the session ran, the time with the 30-day average beside it.
    private func figures(_ averages: NunaBreathAverages?) -> some View {
        let p = record.rmssdChangePct
        return HStack(alignment: .top, spacing: 16) {
            NunaLogFigure(label: "HRV move", value: p.map { String(format: "%+.0f%%", locale: AppLanguage.activeLocale, $0) } ?? "–",
                          color: (p ?? 0) >= 5 ? NunaPalette.charge : NunaPalette.textPrimary)
            NunaLogFigure(label: "Time", value: NunaWorkoutLogFigures.clock(Double(record.seconds)),
                          pill: averages?.seconds.map { NunaAveragePill(value: Double(record.seconds), average: $0, text: NunaWorkoutLogFigures.clock($0)) })
        }
    }

    private struct Stat: Identifiable {
        let id: String; let icon: String; let label: LocalizedStringKey; let value: String; let unit: String
        var pill: (value: Double, average: Double, text: String)?
    }

    private func pill(_ value: Double?, _ average: Double?, _ unit: String, decimals: Int = 0) -> (value: Double, average: Double, text: String)? {
        guard let value, let average else { return nil }
        return (value, average, String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, average) + " " + unit)
    }

    private var stats: [Stat] {
        let a = NunaBreathAverages(for: record, in: NunaBreathLog.all())
        func whole(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "–" }
        // Grouped by what they measure, three to a row: the heart rate (start, end, average), the HRV (start, peak, average), and last what belongs to neither.
        var out: [Stat] = []
        if record.hrStart != nil { out.append(Stat(id: "hrStart", icon: NunaIcons.heartRate, label: "Start HR", value: whole(record.hrStart), unit: "bpm")) }
        if record.hrEnd != nil { out.append(Stat(id: "hrEnd", icon: NunaIcons.heartRate, label: "End HR", value: whole(record.hrEnd), unit: "bpm")) }
        if record.hrAvg != nil { out.append(Stat(id: "hrAvg", icon: NunaIcons.avgHr, label: "Avg HR", value: whole(record.hrAvg), unit: "bpm", pill: pill(record.hrAvg, a?.hrAvg, "bpm"))) }
        if record.rmssdStart != nil { out.append(Stat(id: "hrvStart", icon: NunaIcons.hrv, label: "Start HRV", value: whole(record.rmssdStart), unit: "ms")) }
        if record.rmssdPeak != nil { out.append(Stat(id: "hrvPeak", icon: NunaIcons.hrv, label: "Peak HRV", value: whole(record.rmssdPeak), unit: "ms")) }
        if record.rmssdAvg != nil { out.append(Stat(id: "hrvAvg", icon: NunaIcons.hrv, label: "Avg HRV", value: whole(record.rmssdAvg), unit: "ms", pill: pill(record.rmssdAvg, a?.rmssdAvg, "ms"))) }
        out.append(Stat(id: "breaths", icon: NunaIcons.breathing, label: "Breaths", value: "\(record.breaths)", unit: ""))
        if let pace = record.pace {
            out.append(Stat(id: "pace", icon: "speedometer", label: "Pace", value: String(format: "%.1f", locale: AppLanguage.activeLocale, pace), unit: "/min",
                            pill: pill(pace, a?.pace, "br/min", decimals: 1)))
        }
        return out
    }

    private func keyStatistics(_ averages: NunaBreathAverages?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Under the tabs the tab already names the block; only the comparison is left to say.
            if hasCurves {
                if averages != nil {
                    Text("vs. 30 day average").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingHead(0.4)).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                NunaLogSectionTitle(title: "Key statistics", trailing: averages != nil ? "vs. 30 day average" : nil)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(stats) { NunaLogStatTile(icon: $0.icon, label: $0.label, value: $0.value, unit: $0.unit, pill: $0.pill) }
            }
        }
    }

    /// The readings of a series as points on the session's own clock; a stretch the strap missed is left out.
    private func points(_ series: [Double]) -> [HRBucket] {
        series.enumerated().compactMap { i, v in v > 0 ? HRBucket(ts: record.startTs + i * record.step, bpm: v, minBpm: v, maxBpm: v) : nil }
    }

    private var hr: [HRBucket] { points(record.hrSeries) }
    private var hrv: [HRBucket] { points(record.rmssdSeries) }
    /// The strap read enough of either curve to draw it; without, the report is the figures and the statistics alone.
    private var hasCurves: Bool { hr.count >= 3 || hrv.count >= 3 }

    /// The strap's two curves through the session, each between the marks of its start and end (the heart rate is the tab's own name; the HRV is named
    /// when both are there). A curve with too few
    /// readings is left out, and when both are, one line says so.
    @ViewBuilder private var charts: some View {
        let both = hr.count >= 3 && hrv.count >= 3
        if hr.count >= 3 { chart(nil, points: hr, tint: NunaWorkoutLogZones.hrBlue, step: 25) }
        if hrv.count >= 3 { chart(both ? "HRV (RMSSD)" : nil, points: hrv, tint: NunaPalette.restLight, step: 20) }
        if !hasCurves {
            Text("Not enough readings from the strap in this session.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    private func chart(_ title: LocalizedStringKey?, points: [HRBucket], tint: Color, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { NunaLogSectionTitle(title: title) }
            NunaWorkoutHRArea(buckets: points, start: record.startTs, end: max(end, record.startTs + 1), step: step, tint: tint)
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
}

/// The wearer's own 30-day average of one technique, from their other sessions of it. nil under two sessions: an average of one is the session itself.
private struct NunaBreathAverages {
    let seconds: Double?, hrAvg: Double?, rmssdAvg: Double?, pace: Double?

    init?(for r: NunaBreathRecord, in all: [NunaBreathRecord]) {
        let from = r.startTs - 30 * 86_400
        let others = all.filter { $0.id != r.id && $0.displayTitle == r.displayTitle && $0.startTs >= from && $0.startTs < r.startTs }
        guard others.count >= 2 else { return nil }
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        seconds = mean(others.map { Double($0.seconds) })
        hrAvg = mean(others.compactMap(\.hrAvg))
        rmssdAvg = mean(others.compactMap(\.rmssdAvg))
        pace = mean(others.compactMap(\.pace))
    }
}

private extension NunaBreathRecord {
    /// Breaths a minute over the whole session.
    var pace: Double? { seconds > 0 && breaths > 0 ? Double(breaths) / (Double(seconds) / 60) : nil }
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
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .sheet(item: $opened, onDismiss: { records = NunaBreathLog.all() }) { r in
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
        let name = r.displayTitle
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; f.timeStyle = .short
        return HStack(spacing: 12) {
            NunaActivityGlyph(name: goal.activity, size: 24).foregroundStyle(goal.tint).frame(width: 30)
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
