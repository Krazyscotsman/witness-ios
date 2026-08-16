# Witness iOS — Graph decode fix (name_complete Bool) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. DEBUG logging kept in (per request) to confirm render.

## Root cause (confirmed via 🩺[Graph] log)
`GET /api/v1/graph` → 200 with real data, but decode threw:
`typeMismatch: expected String. Path: nodes[0].nameComplete. Found bool instead.`
`GraphNode.nameComplete` was `String?` but the backend sends `"name_complete": true` (a Bool). One wrong field
type fails the whole decode → `.failed`. Same class as `context_summary`.

## Applied (APIModels.swift + GraphViewModel.swift)
- **GraphNode.nameComplete:** `String?` → **`Bool?`** (the fix).
- **GraphViewModel.map():** label fallback `n.label ?? n.nameComplete ?? "Unknown"` → **`n.label ?? "Unknown"`**
  (nameComplete is a Bool flag, not a display string — also required for compile).
- **GraphEdge (preemptive hardening):** dropped the 6 fields iOS never uses — `id`, `memory_count`,
  `line_style`, `color`, `width`, `label` — leaving only `source`, `target`, `relationshipType?`, `strength?`.
  Rationale below.

## Why nodes need nothing further, and edges were hardened
Swift decodes struct fields in declaration order and failed at `nameComplete`. Therefore:
- Node fields declared BEFORE it — `id, label, type, isAnchor, isNarrator, memoryCount, aliases` — all decoded
  cleanly (the decoder reached nameComplete).
- Node fields AFTER it — `anchor_rel_type, birth_date, death_date, color, border_color, size` — you verified
  from the raw body (nulls / strings / int). 
- ⇒ **All node fields are accounted for; only `nameComplete` needed changing.**
- **Edges never decoded** (nodes[0] failed first) AND were **truncated from the DEBUG body** → entirely
  unverified. Since iOS only uses source/target/relationshipType/strength (app palette ignores the precomputed
  edge styling), decoding *only those 4* removes 6 potential type-mismatch landmines on the unverified part.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: APIModels,
  GraphViewModel (0 issues each).
- Confirmed `nameComplete` had a single reader (the VM label fallback) → updated; no other references.

## Residual risk (retained logging will catch)
- The 4 used edge fields still decode: `source`/`target` (String, required), `relationshipType` (String?),
  `strength` (Double?). If any comes back as an unexpected type on the real edge objects, the kept
  `🩺[Graph] caught:` line will name it on next open. `GraphStats` (all Int?) is unused-but-harmless, left as-is.

## What to expect on next Graph open
- Decode should now succeed → state `.loaded` → the force-directed engine renders the real ~95 nodes / 56 edges.
- ⚠️ Per the earlier diagnosis, that engine is **not tuned for this volume** (single-ring seed, screen-clamped
  bounds, 60fps full-array republish, no zoom) — so a successful decode likely reveals an **overlapping /
  slow-to-settle clump**, i.e. the RENDER problem, which is a separate (rebuild-scope) task. If instead you see
  another `🩺[Graph] caught:` line, paste it — it'll be the next field to fix.

## Next
Open Graph, confirm it renders (no `caught:` line). Once confirmed, remove the DEBUG logging (the graph blocks in
APIClient/GraphViewModel, and the witness blocks when ready). No git.
