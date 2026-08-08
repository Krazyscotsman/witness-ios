# Witness — Media gallery missing recordings (item 14) — Diagnosis

Status: **DIAGNOSIS ONLY — no fix proposed, nothing changed.** No git.

## 1. Gallery data source
MediaView's live source is `MediaStore.shared.captured: [CapturedMedia]` (MediaCapture.swift:28–34)
— an in-memory, session-only @Published array (singleton, NOT persisted).
- `recentlyAdded` group built from `store.captured` → "Recently added".
- `allGroups = recentlyAdded + groups`, where `groups` is static `MediaGroup.samples`.
Only writers to `captured`: CaptureControl's onCapture →
  - MemoriesView header: `CaptureControl { MediaStore.shared.add($0) }`
  - MediaView navBar: `CaptureControl { store.add($0) }`
CaptureControl produces CapturedMedia from the camera (CameraPicker) or photo library (images only).

## 2. Audio recordings — CONFIRMED MISSING
- Path: RecordView → AudioRecorder.beginRecording() → writes Documents/Recordings/voice_<ts>.m4a,
  exposed as lastRecordingURL. Neither RecordView nor AudioRecorder ever calls MediaStore.add.
  → audio lands on disk, never registered with the gallery source → can't appear.
- Model gap: CapturedMedia requires a non-optional `image: UIImage`, its kind is only .image/.video,
  and it has `videoURL` but NO `audioURL`. MediaKind.audio exists but is unused by capture. So a fix
  needs BOTH a registration call AND a CapturedMedia/MediaStore extension for audio
  (audio URL + placeholder thumbnail).

## 3. Video — actually PRESENT in code (suspicion appears unfounded)
- CameraPicker (MediaCapture.swift:109–124): video → info[.mediaURL] → CapturedMedia(kind:.video,
  videoURL:url, image:thumb) → parent.onCapture(...) → MediaStore.add. So camera videos DO register
  and appear (thumbnail + play badge; shows under All + Video filter).
- The camera control is the ONLY video source; RecordView records AUDIO ONLY. No missing-video path.
- Non-code caveats that could make a video LOOK absent: thumbnail generator falling back to a generic
  icon (still a tile), or the camera temp videoURL being purged later (affects playback, not the tile).

## Real gap summary
- Audio: genuinely missing (never registered + model can't represent audio). This is the bug.
- Video: not missing in code (camera videos are registered + shown).
- Architectural crux for the fix: two disconnected stores — gallery reads in-memory MediaStore,
  audio lives on disk (Documents/Recordings/) and is read directly by other features (transcribe
  scaffold, MemoryDetailView.resolveMemoryAudioURL). Fix likely bridges/unifies these (register
  finished recordings into an audio-extended MediaStore, and/or make MediaStore durable) — a real
  design choice to decide before implementing.

## Next
No fix proposed yet — awaiting scope decision on how to bridge audio (and whether to make MediaStore
durable). No git.
