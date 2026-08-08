# Witness — Media display/orientation (item 13, display side) — Result

Date: 2026-08-08

## Honest outcome: the approved display fix was already in place
- Lightbox `scaledToFit`: ALREADY the current state (MediaView.swift:173 —
  `Image(uiImage: ui).resizable().scaledToFit()` in a `.frame(height: 320)`). It already shows
  the full image uncropped and correctly proportioned. No code change was needed or made — not
  faked.
- Grid `scaledToFill`: kept as-is (MediaView.swift:121), per instruction. No change.
- Net display code change: NONE (the requested state already existed).

## The one change actually made
Added an orientation-normalization DEFERRAL comment at the upload seam (MediaCapture.swift,
MediaStore):
```
// Orientation: captured UIImages carry correct .imageOrientation (EXIF), so in-app display
// (SwiftUI Image) is already upright — no per-capture normalization needed. When the upload
// path is wired (item 10), normalize the pixel buffer to .up before sending raw bytes, since
// the backend / other tools may ignore EXIF orientation.
```
No normalizedUIImage()/per-capture redraw added (deferred to item 10, as instructed).

## Build result
`The project built successfully.` — 0 errors.
MediaCapture.swift diagnostics: no issues.
**0 errors, 0 warnings.**

## Tell-apart (on-device)
Since no display code changed and the lightbox already shows the full image, if the artifact
persists on device it isolates to the capture-time stock UIImagePickerController in landscape
(item 13), NOT our display path. In-app orientation is correct via .imageOrientation.

## Not done (as instructed)
- No pixel-orientation normalization now (deferred to item 10 with the comment).
- Grid crop kept (scaledToFill). No git.
