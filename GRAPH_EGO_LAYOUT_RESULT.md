# Witness — Memory Graph: radial "ego" layout (frontend parity) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. Pure trig, no physics. Stage-1 + Stage-3 nav preserved.

## Applied
- **AnchorRegistry.swift** — added `personEntityId` to `RelationshipRow` (the anchor→graph-node match key).
- **EgoGraph.swift** (NEW) — `GraphCat` (family/romantic/friend/professional/pet + §5 CATEGORY_COLORS bg/text/
  border); `GraphClassify` (FILTER_GROUPS, `anchorCategory` with skip set + professional default, `edgeCategory`,
  `compactRelType` §2 map, significance rank, name helpers); `EgoPlaced`/`EgoField`; **`EgoLayout.compute`** —
  deterministic radial trig: root ring from anchors (dedupe by node id → top significance → sort → cap 20),
  focused ring from graph edges (cap 14 + ring-2 cap 8), count-tiered radii (150/190/230/270), node radii
  (30/26/23/20), `cx=420`, `cy`/`viewBoxH`, ring1 angle `2πi/count − π/2`, ring2 `−π/4`.
- **GraphViewModel.swift** — fetches **both** `/api/v1/graph` + `/timeline/relationships` (best-effort) once;
  publishes `anchors` + builds `nodeByID`; `.loaded` when any nodes **or** anchors exist.
- **GraphView.swift** (rewritten) — force sim / `GraphLayout` / `GraphMode`(Web) / `RelBucket` removed. Single
  `Canvas` draws the radial field (guide circles, category-colored spokes, navy+gold center with "Click anyone
  to explore" hint, category `bg/border/text` ring nodes, "First L." names, gold `compactRelType` labels on the
  root ring only) via the Stage-3 `screen`/`fitToView`/pinch/pan (node-drag removed — positions are computed).
  Tap → `NodeDetailSheet`; **"Visible bonds"** panel = 5 eye-toggles (multi-select) + Reset; **"← Back to
  {narrator}"** when focused. Re-fit on focus/filter/size/anchors change.
- **NodeDetailSheet.swift** — added `onExplore: ((GNode) -> Void)?` + an **"Explore connections"** button
  (hidden when nil); avatar recolor via `GraphCat`. GraphView passes the closure → sets `focusedEntityId`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: GraphView,
  EgoGraph, GraphViewModel, NodeDetailSheet (0 issues each).
- One self-caught build error: `NodeDetailSheet` still referenced the removed `RelBucket` for the avatar →
  switched to `GraphClassify.edgeCategory(...).text`.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend / on device** (none here). Verified: compile 0/0 + the deterministic
  trig + classification maps + dual-fetch + re-center/filter wiring read through. **Device checks:** the
  web-parity *look*; the **`person_entity_id == graph node.id`** match (if ids don't line up, root nodes still
  render from anchor data and tap uses `person_entity_id`); and `/timeline/relationships` field scale.
- Accepted per approval: **ring-2 spokes originate from center** (parent-threading is a follow-up); Web mode and
  node-drag removed.
- DEBUG `🩺[Graph]` logging (APIClient + GraphViewModel catch) left in, untouched.

## No git.
