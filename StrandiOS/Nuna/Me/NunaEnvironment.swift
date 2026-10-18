#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Weather and air: your own OpenWeather and IQAir keys in the Keychain, one switch, and a button that reads the place you are in now.
/// Off by default; while it is off, nothing is requested. Only a place rounded to about a kilometre is ever sent.
struct NunaEnvironmentView: View {
    @AppStorage(EnvironmentExperiment.enabledKey) private var enabled = false
    @ObservedObject private var store = EnvironmentStore.shared
    @State private var owKey = ""
    @State private var iqKey = ""
    @State private var owSaved = EnvironmentKeyStore.has(.openWeather)
    @State private var iqSaved = EnvironmentKeyStore.has(.iqAir)
    @State private var busy: EnvironmentKeyStore.Account?
    @State private var notes: [EnvironmentKeyStore.Account: String] = [:]

    var body: some View {
        NunaDetailScreen("Weather and air", trailing: AnyView(NunaChip("Experimental"))) {
            NunaCard(highlight: enabled) {
                NunaToggleRow("Enable weather and air", subtitle: "Off by default. While it is off, no request is made to OpenWeather or IQAir", systemImage: "cloud.sun", isOn: $enabled).padding(.vertical, 8)
            }
            if !enabled { needs } else { on }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: enabled) { _, now in
            if now {
                EnvironmentLocation.shared.requestAuthorization()
                Task { await store.refreshIfNeeded(maxAge: 0) }
            } else {
                store.forget()
            }
        }
    }

    // MARK: Off

    private var needs: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaSettingsGroup("What you need") {
                NunaListRow("An OpenWeather key", description: "Free plan: temperature, how it feels, wind, rain and a short forecast", systemImage: "key")
                NunaDivider()
                NunaListRow("An IQAir key", description: "Free Community plan: the air quality index of the nearest station", systemImage: "key")
                NunaDivider()
                NunaListRow("Either one is enough", description: "With only OpenWeather, the air comes from its particle reading", systemImage: "checkmark.circle")
            }
            nunaFootnote("Anya reads the weather and the air on Today, in her suggestion for a session, and after you train, to tell you when heat or bad air explains a heart rate that ran high.")
        }
    }

    // MARK: On

    private var on: some View {
        VStack(spacing: NunaSpacing.section) {
            keyCard(.openWeather, title: "OpenWeather", hint: "Made at openweathermap.org, under your account's API keys. A new key can take up to two hours to work.",
                    text: $owKey, saved: owSaved)
            keyCard(.iqAir, title: "IQAir", hint: "Made at iqair.com, in the API section of your dashboard (Community plan).", text: $iqKey, saved: iqSaved)
            nowCard
            nunaFootnote("Your place, rounded to about a kilometre, is sent to OpenWeather and IQAir to get the weather and air, and nothing else about you. Your keys stay in this iPhone's Keychain and each goes only to its own service. Turning this off forgets what was read.")
        }
    }

    private func keyCard(_ account: EnvironmentKeyStore.Account, title: LocalizedStringKey, hint: LocalizedStringKey, text: Binding<String>, saved: Bool) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap(title)
                    Spacer()
                    if saved { Label("Saved", systemImage: "checkmark.circle.fill").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.charge).textCase(nil) }
                }
                if saved {
                    Button { remove(account) } label: {
                        Text("Remove key").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                } else {
                    Text(hint).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NunaFormField("Key") {
                        SecureField("", text: text, prompt: Text("Paste the key").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    let empty = text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
                    Button { save(account, text.wrappedValue); text.wrappedValue = "" } label: {
                        HStack(spacing: 8) {
                            if busy == account { ProgressView().tint(NunaPalette.onAccent) }
                            Text("Save and check").font(.nuna(size: 15, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(busy != nil || empty).opacity(busy != nil || empty ? 0.4 : 1)
                }
                if let n = notes[account] {
                    Text(verbatim: n).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
    }

    private var nowCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Right now")
                if let s = store.snapshot {
                    Text(verbatim: NunaEnvironmentFormat.line(s)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    if let a = store.advice {
                        Text(verbatim: NunaMark.plain(NunaInsightText.environment(a, s))).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                } else if !store.hasKeys {
                    Text("Save a key to read the weather and air here.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else {
                    Text("Nothing read yet.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if let e = store.lastError {
                    Text(verbatim: e).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                Button { Task { await store.refresh() } } label: {
                    HStack(spacing: 8) {
                        if store.isRefreshing { ProgressView().tint(NunaPalette.textPrimary) } else { Image(systemName: "arrow.clockwise") }
                        Text("Read it now").font(.nuna(size: 15, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
                .buttonStyle(.plain).disabled(store.isRefreshing || !store.hasKeys).opacity(store.isRefreshing || !store.hasKeys ? 0.4 : 1)
            }
        }
    }

    // MARK: Actions

    private func save(_ a: EnvironmentKeyStore.Account, _ key: String) {
        guard busy == nil else { return }
        busy = a; notes[a] = nil
        Task {
            defer { busy = nil }
            guard EnvironmentKeyStore.save(key, for: a) else { notes[a] = String(localized: "The Keychain would not keep the key."); return }
            // A wrong key fails here, with a clear message, not as an empty card later.
            if let problem = await store.check(a == .openWeather ? .openWeather : .iqAir) {
                EnvironmentKeyStore.clear(a)
                notes[a] = problem
                return
            }
            if a == .openWeather { owSaved = true } else { iqSaved = true }
            await store.refresh()
        }
    }

    private func remove(_ a: EnvironmentKeyStore.Account) {
        EnvironmentKeyStore.clear(a)
        if a == .openWeather { owSaved = false } else { iqSaved = false }
        notes[a] = nil
        if !EnvironmentKeyStore.hasAny { store.forget() }
    }
}

/// How a reading is said in one line: where, how warm, how it feels, how clean the air is.
enum NunaEnvironmentFormat {
    static func line(_ s: EnvironmentSnapshot) -> String {
        var parts: [String] = []
        if let p = s.place { parts.append(p) }
        if let t = s.tempC ?? s.feelsLikeC {
            var temp = NunaInsightText.degrees(t)
            if let f = s.feelsLikeC, abs(f - t) >= 2 { temp += " (" + String(localized: "feels like \(NunaInsightText.degrees(f))") + ")" }
            parts.append(temp)
        }
        if let aqi = s.usAqi { parts.append(String(localized: "AQI \(aqi)")) }
        return parts.joined(separator: " · ")
    }

    static func airColor(_ aqi: Int) -> Color {
        switch AirQuality.band(usAqi: aqi) {
        case .good: return NunaPalette.charge
        case .moderate, .unhealthyForSensitive: return NunaPalette.warning
        default: return NunaPalette.alert
        }
    }

    static func levelColor(_ l: EnvironmentAdvice.Level) -> Color {
        switch l { case .good: return NunaPalette.charge; case .adjust: return NunaPalette.warning; case .indoors: return NunaPalette.alert }
    }

    /// An icon for the sky.
    static func symbol(_ s: EnvironmentSnapshot) -> String {
        let id = s.conditionId ?? 800
        switch id {
        case 200..<300: return "cloud.bolt.rain"
        case 300..<400: return "cloud.drizzle"
        case 500..<600: return "cloud.rain"
        case 600..<700: return "cloud.snow"
        case 700..<800: return "cloud.fog"
        case 801...802: return "cloud.sun"
        case 803...: return "cloud"
        default: return (s.effectiveC ?? 0) >= 33 ? "sun.max" : "sun.min"
        }
    }
}
#endif
