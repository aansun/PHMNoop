import StrandDesign
import SwiftUI
import WidgetKit

/// Wide score widget inspired by the NOOP Rings glance: Recovery and Strain arcs in the centre, with
/// HRV, Steps and strap battery arranged around them.
struct PHMNRingsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PHMNRingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PHMNRingsEntry {
        PHMNRingsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PHMNRingsEntry) -> Void) {
        let fallback: WidgetSnapshot = context.isPreview ? .placeholder : .unavailable
        completion(PHMNRingsEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PHMNRingsEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .unavailable
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [PHMNRingsEntry(date: Date(), snapshot: snapshot)], policy: .after(next)))
    }
}

private enum PHMNRingsSecondaryMetric {
    case steps
    case calories
}

private struct PHMNRingsWidgetView: View {
    let entry: PHMNRingsEntry
    let secondaryMetric: PHMNRingsSecondaryMetric

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var recoveryColor: Color {
        snapshot.recovery.map { StrandPalette.recoveryColor(Double($0)) } ?? StrandPalette.textTertiary
    }
    private var strainColor: Color {
        snapshot.effort == nil ? StrandPalette.textTertiary : StrandPalette.effortColor
    }
    private var effortText: String {
        snapshot.effortDisplay ?? snapshot.effort.map(String.init) ?? "—"
    }
    private var stepsText: String {
        snapshot.steps?.formatted() ?? "—"
    }
    private var caloriesText: String {
        snapshot.caloriesKcal?.formatted() ?? "—"
    }
    private var secondaryLabel: String {
        secondaryMetric == .calories ? String(localized: "Calories") : String(localized: "Steps")
    }
    private var secondaryText: String {
        secondaryMetric == .calories ? caloriesText : stepsText
    }
    private var batteryText: String {
        snapshot.batteryPct.map { "\($0)%" } ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                heartRate
                Spacer(minLength: 0)
                battery
            }

            Spacer(minLength: 2)

            HStack(alignment: .center, spacing: 18) {
                metricColumn(
                    primaryLabel: String(localized: "Recovery"),
                    primaryValue: snapshot.recovery.map(String.init) ?? "—",
                    primaryColor: recoveryColor,
                    secondaryLabel: String(localized: "HRV"),
                    secondaryValue: snapshot.hrv.map(String.init) ?? "—",
                    primarySuffix: snapshot.recovery == nil ? nil : "%",
                    primaryValueFirst: true,
                    alignment: .trailing,
                    frameAlignment: .trailing
                )
                .frame(width: 88, alignment: .trailing)

                scoreRings
                    .frame(width: 96, height: 96)

                metricColumn(
                    primaryLabel: String(localized: "Strain"),
                    primaryValue: effortText,
                    primaryColor: strainColor,
                    secondaryLabel: secondaryLabel,
                    secondaryValue: secondaryText,
                    primarySuffix: nil,
                    primaryValueFirst: true,
                    alignment: .leading,
                    frameAlignment: .leading
                )
                .frame(width: 88, alignment: .leading)
            }

            Spacer(minLength: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(StrandPalette.textPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var heartRate: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(StrandFont.rounded(10, weight: .bold))
            Text(snapshot.bpm.map(String.init) ?? "—")
                .font(StrandFont.rounded(11, weight: .bold))
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityLabel(snapshot.bpm.map { "Heart rate \($0)" } ?? "Heart rate unavailable")
    }

    private var battery: some View {
        HStack(spacing: 4) {
            Text(batteryText)
                .font(StrandFont.rounded(10, weight: .bold))
            Image(systemName: "battery.100")
                .font(StrandFont.rounded(11, weight: .bold))
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityLabel("Battery \(batteryText)")
    }

    private func metricColumn(primaryLabel: String, primaryValue: String, primaryColor: Color,
                              secondaryLabel: String, secondaryValue: String,
                              primarySuffix: String?,
                              primaryValueFirst: Bool,
                              alignment: HorizontalAlignment,
                              frameAlignment: Alignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            metric(label: primaryLabel, value: primaryValue, color: primaryColor,
                   suffix: primarySuffix, valueFirst: primaryValueFirst,
                   alignment: alignment, frameAlignment: frameAlignment)
            Rectangle()
                .fill(StrandPalette.hairline.opacity(0.8))
                .frame(height: 1)
                .padding(.vertical, 8)
            metric(label: secondaryLabel, value: secondaryValue,
                   color: StrandPalette.textSecondary, valueFirst: false, alignment: alignment,
                   frameAlignment: frameAlignment)
        }
    }

    @ViewBuilder
    private func metric(label: String, value: String, color: Color,
                        suffix: String? = nil,
                        valueFirst: Bool,
                        alignment: HorizontalAlignment,
                        frameAlignment: Alignment) -> some View {
        VStack(spacing: 3) {
            if valueFirst {
                metricValue(value, color: color, suffix: suffix, frameAlignment: frameAlignment)
                metricLabel(label, color: color, frameAlignment: frameAlignment)
            } else {
                metricLabel(label, color: color, frameAlignment: frameAlignment)
                metricValue(value, color: color, frameAlignment: frameAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func metricLabel(_ label: String, color: Color, frameAlignment: Alignment) -> some View {
        Text(label.uppercased())
            .font(StrandFont.rounded(9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func metricValue(_ value: String, color: Color, suffix: String? = nil,
                             frameAlignment: Alignment = .center) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: suffix == nil ? 0 : 1) {
            Text(value)
                .font(StrandFont.rounded(17, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .allowsTightening(true)
            if let suffix {
                Text(suffix)
                    .font(StrandFont.rounded(9, weight: .bold))
                    .foregroundStyle(color)
                    .baselineOffset(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var scoreRings: some View {
        ZStack {
            // The outer blue ring is Strain; the inner ring is Recovery, matching the app's
            // current metric tokens rather than a widget-only palette.
            PHMNRing(progress: snapshot.effort.map { Double($0) / 100 } ?? 0,
                     color: strainColor, lineWidth: 9, diameter: 96)
            PHMNRing(progress: snapshot.recovery.map { Double($0) / 100 } ?? 0,
                     color: recoveryColor, lineWidth: 8, diameter: 72)
        }
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let format = secondaryMetric == .calories
            ? String(localized: "Recovery %@, HRV %@, Strain %@, Calories %@, Battery %@")
            : String(localized: "Recovery %@, HRV %@, Strain %@, Steps %@, Battery %@")
        return String(format: format,
                      snapshot.recovery.map { "\($0)%" } ?? "—",
                      snapshot.hrv.map(String.init) ?? "—",
                      effortText, secondaryText, batteryText)
    }
}

private struct PHMNRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(StrandPalette.textTertiary.opacity(0.17), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-90))
    }
}

struct PHMNRingsWidget: Widget {
    static let kind = "PHMNRingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNRingsProvider()) { entry in
            PHMNRingsWidgetView(entry: entry, secondaryMetric: .steps)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("NOOP Rings")
        .description("Recovery, HRV, Strain, Steps and battery at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

/// A separate widget kind so the redesigned full-ring treatment can be added to the simulator
/// without being confused with an already-installed NOOP Rings instance.
struct NOOPRing2Widget: Widget {
    static let kind = "NOOPRing2Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNRingsProvider()) { entry in
            PHMNRingsWidgetView(entry: entry, secondaryMetric: .calories)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("NOOP Ring 2")
        .description("Full Recovery and Strain rings with HRV, Calories and battery.")
        .supportedFamilies([.systemMedium])
    }
}
