#if os(iOS)
import SwiftUI
import StrandDesign

/// Date picker for Today. Picking a past day only changes what is displayed; it never edits data.
struct NunaDateSheet: View {
    @Binding var dayOffset: Int
    @Environment(\.dismiss) private var dismiss
    @State private var picked = Date()

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a day")
                .font(.system(size: NunaTypeSize.h2, weight: .bold, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
                .padding(.top, 20)
            HStack(spacing: 8) {
                shortcut("Today", 0)
                shortcut("Yesterday", 1)
                shortcut("7 days ago", 7)
            }
            NunaCard(small: true) {
                DatePicker("", selection: $picked, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .tint(NunaPalette.charge)
                    .environment(\.locale, AppLanguage.activeLocale)
            }
            Button("Show this day") { apply(picked) }.buttonStyle(.nuna(.primary, fullWidth: true))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { picked = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    }

    private func shortcut(_ title: LocalizedStringKey, _ offset: Int) -> some View {
        Button { dayOffset = offset; dismiss() } label: { Text(title).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity) }
            .buttonStyle(.nuna(dayOffset == offset ? .primary : .ghost, height: 40))
    }

    private func apply(_ date: Date) {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        dayOffset = max(0, days)
        dismiss()
    }
}
#endif
