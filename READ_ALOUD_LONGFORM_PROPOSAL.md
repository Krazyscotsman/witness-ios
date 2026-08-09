# Witness — Long-form read-aloud (chunked, resumable, chosen voice, follow-along) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval.** No git. Accessibility requirement; must work on the
~174K-char April 28, 1993 memory.

## APIs verified (iOS 26 SDK, via DocumentationSearch)
- `AVSpeechSynthesisVoice.gender: AVSpeechSynthesisVoiceGender` (.male/.female/.unspecified) ✓
- `AVSpeechUtterance.postUtteranceDelay` / `preUtteranceDelay` ✓
- Synthesizer maintains a queue; enqueue in order; pause resumes from paused point; stop removes remaining ✓
- ⚠️ Enqueuing the SAME utterance twice throws → one fresh utterance per chunk ✓
- `willSpeakRangeOfSpeechString` = per-word ranges (future word-level highlight seam; paragraph-level now)

## Read-first findings
- `Speaker.speak(_:)` builds ONE utterance from the whole string (the 174K truncation cause); voice via
  `bestVoice()` uses locale+quality only and ignores `profile.voice`. Delegate flips isSpeaking/isPaused;
  handleEnd() resets + deactivates session guarded by `!synthesizer.isSpeaking`.
- `MemoryDetailView`: readAloudControl → toggleReadAloud() speaks `spokenText` (full narrative). Narrative =
  `LazyVStack { ForEach(vm.paragraphs.enumerated) { Text } }`. listenPlayer.toggleListen() stops speaker
  (mutual exclusion); onDisappear stops both. `MemoryDetailViewModel.paragraphs` = off-main ≤4000-char chunks.

---

## FULL proposed Speaker.swift (rewrite)
```swift
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
        let parts = id.split(separator: "_").map(String.init)
        let style = parts.first ?? "playful"
        let gender = parts.count > 1 ? parts[1] : "female"

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

    // MARK: Delegate (callbacks may arrive off-main → marshal to @MainActor)
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = true
            self.isPaused = false
            if let i = self.indexForUtterance[ObjectIdentifier(utterance)] { self.currentParagraph = i }
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
```

---

## MemoryDetailView.swift — diffs

### a) drive chunked speech + snippet fallback
```diff
     private func toggleReadAloud() {
         if speaker.isPaused { speaker.resume() }
         else if speaker.isSpeaking { speaker.pause() }
         else {
-            audioPlayer.stop()                // stop the recording player so they don't overlap
-            speaker.speak(spokenText)
+            audioPlayer.stop()                // mutual exclusion with the recording player
+            if !vm.paragraphs.isEmpty { speaker.speak(paragraphs: vm.paragraphs) }
+            else if !spokenText.isEmpty { speaker.speak(spokenText) }   // snippet before detail loads
         }
     }
```
```diff
-        .disabled(spokenText.isEmpty)
-        .opacity(spokenText.isEmpty ? 0.45 : 1)
+        .disabled(vm.paragraphs.isEmpty && spokenText.isEmpty)
+        .opacity(vm.paragraphs.isEmpty && spokenText.isEmpty ? 0.45 : 1)
```

### b) follow-along highlight + scroll ids on the narrative
```diff
     private var narrative: some View {
         LazyVStack(alignment: .leading, spacing: 14) {
-            ForEach(Array(vm.paragraphs.enumerated()), id: \.offset) { _, para in
-                Text(para)
-                    .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
-                    .lineSpacing(7)
-                    .frame(maxWidth: .infinity, alignment: .leading)
+            ForEach(Array(vm.paragraphs.enumerated()), id: \.offset) { i, para in
+                Text(para)
+                    .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
+                    .lineSpacing(7)
+                    .frame(maxWidth: .infinity, alignment: .leading)
+                    .padding(.horizontal, 10).padding(.vertical, 6)
+                    .background(RoundedRectangle(cornerRadius: 10)
+                        .fill(speaker.currentParagraph == i ? WV.teal.opacity(0.10) : .clear))
+                    .id(Self.paraID(i))
+                    .animation(.easeInOut(duration: 0.25), value: speaker.currentParagraph)
             }
         }
     }
+    private static func paraID(_ i: Int) -> String { "para-\(i)" }
```

### c) wrap the page ScrollView in ScrollViewReader + auto-scroll the spoken paragraph
```diff
-            ScrollView(showsIndicators: false) {
-                VStack(spacing: 0) {
-                    cover
-                    ...
-                }
-            }
-            .ignoresSafeArea(edges: .top)
+            ScrollViewReader { proxy in
+                ScrollView(showsIndicators: false) {
+                    VStack(spacing: 0) {
+                        cover
+                        ...
+                    }
+                }
+                .ignoresSafeArea(edges: .top)
+                .onChange(of: speaker.currentParagraph) { _, idx in
+                    guard let idx else { return }
+                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.paraID(idx), anchor: .center) }
+                }
+            }
```

### d) progress under the Read-aloud button (in loadedBody)
```diff
             readAloudControl
+            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
             if audioURL != nil {
                 listenPlayer
             } else {
                 Text("No recording to play yet.")
                     .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.4))
             }
```
```swift
    private var readAloudProgress: some View {
        let n = (speaker.currentParagraph ?? 0) + 1
        let m = max(speaker.paragraphCount, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Reading \(n) of \(m)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.1))
                    Capsule().fill(WV.teal).frame(width: geo.size.width * CGFloat(n) / CGFloat(m))
                }
            }
            .frame(height: 4)
        }
    }
```

Mutual exclusion (listenPlayer.toggleListen → speaker.stop()) and onDisappear stop-both are unchanged.

---

## Acceptance & honesty
- Build 0/0 + diagnostics after approval.
- I will verify (RunCodeSnippet) that speak(paragraphs:) with the 174K split enqueues the expected chunk
  count. **True audible read-to-completion is a device listen** — I'll say so plainly, not claim I heard it.
- Highlight is paragraph-level (coarse for the giant single-paragraph memory); word-level via
  willSpeakRange is a future enhancement. Highlight adds slight padding around each paragraph.
- No neural path built — only the commented seam.
