import Foundation
import Speech
import Combine

/// On-device, private speech-to-text for a recorded audio file. Interactive/offline only —
/// the authoritative stored transcript still comes from the backend Whisper pipeline
/// (/memories/voice), which this does NOT touch. Never falls back to cloud recognition.
@MainActor
final class Transcriber: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case done
        case unavailable(reason: String)
        case denied
        case noSpeech
    }

    @Published private(set) var isTranscribing = false
    @Published private(set) var transcript = ""
    @Published private(set) var progress: Double? = nil   // indeterminate: URL recognition reports no fraction
    @Published private(set) var state: State = .idle

    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var pendingURL: URL?                           // resumes a transcribe after a first-time auth grant

    // MARK: Permission

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            // The Speech framework does NOT guarantee this handler runs on the main thread,
            // so hop to the main actor before touching @Published state.
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized:
                    if self.state == .denied { self.state = .idle }
                    if let url = self.pendingURL { self.pendingURL = nil; self.beginRecognition(url: url) }
                case .denied, .restricted:
                    self.state = .denied; self.pendingURL = nil
                case .notDetermined:
                    self.state = .idle
                @unknown default:
                    self.state = .denied; self.pendingURL = nil
                }
            }
        }
    }

    // MARK: Transcribe

    func transcribe(url: URL) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            beginRecognition(url: url)
        case .notDetermined:
            pendingURL = url            // ask, then auto-start on grant (see requestPermission)
            requestPermission()
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranscribing = false
        if state == .running { state = .idle }
    }

    // MARK: Internals

    private func beginRecognition(url: URL) {
        cancel()
        transcript = ""
        progress = nil

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            state = .unavailable(reason: "Speech recognition isn't supported for this language.")
            return
        }
        self.recognizer = recognizer

        guard recognizer.isAvailable else {
            state = .unavailable(reason: "Speech recognition is temporarily unavailable.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // Privacy: do NOT silently fall back to cloud.
            state = .unavailable(reason: "On-device recognition isn't available for this language.")
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true      // audio stays on device
        request.shouldReportPartialResults = true

        isTranscribing = true
        state = .running

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Recognition callbacks arrive off-main → marshal to the main actor before
            // touching @Published state (same pattern as AudioRecorder/AudioPlayer).
            Task { @MainActor [weak self] in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal {
                // Code-independent no-speech path: a clean final with no words.
                finish(with: transcript.isEmpty ? .noSpeech : .done)
            }
            return
        }

        if let error {
            let ns = error as NSError
            // HEURISTIC (may be brittle across OS versions): Apple reports "no speech
            // detected" as an error, and there is no public constant. Observed codes are
            // 203 / 1110 in kAFAssistantErrorDomain. If the code matches → .noSpeech.
            // If it doesn't match, we STILL resolve cleanly (never hang): partial text →
            // .done; otherwise surface the real error via .unavailable(reason) with Apple's
            // own message (which for genuine no-speech typically reads "No speech detected").
            if ns.code == 203 || ns.code == 1110 {
                finish(with: .noSpeech)
            } else if !transcript.isEmpty {
                finish(with: .done)
            } else {
                finish(with: .unavailable(reason: ns.localizedDescription))
            }
        }
    }

    private func finish(with newState: State) {
        // Single terminal exit: guarantees isTranscribing clears and state becomes terminal
        // on EVERY path (final, error, matched/unmatched code) — no hang, no crash.
        task = nil
        isTranscribing = false
        state = newState
    }

    // For the temporary proof UI.
    var stateDescription: String {
        switch state {
        case .idle: return "idle"
        case .running: return "running"
        case .done: return "done"
        case .unavailable(let reason): return "unavailable — \(reason)"
        case .denied: return "denied"
        case .noSpeech: return "no speech detected"
        }
    }
}
