# Witness — Graph: remove debug red + fix centering-on-open (live fit transform) — Result

Date: 2026-08-17. Build **0 errors / 0 warnings**. No git.

## A) Removed the debug red background
Deleted `.background(Color.red)` from the chips `HStack`. No replacement color — the chips' own pill
backgrounds show over the panel's parchment (the red test had already confirmed the chips render:
Family/Romantic/Friends… in a scrollable row).

## B) Fixed centering-on-open — the transform is now derived at draw time (no timing dependency)

### Root cause
The old code stored the fit as `@State` (`fitScale`, `contentCenter`) and set it imperatively via
`fitToView(...)`, triggered by `onAppear` / `onChange(of: geo.size)`. On first layout the GeometryReader's
size resolves to `.zero` at `onAppear` (so `fitToView` hit its `guard geo != .zero` and no-opped) and the
follow-up `onChange` didn't reliably re-fire — leaving `contentCenter = (0,0)`, `fitScale = 1`. With
`contentCenter = (0,0)`, `screen()` maps the virtual center `(420, cy)` to `geo/2 + (420, cy)` → the graph is
pushed to the **bottom-right**, exactly the reported symptom. It also explained the dead reset button:
`canvasSize` stayed `.zero`, so the reset (`fitToView(canvasSize)`) no-opped until a manual gesture forced a
relayout.

### The fix
Made the base fit a **pure function computed every draw**, so it can never be "unset" on the first frame:
- **Removed** stored `fitScale` / `contentCenter` / `canvasSize`, the imperative `fitToView(...)`, and the
  `onAppear` + `onChange(of: geo.size)` fit plumbing.
- **Added `fit(field, geo) -> GTransform{center, live}`** — computes the placed-node bounding box + a
  fit-to-canvas scale from the *current* `geo`, then `live = scale * zoom * pinch`. Called once per draw in
  `drawEgo` and in `nearestPlaced`.
- **`screen(v, geo, tf)`** now uses that transform; node radii and label sizes use `tf.live`.
- **`resetView()`** (nav-bar fit button + `onChange(focusedEntityId)` + `onChange(filters)`) just clears
  `zoom`/`pan`; the live base-fit re-centers automatically → re-center + filter changes recompose cleanly, and
  the reset button works immediately (no stale `canvasSize`).

Because the transform is derived from the real `geo` on every render, the graph is **fit-and-centered on the
first real-size draw** — no manual pan. Pinch-zoom/pan layer on top as before.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean** for
  GraphView.swift (0 issues).

## Honest scope / caveats
- **NOT run on device by me** (this environment only builds + reads diagnostics; it can't launch the
  simulator). The centering mechanism is now timing-independent *by construction* — there's no stored transform
  that can be missed on the first frame — so it should render centered on open; your device check confirms the
  visual.
- `fit(...)` recomputes the ≤22-node radial `field` per draw — trivially cheap at this scale.
- If the initial framing looks too tight/loose on your device, the single knob is `margin` (currently 100) in
  `fit(...)`.

## No git.
