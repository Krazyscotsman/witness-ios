# Witness — On-device Text-to-Speech (item 2): Speaker + "Read aloud" — Proposal

Status: **PROPOSED — nothing written to the project, nothing applied.** No git. No permission needed.

## Read-first findings (MemoryDetailView)
- Memory text: `SampleMemory.narrative` is the full written body (`Text(memory.narrative)`).
  Read-aloud speaks `memory.narrative`. (Option: prepend title — flagged, not assumed.)
- "Listen" layout: `actionsRow` = 3 chips (Listen · Add media · Create image); the Listen chip
  toggles playback of the audio RECORDING, with a `listenPlayer` bar below when a recording
  exists. So "Read aloud" should be a SEPARATE control under the narrative text, distinct icon +
  label, not another chip.

## Verified iOS 26 SDK signatures
- AVSpeechSynthesizer.speak(_:) (fresh utterance each call — reuse throws)
- pauseSpeaking(at: AVSpeechBoundary) -> Bool ; stopSpeaking(at:) -> Bool ; continueSpeaking() -> Bool
- isSpeaking / isPaused ; AVSpeechBoundary.immediate / .word
- Delegate: speechSynthesizer(_:didStart:/didPause:/didContinue:/didFinish:/didCancel:)
- AVSpeechUtterance(string:), .rate, .pitchMultiplier, .voice
- AVSpeechUtteranceDefaultSpeechRate
- AVSpeechSynthesisVoice.speechVoices(), init?(language:), .quality (.default/.enhanced/.premium), .language
- Docs: system doesn't auto-retain the synthesizer → hold as stored property (view holds Speaker via @StateObject).

## New file — Speaker.swift
```swift
import AVFoundation
import Combine

/// On-device text-to-speech. Fully local, no backend. Reusable — "read a memory aloud"
/// now, and the voice-output half of Talk later. Premium/branded voices are item 12.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

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

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
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
            .max(by: { rank($0.quality) < rank($1.quality) }) { return exact }
        let base = preferred.split(separator: "-").first.map(String.init) ?? preferred
        if let sameLang = voices.filter({ $0.language.hasPrefix(base) })
            .max(by: { rank($0.quality) < rank($1.quality) }) { return sameLang }
        return AVSpeechSynthesisVoice(language: preferred) ?? AVSpeechSynthesisVoice(language: base)
    }

    // Delegate callbacks may arrive off-main → marshal to @MainActor.
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
        guard !synthesizer.isSpeaking else { return }   // guards the stop-to-restart race
        isSpeaking = false
        isPaused = false
        deactivateSession()
    }
}
```

## MemoryDetailView.swift diff
State:
```diff
     @State private var showAsk = false
+    @StateObject private var speaker = Speaker()
```
Under the narrative:
```diff
                         Text(memory.narrative)
                             .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
                             .lineSpacing(7).fixedSize(horizontal: false, vertical: true)
+                        readAloudControl.padding(.top, 6)
                         metadataRow.padding(.top, 2)
```
Stop on disappear:
```diff
-        .onDisappear { audioPlayer.stop() }
+        .onDisappear { audioPlayer.stop(); speaker.stop() }
```
New control + helpers:
```swift
    // Read aloud: speaks the memory's WRITTEN text via on-device TTS. Distinct from "Listen"
    // (which plays the audio recording). Tap toggles read → pause → resume.
    private var readAloudControl: some View {
        Button { toggleReadAloud() } label: {
            HStack(spacing: 7) {
                Image(systemName: readAloudIcon).font(.system(size: 14, weight: .medium))
                Text(readAloudLabel).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(WV.teal)
            .padding(.horizontal, 14).frame(height: 38)
            .background(WV.teal.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
        }
        .witnessPress()
        .witnessHint("Read this memory's written words aloud, on your device.")
    }

    private var readAloudIcon: String {
        if speaker.isPaused { return "play.fill" }
        if speaker.isSpeaking { return "pause.fill" }
        return "text.bubble.fill"
    }
    private var readAloudLabel: String {
        if speaker.isPaused { return "Resume" }
        if speaker.isSpeaking { return "Pause" }
        return "Read aloud"
    }
    private func toggleReadAloud() {
        if speaker.isPaused { speaker.resume() }
        else if speaker.isSpeaking { speaker.pause() }
        else {
            audioPlayer.pause()               // don't overlap with the audio-recording player
            speaker.speak(memory.narrative)
        }
    }
```

## Decisions to confirm
- Distinct-from-Listen: Read aloud uses text.bubble.fill + "Read aloud" under the narrative;
  Listen keeps speaker.wave.2.fill in the actions row. (Option: relabel Listen → "Play recording".)
- Cross-touch: toggleReadAloud pauses audioPlayer so TTS + recording don't overlap; reverse
  (stop speech when tapping Listen) NOT added unless you want it symmetric.
- Speak narrative only (vs. title + narrative). Rate = default * 0.92.

## After approval
Create Speaker.swift, apply MemoryDetailView wiring, build 0/0, report honestly. No git.
```
