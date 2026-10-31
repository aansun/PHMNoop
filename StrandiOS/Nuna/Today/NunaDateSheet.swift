#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Choose a day: a month grid whose day numbers are coloured by that day's Charge (red below 34, yellow 34-66, green above 66). The day being
/// viewed is circled, today is a filled circle, and tapping a day opens it. Past days are view-only; picking one never edits data.
struct NunaDateSheet: View {
    @Binding var dayOffset: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @State private var month = Date()

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var viewed: Date { cal.date(byAdding: .day, value: -dayOffset, to: today) ?? today }
    private var rows: [String: DailyMetric] { Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, l in l }) }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(verbatim: monthTitle).font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer()
                arrow("chevron.left", enabled: true) { shiftMonth(-1) }
                arrow("chevron.right", enabled: !isCurrentMonth) { shiftMonth(1) }
            }
            let symbols = weekdaySymbols
            HStack(spacing: 0) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(verbatim: symbols[i].uppercased()).font(.nuna(size: 11.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, d in dayCell(d) }
            }
            HStack(spacing: 14) {
                Spacer()
                legend(NunaPalette.scoreLow, "<34%"); legend(NunaPalette.scoreMid, "34%–66%"); legend(NunaPalette.scoreHigh, ">66%")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 26).padding(.bottom, 20)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { month = viewed }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(!enabled)
    }

    @ViewBuilder private func dayCell(_ date: Date?) -> some View {
        if let date {
            let isFuture = date > today
            let isToday = cal.isDate(date, inSameDayAs: today)
            let isViewed = cal.isDate(date, inSameDayAs: viewed)
            let charge = rows[Repository.localDayKey(date)]?.recovery
            Button { open(date) } label: {
                Text(verbatim: "\(cal.component(.day, from: date))")
                    .font(.nuna(size: 17, weight: .semibold, design: NunaType.design))
                    .foregroundStyle(isFuture ? NunaPalette.textMuted.opacity(0.45) : (charge.map(nunaChargeColor) ?? NunaPalette.textSecondary))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(isToday ? NunaPalette.textPrimary.opacity(0.14) : Color.clear))
                    .overlay(Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: isViewed ? 2 : 0))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain).disabled(isFuture)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(verbatim: text).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    // MARK: Helpers

    private func open(_ date: Date) {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day ?? 0
        dayOffset = max(0, days)
        dismiss()
    }

    private func shiftMonth(_ by: Int) { month = cal.date(byAdding: .month, value: by, to: month) ?? month }

    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: today, toGranularity: .month) }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: month)
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        let s = f.shortStandaloneWeekdaySymbols ?? []
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
}
#endif
