# Witness — Register voice recordings with the Media gallery (item 14) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval.** No git.

## Read-first
### MediaStore item construction (and what audio needs)
- MediaStore.shared.captured holds `CapturedMedia` (MediaCapture.swift:8–24): id (auto UUID),
  `image: UIImage` (NON-optional), `kind: MediaKind`, `videoURL: URL?`, `fileName: String`.
- Gallery maps CapturedMedia → `MediaItem(id, fileName, kind, memoryTitle: nil, image: $0.image)`
  for "Recently added". Audio tile styling (gold gradient + waveform icon, like sample
  `voice_note.m4a`) renders when `kind == .audio` AND `image == nil`.
- MediaKind.audio already exists; MediaItem.image is already optional. The ONLY blocker is
  `CapturedMedia.image` being non-optional. Minimal enabling change: make it `UIImage?`.
  No URL/date needed just to appear (gallery playback is a separate TODO; group is dateless).
  Backward-compatible: camera/library still pass a real UIImage.

### Cleanest registration point
`RecordView.stopRecording()` — the record flow's save path, already holds
`recorder.lastRecordingURL`. Keeps AudioRecorder decoupled from the gallery. Precise:
cancel deletes+nils the URL (never registers); text saveMemory() path untouched.

## Proposed diff
### 1 — MediaCapture.swift (image → optional)
```diff
 struct CapturedMedia: Identifiable {
     let id = UUID().uuidString
-    let image: UIImage          // a photo, or a video's thumbnail frame
+    let image: UIImage?         // a photo, or a video's thumbnail frame; nil for audio (no frame)
     let kind: MediaKind         // .image / .video / .audio
     let videoURL: URL?
     let fileName: String
```

### 2 — RecordView.swift (register on save)
```diff
     private func stopRecording() {
         Haptics.recordStop()
         recorder.stopRecording()
+        // Register the finished recording with the in-session MediaStore the gallery reads,
+        // so it shows in "Recently added" as an audio item. Reuses the existing MediaStore /
+        // CapturedMedia (kind: .audio). In-memory only — see the limitation note below.
+        if let url = recorder.lastRecordingURL {
+            MediaStore.shared.add(CapturedMedia(image: nil, kind: .audio, videoURL: nil,
+                                                fileName: url.lastPathComponent))
+        }
         withAnimation { saved = true }
     }
```

## Honest limitation (confirmed, not solved)
MediaStore is in-memory (session-only). Registered recordings appear in "Recently added" for
the current session but do NOT persist across relaunches — expected/acceptable now; durable
storage is backend-era (item 10). NOT adding: persistence, audioURL field, video handling,
photo-library saving, upload. Sample data + layout untouched.

Alternative (not recommended): pass UIImage(systemName:"waveform") instead of making image
optional — renders a stretched glyph rather than the designed audio tile.

## After approval
Apply both edits → build 0/0 → report honestly. No git.
