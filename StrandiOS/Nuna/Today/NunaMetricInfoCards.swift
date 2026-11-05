#if os(iOS)
import SwiftUI
import StrandDesign

/// One explanation card: a title and paragraphs, in the type the other explanation cards use.
private struct NunaInfoCard<Content: View>: View {
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
#endif
