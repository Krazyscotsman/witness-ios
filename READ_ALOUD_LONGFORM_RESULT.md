# Witness — Long-form read-aloud (chunked, resumable, chosen voice, follow-along) — Result

Date: 2026-08-09. Build **0 errors / 0 warnings**. No git.

## Applied
### Speaker.swift (rewritten)
- `speak(paragraphs: [String])`: enqueues each paragraph as its own `AVSpeechUtterance` (native queue) so a
  very long narrative reads to completion instead of truncating a single giant utterance. `speak(_:)` kept
  for short Talk replies.
- `@Published currentParagraph: Int?` + `paragraphCount: Int`, driven by a per-utterance→index map in
  `didStart`. `handleEnd()` tears down ONLY when the whole queue finishes (`!synthesizer.isSpeaking`);
  intermediate per-utterance `didFinish` calls return early.
- `voiceSelection()` reads `UserDefaults[profile.voice]` (default `playful_female`), maps `<style>_<gender>`:
  gender → male/female `AVSpeechSynthesisVoice` (prefer premium/enhanced), style → rate/pitch
  (warm=slower/lower, direct=brisker, playful=lighter/higher). Applied to EVERY utterance → one chosen voice
  for all callers (memories now, Talk later).
- pause/resume use native transport (resume from paused point); stop clears queue + resets.
- NEURAL-TTS SEAM comment at the per-chunk enqueue (Gemini/self-hosted per-chunk → AudioPlayer, same
  currentParagraph/paragraphCount contract). Not built.

### MemoryDetailView.swift
- Read-aloud now calls `speaker.speak(paragraphs: vm.paragraphs)` (snippet single-string fallback before
  detail loads). Button disabled only when both paragraphs and snippet are empty.
- Follow-along: the paragraph where `speaker.currentParagraph == i` gets a subtle teal tint; page wrapped in
  `ScrollViewReader` with `.id("para-\(i)")` and `onChange(currentParagraph)` auto-scrolls it to center.
- Progress: "Reading N of M" + a thin bar under the button while speaking/paused.
- One button unchanged (tap start/pause/resume). Listen mutual-exclusion + onDisappear stop-both preserved.

## Verified (actually executed)
- Build: **0 errors, 0 warnings.** Per-file diagnostics: Speaker.swift and MemoryDetailView.swift both
  report no issues.
- One Swift-6 warning appeared on first build (capturing non-Sendable `AVSpeechUtterance` in the `@Sendable`
  Task) and was fixed by hoisting `ObjectIdentifier(utterance)` (Sendable) out of the closure; rebuilt clean.
- **174K chunk count (RunCodeSnippet):** the ~174K single-paragraph worst case → split = **44 paragraphs**;
  `speak(paragraphs:)`'s trim+filter → **44 utterances would be enqueued**, max chunk **4000 chars, 0 over
  cap**. A normal paragraphed narrative → 3 utterances. This confirms the queue is CONSTRUCTED correctly
  (44 bounded utterances, not one giant one).
- All APIs pre-verified against the iOS 26 SDK (gender/quality, postUtteranceDelay, queue/pause/stop
  semantics, "re-enqueue throws").

## Honest scope (accepted items confirmed)
- **Audible read-to-completion is a DEVICE LISTEN — I did not and cannot hear it here.** I verified the queue
  is built with 44 bounded utterances and that it compiles/builds; whether all 44 play through end-to-end on
  hardware needs an on-device listen (also verify pause/resume mid-read and that leaving the screen stops it).
- **Paragraph-level highlight is coarse on the single-giant-paragraph April 28 memory** (chunks ≈ 4000 chars,
  so the highlight advances in big steps). Accepted; word-level highlight via
  `willSpeakRangeOfSpeechString` is left as a future enhancement — the seam remains.
- Highlight adds slight padding around each narrative paragraph (subtle layout change).
- Voice is distinguishable, not richly characterful — real character arrives with neural TTS (seam left).

## No git.
