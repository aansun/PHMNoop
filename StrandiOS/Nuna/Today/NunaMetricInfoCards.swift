#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

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

/// Under the Weather and air page: why the weather and the air matter and how to tell good air.
struct NunaWeatherAirExplainer: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaInfoCard(title: "Why weather and air matter") {
                nunaInfoParagraph("Heat, humidity, rain and wind change how hard the same session feels. Your heart works harder in the heat, and recovery slows after a hot or humid day.")
                nunaInfoParagraph("The air matters as much. Fine particles in polluted air reach deep into your lungs, and hard breathing outdoors takes in more of them.")
                nunaInfoParagraph("Knowing both before you go out helps you choose when, where and how hard to train.")
            }
            NunaInfoCard(title: "How to tell if the air is good") {
                nunaInfoParagraph("Air quality is given as an index (AQI). The lower the number, the cleaner the air.")
                VStack(alignment: .leading, spacing: 10) {
                    nunaInfoBullet("0 to 50, good: clean air, train as usual")
                    nunaInfoBullet("51 to 100, moderate: fine for most people; if you are sensitive, go a little easier")
                    nunaInfoBullet("101 to 150, unhealthy for sensitive groups: keep it shorter and easier if you have asthma or a heart or lung condition")
                    nunaInfoBullet("151 and above, unhealthy: move the session indoors")
                }
                nunaInfoParagraph("Air is usually cleaner in the early morning and after rain, and worse at rush hour and on still, hot afternoons.")
            }
        }
    }
}

/// Under the Body clock page: where the estimate comes from and what it is not.
struct NunaBodyClockInfo: View {
    var body: some View {
        NunaInfoCard(title: "How it's calculated") {
            nunaInfoParagraph("Your heart rate rises and falls over the day. PHMN fits one smooth daily cycle to the last 14 days, finds its lowest and highest points, and places your body-clock low about when your heart-rate rhythm bottoms out.")
            nunaInfoParagraph("It is an on-device estimate from your heart-rate rhythm, not a medical measurement and not a body temperature reading.")
        }
    }
}

/// Under the Rhythm page: how to read the scatter, with the three figures that describe its shape for anyone who wants them.
struct NunaRhythmReadingInfo: View {
    var window: RhythmScreener.WindowResult?

    var body: some View {
        NunaInfoCard(title: "How to read it") {
            nunaInfoParagraph("Each dot sets one gap between heartbeats against the next. A long, narrow cloud along the line means the timing changed smoothly. A rounder, wider cloud means it jumped more from one beat to the next.")
            if let w = window, let sd1 = w.sd1, let sd2 = w.sd2, let ratio = w.sd1sd2 {
                VStack(spacing: 0) {
                    figure("Width (SD1)", String(format: "%.0f ms", locale: AppLanguage.activeLocale, sd1))
                    NunaDivider()
                    figure("Length (SD2)", String(format: "%.0f ms", locale: AppLanguage.activeLocale, sd2))
                    NunaDivider()
                    figure("Width to length", String(format: "%.2f", locale: AppLanguage.activeLocale, ratio))
                }
                nunaInfoParagraph("These three describe the ellipse drawn over the bright dots. They have no good or bad value on their own.")
            }
        }
    }

    private func figure(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nunaWords(size: 15)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 8)
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
        }
        .padding(.vertical, 10)
    }
}

/// Under the Rhythm page: where the reading comes from and what it is not. The last paragraph is the standing disclaimer.
struct NunaRhythmMeasureInfo: View {
    var body: some View {
        NunaInfoCard(title: "How it's measured") {
            nunaInfoParagraph("While you sleep and lie still, PHMN reads the time between your heartbeats in five-minute windows. Windows with movement or a noisy signal are left out.")
            nunaInfoParagraph("It is an experimental picture, not a diagnosis, not an ECG and not a medical device, and it cannot detect any heart condition. If you feel unwell or are worried, contact a qualified professional; in an emergency, your local emergency service.")
        }
    }
}

/// Under the strap's battery page: how to look after the battery, and what the figures on the page are.
struct NunaBatteryCareInfo: View {
    var body: some View {
        NunaInfoCard(title: "Looking after the battery") {
            VStack(alignment: .leading, spacing: 10) {
                nunaInfoBullet("Charge the strap while you are awake, in the shower or at your desk, so no sleep data is lost.")
                nunaInfoBullet("Avoid heat: do not charge in direct sunlight.")
                nunaInfoBullet("Dry the contacts: clean and dry them before charging.")
            }
            nunaInfoParagraph("The percentage is read from the strap. The time left is estimated from the readings of this session only and gets better the longer the strap stays connected.")
        }
    }
}

/// On the keys page of Weather and air: what each of the two keys is used for and what leaves the phone.
struct NunaWeatherAirKeysInfo: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaInfoCard(title: "What each key is for") {
                VStack(alignment: .leading, spacing: 10) {
                    nunaInfoBullet("OpenWeather gives the weather now, the forecast for the days ahead and the air forecast hour by hour.")
                    nunaInfoBullet("IQAir gives the air quality measured at the nearest station, used for the reading now.")
                }
                nunaInfoParagraph("Both keys are needed. Your place, rounded to about a kilometre, is sent to each service and nothing else about you. The keys stay in this iPhone's Keychain and each goes only to its own service. Turning this off forgets what was read.")
            }
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
