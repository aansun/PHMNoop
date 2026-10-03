import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Compact Today surface for Stress, using the same intraday curve and score language as the Stress
/// widget. The curve comes from `StressDayCurve`, so the app and widget never invent separate readings.
struct StressTodayCardView: View {
    @EnvironmentObject private var repo: Repository
    @State private var result: DaytimeStress.Result?

    private var scoredHours: [DaytimeStress.HourPoint] {
        result?.hours.filter { $0.level != nil } ?? []
    }

    private var latest: DaytimeStress.HourPoint? {
        result?.hours.last(where: { $0.level != nil })
    }

    var body: some View {
        NavigationLink(value: TabRoute.stress) {
            NoopCard(tint: StressRamp.calm) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack(alignment: .lastTextBaseline, spacing: NoopMetrics.space2) {
                        Text("Stress")
                            .font(StrandFont.overline)
                            .tracking(StrandFont.overlineTracking)
                            .foregroundStyle(StrandPalette.textPrimary)

                        Spacer(minLength: NoopMetrics.space2)

                        if let latest, let level = latest.level {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(StressTrace.formatLevel(level))
                                    .font(StrandFont.rounded(26, weight: .bold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text("of 3")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        } else {
                            Text("—")
                                .font(StrandFont.rounded(26, weight: .bold))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }

                    if let result, !scoredHours.isEmpty {
                        HStack(alignment: .top, spacing: NoopMetrics.space2) {
                            VStack(alignment: .trailing, spacing: 0) {
                                ForEach([3, 2, 1, 0], id: \.self) { tick in
                                    Text("\(tick)")
                                        .font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                    if tick > 0 { Spacer(minLength: 0) }
                                }
                            }
                            .frame(width: 14, height: 78)

                            DaytimeLoadLine(hours: result.hours)
                        }

                        StressTodayTimeAxis(hours: result.hours)

                        if let peak = result.peak, let peakLevel = peak.level {
                            HStack(spacing: 4) {
                                Text("Peak")
                                Text(verbatim: "\(StressTrace.formatLevel(peakLevel)) · \(peakDate(peak))")
                            }
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(StrandPalette.statusWarning.opacity(0.18), in: Capsule())
                        }
                    } else {
                        Text("Calibrating")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .task(id: repo.refreshSeq) {
            result = await StressDayCurve.today(repo: repo)?.result
        }
    }

    private func peakDate(_ point: DaytimeStress.HourPoint) -> String {
        Date(timeIntervalSince1970: TimeInterval(point.startTs))
            .formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityLabel: String {
        guard let latest, let level = latest.level else {
            return String(localized: "Stress, calibrating")
        }
        return String(localized: "Stress \(StressTrace.formatLevel(level)) of 3")
    }
}

private struct StressTodayTimeAxis: View {
    let hours: [DaytimeStress.HourPoint]

    private var scored: [DaytimeStress.HourPoint] {
        hours.filter { $0.level != nil }
    }

    var body: some View {
        if let first = scored.first, let last = scored.last, first.startTs != last.startTs {
            HStack {
                Text(axisDate(first.startTs))
                Spacer(minLength: 0)
                Text(axisDate(last.startTs))
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func axisDate(_ timestamp: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .omitted, time: .shortened)
    }
}
