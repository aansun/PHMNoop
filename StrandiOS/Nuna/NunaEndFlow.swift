#if os(iOS)
import SwiftUI
import StrandDesign

/// What is being ended, for the words of the two popups.
enum NunaEndSubject {
    case session, workout
    var discardTitle: LocalizedStringKey { self == .workout ? "Discard workout" : "Discard session" }
    var discardMessage: LocalizedStringKey {
        self == .workout ? "You will lose all of your data from this workout. Are you sure you want to discard it?"
                         : "You will lose all of your data from this session. Are you sure you want to discard it?"
    }
}

extension View {
    /// What End does on a running activity, as on WHOOP: a sheet from the bottom with the two choices (end and save, or discard), and, for discard, a
    /// second question in the middle of the screen before anything is thrown away. Backing out of either leaves the activity as it was.
    func nunaEndFlow(isPresented: Binding<Bool>, subject: NunaEndSubject = .session, save: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        modifier(NunaEndFlow(isPresented: isPresented, subject: subject, save: save, discard: discard))
    }

    /// The question in the middle of the screen before a discard: the data goes if the answer is Discard.
    func nunaDiscardModal(isPresented: Binding<Bool>, title: LocalizedStringKey, message: LocalizedStringKey, discard: @escaping () -> Void) -> some View {
        overlay { NunaDiscardModal(isPresented: isPresented, title: title, message: message, discard: discard) }
    }
}

private struct NunaEndFlow: ViewModifier {
    @Binding var isPresented: Bool
    let subject: NunaEndSubject
    let save: () -> Void
    let discard: () -> Void
    private enum Choice { case save, discard }
    /// Picked in the sheet and carried out once it has gone, so one screen is not taken down while another is still leaving.
    @State private var choice: Choice?
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                let c = choice; choice = nil
                switch c { case .save: save(); case .discard: asking = true; case nil: break }
            }) {
                VStack(spacing: 12) {
                    option(NunaIcons.finish, "End and save") { choice = .save; isPresented = false }
                    option(NunaIcons.discard, "Discard") { choice = .discard; isPresented = false }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 34).frame(maxHeight: .infinity, alignment: .top)
                .background(NunaBackdrop())
                .preferredColorScheme(NunaTheme.colorScheme)
                .nunaSheetChrome(detents: [.height(222)])
            }
            .nunaDiscardModal(isPresented: $asking, title: subject.discardTitle, message: subject.discardMessage, discard: discard)
    }

    private func option(_ icon: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                NunaGlyph(icon, pointSize: 22, weight: .regular).foregroundStyle(NunaPalette.textPrimary).frame(width: 34)
                Text(title).font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).frame(height: 64)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NunaDiscardModal: View {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let discard: () -> Void

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.62).ignoresSafeArea().contentShape(Rectangle()).onTapGesture {}
                VStack(spacing: 18) {
                    Text(title).font(.nuna(size: 19, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(message).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        Button { isPresented = false; discard() } label: {
                            Text("Discard").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.onAccent)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        Button { isPresented = false } label: {
                            Text("Cancel").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 2))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22).padding(.vertical, 26).frame(maxWidth: 340)
                .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented)
        .allowsHitTesting(isPresented)
    }
}
#endif
