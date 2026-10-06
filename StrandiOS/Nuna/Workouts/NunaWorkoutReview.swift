#if os(iOS)
import SwiftUI
import PhotosUI
import StrandDesign
import WhoopStore

/// How hard a session felt, in the wearer's own words, on a four-step scale. It is the person's read, not a measurement: Anya uses it to
/// size what comes next. The raw values are what older builds stored, so a saved review keeps its meaning.
enum NunaWorkoutFeeling: String, CaseIterable, Identifiable {
    case easy, fairlyHard, hard, veryHard
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .easy: return "Easy"
        case .fairlyHard: return "Decent"
        case .hard: return "Challenging"
        case .veryHard: return "Full power"
        }
    }
    var plain: String {
        switch self {
        case .easy: return String(localized: "Easy")
        case .fairlyHard: return String(localized: "Decent")
        case .hard: return String(localized: "Challenging")
        case .veryHard: return String(localized: "Full power")
        }
    }
    var tint: Color {
        switch self {
        case .easy: return NunaPalette.rest
        case .fairlyHard: return NunaPalette.charge
        case .hard: return NunaPalette.warning
        case .veryHard: return NunaPalette.alert
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct NunaWorkoutReview: Codable, Equatable {
    var feeling: String?
    /// File names inside the session's folder, in the order they were added.
    var photos: [String] = []
    var feelingValue: NunaWorkoutFeeling? { feeling.flatMap(NunaWorkoutFeeling.init(rawValue:)) }
}

/// What the wearer said about a session, kept on this iPhone beside the session's natural key (start time and sport), the same key
/// the route uses. Photos are stored as JPEGs shrunk to 1600 px, in a folder of their own under Application Support.
enum NunaWorkoutReviewStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WorkoutReviews", isDirectory: true)
    }
    private static func folder(_ startTs: Int, _ sport: String) -> URL {
        let safe = sport.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return root.appendingPathComponent("\(startTs)-\(safe)", isDirectory: true)
    }
    private static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load(startTs: Int, sport: String) -> NunaWorkoutReview {
        let url = folder(startTs, sport).appendingPathComponent("review.json")
        guard let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(NunaWorkoutReview.self, from: data) else { return NunaWorkoutReview() }
        return r
    }

    static func save(_ review: NunaWorkoutReview, startTs: Int, sport: String) {
        let dir = folder(startTs, sport); ensure(dir)
        if let data = try? JSONEncoder().encode(review) { try? data.write(to: dir.appendingPathComponent("review.json"), options: .atomic) }
    }

    /// Stores a picked photo and returns its file name. nil when the data is not an image.
    static func addPhoto(_ data: Data, startTs: Int, sport: String) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let dir = folder(startTs, sport); ensure(dir)
        let name = UUID().uuidString + ".jpg"
        do { try jpeg.write(to: dir.appendingPathComponent(name), options: .atomic) } catch { return nil }
        return name
    }

    static func image(_ name: String, startTs: Int, sport: String) -> UIImage? {
        UIImage(contentsOfFile: folder(startTs, sport).appendingPathComponent(name).path)
    }

    static func removePhoto(_ name: String, startTs: Int, sport: String) {
        try? FileManager.default.removeItem(at: folder(startTs, sport).appendingPathComponent(name))
    }

    /// Everything kept for a session, when the session itself is deleted.
    static func remove(startTs: Int, sport: String) {
        try? FileManager.default.removeItem(at: folder(startTs, sport))
    }
}

/// What the review screen is editing. On the screen that follows a workout nothing is kept until OK; on a saved session every change is
/// kept as it is made.
@MainActor
final class NunaWorkoutReviewDraft: ObservableObject {
    struct Photo: Identifiable {
        let id = UUID()
        /// The file it already has on disk, or nil while it is only picked.
        var stored: String?
        var image: UIImage
        var data: Data?
    }

    let startTs: Int
    let sport: String
    let immediate: Bool
    /// Slider position, 0 to 3. A saved session that was never rated has no value until the slider is moved.
    @Published var step: Double = 0
    @Published var rated: Bool
    @Published var photos: [Photo] = []
    @Published var uploadToStrava = false
    private var removed: [String] = []

    init(startTs: Int, sport: String, immediate: Bool) {
        self.startTs = startTs; self.sport = sport; self.immediate = immediate
        let saved = NunaWorkoutReviewStore.load(startTs: startTs, sport: sport)
        // After a workout the scale starts on Easy; on a saved session only a real answer counts.
        rated = !immediate || saved.feeling != nil
        step = Double(saved.feelingValue?.index ?? 0)
        photos = saved.photos.compactMap { name in
            NunaWorkoutReviewStore.image(name, startTs: startTs, sport: sport).map { Photo(stored: name, image: $0, data: nil) }
        }
    }

    var feeling: NunaWorkoutFeeling { NunaWorkoutFeeling.allCases[min(max(Int(step.rounded()), 0), 3)] }

    func setStep(_ v: Double) {
        step = v; rated = true
        if immediate { commit() }
    }

    func add(_ items: [Data]) {
        for data in items {
            guard let image = UIImage(data: data) else { continue }
            photos.append(Photo(stored: nil, image: image, data: data))
        }
        if immediate { commit() }
    }

    func remove(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        if let name = photos[i].stored { removed.append(name) }
        photos.remove(at: i)
        if immediate { commit() }
    }

    /// Writes the rating and the photos, and drops the ones taken away.
    func commit() {
        for name in removed { NunaWorkoutReviewStore.removePhoto(name, startTs: startTs, sport: sport) }
        removed = []
        for i in photos.indices where photos[i].stored == nil {
            if let data = photos[i].data, let name = NunaWorkoutReviewStore.addPhoto(data, startTs: startTs, sport: sport) {
                photos[i].stored = name; photos[i].data = nil
            }
        }
        let review = NunaWorkoutReview(feeling: rated ? feeling.rawValue : nil, photos: photos.compactMap(\.stored))
        NunaWorkoutReviewStore.save(review, startTs: startTs, sport: sport)
    }
}

/// "How did it feel?" as a slider with four steps, and the photos as a carousel.
struct NunaWorkoutReviewCard: View {
    @ObservedObject var draft: NunaWorkoutReviewDraft
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: UUID?
    @State private var page = 0

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                feelingSlider
                NunaDivider()
                photosSection
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var datas: [Data] = []
                for item in items { if let d = try? await item.loadTransferable(type: Data.self) { datas.append(d) } }
                picked = []
                let before = draft.photos.count
                draft.add(datas)
                // Show the first one that was just added.
                if draft.photos.count > before { page = before }
            }
        }
        .fullScreenCover(item: Binding(get: { viewing.map { Photo(id: $0) } }, set: { viewing = $0?.id })) { p in viewer(p.id) }
    }

    private struct Photo: Identifiable { let id: UUID }

    // MARK: Slider

    private var feelingSlider: some View {
        let f = draft.feeling
        let tint = draft.rated ? f.tint : NunaPalette.textMuted
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                nunaTrendsCap("How did it feel?")
                Spacer()
                Text(draft.rated ? f.title : "Slide to rate").font(.nuna(size: 20, weight: .heavy)).foregroundStyle(tint)
                    .contentTransition(.opacity).animation(.easeOut(duration: 0.15), value: f)
            }
            Slider(value: Binding(get: { draft.step }, set: { draft.setStep($0.rounded()) }), in: 0...3, step: 1)
                .tint(tint)
                .sensoryFeedback(.selection, trigger: Int(draft.step))
                .accessibilityLabel(Text("How did it feel?"))
                .accessibilityValue(Text(f.title))
            // Each label sits under its own stop: the slider's ends are the first and last, the others a third apart.
            GeometryReader { geo in
                let thumb: CGFloat = 14   // the slider keeps its thumb this far inside each end
                let usable = max(geo.size.width - 2 * thumb, 1)
                ForEach(NunaWorkoutFeeling.allCases) { item in
                    let on = draft.rated && item == f
                    Text(item.title).font(.nuna(size: 10, weight: .heavy)).tracking(0).lineLimit(1).fixedSize()
                        .foregroundStyle(on ? item.tint : NunaPalette.textMuted)
                        .position(x: min(max(thumb + usable * CGFloat(item.index) / 3, labelHalf(item)), geo.size.width - labelHalf(item)), y: 8)
                }
            }
            .frame(height: 16)
        }
    }

    /// Half the width of a label, so the first and last never run off the card.
    private func labelHalf(_ item: NunaWorkoutFeeling) -> CGFloat {
        switch item { case .easy: return 18; case .fairlyHard: return 26; case .hard: return 37; case .veryHard: return 33 }
    }

    // MARK: Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                nunaTrendsCap("Photos")
                Spacer()
                PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.nuna(size: 14, weight: .bold))
                        Text("Add").font(.nuna(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                    .background(NunaPalette.glassStrong, in: Capsule())
                }
            }
            if draft.photos.isEmpty {
                Text("Add a photo of the run, the view or the gym.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            } else {
                carousel
            }
        }
    }

    /// One photo at a time, swiped sideways, with a count and dots. Tapping opens it full screen.
    private var carousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(draft.photos.enumerated()), id: \.element.id) { i, photo in
                    Button { viewing = photo.id } label: {
                        Image(uiImage: photo.image).resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 240).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 240)
            .overlay(alignment: .topTrailing) {
                if draft.photos.count > 1 {
                    Text(verbatim: "\(min(page, draft.photos.count - 1) + 1) / \(draft.photos.count)")
                        .font(.nuna(size: 12, weight: .heavy, design: NunaType.design)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 24).background(.black.opacity(0.5), in: Capsule()).padding(10)
                }
            }
            if draft.photos.count > 1 {
                HStack(spacing: 6) {
                    ForEach(draft.photos.indices, id: \.self) { i in
                        Capsule().fill(i == page ? NunaPalette.textPrimary : NunaPalette.hairline).frame(width: i == page ? 18 : 6, height: 6)
                            .animation(.easeOut(duration: 0.2), value: page)
                    }
                }
            }
        }
        .onChange(of: draft.photos.count) { _, n in page = min(page, max(n - 1, 0)) }
    }

    private func viewer(_ id: UUID) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let photo = draft.photos.first(where: { $0.id == id }) {
                Image(uiImage: photo.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                Button { draft.remove(id); viewing = nil } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }.accessibilityLabel(Text("Delete photo"))
                Button { viewing = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }.accessibilityLabel(Text("Close"))
            }
            .foregroundStyle(.white).padding(16)
        }
    }
}

// MARK: - Strava

/// Where a session stands with Strava, from the settings and the upload ledger.
enum NunaStravaState: Equatable {
    case off, notConnected, notEligible, uploaded, processing, ready
}

@MainActor
enum NunaStravaCheck {
    /// Only a GPS route or a treadmill session can go to Strava, as a FIT file.
    static func eligible(_ r: WorkoutRow) -> Bool {
        if StravaActivityType.isTreadmill(r.sport) { return true }
        guard let route = RouteStore.load(startTs: r.startTs, sport: r.sport) else { return false }
        return RouteMath.decode(route.polyline).count >= 2
    }

    static func state(_ r: WorkoutRow) -> NunaStravaState {
        guard StravaExperiment.isEnabled else { return .off }
        guard StravaTokenStore.isConnected, StravaCredentials.current != nil else { return .notConnected }
        guard eligible(r) else { return .notEligible }
        if let rec = StravaActivityStore.record(for: StravaSettingsModel.workoutKey(for: r)) { return rec.isComplete ? .uploaded : .processing }
        return .ready
    }
}

/// The Strava line of a session. After a workout it is a checkbox: ticked and locked when uploads are automatic, unticked and free when
/// they are manual (it uploads when OK is tapped). On a saved session it shows where the upload stands, with a button when it has not gone.
struct NunaWorkoutStravaCard: View {
    let row: WorkoutRow
    /// After a workout (a checkbox) or on a saved session (a status and a button).
    let afterWorkout: Bool
    @Binding var checked: Bool
    @AppStorage(StravaExperiment.automaticUploadKey) private var automatic = false
    @StateObject private var model = StravaSettingsModel()
    @State private var state: NunaStravaState = .off

    var body: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                NunaIconTile("figure.run.circle", tint: NunaPalette.effortText)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Strava").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: subtitle).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
        }
        .task { await watch() }
        .onChange(of: automatic) { _, _ in state = NunaStravaCheck.state(row); syncChecked() }
    }

    private var auto: Bool { automatic && (state == .ready || state == .processing || state == .uploaded) }

    private var subtitle: String {
        switch state {
        case .off: return String(localized: "Off. Turn it on in Me › Strava")
        case .notConnected: return String(localized: "Not connected. Connect it in Me › Strava")
        case .notEligible: return String(localized: "Only GPS and treadmill workouts go to Strava")
        case .uploaded: return String(localized: "On Strava")
        case .processing: return String(localized: "Strava is processing it")
        case .ready:
            if afterWorkout { return auto ? String(localized: "Uploaded automatically") : String(localized: "Upload when you tap OK") }
            return String(localized: "Not on Strava yet")
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .off, .notConnected, .notEligible:
            EmptyView()
        case .uploaded:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(NunaPalette.charge)
        case .processing:
            ProgressView().controlSize(.small).tint(NunaPalette.textSecondary)
        case .ready:
            if afterWorkout {
                checkbox
            } else {
                Button { Task { await model.upload(row); state = NunaStravaCheck.state(row) } } label: {
                    Text("Upload").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 16).frame(height: 34).background(NunaPalette.accent, in: Capsule())
                }.buttonStyle(.plain).disabled(model.busy)
            }
        }
    }

    private var checkbox: some View {
        Button { if !auto { checked.toggle() } } label: {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(checked ? NunaPalette.charge : NunaPalette.textSecondary)
                .opacity(auto ? 0.7 : 1)
        }
        .buttonStyle(.plain).disabled(auto)
        .accessibilityLabel(Text("Upload to Strava"))
        .accessibilityValue(Text(checked ? "On" : "Off"))
    }

    private func syncChecked() {
        // Automatic uploads are already on their way, so the box is ticked and cannot be changed; manual ones start unticked.
        if auto { checked = true }
    }

    /// Reads the settings and the ledger now, and again every couple of seconds while an automatic upload is under way.
    private func watch() async {
        for _ in 0..<30 {
            state = NunaStravaCheck.state(row)
            model.reload()
            syncChecked()
            if state == .uploaded || state == .off || state == .notConnected || state == .notEligible { break }
            if !afterWorkout && state != .processing { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

/// The review on a saved session: every change is kept as it is made.
struct NunaWorkoutReviewSection: View {
    let row: WorkoutRow
    @StateObject private var draft: NunaWorkoutReviewDraft

    init(row: WorkoutRow) {
        self.row = row
        _draft = StateObject(wrappedValue: NunaWorkoutReviewDraft(startTs: row.startTs, sport: row.sport, immediate: true))
    }

    var body: some View { NunaWorkoutReviewCard(draft: draft) }
}

/// The screen after a workout: how it felt, photos, the Strava line and OK. Nothing is kept until OK is tapped.
struct NunaWorkoutFinishedReview: View {
    let row: WorkoutRow
    let onDone: () -> Void
    @StateObject private var draft: NunaWorkoutReviewDraft
    @State private var strava = false
    @AppStorage(StravaExperiment.automaticUploadKey) private var automatic = false

    init(row: WorkoutRow, onDone: @escaping () -> Void) {
        self.row = row; self.onDone = onDone
        _draft = StateObject(wrappedValue: NunaWorkoutReviewDraft(startTs: row.startTs, sport: row.sport, immediate: false))
    }

    var body: some View {
        VStack(spacing: 14) {
            NunaWorkoutReviewCard(draft: draft)
            NunaWorkoutStravaCard(row: row, afterWorkout: true, checked: $strava)
            Button(action: ok) {
                Text("OK").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
    }

    private func ok() {
        draft.commit()
        // Manual uploads go when OK is tapped. An automatic one was started the moment the session ended.
        if strava && !automatic && NunaStravaCheck.state(row) == .ready {
            let row = row
            Task { await StravaSettingsModel().upload(row) }
        }
        onDone()
    }
}
#endif
