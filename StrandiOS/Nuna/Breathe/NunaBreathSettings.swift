#if os(iOS)
import SwiftUI
import StrandDesign

/// The Breathing module's options, kept to what changes a session: its cues, its length, Anya's pick and the data.
struct NunaBreathSettingsView: View {
    let onClose: () -> Void
    @AppStorage(NunaBreathPrefs.hapticsKey) private var haptics = true
    @AppStorage(NunaBreathAudioMode.key) private var audioModeRaw = ""
    @AppStorage(NunaBreathPrefs.countdownKey) private var countdown = true
    @AppStorage(NunaBreathPrefs.lengthKey) private var length = 0
    @AppStorage(NunaBreathPrefs.anyaKey) private var anya = true
    @State private var memoryCount = NunaAnyaMemory.entries(.breathing).count
    @State private var sessionCount = NunaBreathLog.all().count
    @State private var confirmForget = false
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                HStack {
                    Text("Breathing settings").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                NunaSettingsGroup("Cues") {
                    NunaToggleRow("Strap haptics", systemImage: "applewatch.radiowaves.left.and.right", isOn: $haptics).padding(.vertical, 8)
                    NunaDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.wave.2").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 24)
                            Text("Audio cues").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        NunaSegmented(NunaBreathAudioMode.allCases.map { (value: $0.rawValue, title: $0.title) }, selection: Binding(
                            get: { NunaBreathAudioMode.stored.rawValue }, set: { audioModeRaw = $0 }))
                    }.padding(.vertical, 10)
                    NunaDivider()
                    NunaToggleRow("Countdown", systemImage: "timer", isOn: $countdown).padding(.vertical, 8)
                }
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("Session length")
                    NunaSegmented([(value: 0, title: "Default"), (value: 5, title: "5 min"), (value: 10, title: "10 min"), (value: 15, title: "15 min")], selection: $length)
                }
                NunaSettingsGroup("Anya") {
                    NunaToggleRow("Suggest an exercise", systemImage: NunaGlyph.anya, isOn: $anya).padding(.vertical, 8)
                }
                NunaSettingsGroup("Data") {
                    Button { confirmForget = true } label: {
                        NunaListRow("Forget Anya's notes", subtitle: LocalizedStringKey(String(localized: "\(memoryCount) notes")), systemImage: "brain", showsChevron: false)
                    }.buttonStyle(.plain).disabled(memoryCount == 0).opacity(memoryCount == 0 ? 0.5 : 1)
                    NunaDivider()
                    Button { confirmClear = true } label: {
                        NunaListRow("Clear history", subtitle: LocalizedStringKey(String(localized: "\(sessionCount) sessions")), systemImage: "trash", showsChevron: false)
                    }.buttonStyle(.plain).disabled(sessionCount == 0).opacity(sessionCount == 0 ? 0.5 : 1)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .alert("Forget Anya's notes?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { NunaAnyaMemory.clear(.breathing); memoryCount = 0 }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Clear the breathing history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { NunaBreathLog.clear(); sessionCount = 0 }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }
}
#endif
