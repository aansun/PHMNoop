#if os(iOS)
import SwiftUI
import StrandDesign

/// The Breathing module's options, kept to what changes a session: its cues, its length, Anya's pick and the data.
///
/// Laid out like Appearance: one small heading for each thing the page does, and under it one card for each setting, so a card is one choice and nothing
/// shares a card with something else. A switch stays a switch. A choice among several (the audio cues, the session length) is a single row that shows the
/// choice in force and opens the same bottom sheet the app's other drop-downs use, instead of laying every option out on the page.
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
                header
                section("Haptics") {
                    card { NunaToggleRow("Strap haptics", systemImage: "applewatch.radiowaves.left.and.right", isOn: $haptics).padding(.vertical, 4) }
                }
                section("Audio") {
                    card {
                        NunaChoiceRow("Audio cues", systemImage: "speaker.wave.2",
                                      options: NunaBreathAudioMode.allCases.map { (value: $0.rawValue, title: $0.title) },
                                      selection: Binding(get: { NunaBreathAudioMode.stored.rawValue }, set: { audioModeRaw = $0 }))
                    }
                }
                section("Session") {
                    card { NunaToggleRow("Countdown", systemImage: "timer", isOn: $countdown).padding(.vertical, 4) }
                    card {
                        NunaChoiceRow("Session length", systemImage: "clock",
                                      options: [(value: 0, title: "Default"), (value: 5, title: "5 min"), (value: 10, title: "10 min"), (value: 15, title: "15 min")],
                                      selection: $length)
                    }
                }
                section("Anya") {
                    card { NunaToggleRow("Suggest an exercise", systemImage: NunaGlyph.anya, isOn: $anya).padding(.vertical, 4) }
                }
                section("Data") {
                    card {
                        Button { confirmForget = true } label: {
                            NunaListRow("Forget Anya's notes", subtitle: LocalizedStringKey(String(localized: "\(memoryCount) notes")), systemImage: "brain", showsChevron: false)
                        }.buttonStyle(.plain).disabled(memoryCount == 0).opacity(memoryCount == 0 ? 0.5 : 1)
                    }
                    card {
                        Button { confirmClear = true } label: {
                            NunaListRow("Clear history", subtitle: LocalizedStringKey(String(localized: "\(sessionCount) sessions")), systemImage: "trash", showsChevron: false)
                        }.buttonStyle(.plain).disabled(sessionCount == 0).opacity(sessionCount == 0 ? 0.5 : 1)
                    }
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

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("Breathing settings").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 38)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    /// A heading and the cards under it, one card to a setting.
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader(title)
            content()
        }
    }

    /// The card every setting sits in, inset like the cards on the Appearance page.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { content() }
    }
}
#endif
