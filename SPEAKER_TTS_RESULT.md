# Witness — On-device TTS (item 2): Speaker + "Read aloud" — Result

Date: 2026-08-08

## Applied
### New file: Witness/Witness/Speaker.swift
- @MainActor ObservableObject, NSObject + AVSpeechSynthesizerDelegate, import AVFoundation.
- Published isSpeaking / isPaused.
- speak(_:) — stops any current speech, configures .playback session, builds a fresh
  AVSpeechUtterance, assigns bestVoice(), rate = AVSpeechUtteranceDefaultSpeechRate * 0.92,
  pitch 1.0, speaks.
- pause() = pauseSpeaking(at: .word); resume() = continueSpeaking(); stop() =
  stopSpeaking(at: .immediate) + reset + deactivate session.
- bestVoice(): best available premium > enhanced > default for the device language, falling
  back to AVSpeechSynthesisVoice(language:). No download prompting (branded voices = item 12).
- Delegate didStart/didPause/didContinue/didFinish/didCancel → marshalled to @MainActor;
  session deactivated on finish/cancel via handleEnd() (guarded against the stop-to-restart race).

### MemoryDetailView.swift wiring
- `@StateObject private var speaker = Speaker()`.
- `readAloudControl` (teal capsule) placed directly UNDER the narrative text; speaks
  memory.narrative; toggles Read aloud → Pause → Resume.
- `.onDisappear` now also calls `speaker.stop()`.
- Mutual exclusion wired BOTH directions:
  - toggleReadAloud (start) calls `audioPlayer.stop()` first.
  - toggleListen (start) calls `speaker.stop()` first.

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: Speaker.swift and MemoryDetailView.swift both report no issues.
**0 errors, 0 warnings.**

## Confirmations requested

### (a) Distinct enough not to confuse Listen vs Read aloud
Yes — three independent differentiators:
- Placement: "Listen" is a chip in the media-actions row (with the play/pause + progress
  scrub bar below it); "Read aloud" is a separate capsule directly under the written narrative.
- Icon: Listen = `speaker.wave.2.fill` (audio waveform); Read aloud = `text.bubble.fill` (text).
- Label + hint: "Listen" (hint about the recording) vs "Read aloud" (hint: "Read this memory's
  written words aloud, on your device").
Honest note: the label is "Read aloud", NOT "Scarlett reads" — because it uses the system voice,
not a branded Scarlett voice (that's item 12). Calling it Scarlett would overclaim. If you want
it even more unambiguous, relabeling the Listen chip → "Play recording" is a one-word change I
can do on request (I did not, since you didn't ask to change Listen).

### (b) Triggering either reliably stops the other (no overlap)
Yes, wired symmetrically and verified in code:
- Start Read aloud → `audioPlayer.stop()` then `speaker.speak(...)`.
- Start Listen → `speaker.stop()` then `audioPlayer.play()`.
Both share the .playback session; stop() deactivates before the other reactivates, so they
cannot play simultaneously.

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0); mutual-exclusion wiring
  confirmed by code (both directions call the other's stop() before starting).
- NOT run interactively. Actual speech + the no-overlap behavior are device/simulator-checkable
  (open a memory → Read aloud; then tap Listen → speech stops and the recording plays, and
  vice versa). On simulator, expect the default (robotic) voice unless an enhanced voice is
  installed — accepted, this is the functional version.

## Out of scope (not built)
- No app-wide read-aloud (Learn/Explain/entity), no Talk wiring, no premium/branded voices
  (item 12), no download prompting. Engine + memories only. No permission needed. No git.
