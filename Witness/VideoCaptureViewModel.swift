import SwiftUI
import Combine
@preconcurrency import AVFoundation
import Speech

/// Video → extract audio (.m4a) → on-device transcription (iOS 26 SpeechAnalyzer). Publishes an honest % while
/// transcribing (frames consumed). All published state is plain; the iOS-26 calls are gated with @available so
/// the type compiles on any OS. Video is kept LOCAL only — nothing is uploaded.
@MainActor
final class VideoCaptureViewModel: ObservableObject {
    enum Phase: Equatable { case idle, extracting, transcribing, ready, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var progress: Double = 0      // 0…1 while transcribing
    @Published private(set) var videoURL: URL?            // the local capture being processed

    /// Coarse capability gate (SpeechAnalyzer is iOS 26+). Deeper locale/availability is checked at run time.
    static var isSupported: Bool { if #available(iOS 26.0, *) { return true } else { return false } }

    private enum VErr: Error { case noAudioTrack, exportFailed, unsupported, noFormat }

    func process(videoURL url: URL) {
        videoURL = url
        transcript = ""; progress = 0
        Task { await run(url) }
    }
    func reset() {
        phase = .idle; transcript = ""; progress = 0; videoURL = nil
    }

    private func run(_ url: URL) async {
        guard Self.isSupported else { phase = .failed("Video memories require iOS 26."); return }
        do {
            phase = .extracting
            let audio = try await extractAudio(from: url)
            phase = .transcribing
            if #available(iOS 26.0, *) {
                transcript = try await transcribe(audio: audio)
                phase = .ready
            } else {
                phase = .failed("Video memories require iOS 26.")
            }
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
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VErr.exportFailed
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString).m4a")
        try await export.export(to: out, as: .m4a)   // iOS 18+ async export; throws on failure
        return out
    }

    // MARK: on-device transcription with honest progress (frames consumed)
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
                let outBuf: AVAudioPCMBuffer
                if let conv = converter, let o = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) {
                    var supplied = false
                    conv.convert(to: o, error: nil) { _, status in
                        if supplied { status.pointee = .noDataNow; return nil }
                        supplied = true; status.pointee = .haveData; return inBuf
                    }
                    outBuf = o
                } else {
                    outBuf = inBuf
                }
                cont.yield(AnalyzerInput(buffer: outBuf))
                fed += Double(inBuf.frameLength)
                let p = min(1, fed / totalFrames)
                await MainActor.run { self?.progress = p }
            }
            cont.finish()
        }

        let last = try await analyzer.analyzeSequence(inputSequence)
        if let last {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        _ = await feeder.value
        await MainActor.run { self.progress = 1 }
        return try await collector.value
    }
}
