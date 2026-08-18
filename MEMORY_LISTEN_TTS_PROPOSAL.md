# Witness — Memory "Listen" (on-device TTS) upgrade — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only, no backend.

## Read-first (current state — more advanced than assumed)
- Trigger: MemoryDetailView `readAloudControl` pill → `toggleReadAloud()` → `speaker.speak(paragraphs: vm.paragraphs)`
  (or `speaker.speak(spokenText)` snippet fallback). Pill toggles Read aloud → Pause → Resume. `readAloudProgress`
  = "Reading N of M" + bar. Follow-along highlight + auto-scroll via `speaker.currentParagraph`. Stop on
  disappear + when the recording player starts.
- `Speaker.swift` ALREADY: chunked utterance queue (one per paragraph), transport (pause .word / resume / stop),
  `.playback` session, quality-ranked voice (premium>enhanced>default) but GENDER-constrained from
  `Profile.voiceKey`, currentParagraph/paragraphCount, neural-TTS seam comment.
- Gaps: (1) no Ava/best-English pick; (2) voice name not exposed/shown; (3) NO interruption handling;
  (4) whole-paragraph chunks → a 108K one-paragraph memory = one giant utterance (stall risk); (5) no Stop
  button; (6) no "download Enhanced voice" hint; (7) `listenPlayer` plays a RANDOM most-recent local .m4a via
  `resolveMemoryAudioURL()` (the placeholder/random-clip).

## Decisions (recommended; change any)
1. Memory read-aloud uses the BEST device voice (Ava/premium), not the companion gendered voice (companion
   unchanged elsewhere).
2. Kill the random-clip player (`resolveMemoryAudioURL → nil`); keep the recording UI dormant for a future
   per-memory audio endpoint (don't rip it out).
3. Paragraph-granular progress kept; internal sentence sub-chunks for reliability.

---

## Speaker.swift — best voice + interruptions + sentence sub-chunking + name/quality

### Published additions
```diff
     @Published private(set) var currentParagraph: Int?
     @Published private(set) var paragraphCount = 0
+    @Published private(set) var voiceName: String = ""          // chosen reading voice, for display
+    @Published private(set) var onlyDefaultQuality = false      // true → no enhanced/premium English installed
```

### init/deinit — interruption observer
```diff
     override init() {
         super.init()
         synthesizer.delegate = self
+        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
+                                               name: AVAudioSession.interruptionNotification, object: nil)
     }
+    deinit { NotificationCenter.default.removeObserver(self) }
+
+    @objc nonisolated private func handleInterruption(_ n: Notification) {
+        guard let info = n.userInfo,
+              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
+              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
+        Task { @MainActor [weak self] in
+            guard let self else { return }
+            if type == .began {
+                if self.isSpeaking && !self.isPaused { self.pause() }              // e.g. incoming call
+            } else if type == .ended {
+                let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
+                    .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
+                if opts.contains(.shouldResume) && self.isPaused { self.configureSession(); self.resume() }
+            }
+        }
+    }
```

### Best reading voice (English, quality-ranked, prefer Ava) + name/quality
```swift
// The best installed English voice for narration: highest quality (premium>enhanced>default), preferring
// "Ava" within the top tier, then the current locale. Independent of the companion gendered voice.
private static func voiceRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
    switch q { case .premium: return 3; case .enhanced: return 2; case .default: return 1; @unknown default: return 0 }
}
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

// Sentence/paragraph chunker: split on . ! ? and newlines (order kept), coalesce to ~target chars, hard-split
// any monster sentence. Ensures a very long paragraph reads to completion without a single giant utterance.
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
        if buf.isEmpty { buf = s } else if buf.count + 1 + s.count <= target { buf += " " + s } else { chunks.append(buf); buf = s }
        while buf.count > target * 2 {
            let idx = buf.index(buf.startIndex, offsetBy: target)
            chunks.append(String(buf[..<idx])); buf = String(buf[idx...])
        }
    }
    if !buf.isEmpty { chunks.append(buf) }
    return chunks
}
```

### speak(paragraphs:) — sub-split per paragraph, map back to paragraph index, set name/quality
```diff
     func speak(paragraphs: [String]) {
-        let chunks = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
-        guard !chunks.isEmpty else { return }
+        let paras = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
+        guard !paras.isEmpty else { return }
         synthesizer.stopSpeaking(at: .immediate)
         indexForUtterance.removeAll()
         currentParagraph = nil
-        paragraphCount = chunks.count
+        paragraphCount = paras.count
         configureSession()
-        let selection = voiceSelection()
-        for (i, chunk) in chunks.enumerated() {
-            let u = AVSpeechUtterance(string: chunk)
-            u.voice = selection.voice
-            u.rate = selection.rate
-            u.pitchMultiplier = selection.pitch
-            u.postUtteranceDelay = 0.2
-            indexForUtterance[ObjectIdentifier(u)] = i
-            synthesizer.speak(u)
-        }
+        let voice = Self.bestReadingVoice()
+        voiceName = voice?.name ?? "System voice"
+        onlyDefaultQuality = (voice?.quality ?? .default) == .default
+        let rate = AVSpeechUtteranceDefaultSpeechRate * 0.9   // a touch slower for comfortable listening
+        for (i, para) in paras.enumerated() {
+            // NEURAL-TTS SEAM (unchanged contract): swap this per-chunk enqueue for fetch+play; keep
+            // indexForUtterance[u] = i so the paragraph highlight/auto-scroll need no changes.
+            for chunk in Self.sentenceChunks(para) {          // huge paragraphs → many small utterances (no stall)
+                let u = AVSpeechUtterance(string: chunk)
+                u.voice = voice; u.rate = rate; u.pitchMultiplier = 1.0; u.postUtteranceDelay = 0.15
+                indexForUtterance[ObjectIdentifier(u)] = i     // sub-chunk → its display paragraph
+                synthesizer.speak(u)
+            }
+        }
     }
```

### speak(_:) short path — use the best reading voice too
```diff
-        configureSession()
-        let selection = voiceSelection()
-        let u = AVSpeechUtterance(string: trimmed)
-        u.voice = selection.voice
-        u.rate = selection.rate
-        u.pitchMultiplier = selection.pitch
-        synthesizer.speak(u)
+        configureSession()
+        let voice = Self.bestReadingVoice()
+        voiceName = voice?.name ?? "System voice"
+        onlyDefaultQuality = (voice?.quality ?? .default) == .default
+        let u = AVSpeechUtterance(string: trimmed)
+        u.voice = voice; u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9; u.pitchMultiplier = 1.0
+        synthesizer.speak(u)
```
Remove the now-unused `voiceSelection()` + `bestVoice(gender:)` (replaced by `bestReadingVoice()`).
`voiceName`/`onlyDefaultQuality` reset to ""/false in `stop()`/`handleEnd()` is optional (harmless to keep last value; I'll leave voiceName so the label persists between reads).

## MemoryDetailView.swift — Stop button, voice name, install hint, kill random clip

### readAloudControl — add a Stop button beside the pill
```diff
-        .disabled(vm.paragraphs.isEmpty && spokenText.isEmpty)
-        .opacity(vm.paragraphs.isEmpty && spokenText.isEmpty ? 0.45 : 1)
-        .witnessPress()
-        .witnessHint("Read this memory's written words aloud, on your device.")
+        // (unchanged pill) …
```
```swift
// New: show Read-aloud pill + Stop together while speaking.
private var readAloudRow: some View {
    HStack(spacing: 10) {
        readAloudControl
        if speaker.isSpeaking || speaker.isPaused {
            Button { speaker.stop() } label: {
                HStack(spacing: 6) { Image(systemName: "stop.fill").font(.system(size: 13, weight: .medium)); Text("Stop").font(.system(size: 14, weight: .medium)) }
                    .foregroundStyle(WV.danger).padding(.horizontal, 14).frame(height: 38)
                    .background(WV.danger.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(WV.danger.opacity(0.25), lineWidth: 1))
            }.witnessPress()
        }
        Spacer(minLength: 0)
    }
}
```
loadedBody: replace `readAloudControl` with `readAloudRow`, and add the install hint under the progress.
```diff
-            readAloudControl
-            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
+            readAloudRow
+            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
+            enhancedVoiceHint
```

### readAloudProgress — add the voice name line
```diff
             Text("Reading \(n) of \(m)")
                 .font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.5))
+            if !speaker.voiceName.isEmpty {
+                Text("Voice: \(speaker.voiceName)").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
+            }
```

### One-time dismissible "install a better voice" hint
```swift
@AppStorage("hint.enhancedVoiceDismissed") private var enhancedVoiceHintDismissed = false
@State private var onlyDefaultVoice = false   // set on appear via Speaker.readingVoiceInfo()

@ViewBuilder private var enhancedVoiceHint: some View {
    if onlyDefaultVoice && !enhancedVoiceHintDismissed {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.wave.2").font(.system(size: 13)).foregroundStyle(WV.gold)
            Text("For a more natural voice, add an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices, then reopen.")
                .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { enhancedVoiceHintDismissed = true } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.4)) }
        }
        .padding(12).background(WV.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
```
Set `onlyDefaultVoice` in `.onAppear`: `onlyDefaultVoice = Speaker.readingVoiceInfo().isDefaultOnly`.

### Kill the random-clip player
```diff
     private func resolveMemoryAudioURL() -> URL? {
-        let fm = FileManager.default
-        …most-recent local Recordings/*.m4a…
+        // Placeholder removed: no per-memory audio endpoint yet, so do NOT play an unrelated recording.
+        // When GET /api/v1/memories/{id}/audio exists, resolve + return it here; the listenPlayer UI is ready.
+        return nil
     }
```
(The `listenPlayer` block then never shows a random clip; "No recording to play yet." remains — or hide that
line too if you prefer.)

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the real voice quality (Ava/premium vs default), long-memory
start-to-finish read, call-interruption pause/resume, and the install hint are device checks (the simulator has
limited voices). Option B (Gemini HD) plugs into the documented seam behind a future toggle. No git.
