# Witness — Memory playback ("Listen") Result

Date: 2026-08-07

## Applied (MemoryDetailView.swift only)
- Added `@StateObject private var audioPlayer = AudioPlayer()` (reused existing player;
  no second player class) and `@State private var audioURL: URL?`.
- Listen chip wired to real play/pause: icon/label swap (speaker.wave.2.fill "Listen" ↔
  pause.fill "Pause"), `.disabled`/dimmed when `audioURL == nil`, hint corrected to
  "Play this memory's audio recording." (was TTS wording).
- Compact `listenPlayer` bar (teal play/pause `witnessPress()` + teal progress capsule on
  light track + mm:ss monospaced labels) — mirrors the saved-screen player — shown below
  `actionsRow` when `audioURL != nil`.
- Explicit empty state: when `audioURL == nil`, a subtle visible line
  "No recording to play yet." is shown (in addition to the dimmed chip).
- `.onAppear` resolves + loads the audio; `.onDisappear` stops playback.
- `resolveMemoryAudioURL(for:)`: returns the newest `Documents/Recordings/*.m4a` (or nil),
  with `// PLACEHOLDER until GET /api/v1/memories/{id}/audio` and a note that SampleMemory
  has only a client-side UUID, not a server id. No network call implemented.

Redundancy (approved): both the Listen chip and the bar can toggle play/pause — intentional.

## Build result
`The project built successfully.` — 0 errors.
`MemoryDetailView.swift` diagnostics: no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + successful full build + per-file diagnostics.
- NOT run interactively here. Playback is device/simulator-checkable because it plays a
  real local `.m4a`: record something first (so Documents/Recordings/ has a file), then open
  a memory — the bar should play the newest recording; with no recordings, the chip is
  dimmed and "No recording to play yet." shows.

## Out of scope (as instructed)
- No transcription, TTS, Talk voice loop, or networking/streaming.
- The real GET /memories/{id}/audio is a marked placeholder, not implemented.
- No git.
