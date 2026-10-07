#if os(iOS)
import SwiftUI
import MuscleMap
import StrandDesign

/// One exercise of the library: the animated demo, the muscles it works on a body map, how to do it.
struct NunaExerciseDetailView: View {
    let exerciseId: String

    var body: some View {
        if let e = NunaExerciseLibrary.exercise(id: exerciseId) {
            NunaDetailScreen(LocalizedStringKey(e.name)) { content(e) }
        } else {
            NunaDetailScreen("Exercise") {
                NunaCard { Text("This exercise is not in the library.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
    }

    @ViewBuilder private func content(_ e: NunaLibraryExercise) -> some View {
        NunaExerciseDemo(exercise: e)
        HStack(spacing: 8) {
            if let t = e.equipmentTitle { NunaChip(verbatim: t) }
            if let t = e.levelTitle { NunaChip(verbatim: t) }
            if let m = e.mechanic { NunaChip(verbatim: m == "compound" ? String(localized: "Compound") : String(localized: "Isolation")) }
            Spacer(minLength: 0)
        }
        musclesCard(e)
        instructionsCard(e)
        nunaFootnote("Photos and text: free-exercise-db, public domain (The Unlicense). The body map is MuscleMap, MIT licence. Both are listed under About › Open-source notices.")
    }

    private func musclesCard(_ e: NunaLibraryExercise) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Muscles worked")
                NunaExerciseBodyMap(primary: e.primaryMap, secondary: e.secondaryMap)
                VStack(alignment: .leading, spacing: 8) {
                    legendRow(color: NunaExerciseBodyMap.primaryColor, title: "Main", names: e.primaryMuscles)
                    if !e.secondaryMuscles.isEmpty { legendRow(color: NunaExerciseBodyMap.secondaryColor, title: "Also", names: e.secondaryMuscles) }
                }
            }
        }
    }

    private func legendRow(color: Color, title: LocalizedStringKey, names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: names.map(NunaLibraryExercise.title).joined(separator: ", ")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 0)
        }
    }

    private func instructionsCard(_ e: NunaLibraryExercise) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("How to do it")
                ForEach(Array(e.instructions.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(i + 1)").font(.nuna(size: 12, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.onAccent)
                            .frame(width: 22, height: 22).background(NunaPalette.accent, in: Circle())
                        Text(verbatim: step).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
    }
}

/// The front and the back of the body side by side, with the main muscles in one colour and the helping ones in another.
struct NunaExerciseBodyMap: View {
    let primary: [Muscle]
    let secondary: [Muscle]
    var height: CGFloat = 250

    static let primaryColor = NunaPalette.accent
    static let secondaryColor = NunaPalette.rest

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BodySide.allCases, id: \.self) { side in
                BodyView(gender: .male, side: side)
                    .highlight(secondary, color: Self.secondaryColor, opacity: 0.85)
                    .highlight(primary, color: Self.primaryColor)
                    .frame(maxWidth: .infinity).frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Body map of the muscles worked"))
    }
}

// MARK: - The library

/// The exercises of the library with a still of each, to open one.
struct NunaExerciseLibraryView: View {
    var body: some View {
        NunaDetailScreen("Exercise library") {
            Text("Animated demos and the muscles each exercise works. This is a sample of the library; more exercises are added over time.")
                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                VStack(spacing: 0) {
                    ForEach(Array(NunaExerciseLibrary.all.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaWorkoutRoute.exercise(e.id)) { row(e) }.buttonStyle(.plain)
                    }
                }
            }
            nunaFootnote("Photos and text: free-exercise-db, public domain. See About › Open-source notices.")
        }
    }

    private func row(_ e: NunaLibraryExercise) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = e.frames.first, let img = NunaExerciseLibrary.image(f) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else { Color.clear }
            }
            .frame(width: 64, height: 48).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: e.name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                Text(verbatim: e.primaryMuscles.map(NunaLibraryExercise.title).joined(separator: ", ") + (e.equipmentTitle.map { " · " + $0 } ?? ""))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }
}
#endif
