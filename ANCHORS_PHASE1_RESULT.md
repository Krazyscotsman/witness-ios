# Witness — Anchors Phase 1 (backend-wired list + detail + inert delete) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIModels.swift** — `EntitySummary` (id required; name/type/memory_count/first_seen/is_anchor lenient),
  `EntityDetailDTO` (**attributes omitted**), `LinkedMemory` (**narrative omitted**). snake_case CodingKeys.
- **AnchorsListView.swift (new)**:
  - `AnchorsListViewModel` — GET `/api/v1/entities` (top-level array, 20s) → **client-side filter
    `isAnchor == true`** → states idle/loading/loaded/failed; **401 → refresh → retry-once** like memories.
  - `AnchorEntityDetailViewModel` — GET `/api/v1/entities/{id}` per-open; same 401 path.
  - `AnchorTypeStyle` — type→SF Symbol with a **neutral fallback** for unknown types.
  - `AnchorsListView` — anchors-only list (name, type label, memory_count), warm **"No anchors yet."** empty
    state, loading + failed(+Try again), pull-to-refresh. Pushed inside the Insights stack.
  - `AnchorEntityDetailView` — header (name/type/count) + **LINKED MEMORIES** (title + date/role); each links
    into the **existing `MemoryDetailView`** via a `MemoryDTO(linked:)` built from id/title/date (guarded when
    id is missing → non-tappable). Narratives are never rendered.
  - **Inert Delete** — destructive button + confirmation ("Delete this anchor? This can't be undone.") →
    `deleteAnchor()` **no-op stub**: names the two forbidden endpoints as do-NOT-call, marks the wiring seam,
    and shows a subtle **"Anchor deletion isn't available yet."** note so no tester is misled. Nothing is sent
    to the backend.
- **InsightsView.swift** — takes `@ObservedObject var auth`; `case "anchors"` now opens `AnchorsListView(auth:)`.
- **MainTabView.swift** — `InsightsView(auth: auth, path: $insightsPath)`.

## Left intact (per decision #1)
The local "Truth Registry" `AnchorsView` / `AnchorsModel` / forms remain in the codebase, now **unreferenced**
(no name collisions — new types are `AnchorsListView` / `AnchorEntityDetailView`). Not deleted.

## Verified
- Build: **0 errors / 0 warnings** (clean on first build). Per-file diagnostics — AnchorsListView, APIModels,
  InsightsView, MainTabView — all report no issues.
- Delete is a genuine no-op (no networking); `is_anchor == true` filter lives in the list VM; attributes and
  narrative are not modeled; auth + 401-refresh threaded; linked memories reuse `MemoryDetailView`.

## Honest scope / caveats
- **NOT exercised against the live backend.** The `/entities` + `/entities/{id}` decode, the client-side
  anchor filter, and the linked-memory → `MemoryDetailView` hop are wired to the verified contract but
  unconfirmed on real JSON. Device pass recommended: list loads anchors only; a type with an unknown string
  shows the neutral icon; tapping a linked memory opens its detail (which fetches `/detail` by id); Delete →
  confirm → shows "not available yet" and changes nothing; backend down → failed state + working Try again.
- Linked-memory date is shown raw (the string from `linked_memories[].date`); the full memory detail formats
  its own date from `/detail`.
- Pop-to-root still works: these are closure-based pushes on `insightsPath`, cleared on Insights re-tap.

## No git.
