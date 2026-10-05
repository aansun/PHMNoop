import SwiftUI
import WidgetKit
import AppIntents
import StrandDesign

// Shared pieces of the Nuna widgets (Score, Vital sign, Anya, Steps), drawn with the Nuna tokens. The widgets only draw finished numbers
// the app wrote into the shared snapshot; nothing is computed here beyond picking a colour and formatting.

enum NunaW {
    /// Charge reads green from 67, amber from 34, red below (the same bands as Today).
    static func chargeColor(_ v: Int?) -> Color {
        guard let v else { return NunaPalette.textMuted }
        return v >= 67 ? NunaPalette.charge : (v >= 34 ? NunaPalette.warning : NunaPalette.alert)
    }

    /// One word for the Charge band, for the large widget's title.
    static func chargeWord(_ v: Int?) -> LocalizedStringKey {
        guard let v else { return "No data" }
        return v >= 67 ? "Ready for a moderate load" : (v >= 34 ? "Keep it light today" : "Recover today")
    }

    static func updated(_ d: Date) -> Text {
        d == .distantPast ? Text("No data") : Text("Updated \(d.formatted(date: .omitted, time: .shortened))")
    }

    static func number(_ v: Double, decimals: Int = 0, signed: Bool = false) -> String {
        let f = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(decimals))
        let s = v.formatted(signed ? f.sign(strategy: .always()) : f)
        return s
    }

    /// The day's mean stress on the 0 to 3 scale, from the published curve (moving hours left out), or nil when nothing was scored.
    static func stressAverage(_ s: WidgetSnapshot) -> Double? {
        let levels = s.stressCurve().filter { !$0.moving }.compactMap { $0.level }
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / Double(levels.count)
    }

    static func stressWord(_ v: Double) -> LocalizedStringKey { v < 1.5 ? "Low" : (v < 2.25 ? "Medium" : "High") }
}

/// A ring that fills to a fraction, with its figure in the middle.
struct NunaWRing<Centre: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 9
    @ViewBuilder var centre: () -> Centre

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(min(fraction, 1), fraction > 0 ? 0.015 : 0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
            centre()
        }
    }
}

/// Small uppercase caption in the muted ink.
struct NunaWCap: View {
    let text: Text
    var size: CGFloat = 10
    var body: some View {
        text.font(.nuna(size: size, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The strap battery as the mockups draw it: a small cell and the percentage.
struct NunaWBattery: View {
    let percent: Int?
    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(NunaPalette.textSecondary, lineWidth: 1.4).frame(width: 26, height: 10)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(NunaPalette.charge)
                    .frame(width: max(0, 21 * CGFloat(min(max(percent ?? 0, 0), 100)) / 100), height: 6).padding(.leading, 2.5)
            }
            Text(verbatim: percent.map { "\($0)%" } ?? "–").font(.nuna(size: 10.5, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

/// A coloured status pill ("Normal", "2 out of range").
struct NunaWPill: View {
    let text: Text
    let color: Color
    var body: some View {
        text.font(.nuna(size: 10, weight: .heavy)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 8).frame(height: 20)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    /// The widget card: the Nuna card colour as the container, so it follows light and dark.
    func nunaWidgetBackground() -> some View {
        containerBackground(NunaPalette.card, for: .widget)
    }
}

/// Deep links the widgets open; the app routes the host.
enum NunaWLink {
    static let today = URL(string: "noop://today")!
    static let health = URL(string: "noop://health")!
    static let anya = URL(string: "noop://anya")!
}

// MARK: - Vital metadata

enum NunaVitalKey: String, CaseIterable {
    case hrv, rhr, spo2, resp, skin, stress

    var label: LocalizedStringKey {
        switch self {
        case .hrv: "HRV"
        case .rhr: "Resting HR"
        case .spo2: "SpO₂"
        case .resp: "Breathing"
        case .skin: "Skin temp"
        case .stress: "Stress"
        }
    }
    var short: LocalizedStringKey {
        switch self {
        case .hrv: "HRV"
        case .rhr: "RHR"
        case .spo2: "SpO₂"
        case .resp: "Breathing"
        case .skin: "Skin"
        case .stress: "Stress"
        }
    }
    var unit: String {
        switch self {
        case .hrv: "ms"
        case .rhr: "bpm"
        case .spo2: "%"
        case .resp: String(localized: "/min")
        case .skin: "°C"
        case .stress: "/ 3"
        }
    }
    var decimals: Int { self == .resp || self == .skin || self == .stress ? 1 : 0 }
}

/// A vital as the widgets draw it, whether it came from the night's readings or from the stress curve.
struct NunaVitalValue: Identifiable {
    let key: NunaVitalKey
    let value: Double
    var delta: Double?
    var deltaBasis: String?
    var position: Double?
    var outOfRange = false
    var id: String { key.rawValue }

    var text: String { NunaW.number(value, decimals: key.decimals, signed: key == .skin) }
}

extension WidgetSnapshot {
    /// The vitals for the chosen metrics, in the chosen order, leaving out any the night did not produce.
    func vitalValues(for keys: [NunaVitalKey]) -> [NunaVitalValue] {
        keys.compactMap { key in
            if key == .stress { return NunaW.stressAverage(self).map { NunaVitalValue(key: .stress, value: $0, outOfRange: $0 >= 2.25) } }
            guard let v = vitals?.first(where: { $0.key == key.rawValue }) else { return nil }
            return NunaVitalValue(key: key, value: v.value, delta: v.delta, deltaBasis: v.deltaBasis, position: v.position, outOfRange: v.outOfRange)
        }
    }
}
