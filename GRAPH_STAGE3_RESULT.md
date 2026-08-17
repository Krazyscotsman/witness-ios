# Witness — Memory Graph Stage 3 (layout polish + zoom/pan) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. Client-side only. Stage 1 + Stage 2 preserved.

## Applied (GraphView.swift)
- **Engine rewrite (`GraphLayout`):** positions/edges in **plain storage** (no per-frame array `@Published`);
  a tiny `@Published tick` drives the single Canvas and **stops** when settled. **Cooling** (`alpha *= 0.98`,
  displacement scales by `alpha`) → `settled = true` + `stop()` at `alpha < 0.02` or negligible motion.
  **Collision separation** (2-pass, min gap `r_i + r_j + labelPad`). **Bucket-sector spiral seeding** in a
  **virtual space** sized to node count (no screen clamp). `id→index` dict for O(1) lookups. `mode` didSet →
  restart; `drag(_:toVirtual:)` pins; `reseed()`/`wake()` kept.
- **Render rewrite:** the 95 `ForEach` node views are gone — one immediate-mode `Canvas` draws edges + node
  circles + anchor rings + narrator star + labels, via a virtual→screen transform (`screen`/`virtual`,
  `liveScale = fitScale * zoom * pinch`). Draw split into `drawEdges`/`drawNode` helpers (kept the Canvas
  closure small so the type-checker is happy).
- **Zoom/pan/drag/tap:** `MagnificationGesture` (clamped 0.3–4×) + a `DragGesture` that drags a node if the
  touch starts on one (`nearestVisibleNode` hit-test → `layout.drag(toVirtual:)`) else pans; `SpatialTapGesture`
  → opens the Stage-1 `NodeDetailSheet`.
- **Fit-to-view:** `fitToView` centers + scales the visible subset into the screen; runs on appear, size change,
  **settle**, **filter change** (+ `wake()`), and **mode change**. Nav-bar button → **reset-to-fit**
  (fit icon).
- **Labels:** shown only when on-screen radius ≥ 15 (faded by size), **always** for selected + narrator → no
  unreadable stacking.
- **Preserved:** Stage 2 `RelBucket` chips/filter/color + `matchingIDs`/`visibleEdges`/`isVisible`; Stage 1
  tap → sheet → memories; header stats; mode toggle. `GraphViewModel`, `NodeDetailSheet`, DEBUG `🩺[Graph]`
  logging untouched.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: GraphView
  (0 issues).
- Two self-caught build errors on the way to green (both fixed): (1) the Canvas closure was too complex for the
  type-checker → split into `drawEdges`/`drawNode`; (2) used a non-existent `resolveText` → corrected to
  `ctx.resolve(_:)`.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend / on device** (none here). Verified: compile 0/0 + the engine
  (cooling/collision/seeding/settle-stop) + the transform/gesture/fit logic read through. The **feel** —
  clean settle with no overlap, the sim actually stopping (no 60fps drain), smooth pinch/pan + node-drag + tap,
  label de-clutter at ~95 nodes — is a device check I can't run.
- Filter change re-fits to the visible subset + `wake()` (positions stay stable; not re-solved from scratch),
  per the approved decision.
- Collision uses `r_i + r_j + labelPad` (labelPad 18); tune if labels still crowd at high zoom.
- DEBUG `🩺[Graph]` logging left in.

## No git.
