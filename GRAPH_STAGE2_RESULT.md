# Witness — Memory Graph Stage 2 (relationship-classification filter chips) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. Client-side only. (Stages 3–4 later.)

## Applied
- **GraphView.swift — RelGroup → RelBucket:** replaced the incomplete `struct RelGroup` with
  `enum RelBucket { romantic, family, professional, friends, other }` — each with `label`, palette `color`, and
  the full snake_case `values` sets; `static func bucket(for:) -> RelBucket` (case-insensitive, `.other`
  fallback so `pet_owner`/`participated_in`/unknowns land in Other). One classification now drives BOTH filter
  and color.
- **State/filter:** `@State enabled: Set<String>` → `@State selectedBucket: RelBucket? = nil`;
  `.onChange(of: selectedBucket) { layout.wake() }` (re-settle).
- **Chips:** single-select row — `All` + the 5 buckets (bucket-colored dot + capsule, teal for All); tapping a
  bucket selects it, tapping it again returns to All.
- **Filter logic** (layered on the active My Circle / Web mode; narrator always shown): `matchingIDs`
  (All → every id; else narrator + nodes whose `bucket(primaryRel)` matches); `visibleEdges` = both endpoints in
  `matchingIDs` (and, in ego, touching the narrator); `isVisible` = narrator always, else in `matchingIDs` and
  (web → shown / ego → on a visible edge).
- **Color:** node `RelBucket.bucket(for: node.primaryRel).color`; edge `RelBucket.bucket(for: e.relType).color`.
- **NodeDetailSheet.swift:** avatar fill → `RelBucket.bucket(for: node.primaryRel).color`.
- **GraphViewModel.swift:** stale comment RelGroup → RelBucket (one word). (APIModels:709 comment left as-is.)

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: GraphView,
  NodeDetailSheet (0 issues each). No transient error 5.
- Confirmed `RelGroup` had exactly the 6 call sites (5 in GraphView + 1 in NodeDetailSheet) + 2 comments; all
  updated; no remaining `RelGroup` references in code.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the bucket map +
  the single-select filter/matchingIDs/visibleEdges logic + recolor. A device pass confirms: chips filtering the
  real ~95/56 within My Circle / Web, re-settle on change, and Other catching pet_owner/participated_in/unknown
  relationship types.
- **Layout perf/overlap at ~95 nodes remains Stage 3** — untouched. The filter recompute is the same big-O as
  before (a per-render `matchingIDs`/`visibleEdges` pass), heaviest only during the settling animation.
- Node bucket = `bucket(node.primaryRel)`, reusing Stage-1's anchor_rel_type → edge-to-narrator → strongest
  derivation (= the rel connecting them to the center). Mapped from the raw string; server colors unused.
- DEBUG 🩺[Graph] logging left in, per request.

## No git.
