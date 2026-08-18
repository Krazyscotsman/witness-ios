# Witness iOS — Graph "Visible bonds" filter state — Report

**Date:** 2026-08-17. Report only — no code changed. Read from current source.

## Short answer
The "Visible bonds" filter is **present and fully wired** in the current code — not missing, not disconnected.

## 1. Filter UI present? YES (GraphView.swift)
- `@State private var filters: Set<GraphCat> = Set(GraphCat.allCases)` (line 13) — all 5 on at start.
- `private var controls` (lines 234–255): "VISIBLE BONDS" header + Reset + a horizontal row of `catChip`
  toggles over `ForEach(GraphCat.allCases)`. Also shows "← Back to {narrator}" when focused (line 238).
- `catChip(_:)` (257–268): eye/eye.slash + category dot + label; tap → `filters.remove(c)` / `filters.insert(c)`
  (line 267) — multi-select show/hide (spec §4).
- Mounted in the `.loaded` branch: `VStack{ Color.clear; canvas; controls }` (line 43).

## 2. Old Stage-2 chips? Removed + replaced cleanly
The Stage-2 `RelBucket` enum + single-select chip row were deleted in the ego rebuild and replaced by this
`GraphCat`-driven multi-select panel. No stale/disconnected chips remain.

## 3. EgoLayout accepts AND applies activeFilters? YES (EgoGraph.swift)
- Passed in: `EgoLayout.compute(..., filters: filters, ...)` (GraphView.swift:26).
- Applied, both rings:
  - Root/anchor: `guard let cat = GraphClassify.anchorCategory(rel), filters.contains(cat) else { continue }`.
  - Focused/edge: `let cat = GraphClassify.edgeCategory(e.relType); guard filters.contains(cat) else { continue }`.
- Maps (FILTER_GROUPS, anchorCategoryMap skip set, edgeCategory) are defined AND gated by the toggles.

## 4. Cleanest place to add the panel
Already exists (`controls` at the bottom of the loaded VStack). Nothing to add.

## Why it may look "not present/working" (hypotheses — not run here)
Code has it, so the gap is runtime/build:
1. STALE BUILD/INSTALL — a device build from before the ego rewrite would show the radial graph without the
   panel. Rebuild + reinstall and recheck FIRST.
2. EMPTY/THIN ANCHORS — the root ring is built from `vm.anchors` (/timeline/relationships). If that returned
   few/no rows (or person_entity_id match is thin), toggling changes little visibly → reads as "not working."
   There's a DEBUG 🩺[Graph] log for /api/v1/graph but NONE for /timeline/relationships — adding one would
   confirm the anchor count.
3. LAYOUT VISIBILITY — `canvas` is a greedy GeometryReader sibling of `controls` in the VStack (same structure
   Stage-3's working filter row used); worth eyeballing on-device that the panel isn't below the fold / under
   the tab bar.

## Bottom line
"Visible bonds" is implemented and connected in source. The next step is not to wire it — it's to confirm the
running build and that /timeline/relationships is actually returning anchors (optionally add a 🩺 log for it).
