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
    /// The chosen reading voice's display name (for the UI). Persists between reads.
    @Published private(set) var voiceName: String = ""
    /// True when only a default-quality English voice is installed (→ offer the "install Enhanced voice" hint).
    @Published private(set) var onlyDefaultQuality = false

    private let synthesizer = AVSpeechSynthesizer()
    private var indexForUtterance: [ObjectIdentifier: Int] = [:]   // utterance → paragraph index

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Interruptions (incoming call, etc.) — pause, then resume if the system says we may.
    @objc nonisolated private func handleInterruption(_ n: Notification) {
        guard let info = n.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        // Extract the Sendable values here so the @Sendable Task doesn't capture the non-Sendable userInfo dict.
        let shouldResume: Bool = {
            guard type == .ended, let o = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return false }
            return AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume)
        }()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if type == .began {
                if self.isSpeaking && !self.isPaused { self.pause() }
            } else if type == .ended, shouldResume, self.isPaused {
                self.configureSession(); self.resume()
            }
        }
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
        let voice = Self.bestReadingVoice()
        voiceName = voice?.name ?? "System voice"
        onlyDefaultQuality = (voice?.quality ?? .default) == .default
        let rate = AVSpeechUtteranceDefaultSpeechRate * 0.9    // a touch slower for comfortable listening
        for (i, para) in chunks.enumerated() {
            // NEURAL-TTS SEAM: to voice chunks with Gemini / a self-hosted neural TTS instead of the
            // on-device synthesizer, replace this per-chunk enqueue with: fetch audio for the chunk
            // (e.g. POST /api/v1/tts/generate { text: chunk, voice: <profile.voice> }), play the returned
            // bytes via AudioPlayer, set currentParagraph = i when each chunk starts, and call handleEnd()
            // after the last. The currentParagraph / paragraphCount contract is identical, so the
            // follow-along highlight + auto-scroll in MemoryDetailView need NO changes. Do NOT build now.
            for chunk in Self.sentenceChunks(para) {   // sub-split → a huge paragraph never becomes one giant utterance
                let u = AVSpeechUtterance(string: chunk)
                u.voice = voice
                u.rate = rate
                u.pitchMultiplier = 1.0                 // natural pitch
                u.postUtteranceDelay = 0.15             // a small breath between chunks
                indexForUtterance[ObjectIdentifier(u)] = i   // sub-chunk → its display paragraph (highlight intact)
                synthesizer.speak(u)                    // fresh utterance each time (re-enqueue throws)
            }
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
        let voice = Self.bestReadingVoice()
        voiceName = voice?.name ?? "System voice"
        onlyDefaultQuality = (voice?.quality ?? .default) == .default
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.pitchMultiplier = 1.0
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

    // MARK: Best reading voice (decoupled from the companion gendered voice — this is the best NARRATION voice).

    private static func voiceRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q { case .premium: return 3; case .enhanced: return 2; case .default: return 1; @unknown default: return 0 }
    }
    /// Highest-quality installed English voice (premium > enhanced > default), preferring "Ava" within the top
    /// tier, then the current locale. Independent of Profile.voiceKey (that gendered voice is for Talk).
    static func bestReadingVoice() -> AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let sorted = voices.sorted { a, b in
            if voiceRank(a.quality) != voiceRank(b.quality) { return voiceRank(a.quality) > voiceRank(b.quality) }
            let aAva = a.name.localizedCaseInsensitiveContains("Ava"), bAva = b.name.localizedCaseInsensitiveContains("Ava")
            if aAva != bAva { return aAva }
            if (a.language == preferred) != (b.language == preferred) { return a.language == preferred }
            return a.name < b.name
        }
        return sorted.first ?? AVSpeechSynthesisVoice(language: preferred)
    }
    /// For the UI (name + whether to nudge the user to install a better voice), independent of playback.
    static func readingVoiceInfo() -> (name: String, isDefaultOnly: Bool) {
        guard let v = bestReadingVoice() else { return ("System voice", true) }
        return (v.name, v.quality == .default)
    }

    /// Splits text on . ! ? and newlines (order kept), coalesces to ~`target` chars, and hard-splits any
    /// monster sentence — so a very long paragraph reads to completion instead of becoming one giant utterance.
    static func sentenceChunks(_ text: String, target: Int = 320) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        var sentences: [String] = [], cur = ""
        for ch in raw {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                let s = cur.trimmingCharacters(in: .whitespacesAndNewlines); if !s.isEmpty { sentences.append(s) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines); if !tail.isEmpty { sentences.append(tail) }
        var chunks: [String] = [], buf = ""
        for s in sentences {
            if buf.isEmpty { buf = s }
            else if buf.count + 1 + s.count <= target { buf += " " + s }
            else { chunks.append(buf); buf = s }
            while buf.count > target * 2 {
                let idx = buf.index(buf.startIndex, offsetBy: target)
                chunks.append(String(buf[..<idx])); buf = String(buf[idx...])
            }
        }
        if !buf.isEmpty { chunks.append(buf) }
        return chunks
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
