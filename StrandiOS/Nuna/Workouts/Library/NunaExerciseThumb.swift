#if os(iOS)
import SwiftUI
import StrandDesign

/// The small still of an exercise from the library, or a plain dumbbell when the name is not in it. Used in the session, the programs
/// and the pickers so the same exercise always looks the same.
struct NunaExerciseThumb: View {
    let exercise: NunaLibraryExercise?
    var width: CGFloat = 56
    var height: CGFloat = 42

    init(name: String, width: CGFloat = 56, height: CGFloat = 42) {
        self.exercise = NunaExerciseLibrary.match(name); self.width = width; self.height = height
    }
    init(_ exercise: NunaLibraryExercise?, width: CGFloat = 56, height: CGFloat = 42) {
        self.exercise = exercise; self.width = width; self.height = height
    }

    var body: some View {
        Group {
            if let e = exercise, let img = NunaExerciseLibrary.thumbnail(e) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "dumbbell.fill").font(.system(size: height * 0.38, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(NunaPalette.glassStrong)
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
