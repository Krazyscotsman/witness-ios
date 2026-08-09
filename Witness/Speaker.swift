import AVFoundation
import Combine

/// On-device text-to-speech. Fully local, no backend. Long-form read-aloud speaks a memory paragraph by
/// paragraph as a native utterance queue (so even the densest ~174K-char narrative reads to completion),
/// in the user's chosen companion voice, and reports which paragraph is speaking for follow-along highlight.
/// A single-string speak(_:) remains for short Talk replies. Neural TTS (Gemini/self-hosted) can slot in
/// behind the same contract later — see the seam in speak(paragraphs:).
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    /// Index (into the paragraphs passed to speak(paragraphs:)) of the chunk currently being spoken.
    @Published private(set) var currentParagraph: Int?
    /// Total chunks in the current long-form read (0 when idle or during single-string speak).
    @Published private(set) var paragraphCount = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var indexForUtterance: [ObjectIdentifier: Int] = [:]   // utterance → paragraph index

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Long-form (chunked, queued) — the memory read-aloud path.

    /// Enqueues each paragraph as its own AVSpeechUtterance. The synthesizer speaks them in order as a
    /// native queue, so a very long narrative (e.g. ~174K chars ≈ 44 chunks) reads to completion instead of
    /// truncating the way a single giant utterance does. Uses the chosen companion voice for every chunk.
    /// pause()/resume()/stop() act on the whole queue.
    func speak(paragraphs: [String]) {
        let chunks = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !chunks.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)   // clear anything already queued
        indexForUtterance.removeAll()
        currentParagraph = nil
        paragraphCount = chunks.count

        configureSession()
        let selection = voiceSelection()
        for (i, chunk) in chunks.enumerated() {
            // NEURAL-TTS SEAM: to voice chunks with Gemini / a self-hosted neural TTS instead of the
            // on-device synthesizer, replace this per-chunk enqueue with: fetch audio for `chunk`
            // (e.g. POST /api/v1/tts/generate { text: chunk, voice: <profile.voice> }), play the returned
            // bytes via AudioPlayer, set currentParagraph = i when each chunk starts, and call handleEnd()
            // after the last. The currentParagraph / paragraphCount contract is identical, so the
            // follow-along highlight + auto-scroll in MemoryDetailView need NO changes. Do NOT build now.
            let u = AVSpeechUtterance(string: chunk)
            u.voice = selection.voice
            u.rate = selection.rate
            u.pitchMultiplier = selection.pitch
            u.postUtteranceDelay = 0.2                 // a small breath between paragraphs
            indexForUtterance[ObjectIdentifier(u)] = i
            synthesizer.speak(u)                       // fresh utterance each time (re-enqueue throws)
        }
    }

    // MARK: Short single-string — kept for Talk replies / short prompts.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        indexForUtterance.removeAll()
        currentParagraph = nil
        paragraphCount = 0

        configureSession()
        let selection = voiceSelection()
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = selection.voice
        u.rate = selection.rate
        u.pitchMultiplier = selection.pitch
        synthesizer.speak(u)
    }

    // MARK: Transport (whole queue)
    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)   // resumes from this point, not the chunk start
    }
    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        indexForUtterance.removeAll()
        isSpeaking = false
        isPaused = false
        currentParagraph = nil
        paragraphCount = 0
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

    // MARK: Chosen companion voice — read once, applied to every utterance.

    /// Reads profile.voice (default "playful_female") and maps <style>_<gender> onto an on-device voice:
    /// gender → male/female AVSpeechSynthesisVoice (prefer premium/enhanced), style → rate/pitch character.
    /// Honest: distinguishable, not richly characterful — real character arrives with neural TTS.
    private func voiceSelection() -> (voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float) {
        let id = UserDefaults.standard.string(forKey: Profile.voiceKey) ?? "playful_female"
        // Accepts a full "<style>_<gender>" id OR a bare gender ("female"/"male"); anything else → female,
        // default character. Never crashes on an unexpected value.
        let tokens = id.split(separator: "_").map(String.init)
        let gender = (tokens.last == "male") ? "male" : "female"
        let style = tokens.count >= 2 ? tokens[0] : "default"   // bare gender → neutral rate/pitch

        let base = AVSpeechUtteranceDefaultSpeechRate
        var rate = base * 0.92
        var pitch: Float = 1.0
        switch style {
        case "warm":    rate = base * 0.88; pitch = 0.96   // calm, unhurried, a touch lower
        case "direct":  rate = base * 0.96; pitch = 1.00   // brisker, neutral
        case "playful": rate = base * 0.94; pitch = 1.08   // lighter, a touch higher
        default: break
        }
        return (bestVoice(gender: gender), rate, pitch)
    }

    private func bestVoice(gender: String) -> AVSpeechSynthesisVoice? {
        let wanted: AVSpeechSynthesisVoiceGender = (gender == "male") ? .male : .female
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let base = preferred.split(separator: "-").first.map(String.init) ?? preferred
        let voices = AVSpeechSynthesisVoice.speechVoices()

        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            case .default: return 1
            @unknown default: return 0
            }
        }
        // exact locale + gender → base-language + gender → locale (any gender) → constructed fallback.
        if let v = voices.filter({ $0.language == preferred && $0.gender == wanted })
            .max(by: { rank($0.quality) < rank($1.quality) }) { return v }
        if let v = voices.filter({ $0.language.hasPrefix(base) && $0.gender == wanted })
            .max(by: { rank($0.quality) < rank($1.quality) }) { return v }
        if let v = voices.filter({ $0.language == preferred })
            .max(by: { rank($0.quality) < rank($1.quality) }) { return v }
        return AVSpeechSynthesisVoice(language: preferred) ?? AVSpeechSynthesisVoice(language: base)
    }

    // MARK: - AVSpeechSynthesizerDelegate (callbacks may arrive off-main → marshal to @MainActor)

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)   // hoist out: ObjectIdentifier is Sendable, the utterance isn't
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = true
            self.isPaused = false
            if let i = self.indexForUtterance[key] { self.currentParagraph = i }
        }
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

    /// Tears down only when the WHOLE queue is done (synthesizer no longer speaking). Intermediate
    /// per-utterance didFinish calls return early because the next queued utterance keeps isSpeaking true.
    private func handleEnd() {
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        isPaused = false
        currentParagraph = nil
        paragraphCount = 0
        indexForUtterance.removeAll()
        deactivateSession()
    }
}
