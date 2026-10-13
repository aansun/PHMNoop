#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

private func nunaCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

private func nunaFmt(_ v: Double?, _ digits: Int = 0) -> String {
    v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

func nunaSigned(_ v: Double, _ digits: Int = 1) -> String {
    (v >= 0 ? "+" : "−") + String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, abs(v))
}

private func nunaMiniStat(_ label: LocalizedStringKey, _ value: String, unit: String = "") -> some View {
    NunaStatTile(label: label, value: value, unit: unit)
}

// MARK: - Oxygen and breathing

// MARK: - Skin temperature

struct NunaSkinTempView: View {
    /// How the figure is worked out, with what moves it, as one footnote.
    private var howText: String {
        var out = String(localized: "The strap measures skin temperature at the wrist while you sleep and compares it with your own recent nights. The figure is a deviation from your baseline, not your core body temperature.")
        out += "\n\n" + String(localized: "What affects it")
        out += "\n• " + String(localized: "Room temperature") + ": " + String(localized: "A warm room can raise it a little")
        out += "\n• " + String(localized: "Alcohol") + ": " + String(localized: "Log it in your journal to see the link")
        if appModel.cyclePhase != nil { out += "\n• " + String(localized: "Cycle phase") + ": " + String(localized: "The luteal phase can raise your baseline") }
        return out
    }

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var skinS = NunaSeriesModel()
    @State private var showCoach = false

    var body: some View {
        let nights = skinS.readings(14)
        let latest = skinS.latest?.value
        NunaDetailScreen("Skin temperature") {
            NunaCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        nunaCap("Last night")
                        Spacer()
                        if let latest { NunaChip(abs(latest) < 0.5 ? "Small deviation" : "Larger deviation", color: abs(latest) < 0.5 ? NunaPalette.charge : NunaPalette.warning) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: latest.map { nunaSigned($0) } ?? "–").font(.nuna(size: 68, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(68)).foregroundStyle(NunaPalette.textPrimary)
                        if latest != nil { Text("°C").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    Text("Compared with your personal baseline").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    NunaDivider().padding(.vertical, 8)
                    HStack {
                        nunaCap("14 nights")
                        Spacer()
                        Text("Centre line = baseline").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    if nights.count >= 2 {
                        NunaDivergingBars(values: nights.map(\.value))
                        HStack {
                            Text(verbatim: nunaAxisDate(nights.first!.date)); Spacer(); Text(verbatim: nunaAxisDate(nights.last!.date))
                        }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        Text("Not enough data yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    if let latest {
                        NunaDivider().padding(.vertical, 8)
                        VStack(spacing: 8) {
                            NunaDeviationScale(value: latest)
                            HStack { Text("−1 °C"); Spacer(); Text("+1 °C") }
                                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                }
            }
            if coachEnabled, let latest {
                let small = abs(latest) < 0.5
                NunaAnyaCard(verbatim: String(localized: "Skin temperature") + " " + nunaSigned(latest) + " °C · " + (small ? String(localized: "Small deviation") : String(localized: "Larger deviation"))) { showCoach = true }
            }
            NavigationLink(value: NunaTodayRoute.earlyWarning) {
                NunaCard(small: true) { NunaListRow("Early warning", description: "It takes two signals away from your range", systemImage: "bell", showsChevron: true) }
            }.buttonStyle(.plain)
            NunaExpandRow(title: "How it's calculated", systemImage: "sparkles", plain: howText)
        }
        .task { await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop") }
        .sheet(isPresented: $showCoach) {
            NunaAnyaSheet(context: "Skin temperature", metric: NunaAnyaMetric(key: "skin_temp", source: "my-whoop", title: String(localized: "Skin temperature"), unit: "°C", decimals: 1, higherIsBetter: nil))
        }
    }
}

/// Bars up or down from a dashed centre line (the baseline). Bars past half a degree turn yellow.
struct NunaDivergingBars: View {
    let values: [Double]
    var body: some View {
        let scale = max(0.6, values.map { abs($0) }.max() ?? 0.6)
        GeometryReader { geo in
            let mid = geo.size.height / 2
            ZStack {
                HStack(spacing: 5) {
                    ForEach(values.indices, id: \.self) { i in
                        let v = values[i]
                        let h = max(3, CGFloat(abs(v) / scale) * mid)
                        VStack(spacing: 0) {
                            if v >= 0 {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(abs(v) >= 0.5 ? NunaPalette.warning : NunaPalette.rest).frame(height: h)
                                Color.clear.frame(height: mid)
                            } else {
                                Color.clear.frame(height: mid)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(abs(v) >= 0.5 ? NunaPalette.warning : NunaPalette.rest).frame(height: h)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: geo.size.width, y: mid)) }
                    .stroke(NunaPalette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}

/// Three-segment scale from −1 to +1 with a marker at the value.
struct NunaDeviationScale: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            let f = CGFloat(min(max((value + 1) / 2, 0), 1))
            ZStack(alignment: .leading) {
                NunaProportionBar(parts: [(3, NunaPalette.zoneBase), (4, NunaPalette.ink.opacity(0.2)), (3, NunaPalette.zoneBase)], height: 12)
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink).frame(width: 6, height: 20)
                    .shadow(color: NunaPalette.ink.opacity(0.2), radius: 3)
                    .offset(x: min(max(geo.size.width * f - 3, 0), geo.size.width - 6))
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}
#endif
