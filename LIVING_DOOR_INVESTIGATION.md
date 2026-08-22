# Witness — "Living Door" effect — investigation (report only)

Date: 2026-08-19. **No build, no git.** Investigation + recommended approach for a luminance-masked, breathing/
surging brilliance on the Mont Saint-Michel door.

---

## ⚠️ Locked-rules flag (decide first)
CLAUDE.md locks **"the door = entry-world-only rule."** The doorway image currently renders **only** on the
**Threshold** and **Login** screens (via `ParchmentDoorBackground`), never on the main-app **Home ("Your Witness")
tab**. A "living door on the **Home screen**" would place the door in the main world and **break that locked
rule**. The effect fits most naturally on the **entry door (Threshold/Login)** where the door already lives.

**Need a call:** (a) apply to the **entry door** (Threshold/Login) — consistent with the lock *(recommended)*, or
(b) the **Home tab** — requires an explicit exception to the locked rule.

---

## 1. The asset
- **Path:** `Witness/Assets.xcassets/doorway.imageset/doorway.jpg` (image name `"doorway"`).
- **Resolution/format:** **1152×1536**, **JPEG**, **sRGB**, **8-bit**, **no alpha**. Only the **1x** slot is
  populated (2x/3x empty → Xcode may warn; functionally fine). **No HDR gain map / no extended-range data** — a
  plain SDR photo. (For a full-screen 3x background this is below native pixel density, but it's a dark, soft,
  blurred backdrop so acceptable; a higher-res or @2x/@3x export would sharpen it.)
- **Confirmed** it's the brand/Witness Mont Saint-Michel ajar-arched-door image (near-grayscale, dark stone
  passage, light spilling through the door gap and pooling on the floor).
- **Current rendering (important):** `ParchmentDoorBackground` (DesignSystem.swift:110) draws it as a **faint
  monochrome ink watermark** — `grayscale(1) → contrast → colorInvert → luminanceToAlpha`, tinted with
  `WV.printInk`, ~0.16 (login) / 0.41 (threshold) opacity, right-offset behind parchment. This **discards color
  and light**, so the living-light effect is a **new presentation** (show the real light / composite a glow),
  not a tweak of the existing watermark.

## 2. Isolation by luminance — confirmed
The image is near-grayscale and very dark except the **doorway light**, which is unambiguously the brightest
region → a luminance threshold cleanly masks "just the light." Approx locations (normalized, top-left origin):
- Lit door body: **x ≈ 0.42–0.63, y ≈ 0.18–0.58** (arch top ~y0.18–0.30).
- Brightest sliver (ajar gap, the true "light"): **x ≈ 0.58–0.63, y ≈ 0.30–0.57**.
- Light pool on the floor/threshold: **x ≈ 0.28–0.60, y ≈ 0.56–0.63**.
- Glow center of mass ≈ **(0.50, 0.45)** — where a positioned boost/bloom should sit.
- Because the source is grayscale, the light is **white**; a **golden brilliance** (WV.gold) is an *added* tint,
  not amplified existing color.

## 3. Recommended technical approach

### a) Isolate + boost (Core Image, animatable)
`doorway` → luminance → **soft high-pass threshold** (`CIToneCurve` / `CIColorClamp`) to keep only the brights →
**mask** → `CIBloom` / `CIGaussianBloom` + warm tint (`CIColorMatrix` toward gold) → composite over the base
(`CISourceOverCompositing` / additive). The **single animatable parameter** is a brilliance-intensity scalar
(bloom intensity or a color-matrix scale) that drives:
- **Breathing at rest:** slow sine, ~0.08–0.12 Hz, small amplitude.
- **Surge on interaction:** brief ramp-up then ease-back on tap/appear.

### b) HDR/EDR path (light brighter than screen-white) — cleanest native
SwiftUI has no EDR knob for a plain `Image` (and `Image.allowedDynamicRange(.high)` only helps images that
*already contain* HDR color data — ours doesn't). So render the Core Image output into a **Metal-backed view**:
- `MTKView` / `CAMetalLayer` with **`wantsExtendedDynamicRangeContent = true`** (iOS 16+),
- **`pixelFormat = .rgba16Float`**, **`colorspace = CGColorSpace(name: .extendedLinearDisplayP3)`**,
- drawn by a **`CIContext(mtlDevice:)`** with an extended working/output color space,
- wrapped in a `UIViewRepresentable` for SwiftUI.
Output light values **> 1.0** in the masked region then display **super-white** on EDR displays. Gate/scale the
boost by **`UIScreen.potentialEDRHeadroom` / `currentEDRHeadroom`**.
**Reference:** Apple's Core Image sample *"Generating an animation with a Core Image Render Destination"* does
exactly this (EDR-configured MTKView + animated CIContext) — ideal starting point. Prefer plain extended-value
output clamped to headroom over custom `CAEDRMetadata` tone mapping (Apple notes the latter is memory/GPU-heavy).

### c) SDR fallback (non-EDR displays, or headroom ≈ 1.0)
Same filter chain, values **clamp at white**. The effect degrades gracefully to a **warm bloom + subtle
brightness/scale pulse** — still reads as breathing light, just not super-white. Detect via EDR headroom; when
≤ 1.0, render the SDR version (can even skip Metal and use a SwiftUI `TimelineView` + `Canvas`/blurred overlay).

## 4. Performance (Home/entry is a real screen)
Feasible, with one rule: **precompute the static luminance mask + blurred bloom once**, then **animate only the
cheap intensity multiply/composite per frame** — never re-run the Gaussian blur every frame (that's the costly
part). Also:
- Render the door at **reduced resolution** (soft dark backdrop; no need for native pixels).
- Keep it in its **own Metal layer** so animating it doesn't force SwiftUI to recomposite the foreground content.
- Drive with the view's own draw loop / `CAMetalDisplayLink`; breathing ≈ 0.1 Hz; cap to 30–60 fps.
- EDR headroom/brightness changes with display brightness — recompute scale when it changes, not per frame.

## Bottom line
Very doable and a strong fit for the **entry door**. The asset is **SDR-only**, so the "brighter-than-white"
brilliance is **synthesized** — a luminance-masked Core Image bloom (warm/gold), rendered into an **EDR Metal
layer** for super-white on capable displays, with a clean **SDR bloom fallback**. It replaces/augments the
current monochrome ink watermark with a real-light presentation. **Awaiting the surface decision (entry door vs.
Home tab, per the locked rule) before proposing a build.**

## No build. No git.
