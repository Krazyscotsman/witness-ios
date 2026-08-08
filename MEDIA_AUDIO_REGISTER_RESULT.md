# Witness — Register voice recordings with the Media gallery (item 14) — Result

Date: 2026-08-08

## Applied (2 edits)
### MediaCapture.swift
- `CapturedMedia.image`: `UIImage` → `UIImage?` (nil for audio, which has no frame). Comment
  updated to note `.audio`. Backward-compatible: camera/library still pass a real UIImage;
  the gallery's `MediaItem.image` was already optional.

### RecordView.swift — stopRecording()
- After `recorder.stopRecording()`, register the finished file with the in-session MediaStore:
  `MediaStore.shared.add(CapturedMedia(image: nil, kind: .audio, videoURL: nil,
   fileName: url.lastPathComponent))` guarded by `recorder.lastRecordingURL`.
- Single finalize point; cancel (deletes+nils the URL) and the text saveMemory() path never register.

## Visual distinguishability (per your note)
Audio items pass `image: nil`, so the gallery tile renders its designed `.audio` styling —
a GOLD gradient (MediaKind.audio.tone = 0xb08828) + a centered "waveform" icon — clearly
distinct at a glance from photo tiles (which show the actual photo, or a teal "photo" icon).
Matches the existing sample audio item (voice_note.m4a). Also selectable under the "Audio" filter chip.

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: MediaCapture.swift and RecordView.swift both report no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0).
- NOT run interactively. Expected: record a voice memory → on stop it appears in the Media
  gallery's "Recently added" as a gold waveform audio tile. Simulator/device-checkable.

## Accepted limitation (confirmed, not solved)
MediaStore is in-memory (session-only). Registered recordings appear this session but do NOT
persist across app relaunches — accepted for now; durable storage is backend-era (item 10).

## Out of scope (not built)
- No persistence, no audioURL field, no video handling (item 15), no photo-library save, no upload.
- Sample data + gallery layout untouched. No git.
