# Witness — Camera landscape artifact (item 13) — Diagnosis

Status: **DIAGNOSIS ONLY — no fix, nothing changed.** No git.
(Docs-verified; NOT reproduced on device here.)

## CameraPicker config (MediaCapture.swift:90–126)
`sourceType = .camera`, `mediaTypes = ["public.image","public.movie"]`, `videoQuality = .typeHigh`,
delegate set. NO orientation handling: no cameraViewTransform, no cameraOverlayView, no
supported-orientation override, allowsEditing default (false). Stock system camera picker.
Photos via info[.originalImage] (UIImage); videos via info[.mediaURL] → thumbnail via
AVAssetImageGenerator with appliesPreferredTrackTransform = true.

## Orientation through capture → storage → display
STORAGE/DISPLAY ARE CORRECT (docs-confirmed; NOT the bug):
- UIImage auto-applies orientation metadata for display; camera encodes sensor-native landscape
  pixels + orientation metadata; SwiftUI Image(uiImage:) respects it → landscape photo shows
  upright. Our pipeline never strips/re-encodes (UIImage held as-is in CapturedMedia; library
  images via UIImage(data:) preserve EXIF).
- Video thumbnails: appliesPreferredTrackTransform = true is correct → landscape thumbnails
  oriented correctly.

## Actual cause: stock picker in landscape
The artifact / "doesn't fill the horizontal frame" is in UIImagePickerController's OWN camera UI
when the device is held landscape. That system camera interface is portrait-oriented and does not
properly rotate/fill its live preview + review ("Use Photo/Retake") in landscape; our wrapper does
nothing to address it. Apple's guidance: use AVFoundation (AVCaptureSession) for fully customized
capture. So the artifact is in the CAPTURE UI layer, not storage/display.

## Secondary (cosmetic, not the artifact)
- Grid tile: Image(...).resizable().scaledToFill() in fixed-height/flex-width clipped cell →
  landscape photo center-cropped (sides trimmed). Intended grid cropping.
- Lightbox: scaledToFit in height 320 → correctly oriented but letterboxed. Intended.

## Not determined statically / not run
- Whether the app permits landscape: UISupportedInterfaceOrientations is in target/project
  settings, not the readable Info.plist (no orientation key there). Check Xcode → target →
  General → Deployment Info. Portrait-lock vs. rotation changes how bad the mismatch looks.
- Not reproduced on device, so the exact artifact (stretched preview / black bars / review
  mis-fill) isn't visually confirmed — but the architecture points at the stock picker's
  landscape handling since storage/display are provably orientation-correct.

## Summary
- NOT an orientation-metadata bug and NOT our display code (pipeline honors orientation;
  video uses appliesPreferredTrackTransform).
- Cause = stock UIImagePickerController camera's landscape preview/review, uncustomized by our
  wrapper. Fix space (later, not proposed): constrain capture to portrait, OR replace with a
  custom AVFoundation camera that handles landscape. Grid scaledToFill cropping is a separate
  cosmetic choice.

## Next
No fix proposed — awaiting scope decision on the fix direction. No git.
