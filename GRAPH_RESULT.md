# Witness — Graph → GET /api/v1/graph — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git. Read-only.

## Applied
- **APIModels.swift** — `GraphResponse` / `GraphNode` / `GraphEdge` / `GraphStats` (`nonisolated`,
  `.convertFromSnakeCase`; precomputed styling color/border_color/size/line_style/width decoded but unused).
- **GraphViewModel.swift** (NEW, `@MainActor` + `import Combine`) — `load()` → `GET /api/v1/graph` (30s,
  fetch-once, 401→refresh→retry). Maps DTO → existing `GNode`/`GEdge`; derives each node's `primaryRel`
  (anchor_rel_type → edge-to-narrator type → strongest incident edge → neutral) so RelGroup coloring holds.
  Narrator id from `narrator_node_id` (fallback: the `is_narrator` node). States: loading / loaded / empty /
  unavailable / failed. **404 → `.unavailable`** (graceful); `nodes ≤ 1 || no edges → .empty`.
- **GraphView.swift → GraphLayout** — `edges` made `private(set) var`; added `narratorID` + `setGraph(nodes:
  edges:)` which swaps data, recomputes the narrator id, resets `seeded`, and re-seeds if the canvas size is
  known. **No physics changes.**
- **GraphView.swift → view** — added `auth` + `@StateObject vm`; `layout` starts empty; `.task { load; if loaded
  → layout.setGraph(...) }`. Body switches on `vm.state` → loading / empty ("Not enough connections yet") /
  unavailable (404) / failed-retry / loaded (existing header + canvas + controls). `visibleEdges` ego filter now
  uses `layout.narratorID`; first stat relabeled "People" → "Nodes". Narrator (teal + star) / anchor (gold ring)
  distinction and the node-tap info sheet are unchanged.
- **InsightsView.swift** — `case "graph": GraphView(auth: auth)`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: GraphView,
  GraphViewModel, APIModels (0 issues each). No transient error 5.
- Read the real files before editing; `GNode`/`GEdge` memberwise inits, `RelGroup`, and the physics engine used
  as-is. `GNode.samples`/`GEdge.samples` left in place (now unused, not deleted — per approval).

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the load/map/state
  machine + the `setGraph` re-seed path + defensive decode. A device pass confirms: real nodes/edges settling in
  the physics engine, ego/web filtering by the real narrator id, 404 → unavailable, empty vs loaded, and the
  node-tap sheet.
- **App-palette styling** (RelGroup + WV/WT); server precomputed color/size/width **and** `edge.label` are
  decoded but intentionally unused (Canvas has no inline edge-label support; relationship type is conveyed by
  the color legend + node detail).
- **No entity-detail navigation** exists to reach, so node tap keeps the existing info sheet (as approved).
- Sample data remains in the file, unused — say the word to remove it.

## No git.
