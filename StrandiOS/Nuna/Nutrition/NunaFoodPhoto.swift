#if os(iOS)
import SwiftUI
import UIKit
import Vision

/// Photos of meals: resizing one for the provider, reading food names from it on the phone for providers that cannot see, and the camera.
enum NunaFoodPhoto {
    /// The photo shrunk to at most 1280 points on a side, as a PNG (base64) for the provider and as an image for the thumbnail.
    static func prepare(_ data: Data) -> (image: UIImage, base64: String)? {
        guard let source = UIImage(data: data) else { return nil }
        let longest = max(source.size.width, source.size.height)
        let scaled = longest > 1280 ? (source.preparingThumbnail(of: CGSize(width: 1280, height: 1280)) ?? source) : source
        guard let png = scaled.pngData() else { return nil }
        return (scaled, png.base64EncodedString())
    }

    /// Words the classifier uses for any food picture; they say nothing about what is on the plate.
    private static let generic: Set<String> = ["food", "dish", "meal", "cuisine", "plate", "bowl", "tableware", "dishware", "produce", "ingredient", "recipe",
                                              "drink", "beverage", "cup", "table", "kitchen", "snack_food", "fast_food", "baked_goods", "dessert_food", "container", "spoon", "fork", "utensil"]

    /// Food names Vision recognises in the picture, most confident first, made readable ("fried_rice" becomes "fried rice"). Runs on the phone; nothing is sent.
    static func labels(for image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil, let results = request.results else { return [] }
            var seen = Set<String>(), out: [String] = []
            for r in results where r.confidence >= 0.12 {
                let id = r.identifier.lowercased()
                guard !generic.contains(id) else { continue }
                let name = id.replacingOccurrences(of: "_", with: " ")
                if seen.insert(name).inserted { out.append(name) }
                if out.count == 5 { break }
            }
            return out
        }.value
    }
}

/// The system camera, for a photo of a meal.
struct NunaCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NunaCameraPicker
        init(_ parent: NunaCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
