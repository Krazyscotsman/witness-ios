import AVFoundation
import Combine

/// On-device text-to-speech. Fully local, no backend. Reusable — "read a memory aloud"
/// now, and the voice-output half of Talk later. Uses the best available system voice with
/// graceful fallback to the default; premium/branded voices are item 12 (no download prompting).
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Control

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }   // stop first

        configureSession()

        let utterance = AVSpeechUtterance(string: trimmed)     // fresh each time (reuse throws)
        utterance.voice = bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92   // clear, unhurried
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
        // isSpeaking flips via the didStart delegate callback.
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        deactivateSession()
    }

    // MARK: Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: Voice selection — prefer an installed premium/enhanced voice for the device
    // language, else the default. (Custom branded voices are item 12; no download prompting.)

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages.first ?? "en-US"     // BCP-47, e.g. "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices()

        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            case .default: return 1
            @unknown default: return 0
            }
        }

        if let exact = voices.filter({ $0.language == preferred })
            .max(by: { rank($0.quality) < rank($1.quality) }) {
            return exact
        }
        let base = preferred.split(separator: "-").first.map(String.init) ?? preferred
        if let sameLang = voices.filter({ $0.language.hasPrefix(base) })
            .max(by: { rank($0.quality) < rank($1.quality) }) {
            return sameLang
        }
        return AVSpeechSynthesisVoice(language: preferred) ?? AVSpeechSynthesisVoice(language: base)
    }

    // MARK: - AVSpeechSynthesizerDelegate (callbacks may arrive off-main → marshal to @MainActor)

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = true; self?.isPaused = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isPaused = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isPaused = false; self?.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.handleEnd() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.handleEnd() }
    }

    private func handleEnd() {
        // Only tear down if nothing else took over (guards the stop-to-restart race in speak()).
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        isPaused = false
        deactivateSession()
    }
}
