import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import Combine

// MARK: - Captured media held in memory for the session (until upload is wired).
struct CapturedMedia: Identifiable {
    let id = UUID().uuidString
    let image: UIImage?         // a photo, or a video's thumbnail frame; nil for audio (no frame)
    let kind: MediaKind         // .image / .video / .audio
    let videoURL: URL?
    let fileName: String

    static func videoThumbnail(_ url: URL) async -> UIImage {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let result = try? await gen.image(at: time) {
            return UIImage(cgImage: result.image)
        }
        return UIImage(systemName: "play.rectangle.fill") ?? UIImage()
    }
}

// MARK: - Shared in-session store so capture from Memories OR the Gallery both show up.
// Real: each captured asset -> POST /api/v1/memories/{memory_id}/media (multipart).
// Orientation: captured UIImages carry correct .imageOrientation (EXIF), so in-app display
// (SwiftUI Image) is already upright — no per-capture normalization needed. When the upload
// path is wired (item 10), normalize the pixel buffer to .up before sending raw bytes, since
// the backend / other tools may ignore EXIF orientation.
final class MediaStore: ObservableObject {
    static let shared = MediaStore()
    @Published var captured: [CapturedMedia] = []
    private init() {}
    func add(_ m: CapturedMedia) { captured.insert(m, at: 0) }
    func remove(_ id: String) { captured.removeAll { $0.id == id } }
}

// MARK: - Reusable capture control. On a device: menu (camera / library). In the
// Simulator (no camera): goes straight to the photo library so the flow still works.
struct CaptureControl: View {
    enum Style { case cameraButton, addButton }
    var style: Style = .cameraButton
    var onCapture: (CapturedMedia) -> Void

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showMenu = false
    @State private var libraryItem: PhotosPickerItem?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button { cameraAvailable ? (showMenu = true) : (showLibrary = true) } label: { label }
            .witnessPress()
            .confirmationDialog("Add to your memories", isPresented: $showMenu, titleVisibility: .visible) {
                Button("Take Photo or Video") { showCamera = true }
                Button("Choose from Library") { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { onCapture($0) } }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in loadLibrary(item) }
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .cameraButton:
            Image(systemName: "camera.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(WV.teal, in: Circle())
                .shadow(color: WV.teal.opacity(0.3), radius: 8, y: 4)
        case .addButton:
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(WV.teal)
                .frame(width: 44, height: 44).background(WV.teal.opacity(0.12), in: Circle())
        }
    }

    private func loadLibrary(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                await MainActor.run {
                    onCapture(.init(image: img, kind: .image, videoURL: nil,
                                    fileName: "library_\(Int(Date().timeIntervalSince1970)).jpg"))
                }
            }
            await MainActor.run { libraryItem = nil }
        }
    }
}

// MARK: - Apple's camera (photo + video) via UIImagePickerController.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (CapturedMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.image", "public.movie"]
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.dismiss()
                Task {
                    let thumb = await CapturedMedia.videoThumbnail(url)
                    await MainActor.run {
                        parent.onCapture(.init(image: thumb, kind: .video, videoURL: url, fileName: url.lastPathComponent))
                    }
                }
            } else if let img = info[.originalImage] as? UIImage {
                parent.onCapture(.init(image: img, kind: .image, videoURL: nil,
                                       fileName: "photo_\(Int(Date().timeIntervalSince1970)).jpg"))
                parent.dismiss()
            }
        }
    }
}
