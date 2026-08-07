# Witness — Step 1 (Voice-Memo Capture) — Result

Date: 2026-08-06

## Summary
Step 1 is implemented and building cleanly. A real microphone recorder writes `.m4a`
files to disk with a real monotonic elapsed timer and a normalized 0…1 input level; it
is wired into `RecordView`'s mic / pause / trash controls, timer display, and a
mic-permission alert. Out of scope (backend-owned) and NOT built: transcription,
filler-word scrubbing, memory parsing, upload/networking, playback.

## Final build result
`The project built successfully.` (Xcode BuildProject, 0 errors)

- `RecordView.swift` — diagnostics: **no issues** (clean).
- `AudioRecorder.swift` — diagnostics: **no issues** (clean).

**0 errors, 0 warnings.**

### Metering timer — final form (cycle-free AND Swift-6-clean)
The earlier retain-cycle-vs-warning tradeoff is fully resolved. The `startTimer()` timer
closure now weak-captures on the outer closure and binds a strong local before the
`Task`, so there is no retain cycle and no Swift 6 concurrency warning:
```swift
let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
    guard let self else { return }
    Task { @MainActor in self.tick() }
}
```

## Files saved
1. `Witness/Witness/AudioRecorder.swift` — new file (the recorder).
   - Note: it was initially written one directory too deep (a stray nested
     `Witness/Witness/Witness/` folder). It was moved to sit alongside the other
     sources in `Witness/Witness/`, and the stray folder was removed.
2. `Witness/Witness/RecordView.swift` — modified (wiring only):
   - Added `@StateObject private var recorder = AudioRecorder()`.
   - Removed the view's parallel `recording` / `paused` / `elapsed` state and the
     `Timer.publish` (killed the second clock — the recorder is now the single source
     of truth).
   - Mic button → `recorder.startRecording()` / `stopRecording()`.
   - Pause/resume button → `recorder.pauseRecording()` / `resumeRecording()`.
   - Trash button → `recorder.cancelRecording()` (stops + deletes the file).
   - Timer display → `Int(recorder.elapsed)` via the existing `timeString`.
   - Added a microphone-permission alert bound to `recorder.permissionDenied`
     (with an "Open Settings" deep link).
   - Swapped `import Combine` → `import UIKit` (Combine now unused here; UIKit needed
     for the Settings URL). `import Combine` remains in `AudioRecorder.swift`.

## Verification performed
- `XcodeRefreshCodeIssuesInFile` on both files → no issues.
- `BuildProject` full build → succeeded, 0 errors / 0 warnings.
- Confirmed both files' on-disk locations after the move.

## Not done (as instructed)
- No git operations (no add/commit/push).
- No transcription / scrubbing / parsing / upload / playback.
