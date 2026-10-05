#if os(iOS)
import SwiftUI
import StrandDesign

/// The Breathing module's options: how a session is cued, how long it runs, what Anya does here and what is kept.
struct NunaBreathSettingsView: View {
    let onAdvanced: () -> Void
    let onClose: () -> Void
    @AppStorage(NunaBreathPrefs.hapticsKey) private var haptics = true
    @AppStorage(NunaBreathPrefs.audioKey) private var audio = false
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
                    NunaToggleRow("Strap haptics", subtitle: "One pulse on the inhale, two on the exhale", systemImage: "applewatch.radiowaves.left.and.right", isOn: $haptics).padding(.vertical, 8)
                    NunaDivider()
                    NunaToggleRow("Audio cues", subtitle: "A soft tone on each phase, muted by the silent switch", systemImage: "speaker.wave.2", isOn: $audio).padding(.vertical, 8)
                    NunaDivider()
                    NunaToggleRow("Countdown", subtitle: "Three seconds to settle before the first breath", systemImage: "timer", isOn: $countdown).padding(.vertical, 8)
                }
                VStack(alignment: .leading, spacing: 10) {
                    nunaTrendsCap("Session length")
                    NunaSegmented([(value: 0, title: "Template"), (value: 5, title: "5 min"), (value: 10, title: "10 min"), (value: 15, title: "15 min")], selection: $length)
                    Text("Template uses each exercise's own length. A fixed length applies to every template.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaSettingsGroup("Anya") {
                    NunaToggleRow("Suggest an exercise", subtitle: "Reads your heart rate, HRV, stress and Charge", systemImage: NunaGlyph.anya, isOn: $anya).padding(.vertical, 8)
                    NunaDivider()
                    Button { confirmForget = true } label: {
                        NunaListRow("Forget what Anya remembers here", subtitle: LocalizedStringKey(String(localized: "\(memoryCount) notes, kept only in Breathing")), systemImage: "brain", showsChevron: false)
                    }.buttonStyle(.plain).disabled(memoryCount == 0).opacity(memoryCount == 0 ? 0.5 : 1)
                }
                NunaSettingsGroup("Sessions") {
                    Button { confirmClear = true } label: {
                        NunaListRow("Clear history", subtitle: LocalizedStringKey(String(localized: "\(sessionCount) sessions on this phone")), systemImage: "trash", showsChevron: false)
                    }.buttonStyle(.plain).disabled(sessionCount == 0).opacity(sessionCount == 0 ? 0.5 : 1)
                    NunaDivider()
                    Button(action: onAdvanced) {
                        NunaListRow("Resonance and Calm me", subtitle: "The strap-led modes", systemImage: "waveform.path", showsChevron: true)
                    }.buttonStyle(.plain)
                }
                nunaFootnote("Sessions, reports and Anya's notes stay on this iPhone. Anya's notes reach a provider only inside a question you ask in Breathing, and only if you allowed data access.")
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .alert("Forget Anya's notes in Breathing?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { NunaAnyaMemory.clear(.breathing); memoryCount = 0 }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your sessions stay. Only what Anya noted from them and from your questions is removed.") }
        .alert("Clear the breathing history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { NunaBreathLog.clear(); sessionCount = 0 }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every session and report is deleted from this phone. This cannot be undone.") }
    }
}
#endif
