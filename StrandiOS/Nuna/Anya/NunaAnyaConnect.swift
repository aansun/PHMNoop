#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Connect Anya (AnyaConnect.dc)

/// Pick the AI provider Anya talks through. Apple Intelligence runs on this iPhone with no key or account; the rest are
/// the wearer's own account or key. Nothing leaves the phone until a provider is connected, data access is allowed and a
/// question is asked.
struct NunaAnyaConnectView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chatGPT = ChatGPTAuthModel.shared

    var body: some View {
        NunaDetailScreen("Connect Anya") {
            Text("Anya uses the AI provider you choose. Your key is kept in the Keychain and does not leave this iPhone.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            group("No key") {
                Button { choose(.appleIntelligence) } label: {
                    row(icon: "apple.intelligence", title: "Apple Intelligence", subtitle: coach.appleIntelligenceUnavailableReason ?? String(localized: "On this iPhone. No account, no key, no network."),
                        badge: AppleIntelligenceClient.isAvailable ? String(localized: "Recommended") : nil, selected: coach.provider == .appleIntelligence && coach.isConfigured)
                }.buttonStyle(.plain).disabled(!AppleIntelligenceClient.isAvailable)
            }
            group("Account") {
                NavigationLink(value: NunaAnyaRoute.chatGPT) {
                    row(icon: "person.crop.circle", title: "ChatGPT (sign in)", subtitle: String(localized: "Sign in with your ChatGPT account using a one-time device code."),
                        selected: coach.provider == .chatGPT && coach.isConfigured)
                }.buttonStyle(.plain)
            }
            group("Your own API key") {
                keyRow(.anthropic, String(localized: "Paste a key, pick a Claude model."))
                NunaDivider()
                keyRow(.openAI, String(localized: "Paste a key, pick a GPT model."))
                NunaDivider()
                keyRow(.gemini, String(localized: "Can also send chart images."))
            }
            group("Advanced") {
                NavigationLink(value: NunaAnyaRoute.custom) {
                    row(icon: "server.rack", title: "Your own server", subtitle: String(localized: "Ollama, LM Studio, llama.cpp, or any OpenAI-compatible gateway."),
                        selected: coach.provider == .custom && coach.isConfigured)
                }.buttonStyle(.plain)
            }
            NunaCard(small: true) {
                NunaToggleRow("Let Anya use my numbers", subtitle: "Summaries of your computed scores, not raw data", systemImage: "lock.open", isOn: $coach.dataConsent).padding(.vertical, 8)
            }
            Text("Only a text summary of numbers already computed on this iPhone is sent to your chosen provider, and only after you allow it and ask. Raw heartbeat intervals, PPG and motion are never sent.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: coach.isConfigured) { _, ok in if ok { dismiss() } }
    }

    private func choose(_ p: AIProvider) {
        coach.provider = p
        if coach.isConfigured { dismiss() }
    }

    private func keyRow(_ p: AIProvider, _ subtitle: String) -> some View {
        NavigationLink(value: NunaAnyaRoute.apiKey(p.rawValue)) {
            row(icon: "key", title: LocalizedStringKey(p.displayName), subtitle: subtitle, selected: coach.provider == p && coach.isConfigured)
        }.buttonStyle(.plain)
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).padding(.leading, 4)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { VStack(spacing: 0) { content() } }
        }
    }

    private func row(icon: String, title: LocalizedStringKey, subtitle: String, badge: String? = nil, selected: Bool) -> some View {
        HStack(spacing: 14) {
            NunaIconTile(icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: subtitle).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let badge { NunaChip(verbatim: badge).fixedSize().padding(.top, 2) }
            }
            Spacer(minLength: 4)
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right").font(.nuna(size: selected ? 20 : 13, weight: .bold))
                .foregroundStyle(selected ? NunaPalette.charge : NunaPalette.textMuted)
        }.padding(.vertical, 14).contentShape(Rectangle())
    }
}

// MARK: - API key (AnyaKey.dc)

struct NunaAnyaKeyView: View {
    let provider: AIProvider
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var customModel = ""
    @State private var checking = false
    @State private var checked: Int?

    private var saved: Bool { coach.provider == provider && coach.hasKey && AIKeyStore.ownerProvider == provider.rawValue }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(provider.displayName)) {
            NunaCard(small: true) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(NunaPalette.textPrimary)
                    Text("The key is kept in this iPhone's Keychain.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            NunaFormField("API key") {
                NunaKeyField(text: $key, placeholder: saved ? "••••••••••••••••" : "Paste your key", savedKey: saved ? AIKeyStore.read() : nil, showsPaste: true)
            }
            if saved {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(NunaPalette.charge)
                    Text(checked.map { String(localized: "Key accepted · \($0) models found") } ?? String(localized: "A key is saved for this provider")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Spacer()
                    Button { Task { await check() } } label: {
                        Text(checking ? "Checking…" : "Check key").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    }.buttonStyle(.plain).disabled(checking)
                }
            }
            modelCard
            NunaCard(small: true) {
                NunaToggleRow("Let Anya use my numbers", subtitle: "Summaries of computed scores, not raw data", systemImage: "lock.open", isOn: $coach.dataConsent).padding(.vertical, 8)
            }
            Text("Usage is billed by the provider to your account. The key only leaves this iPhone to reach this provider.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
            if let e = coach.errorText, !e.isEmpty {
                Text(verbatim: e).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Button { save() } label: {
                Text("Save and start").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty && !saved).opacity(key.trimmingCharacters(in: .whitespaces).isEmpty && !saved ? 0.4 : 1)
            if saved {
                Button(role: .destructive) { coach.clearKey() } label: {
                    Text("Remove the key").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if coach.provider != provider { coach.provider = provider } }
        .onChange(of: coach.isConfigured) { _, ok in if ok { dismiss() } }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Button { Task { await check() } } label: {
                    Label("Reload the list", systemImage: "arrow.clockwise").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain).disabled(!saved || checking)
            }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(coach.availableModels.prefix(12).enumerated()), id: \.element) { i, m in
                        if i > 0 { NunaDivider() }
                        Button { coach.model = m } label: {
                            HStack {
                                Text(verbatim: m).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Image(systemName: coach.model == m ? "checkmark.circle.fill" : "circle").font(.nuna(size: 20)).foregroundStyle(coach.model == m ? NunaPalette.textPrimary : NunaPalette.textMuted)
                            }.padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    NunaDivider()
                    HStack {
                        TextField("", text: $customModel, prompt: Text("Another model id").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.nuna(size: 15.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        Button("Use") { coach.setCustomModel(customModel); customModel = "" }.font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }.padding(.vertical, 12)
                }
            }
        }
    }

    private func save() {
        coach.provider = provider
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !k.isEmpty { coach.setKey(k); key = "" }
    }

    private func check() async {
        checking = true; defer { checking = false }
        await coach.refreshModels()
        checked = coach.errorText == nil ? coach.availableModels.count : nil
    }
}

// MARK: - Your own server (AnyaCustom.dc)

struct NunaAnyaCustomView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var testing = false
    @State private var tested: (count: Int, ms: Int)?

    var body: some View {
        NunaDetailScreen("Your own server") {
            Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp or your own gateway. It stays on your network.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            NunaFormField("Server URL") {
                TextField("", text: $coach.customBaseURL, prompt: Text("http://192.168.1.20:11434/v1").foregroundStyle(NunaPalette.textMuted))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            NunaFormField("Key (optional)") {
                NunaKeyField(text: $key, placeholder: "Only if your server asks for one", savedKey: AIKeyStore.ownerProvider == AIProvider.custom.rawValue ? AIKeyStore.read() : nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Key header").font(.nuna(size: 11, weight: .heavy)).tracking(0.9).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                NunaSegmented([(value: CustomAIAuthHeader.bearer, title: "Bearer"), (value: .xAPIKey, title: "x-api-key")], selection: $coach.customAuthHeader)
                Text("Bearer for most local servers. x-api-key for gateways that want the key in that header.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
            NunaFormField("Model") {
                TextField("", text: $coach.model, prompt: Text("llama3.1:8b").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !coach.availableModels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(coach.availableModels.prefix(12), id: \.self) { m in
                        Button { coach.model = m } label: {
                            Text(verbatim: m).font(.nuna(size: 13, weight: .bold)).foregroundStyle(coach.model == m ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                .padding(.horizontal, 12).frame(height: 34).background(coach.model == m ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    } }
                }
            }
            if let t = tested {
                NunaCard(small: true) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NunaPalette.charge)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: String(localized: "\(t.count) models found · \(t.ms) ms")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer()
                    }
                }
            } else if let e = coach.errorText, !e.isEmpty {
                Text(verbatim: e).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Button { Task { await test() } } label: {
                Text(testing ? "Testing…" : "Test connection").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(testing || urlEmpty)
            Button { save() } label: {
                Text("Save and start").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(urlEmpty).opacity(urlEmpty ? 0.4 : 1)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if coach.provider != .custom { coach.provider = .custom } }
        .onChange(of: coach.isConfigured) { _, ok in if ok { dismiss() } }
    }

    private var urlEmpty: Bool { coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func storeKey() {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !k.isEmpty { coach.setKey(k); key = "" }
    }

    private func test() async {
        testing = true; tested = nil; defer { testing = false }
        storeKey()
        let t0 = Date()
        await coach.refreshModels()
        if coach.errorText == nil, !coach.availableModels.isEmpty { tested = (coach.availableModels.count, Int(Date().timeIntervalSince(t0) * 1000)) }
    }

    private func save() { storeKey(); coach.connectCustom() }
}

// MARK: - Sign in with ChatGPT (AnyaChatGPT.dc)

struct NunaAnyaChatGPTView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = ChatGPTAuthModel.shared

    var body: some View {
        NunaDetailScreen("Sign in to ChatGPT") {
            if auth.isConnected {
                NunaCard(highlight: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) { Image(systemName: "checkmark.seal.fill").foregroundStyle(NunaPalette.charge); Text("ChatGPT connected").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
                        Text("The token is kept in this iPhone's Keychain and refreshed automatically.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(role: .destructive) { auth.logout() } label: {
                    Text("Sign out of ChatGPT").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            } else if let code = auth.deviceCode {
                NunaCard(highlight: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        nunaTrendsCap("Device code")
                        Text(verbatim: code.userCode).font(.nuna(size: 38, weight: .bold, design: .monospaced)).tracking(nunaTrackingLabel).foregroundStyle(NunaPalette.textPrimary).textSelection(.enabled)
                        Text("Open the ChatGPT sign-in page in your browser and enter this code. It is valid for 15 minutes.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { auth.openVerificationPage() } label: {
                    Text("Open the sign-in page").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                Button { UIPasteboard.general.string = code.userCode } label: {
                    Text("Copy the code").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(NunaPalette.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for approval…").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("The app checks every few seconds").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in with your ChatGPT account using a one-time device code, without pasting an API key.")
                            .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Button { auth.startLogin() } label: {
                            Text(auth.isBusy ? "Getting a code…" : "Get a device code").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain).disabled(auth.isBusy)
                    }
                }
            }
            if let e = auth.errorMessage, !e.isEmpty {
                Text(verbatim: e).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Text("The token is kept in Apple's Keychain and refreshed automatically. Sign out any time from Anya settings.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if coach.provider != .chatGPT { coach.provider = .chatGPT }; auth.refreshConnection() }
        .onChange(of: auth.isConnected) { _, ok in if ok { dismiss() } }
    }
}
#endif
