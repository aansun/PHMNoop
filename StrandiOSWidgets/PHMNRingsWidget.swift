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
                Text("NOOP")
                    .font(StrandFont.rounded(14, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                Spacer(minLength: 0)
                battery
            }

            Spacer(minLength: 3)

            HStack(alignment: .center, spacing: 10) {
                metricColumn(
                    primaryLabel: String(localized: "Recovery"),
                    primaryValue: snapshot.recovery.map { "\($0)%" } ?? "—",
                    primaryColor: recoveryColor,
                    secondaryLabel: String(localized: "HRV"),
                    secondaryValue: snapshot.hrv.map { "\($0) ms" } ?? "—",
                    primaryValueFirst: true,
                    alignment: .trailing,
                    frameAlignment: .trailing
                )
                .frame(width: 94, alignment: .trailing)

                scoreRings
                    .frame(width: 100, height: 100)

                metricColumn(
                    primaryLabel: String(localized: "Strain"),
                    primaryValue: effortText,
                    primaryColor: strainColor,
                    secondaryLabel: secondaryLabel,
                    secondaryValue: secondaryText,
                    primaryValueFirst: true,
                    alignment: .leading,
                    frameAlignment: .leading
                )
                .frame(width: 94, alignment: .leading)
            }

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(StrandPalette.onDarkPrimary)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var battery: some View {
        HStack(spacing: 4) {
            Text(batteryText)
                .font(StrandFont.rounded(12, weight: .semibold))
            Image(systemName: "battery.100")
                .font(StrandFont.rounded(13, weight: .medium))
        }
        .foregroundStyle(StrandPalette.onDarkSecondary)
        .accessibilityLabel("Battery \(batteryText)")
    }

    private func metricColumn(primaryLabel: String, primaryValue: String, primaryColor: Color,
                              secondaryLabel: String, secondaryValue: String,
                              primaryValueFirst: Bool,
                              alignment: HorizontalAlignment,
                              frameAlignment: Alignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            metric(label: primaryLabel, value: primaryValue, color: primaryColor,
                   valueFirst: primaryValueFirst, alignment: alignment, frameAlignment: frameAlignment)
            Rectangle()
                .fill(StrandPalette.hairline.opacity(0.8))
                .frame(height: 1)
                .padding(.vertical, 7)
            metric(label: secondaryLabel, value: secondaryValue,
                   color: StrandPalette.onDarkSecondary, valueFirst: false, alignment: alignment,
                   frameAlignment: frameAlignment)
        }
    }

    @ViewBuilder
    private func metric(label: String, value: String, color: Color,
                        valueFirst: Bool,
                        alignment: HorizontalAlignment,
                        frameAlignment: Alignment) -> some View {
        VStack(spacing: 2) {
            if valueFirst {
                metricValue(value, color: color)
                metricLabel(label, color: color)
            } else {
                metricLabel(label, color: color)
                metricValue(value, color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func metricLabel(_ label: String, color: Color) -> some View {
        Text(label.uppercased())
            .font(StrandFont.rounded(13, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func metricValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(StrandFont.rounded(23, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.60)
            .allowsTightening(true)
    }

    private var scoreRings: some View {
        ZStack {
            // The outer blue ring is Strain; the inner ring is Recovery, matching the app's
            // current metric tokens rather than a widget-only palette.
            PHMNRing(progress: snapshot.effort.map { Double($0) / 100 } ?? 0,
                     color: strainColor, lineWidth: 10, diameter: 100)
            PHMNRing(progress: snapshot.recovery.map { Double($0) / 100 } ?? 0,
                     color: recoveryColor, lineWidth: 9, diameter: 76)
        }
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let format = secondaryMetric == .calories
            ? String(localized: "Recovery %@, HRV %@, Strain %@, Calories %@, Battery %@")
            : String(localized: "Recovery %@, HRV %@, Strain %@, Steps %@, Battery %@")
        return String(format: format,
                      snapshot.recovery.map { "\($0)%" } ?? "—",
                      snapshot.hrv.map { "\($0) ms" } ?? "—",
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
