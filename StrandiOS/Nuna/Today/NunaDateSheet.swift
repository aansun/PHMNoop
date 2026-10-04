#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Choose a day: a month grid with a Charge-coloured dot on days that have data, quick jumps, and a small
/// summary of the day before opening it. Past days are view-only; picking one never edits data.
struct NunaDateSheet: View {
    @Binding var dayOffset: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var month = Date()
    @State private var picked = Calendar.current.startOfDay(for: Date())
    @State private var restByDay: [String: Double] = [:]

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var rows: [String: DailyMetric] { Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, l in l }) }

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                header
                calendarCard
                jumps
                summary
                Text("Past days are view-only. The journal can still be edited.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear {
            picked = cal.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            month = picked
        }
        .task {
            let s = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", days: 400)
            restByDay = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }
            .accessibilityLabel(Text("Close"))
            Spacer()
            Text("Choose date").font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Button { pick(today) } label: { Text("Today").font(.nuna(size: 13.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: Capsule())
                .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1)) }
        }
    }

    // MARK: Calendar

    private var calendarCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)) {
            VStack(spacing: 12) {
                HStack {
                    arrow("chevron.left", enabled: true) { shiftMonth(-1) }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(verbatim: monthTitle).font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: String(localized: "\(recordedCount) days recorded")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    arrow("chevron.right", enabled: !isCurrentMonth) { shiftMonth(1) }
                }
                let symbols = weekdaySymbols
                HStack(spacing: 0) {
                    ForEach(symbols.indices, id: \.self) { i in
                        Text(verbatim: symbols[i]).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, d in
                        dayCell(d)
                    }
                }
                Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                HStack(spacing: 14) {
                    legend(NunaPalette.charge, "Charge 67+"); legend(NunaPalette.warning, "34–66"); legend(NunaPalette.alert, "0–33")
                    Spacer()
                }
            }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 14, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
        }
        .disabled(!enabled)
    }

    @ViewBuilder private func dayCell(_ date: Date?) -> some View {
        if let date {
            let isFuture = date > today
            let isPicked = cal.isDate(date, inSameDayAs: picked)
            let row = rows[Repository.localDayKey(date)]
            Button { if !isFuture { picked = date } } label: {
                VStack(spacing: 3) {
                    Text(verbatim: "\(cal.component(.day, from: date))")
                        .font(.nuna(size: 15, weight: row != nil ? .heavy : .semibold, design: NunaType.design))
                        .foregroundStyle(isPicked ? NunaPalette.onAccent : (isFuture ? NunaPalette.textMuted.opacity(0.5) : (row != nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)))
                    Circle().fill(dot(row, isPicked)).frame(width: 6, height: 6)
                }
                .frame(width: 42, height: 46)
                .background(isPicked ? NunaPalette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
            .buttonStyle(.plain).disabled(isFuture)
        } else {
            Color.clear.frame(height: 46)
        }
    }

    private func dot(_ row: DailyMetric?, _ isPicked: Bool) -> Color {
        guard let row else { return .clear }
        if let r = row.recovery { return isPicked ? NunaPalette.onAccent : nunaChargeColor(r) }
        return isPicked ? NunaPalette.onAccent : NunaPalette.textMuted
    }

    private func legend(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    // MARK: Jumps and summary

    private var jumps: some View {
        FlowChips {
            jump("Yesterday") { pick(cal.date(byAdding: .day, value: -1, to: today) ?? today) }
            jump("7 days ago") { pick(cal.date(byAdding: .day, value: -7, to: today) ?? today) }
            jump("Start of month") { pick(cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today) }
            jump("Last month") {
                let first = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
                pick(cal.date(byAdding: .month, value: -1, to: first) ?? today)
            }
        }
    }

    private func jump(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 40)
                .background(NunaPalette.glassStrong, in: Capsule()).overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        let key = Repository.localDayKey(picked)
        let row = rows[key]
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return NunaCard(highlight: false) {
            VStack(spacing: 16) {
                HStack {
                    Text("Selected").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(verbatim: longDate(picked))
                }
                HStack {
                    score("Charge", row?.recovery.map { String(format: "%.0f%%", $0) }, row?.recovery.map(nunaChargeColor) ?? NunaPalette.textMuted)
                    score("Effort", row?.strain.map { UnitFormatter.effortDisplay($0, scale: scale) }, NunaPalette.effortText)
                    score("Rest", restByDay[key].map { String(format: "%.0f%%", $0) }, NunaPalette.restText)
                }
                Button { apply() } label: { Text(verbatim: String(localized: "Open \(shortDate(picked))")) }
                    .buttonStyle(.nuna(.primary, height: 52, fullWidth: true))
            }
        }
    }

    private func score(_ label: LocalizedStringKey, _ value: String?, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value ?? "–").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(value == nil ? NunaPalette.textMuted : color)
            Text(label).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private func pick(_ date: Date) { picked = date; month = date }

    private func apply() {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: picked), to: today).day ?? 0
        dayOffset = max(0, days)
        dismiss()
    }

    private func shiftMonth(_ by: Int) { month = cal.date(byAdding: .month, value: by, to: month) ?? month }

    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: today, toGranularity: .month) }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: month)
    }

    private var recordedCount: Int {
        let prefix = String(Repository.localDayKey(month).prefix(7))
        return repo.days.filter { $0.day.hasPrefix(prefix) && ($0.recovery != nil || $0.strain != nil || $0.totalSleepMin != nil) }.count
    }

    private var weekdaySymbols: [String] {
        var f = DateFormatter(); f.locale = AppLanguage.activeLocale
        let s = f.shortStandaloneWeekdaySymbols ?? []
        f = DateFormatter()
        guard s.count == 7 else { return [] }
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    /// Month grid with leading blanks; nil = padding cell.
    private var gridDays: [Date?] {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: start) }
    }

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: d)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMMM")
        return f.string(from: d)
    }
}

/// Wrapping row of chips.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        // Two chips per row fit on a phone; the layout wraps on its own.
        if #available(iOS 16.0, *) {
            WrapLayout(spacing: 10) { content }
        } else {
            HStack { content }
        }
    }
}

@available(iOS 16.0, *)
private struct WrapLayout: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
#endif
