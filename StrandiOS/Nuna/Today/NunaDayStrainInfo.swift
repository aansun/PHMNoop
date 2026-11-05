#if os(iOS)
import SwiftUI
import StrandDesign

/// Under the Day Strain trend page: what Day Strain is, and what counts toward it in this app.
struct NunaDayStrainFooter: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    title("What is Day Strain?")
                    paragraph("Day Strain adds up how hard your heart worked across the whole day, not only during workouts. It runs from 0 to 21 by default; Units lets you switch it to 0 to 100.")
                    paragraph("Anything that lifts your heart rate adds to it: a hard session, but also a brisk walk or a flight of stairs. The higher the zone your heart rate is in, the more each minute counts.")
                    paragraph("Read it next to your Recovery. A day with a lot of Strain asks more of your body, so ease off when Recovery is low and push when it is high. The grey stretch on the Strain ring in Today shows the amount to aim for.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    title("What counts toward Day Strain?")
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Time in your heart-rate zones, with the higher zones counting for more")
                        bullet("Workouts, recorded or detected and saved, through their heart rate")
                        bullet("Strength sessions, through the heart rate they raise")
                        bullet("Everyday movement that lifts your heart rate")
                    }
                    paragraph("The muscular share of a gym session is shown in the session itself. It is an estimate and is not added to Day Strain.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nuna(size: 20, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(NunaPalette.textSecondary).frame(width: 4, height: 4).offset(y: -3)
            Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
