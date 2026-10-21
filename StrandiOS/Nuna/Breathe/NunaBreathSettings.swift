#if os(iOS)
import SwiftUI
import StrandDesign

/// The Breathing module's options: how a session is cued, how long it runs, what Anya does here and what is kept.
struct NunaBreathSettingsView: View {
    let onAdvanced: () -> Void
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
                    NunaToggleRow("Strap haptics", subtitle: "One pulse on the inhale, two on the exhale", systemImage: "applewatch.radiowaves.left.and.right", isOn: $haptics).padding(.vertical, 8)
                    NunaDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.wave.2").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 24)
                            Text("Audio cues").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        NunaSegmented(NunaBreathAudioMode.allCases.map { (value: $0.rawValue, title: $0.title) }, selection: Binding(
                            get: { NunaBreathAudioMode.stored.rawValue }, set: { audioModeRaw = $0 }))
                        Text("Tones: a soft tone for each step, a double blip for a hold, muted by the silent switch. Anya's voice: each step said aloud, also with the screen locked.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }.padding(.vertical, 10)
                    NunaDivider()
                    NunaToggleRow("Countdown", subtitle: "Three seconds to settle before the first breath", systemImage: "timer", isOn: $countdown).padding(.vertical, 8)
                }
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("Session length")
                    NunaSegmented([(value: 0, title: "Template"), (value: 5, title: "5 min"), (value: 10, title: "10 min"), (value: 15, title: "15 min")], selection: $length)
                    Text("Template uses each exercise's own length. A fixed length applies to every template.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
                        NunaListRow("Resonance and Calm me", description: "The strap-led modes", systemImage: "waveform.path", showsChevron: true)
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
