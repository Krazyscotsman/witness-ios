# Witness — On-device Transcriber (item 3) — Result

Date: 2026-08-08

## Applied
### New file: Witness/Witness/Transcriber.swift (verified at the correct source path)
- `@MainActor final class Transcriber: ObservableObject`, `import Speech`.
- Published: `isTranscribing`, `transcript`, `progress` (nil/indeterminate), `state`
  (`.idle/.running/.done/.unavailable(reason)/.denied/.noSpeech`).
- `requestPermission()` via `SFSpeechRecognizer.requestAuthorization`, marshalled to
  @MainActor; auto-resumes a pending transcribe on grant.
- `transcribe(url:)` — status switch (authorized → run; notDetermined → ask + auto-resume;
  denied/restricted → .denied). `beginRecognition` creates `SFSpeechRecognizer(locale:.current)`,
  checks `isAvailable` + `supportsOnDeviceRecognition`, builds `SFSpeechURLRecognitionRequest`
  with `requiresOnDeviceRecognition = true` (no cloud fallback) + `shouldReportPartialResults`,
  runs `recognitionTask(with:resultHandler:)`; callback hopped to @MainActor.
- `cancel()`; single-exit `finish(with:)` guarantees no path hangs in `.running`.
- No-speech: empty final → `.noSpeech`; error code 203/1110 → `.noSpeech` (heuristic, labeled);
  else partial text → `.done`; else `.unavailable(reason:)` (kept, per your call).

### RecordView.swift — temporary proof scaffold (saved screen)
- `@StateObject private var transcriber = Transcriber()` (marked TEMP).
- `transcribeScaffold`: "Transcribe (temp)" button → `transcriber.transcribe(recorder.lastRecordingURL)`,
  shows `Engine: <stateDescription>` + live transcript in a 120pt-max scroll box. Inserted in
  savedView after `playbackBar`; `.onDisappear` now also calls `transcriber.cancel()`.
- Clearly marked as a temporary engine-validation scaffold, not a shipped feature.

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: Transcriber.swift and RecordView.swift both report no issues.
**0 errors, 0 warnings.**

## REQUIRED before running on device/simulator
Add to Info.plist (target Info tab) — user is doing this in Xcode:
- Key: NSSpeechRecognitionUsageDescription
- Value: Witness transcribes your recordings on your device so your memories become searchable text.
Without it, requestAuthorization CRASHES at request time (Apple requirement). Build is fine
without it; the crash only happens when the Transcribe button requests authorization.

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0).
- NOT run interactively. The engine is device/simulator-testable: record a memory, then tap
  "Transcribe (temp)" on the saved screen — grant speech permission (needs the Info.plist key)
  and watch partial→final transcript + engine state. On-device only; no network.

## Out of scope (not built)
- No wiring into Talk/exploration/nav/video, no backend path changes, no filler-scrubbing.
- No git.
