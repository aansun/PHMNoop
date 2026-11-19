#if os(iOS)
import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import StrandDesign

/// "Add to Anya": the photo or document a person puts in a question. One set of pickers for the Anya tab and for the sheet that opens over a page, so the
/// "+" does the same in both. The file is read on this iPhone; the result goes to `attachment` and the owner decides how it is sent.
struct NunaAnyaAttachPicker: ViewModifier {
    @Binding var attachment: NunaAnyaView.Attachment?
    @Binding var isPresented: Bool
    @State private var showPhoto = false
    @State private var showDocument = false
    @State private var photoItem: PhotosPickerItem?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .nunaDialog("Add to Anya", isPresented: $isPresented) {
                NunaDialogButton("Photo") { showPhoto = true }
                NunaDialogButton("Document") { showDocument = true }
                NunaDialogButton("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhoto, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showDocument, allowedContentTypes: [.pdf, .plainText, .commaSeparatedText, .json, .rtf, .html], allowsMultipleSelection: false) { importDocument($0) }
            .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
            .alert("Couldn't attach file", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(verbatim: error ?? "") }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                  let resized = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)), let png = resized.pngData() else {
                error = String(localized: "The selected photo could not be read."); photoItem = nil; return
            }
            attachment = .image(name: String(localized: "Photo"), base64: png.base64EncodedString()); photoItem = nil
        }
    }

    private func importDocument(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if let lab = NunaAnyaView.labAttachment(name: url.lastPathComponent, ext: url.pathExtension.lowercased(), data: data) { attachment = lab; return }
            let text: String
            switch url.pathExtension.lowercased() {
            case "pdf":
                guard let doc = PDFDocument(data: data), let s = doc.string else { throw CocoaError(.fileReadCorruptFile) }
                text = s
            case "rtf": text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
            case "html", "htm": text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil).string
            default:
                guard let s = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                text = s
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            attachment = .document(name: url.lastPathComponent, text: String(trimmed.prefix(24_000)))
        } catch {
            self.error = String(localized: "This document could not be read. Choose a PDF or a text-based document.")
        }
    }
}

extension View {
    /// The photo and document pickers of "Add to Anya", opened by setting `isPresented`; what is chosen lands in `attachment`.
    func nunaAnyaAttachPicker(attachment: Binding<NunaAnyaView.Attachment?>, isPresented: Binding<Bool>) -> some View {
        modifier(NunaAnyaAttachPicker(attachment: attachment, isPresented: isPresented))
    }
}
#endif
