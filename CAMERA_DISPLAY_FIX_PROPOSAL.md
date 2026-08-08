# Witness — Media display/orientation fix (item 13, display side) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval + grid choice.** No git.

## Confidence report
- CONFIDENT — grid cropping is the visible issue: tile uses `scaledToFill()` in a fixed
  ~square cell → landscape photos aggressively center-cropped. (scaledToFill preserves aspect
  and CROPS; it does not stretch/distort.)
- CONFIDENT — lightbox already correct: `lightboxView` uses `scaledToFit` in height 320 →
  shows whole image, proportioned. No change needed.
- CONFIDENT — orientation already respected in our code: UIImagePickerController returns a
  UIImage with EXIF baked into .imageOrientation; SwiftUI Image(uiImage:) auto-applies it; we
  store the UIImage as-is and display via Image(uiImage:) → upright. Nothing drops it. NOT
  adding normalization (display doesn't need it; normalize-to-.up only matters for raw pixel
  export/upload = backend-era).
- NEEDS ON-DEVICE: after this fix, confirm a landscape photo shows upright AND proportioned.
  Per code it will. If sideways despite Image(uiImage:), that points upstream to the stock
  picker (item 13), not our display — the intended tell-apart.

## Recommendation: grid = scaledToFit + white matte
Mainstream photo grids use uniform square scaledToFill crops, but given your lean toward
showing the whole image AND the locked "white cards on flat parchment" design rule, the
on-brand premium choice is scaledToFit on a white matte — each tile a white card with the
photo matted inside (whole image visible, uniform cells). Alternative: keep scaledToFill
uniform crop (say so and I'll do that).

## Diff — MediaView.swift (grid tile only)
```diff
             ZStack(alignment: .bottomLeading) {
+                // Uniform white matte so fitted photos/video-thumbs sit as matted cards
+                // (on-brand "white cards on parchment"); keeps cells uniform without cropping.
+                Rectangle().fill(WV.card)
                 if let ui = item.image {
-                    Image(uiImage: ui).resizable().scaledToFill()
+                    Image(uiImage: ui).resizable().scaledToFit()   // whole image, correctly proportioned
                 } else {
                     LinearGradient(colors: [item.kind.tone.opacity(0.30), item.kind.tone.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                     Image(systemName: item.kind.icon).font(.system(size: big ? 40 : 26, weight: .light)).foregroundStyle(item.kind.tone.opacity(0.8))
                         .frame(maxWidth: .infinity, maxHeight: .infinity)
                 }
```
Unchanged: video play badge, filename chip, selection checkmark, .frame(height:), .clipShape,
selection stroke, audio/no-image placeholder path. Lightbox unchanged (already scaledToFit).

Trade-off (honest): with scaledToFit, very wide panoramas show slim white matte bars top/bottom
in the grid (intended matted look); scaledToFill filled but lost their sides.

## After approval
Apply the tile change → build 0/0 → report honestly. On-device confirms upright+proportioned.
No orientation code change (confirmed respected). No git.
