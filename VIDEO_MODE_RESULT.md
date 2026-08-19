# Witness — Video capture mode in RecordView — Result

Date: 2026-08-18. **Build: "The project built successfully" — 0 errors / 0 warnings.** No git. iOS-only; NO
backend transcription; video kept LOCAL only. ⚠️ **Device-only** — SpeechAnalyzer/AVCapture don't run in the
Simulator, so David device-tests the actual transcription.

## Applied
- **Info.plist** — added `NSPhotoLibraryUsageDescription` (camera/mic/speech already present).
- **VideoPicker.swift (NEW)** — `PHPickerViewController` (videos), copies the chosen movie to a temp app URL.
- **VideoStore.swift (NEW)** — moves the captured video to `Documents/WitnessVideos/<memory_id>.<ext>` after save
  (durable, memory-linked, local only; server upload deferred).
- **VideoCaptureViewModel.swift (NEW)** — `@MainActor`, `import Combine`.
  - `process(videoURL:)` → **extract audio** (`AVAssetExportSession` AppleM4A via the modern
    `export(to:as:)`; handles **no-audio-track** + export failure) → **on-device transcribe**.
  - `@available(iOS 26,*) transcribe(...)`: `SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)`
    (not raw en_US), `AssetInventory` install, **`.transcription` accurate preset**, buffer-fed
    `AsyncStream<AnalyzerInput>` with `AVAudioConverter` → **honest `framesFed/totalFrames` %**,
    `analyzeSequence(_:)` + `finalizeAndFinish(through:)`, accumulates **`isFinal`** results.
  - Layered gate: `isSupported` (compile-time `#available`) + runtime supported-locale check → graceful
    `.failed` degrade (review lets the user type; video kept).
- **RecordView.swift** — third **Video** mode:
  - `Mode` gains `.video`; `ModeSwitcher` is now data-driven (`modes:` + per-mode icon) and **hides Video
    pre-iOS 26** (`availableModes`).
  - `videoMode` compose screen: Title/date + **Record video** (`CameraPicker`, native `UIImagePickerController`)
    and **Import video** (`VideoPicker`), with a "stays on this device / never uploaded" note.
  - `startVideo(_:)` mints the session, keeps the URL, kicks off the VM, and **reuses the existing
    review-then-save** screen: `reviewText` auto-fills from `videoVM.transcript`; the status line shows
    "Extracting audio…" / "Transcribing… NN%"; Save calls the existing `submit(text:audio:nil)`.
  - On success, `VideoStore.link(video, to: memory_id)` — **video stays local**, memory created via the existing
    `POST /api/v1/memories` path (`MemoryCreateViewModel`, unchanged). Failure preserves transcript + video.
  - `retrySubmit` / `backFromFailure` / `backToCompose` handle `.video`.

## Verified
- **BuildProject → 0 errors**; **0 warnings** across all touched/new files (RecordView, VideoCaptureViewModel,
  VideoPicker, VideoStore).
- Fixed en route to 0/0: `@preconcurrency import AVFoundation` (AVFAudio Sendable), modern `export(to:as:)`
  (dropped deprecated `exportAsynchronously`/`status`), non-throwing `cancelAndFinishNow()`, and a
  concurrent-capture cleanup in the PHPicker callback.

## Honest caveats (device-only — cannot run here)
- Recording/import → local URL, `AVAssetExportSession` audio extract, the **iOS 26 SpeechAnalyzer** transcription
  + buffer/`AVAudioConverter` progress math, first-run asset download, and the review→save reuse are all runtime
  behaviors verified only by compile (0/0) + the DocumentationSearch-verified API shape. David tests on device.
- Recorder uses `UIImagePickerController` (approved) rather than a bespoke `AVCaptureSession`. Extracted audio is
  discarded after transcription; neither video nor audio is uploaded. Labels: Speak / Type / Video.
- The `AVAudioConverter` one-shot input-block and the buffer chunking are the parts most worth watching on the
  first device run; if a specific device format misbehaves, that helper is the place to adjust.

## No git.
