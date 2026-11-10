#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// One explanation card: a title and paragraphs, in the type the other explanation cards use.
struct NunaInfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.nuna(size: 20, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func nunaInfoParagraph(_ key: LocalizedStringKey) -> some View {
    Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
}

private func nunaInfoBullet(_ key: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Circle().fill(NunaPalette.textSecondary).frame(width: 4, height: 4).offset(y: -3)
        Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }
}

/// Under the Strength activity time trend page: what it is, what strength work gives you, and which workouts count here.
struct NunaStrengthExplainer: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaInfoCard(title: "What is strength activity time?") {
                nunaInfoParagraph("Strength activity time is the time you spend training your muscles against weight or force: lifting, resistance bands, bodyweight sets. It is often linked with building muscle, but it is also a core part of overall fitness that supports endurance, mobility and long-term health.")
            }
            NunaInfoCard(title: "What strength training gives you") {
                nunaInfoParagraph("Beyond strength itself, regular resistance work helps keep your bones dense, supports your heart and makes everyday tasks easier. It is linked with fewer falls and fractures as you age, with staying mobile and independent, and with lower blood pressure.")
            }
            NunaInfoCard(title: "Which workouts count?") {
                VStack(alignment: .leading, spacing: 10) {
                    nunaInfoBullet("Sessions you log in Strength Trainer")
                    nunaInfoBullet("Workouts named strength, lifting, weights, gym or CrossFit, saved from your strap or added by hand")
                }
                nunaInfoParagraph("The time is the length of the session, not only the sets. It is counted for the day the session started.")
            }
        }
    }
}

/// Under the Average Heart Rate page: what the figure is and how it differs from the resting heart rate.
struct NunaAverageHRInfo: View {
    var body: some View {
        NunaInfoCard(title: "What is average heart rate?") {
            nunaInfoParagraph("Average heart rate is the mean of your heart rate across the day.")
            nunaInfoParagraph("A higher average usually means a more active day, because your heart rate rises during hard effort. Stress, poor sleep, illness, heat and tiredness can raise it too, so read it next to how you slept and trained.")
            nunaInfoParagraph("It is not the same as your resting heart rate, which is measured while you are asleep and at rest.")
        }
    }
}

/// Under the VO₂ max trend page: what it is, how it compares with other people your age, and how the figure is estimated.
struct NunaVO2MaxInfo: View {
    /// VO₂ max (ml/kg/min) by age for the 95th, 50th and 5th percentile, read off the published fitness-by-age graph by Jayson Gifford (Brigham Young University).
    static let high: [(Double, Double)] = [(25, 61), (35, 51.5), (45, 47.8), (55, 42.3), (65, 35.2), (75, 31.4)]
    static let average: [(Double, Double)] = [(25, 42.7), (35, 35.9), (45, 31.6), (55, 27.1), (65, 23.7), (73, 21.4)]
    static let low: [(Double, Double)] = [(25, 25.1), (35, 22.4), (45, 19.8), (55, 18.3), (65, 14.7), (73, 13.9)]

    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaInfoCard(title: "What is VO₂ max?") {
                nunaInfoParagraph("VO₂ max is the most oxygen your body can use during hard exercise. It is one of the best single measures of long-term health and fitness.")
                nunaInfoParagraph("Think of it as your cardio fitness level: how well your heart, lungs and muscles work together to keep you strong and performing at your best, at any age.")
                nunaInfoParagraph("A higher VO₂ max does more than help athletic performance. It also builds resilience, your body's ability to adapt to whatever comes its way.")
                nunaInfoParagraph("VO₂ max naturally declines with age, so fitness slips as your body changes. Training that raises your VO₂ max now can slow that decline.")
                nunaInfoParagraph("Investing in it today helps you keep enjoying the activities you love as you get older.")
                chart
            }
            NunaInfoCard(title: "How is it estimated?") {
                nunaInfoParagraph("Your VO₂ max is an estimate, worked out once a week from your resting heart rate and your profile.")
                nunaInfoParagraph("A lab test uses a metabolic cart, a device that measures the gases you breathe in and out during hard exercise, and it is the gold standard. An estimate from a wearable is not a lab result, so read it as a trend over weeks rather than one number.")
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("VO₂ max ").font(.nuna(size: 13, weight: .heavy)).foregroundColor(NunaPalette.textPrimary)
             + Text("(ml/kg/min)").font(.nuna(size: 13, weight: .heavy)).foregroundColor(NunaPalette.textSecondary))
                .tracking(nunaTrackingLabel).textCase(.uppercase)
            Chart {
                line(Self.high, "High", NunaPalette.charge)
                line(Self.average, "Average", NunaPalette.textPrimary)
                line(Self.low, "Low", NunaPalette.warning)
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0...60)
            .chartXScale(domain: 20...78)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: 60, by: 10))) { v in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: String(Int(d))).font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textMuted) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: [25, 35, 45, 55, 65, 75]) { v in
                    AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: String(Int(d))).font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textMuted) } }
                }
            }
            .frame(height: 230)
            Text("Age (years)").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                key("High fitness (95th percentile)", NunaPalette.charge)
                key("Average fitness (50th percentile)", NunaPalette.textPrimary)
                key("Low fitness (5th percentile)", NunaPalette.warning)
            }
            Text("Based on the graph by Jayson Gifford, Brigham Young University")
                .font(.nunaWords(size: 12.5)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    @ChartContentBuilder
    private func line(_ points: [(Double, Double)], _ name: String, _ color: Color) -> some ChartContent {
        ForEach(Array(points.enumerated()), id: \.offset) { _, p in
            LineMark(x: .value("Age", p.0), y: .value("VO₂ max", p.1), series: .value("Percentile", name))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round)).interpolationMethod(.catmullRom)
        }
    }

    private func key(_ text: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(color).frame(width: 12, height: 3)
            Text(text).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }
}
#endif
