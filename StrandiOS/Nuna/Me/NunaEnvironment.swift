#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Weather and air: your own OpenWeather and IQAir keys in the Keychain and one switch. Both keys are needed; each is pasted, saved and checked in one step.
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
        NunaDetailScreen("Weather and air", centersTitle: true) {
            NunaCard(highlight: enabled) {
                NunaToggleRow("Enable weather and air", subtitle: "Off by default. While it is off, no request is made to OpenWeather or IQAir", systemImage: "cloud.sun", isOn: $enabled).padding(.vertical, 8)
            }
            if enabled {
                keyCard(.openWeather, title: "OpenWeather", site: "openweathermap.org", url: "https://home.openweathermap.org/api_keys", text: $owKey, saved: owSaved)
                keyCard(.iqAir, title: "IQAir", site: "iqair.com", url: "https://dashboard.iqair.com/personal/api-keys", text: $iqKey, saved: iqSaved)
                if let e = store.lastError, owSaved, iqSaved {
                    Text(verbatim: e).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaWeatherAirExplainer()
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

    private func keyCard(_ account: EnvironmentKeyStore.Account, title: LocalizedStringKey, site: String, url: String, text: Binding<String>, saved: Bool) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap(title)
                    Spacer()
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.charge).textCase(nil)
                    } else {
                        Text("Required").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                }
                if saved {
                    Button { remove(account) } label: {
                        Text("Remove key").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                } else {
                    NunaFormField("API key") {
                        SecureField("", text: text, prompt: Text("Paste the key").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    let empty = text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
                    Button { save(account, text.wrappedValue); text.wrappedValue = "" } label: {
                        HStack(spacing: 8) {
                            if busy == account { ProgressView().tint(NunaPalette.onAccent) }
                            Text("Save").font(.nuna(size: 15, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(busy != nil || empty).opacity(busy != nil || empty ? 0.4 : 1)
                    if let link = URL(string: url) {
                        Link(destination: link) {
                            HStack(spacing: 6) {
                                Text(verbatim: String(localized: "Get a key at \(site)")).font(.nuna(size: 13.5, weight: .semibold)).textCase(nil)
                                Image(systemName: "arrow.up.right").font(.nuna(size: 11, weight: .bold))
                            }
                            .foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                if let n = notes[account] {
                    Text(verbatim: n).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
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
        if !EnvironmentKeyStore.hasBoth { store.forget() }
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
        case .moderate: return NunaPalette.warning
        case .unhealthyForSensitive: return NunaPalette.caution
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
