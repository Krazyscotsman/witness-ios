import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// PHPickerViewController limited to videos. Copies the chosen movie into a temp app URL (the provider's URL is
/// reclaimed once the callback returns) and hands back a local URL.
struct VideoPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .videos
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ p: VideoPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                Task { @MainActor in parent.dismiss() }
                return
            }
            let p = self.parent
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                let local: URL? = {
                    guard let url else { return nil }
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("import_\(UUID().uuidString).\(ext)")
                    try? FileManager.default.copyItem(at: url, to: dest)
                    return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
                }()
                Task { @MainActor in
                    p.dismiss()
                    if let local { p.onPicked(local) }
                }
            }
        }
    }
}
