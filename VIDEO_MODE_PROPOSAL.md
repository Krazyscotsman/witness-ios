# Witness — Video capture mode in RecordView (record/import → extract audio → on-device transcribe → review-save) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only; NO backend transcription; video kept LOCAL
only. Propose-and-wait per CLAUDE.md. ⚠️ Device-only feature (SpeechAnalyzer won't run in the Simulator).

---

## Read-first findings
- **RecordView** already has the exact reusable spine: `Mode`(speak/type), a `ModeSwitcher` pill, and the stage
  machine `compose → reviewing → processing → done | failed`. `reviewingView` auto-fills `reviewText` from a
  transcript and its Save calls **`submit(text:audio:)`** — the single create path (`MemoryCreateViewModel.save`
  → `POST /api/v1/memories`, 120s, 401→refresh, failure preserves). **Reused as-is.**
- **MemoryCreateViewModel** reused unchanged (video → `audio: nil`; no video/audio upload).
- **MediaCapture** has `CameraPicker` (`UIImagePickerController`, `public.movie`) returning a local video URL
  with audio + `CapturedMedia.videoThumbnail`. Reused for recording.
- **Info.plist** has camera/mic/speech strings; missing `NSPhotoLibraryUsageDescription` (add).

## Verified SpeechAnalyzer API (iOS 26, from DocumentationSearch)
`SpeechTranscriber.supportedLocale(equivalentTo:) async -> Locale?` · `SpeechTranscriber(locale:preset:)` with
`.transcription` (accurate) · `AssetInventory.assetInstallationRequest(supporting:)?.downloadAndInstall()` ·
`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` · `AnalyzerInput(buffer:)` · `analyzeSequence(_:)`
returns lastSampleTime · `finalizeAndFinish(through:)` · `for try await r in transcriber.results { r.isFinal;
r.text }` · device check `SpeechTranscriber.isAvailable`/`supportedLocales`.

## Decisions / flags (recommendation first)
1. **Recorder = `UIImagePickerController` (camera, `public.movie`)**, not a bespoke `AVCaptureSession`. It's fully
   native in-app video+audio, already proven in this codebase (`CameraPicker`), and far less device-only risk.
   Import = `PHPickerViewController` (videos). *Recommend — this is the one deviation from the "AVCaptureSession"
   wording; a custom session is a sizeable follow-up if you want in-app framing/controls.*
2. **Mode labels stay app-consistent:** Speak (audio) / Type (text) / **Video** — the switcher becomes 3-way.
   (Spec said "Text/Audio/Video".) *Recommend.*
3. **No level normalization** in v1 — SpeechAnalyzer tolerates varied levels; a normalization pass (AVAudioEngine
   / export audio-mix) is deferred. *Recommend.*
4. **Extracted audio is NOT uploaded** (transcription only). **Video kept LOCAL only**, linked by filename
   `Documents/WitnessVideos/<memory_id>.<ext>` after save. Memory created via the existing text path
   (`audio: nil`). *Recommend.*
5. **iOS 26 gate:** the Video chip appears only when `#available(iOS 26)`. A deeper `SpeechTranscriber` support /
   supported-locale check runs at transcription time and degrades gracefully (review lets the user type; the
   video is kept). Pre-iOS 26 → chip hidden + a one-line note. *Recommend.*
6. **Transcription:** `.transcription` preset, `supportedLocale(equivalentTo: .current)`, asset install, and a
   **buffer-fed input sequence** so progress is honest (`framesFed/totalFrames` → "Transcribing… 44%"). isFinal
   results accumulated.

---

## Proposed diffs

### Info.plist — add photo-library string
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Witness lets you choose a video from your library to turn into a memory.</string>
```

### New file: VideoPicker.swift (import via PHPicker; copy to a local URL)
```swift
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// PHPickerViewController limited to videos. Copies the chosen movie into a temp app URL and returns it.
struct VideoPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(); cfg.filter = .videos; cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg); p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ p: VideoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { parent.dismiss(); return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                // The provided URL is temporary — copy it before it's reclaimed.
                var local: URL?
                if let url {
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("import_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")
                    try? FileManager.default.copyItem(at: url, to: dest)
                    local = dest
                }
                Task { @MainActor in
                    parent.dismiss()
                    if let local { parent.onPicked(local) }
                }
            }
        }
    }
}
```

### New file: VideoStore.swift (stable local video, linked to memory id)
```swift
import Foundation

/// Keeps captured videos on-device, linked to a memory id by filename. Server upload is deferred (50MB cap).
enum VideoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WitnessVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// Move a temp capture to a stable per-memory location. Returns the stable URL (or nil on failure).
    @discardableResult
    static func link(_ src: URL, to memoryID: String) -> URL? {
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let dest = dir.appendingPathComponent("\(memoryID).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: src, to: dest); return dest }
        catch { try? FileManager.default.copyItem(at: src, to: dest); return FileManager.default.fileExists(atPath: dest.path) ? dest : nil }
    }
    static func url(for memoryID: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first { $0.deletingPathExtension().lastPathComponent == memoryID }
    }
}
```

### New file: VideoCaptureViewModel.swift
```swift
import SwiftUI
import Combine
import AVFoundation
import Speech

/// Video → local file → extract audio (.m4a) → on-device transcription (iOS 26 SpeechAnalyzer). Publishes an
/// honest % while transcribing. All state is plain; the iOS-26 calls are gated with @available so the type
/// compiles on any OS. Video is kept LOCAL only.
@MainActor
final class VideoCaptureViewModel: ObservableObject {
    enum Phase: Equatable { case idle, extracting, transcribing, ready, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var progress: Double = 0      // 0…1 while transcribing
    @Published private(set) var videoURL: URL?            // stable local capture

    /// True only where the whole pipeline can run (SpeechAnalyzer is iOS 26+).
    static var isSupported: Bool { if #available(iOS 26.0, *) { return true } else { return false } }

    private enum VErr: Error { case noAudioTrack, exportFailed, unsupported, noFormat }

    /// Entry point: take a captured/imported video, extract audio, transcribe. Idempotent per URL.
    func process(videoURL url: URL) {
        self.videoURL = url
        transcript = ""; progress = 0
        Task { await run(url) }
    }

    private func run(_ url: URL) async {
        guard Self.isSupported else { phase = .failed("Video memories require iOS 26."); return }
        do {
            phase = .extracting
            let audio = try await extractAudio(from: url)
            phase = .transcribing
            if #available(iOS 26.0, *) {
                let text = try await transcribe(audio: audio)
                transcript = text
                phase = .ready
            } else { phase = .failed("Video memories require iOS 26.") }
        } catch VErr.noAudioTrack {
            phase = .failed("This video has no audio to transcribe — you can type the memory in the next step.")
        } catch VErr.unsupported {
            phase = .failed("On-device transcription isn’t available for your language yet — you can type it instead.")
        } catch {
            phase = .failed("Couldn’t transcribe this video — you can type the memory in the next step.")
        }
    }

    // MARK: audio extract (AppleM4A)
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw VErr.noAudioTrack }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw VErr.exportFailed }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString).m4a")
        export.outputURL = out; export.outputFileType = .m4a
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        guard export.status == .completed else { throw VErr.exportFailed }
        return out
    }

    // MARK: on-device transcription with honest progress
    @available(iOS 26.0, *)
    private func transcribe(audio audioURL: URL) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { throw VErr.unsupported }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await req.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw VErr.noFormat }
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let file = try AVAudioFile(forReading: audioURL)
        let totalFrames = max(1, Double(file.length))

        // Collect finalized text concurrently.
        let collector = Task { () throws -> String in
            var acc = AttributedString()
            for try await r in transcriber.results where r.isFinal { acc += r.text }
            return String(acc.characters)
        }

        // Feed the file as converted buffers; report % on frames consumed.
        let (inputSequence, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let converter = AVAudioConverter(from: file.processingFormat, to: format)
        let feeder = Task { [weak self] in
            let chunk: AVAudioFrameCount = 16_000
            var fed: Double = 0
            while true {
                guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
                do { try file.read(into: inBuf) } catch { break }
                if inBuf.frameLength == 0 { break }
                let out = converter.flatMap { conv -> AVAudioPCMBuffer? in
                    guard let o = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
                    var done = false
                    conv.convert(to: o, error: nil) { _, s in if done { s.pointee = .noDataNow; return nil }; done = true; s.pointee = .haveData; return inBuf }
                    return o
                } ?? inBuf
                cont.yield(AnalyzerInput(buffer: out))
                fed += Double(inBuf.frameLength)
                let p = min(1, fed / totalFrames)
                await MainActor.run { self?.progress = p }
            }
            cont.finish()
        }

        let last = try await analyzer.analyzeSequence(inputSequence)
        if let last { try await analyzer.finalizeAndFinish(through: last) } else { try await analyzer.cancelAndFinishNow() }
        _ = await feeder.value
        await MainActor.run { self.progress = 1 }
        return try await collector.value
    }
}
```
*(The buffer/`AVAudioConverter` details are the one part I can only fully validate on a device — flagged.)*

### RecordView.swift — key changes
- Add the mode + VM + capture presentation state:
```swift
enum Mode: String, CaseIterable { case speak = "Speak", type = "Type", video = "Video" }
@StateObject private var videoVM = VideoCaptureViewModel()
@State private var pendingVideoURL: URL?     // held until save, then linked to the memory id
@State private var showVideoRecorder = false
@State private var showVideoPicker = false
```
- `ModeSwitcher`: make it iterate `Mode.allCases` **filtered** so `.video` only appears when
  `VideoCaptureViewModel.isSupported`; add an icon per mode (`speak→mic.fill`, `type→pencil`, `video→video.fill`).
- Body `.compose`: `if mode == .speak { speakMode } else if mode == .type { typeMode } else { videoMode }`.
- New `videoMode`: Title/date fields + two big buttons — **Record video** (`showVideoRecorder`, reuses
  `CameraPicker`, video only) and **Import video** (`showVideoPicker` → `VideoPicker`). A short note: "Your video
  stays on this device. We transcribe it here — nothing is uploaded." On capture/import → `startVideo(url)`.
- Presentations:
```swift
.fullScreenCover(isPresented: $showVideoRecorder) { CameraPicker { m in if let u = m.videoURL { startVideo(u) } } }
.fullScreenCover(isPresented: $showVideoPicker) { VideoPicker { startVideo($0) } }
```
- `startVideo(_:)` → mint session id, keep the URL, kick off the VM, go to review:
```swift
private func startVideo(_ url: URL) {
    sessionID = UUID().uuidString
    pendingVideoURL = url
    reviewText = ""
    videoVM.process(videoURL: url)
    withAnimation { stage = .reviewing }
}
```
- **Reuse `reviewingView`** with a small branch so video drives the transcript + status:
  - Autofill: add `.onChange(of: videoVM.transcript) { _, v in if mode == .video, !v.isEmpty { reviewText = v } }`.
  - Status line: when `mode == .video`, show the video phase — `extracting` → "Extracting audio…",
    `transcribing` → "Transcribing… \(Int(videoVM.progress*100))%", `failed(let m)` → m, `ready` → hidden. (The
    existing `transcriptStatusLine` stays for Speak.)
  - Save stays `submit(text: reviewText, audio: nil)`.
- `submit(...)` success branch: when a video is pending, link it to the new memory id (video stays local):
```swift
let id = await saver.save(...)
if let id {
    if mode == .video, let v = pendingVideoURL { VideoStore.link(v, to: id) }
    onSaved?(); withAnimation { stage = .done }
} else { ...failed... }
```
  *(needs `saver.save` id captured — it already returns the id; today `submit` only checks non-nil. Minimal
  tweak to bind `id` and use it.)*
- `retrySubmit()` / `backToCompose()` handle `.video` (submit with `audio: nil`; reset `videoVM`/`pendingVideoURL`).
- `ModeSwitcher` note under the pill when unsupported device: "Video memories require iOS 26." (only if we
  choose to show a disabled chip; default is to hide it).

### (No change) MemoryCreateViewModel, InsightsView, the create endpoint.

---

## After approval
Apply, then **BuildProject → 0/0** + per-file diagnostics: Info.plist (build), VideoPicker, VideoStore,
VideoCaptureViewModel, RecordView (+ MediaCapture if I touch CameraPicker for video-only).

Honest caveats I can't run here (all **device-only** — SpeechAnalyzer/AVCapture don't work in the Simulator):
the record/import → local URL, AVAssetExportSession audio extract (incl. no-audio-track), the **iOS 26
SpeechAnalyzer** transcription + buffer/`AVAudioConverter` progress math, asset download on first run, and the
review→save reuse. Video is stored locally and linked by memory id; **nothing is uploaded**. No git.
