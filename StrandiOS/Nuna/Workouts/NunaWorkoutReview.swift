#if os(iOS)
import SwiftUI
import PhotosUI
import StrandDesign

/// How hard a session felt, in the wearer's own words. It is the person's read, not a measurement: Anya uses it to size what comes next.
enum NunaWorkoutFeeling: String, CaseIterable, Identifiable {
    case easy, fairlyHard, hard, veryHard
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .easy: return "Easy"
        case .fairlyHard: return "Fairly hard"
        case .hard: return "Hard"
        case .veryHard: return "Very hard"
        }
    }
    var plain: String {
        switch self {
        case .easy: return String(localized: "Easy")
        case .fairlyHard: return String(localized: "Fairly hard")
        case .hard: return String(localized: "Hard")
        case .veryHard: return String(localized: "Very hard")
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
    var symbol: String {
        switch self {
        case .easy: return "gauge.with.dots.needle.0percent"
        case .fairlyHard: return "gauge.with.dots.needle.33percent"
        case .hard: return "gauge.with.dots.needle.67percent"
        case .veryHard: return "gauge.with.dots.needle.100percent"
        }
    }
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

/// "How was it?" and the photos of a session. Used on the screen that follows a workout and on the saved session.
struct NunaWorkoutReviewCard: View {
    let startTs: Int
    let sport: String
    @State private var review = NunaWorkoutReview()
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: String?
    @State private var loaded = false

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    nunaTrendsCap("How did it feel?")
                    HStack(spacing: 8) {
                        ForEach(NunaWorkoutFeeling.allCases) { f in feelingButton(f) }
                    }
                }
                NunaDivider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        nunaTrendsCap("Photos")
                        Spacer()
                        PhotosPicker(selection: $picked, maxSelectionCount: 4, matching: .images) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.nuna(size: 14, weight: .bold))
                                Text("Add").font(.nuna(size: 13.5, weight: .bold))
                            }
                            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                            .background(NunaPalette.glassStrong, in: Capsule())
                        }
                    }
                    if review.photos.isEmpty {
                        Text("Add a photo of the run, the view or the gym.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(review.photos, id: \.self) { name in
                                    if let img = NunaWorkoutReviewStore.image(name, startTs: startTs, sport: sport) {
                                        Button { viewing = name } label: {
                                            Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(startTs)|\(sport)") {
            review = NunaWorkoutReviewStore.load(startTs: startTs, sport: sport); loaded = true
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let name = NunaWorkoutReviewStore.addPhoto(data, startTs: startTs, sport: sport) { review.photos.append(name) }
                }
                picked = []
                NunaWorkoutReviewStore.save(review, startTs: startTs, sport: sport)
            }
        }
        .fullScreenCover(item: Binding(get: { viewing.map { Photo(name: $0) } }, set: { viewing = $0?.name })) { photo in
            viewer(photo.name)
        }
    }

    private struct Photo: Identifiable { let name: String; var id: String { name } }

    private func feelingButton(_ f: NunaWorkoutFeeling) -> some View {
        let on = review.feeling == f.rawValue
        return Button {
            // Tapping the chosen one again clears it.
            review.feeling = on ? nil : f.rawValue
            NunaWorkoutReviewStore.save(review, startTs: startTs, sport: sport)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: f.symbol).font(.nuna(size: 18, weight: .semibold))
                Text(f.title).font(.nuna(size: 11, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center).padding(.horizontal, 2)
            }
            .foregroundStyle(on ? Color.black : f.tint)
            .frame(maxWidth: .infinity).frame(height: 70)
            .background(on ? f.tint : f.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(f.tint.opacity(on ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func viewer(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let img = NunaWorkoutReviewStore.image(name, startTs: startTs, sport: sport) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                Button {
                    NunaWorkoutReviewStore.removePhoto(name, startTs: startTs, sport: sport)
                    review.photos.removeAll { $0 == name }
                    NunaWorkoutReviewStore.save(review, startTs: startTs, sport: sport)
                    viewing = nil
                } label: { Image(systemName: "trash").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
                    .accessibilityLabel(Text("Delete photo"))
                Button { viewing = nil } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
                    .accessibilityLabel(Text("Close"))
            }
            .foregroundStyle(.white).padding(16)
        }
    }
}
#endif
