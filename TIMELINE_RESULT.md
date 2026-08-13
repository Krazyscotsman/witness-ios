# Witness — Timeline → GET /timeline/visual — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git. Read-only wiring.

## Applied
- **APIModels.swift** — `TimelineResponse` / `TimelineYear` / `TimelineEventDTO` (union, `.convertFromSnakeCase`,
  all `nonisolated`; the four enrichment fields — `people`/`location`/`importanceScore`/`significance` — are
  memory-only). Plus a shared `MemoryDTO(id:title:exactDate:)` convenience init for the source tap-through.
- **TimelineViewModel.swift** (NEW, `@MainActor` + `import Combine`) — `load()` → **bare `GET /timeline/visual`**,
  no params, **60s** timeout (N+1 slow), fetch-once (`.loading`/`.loaded` guard), `refresh()` for pull-to-refresh,
  401→refresh→retry-once. Publishes `years` (sorted newest-first), birthdate, totals.
- **TimelineView.swift** (rewritten) — `auth` + `@StateObject vm`; `.task { load }`; loading spinner
  ("Arranging your life across time…") / failed-retry / empty states.
  - **Narrative:** `vm.years` → year header (+ "Age N") → `eventCard` with a timeline node, branching on `type`:
    **memory** (date + Critical tag + title + snippet, expand → people/location chips + "View memory" →
    `MemoryDetailView(listItem: MemoryDTO(id:title:exactDate:), auth:)` when `memory_id` present),
    **anchor** (category-styled icon for job/education/location, not tappable), **milestone** (gold, flag icon).
  - **Pattern:** three rails — **People / Places / Significant** — across the min→max year axis, a dot per year
    that contains ≥1 matching **memory** event. The stale local **`AnchorStore` is retired** (no longer imported
    or referenced here).
  - **Filters:** `All / People / Places / Significant` (memory-only via `TLFilter.matches`), kept client-side
    **search**; dropped childhood/recent. An honest footnote states filters/rails reflect memory events only.
- **InsightsView.swift** — `case "timeline": TimelineView(auth: auth)`; hub endpoint label corrected to
  `GET /timeline/visual` (was the stale `GET /timeline/relationships`).

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean** for
  TimelineView, TimelineViewModel, APIModels (0 issues each).
- `MemoryDTO(id:title:exactDate:)` matches the memberwise field order in APIModels (id, title, narrative,
  narrativeSnippet, exactDate, …); `MemoryDetailView(listItem:auth:)` init confirmed by reading the file.
- Retired `AnchorStore`/`birthdateISO`/sample events; `FlowWrap` (needs `Element: Identifiable`) avoided for the
  `[String]` people list — used a horizontal chip scroller instead.

## Honest scope / caveats (backend behavior, not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the load/fetch-once/
  refresh state machine + defensive decode. A device pass would confirm: the real N+1 round-trip latency, the
  three event `type`s rendering, memory tap → `/detail`, and Pattern rails populating.
- **Filters are memory-only by nature** — anchors & milestones don't carry people/place/significance, so those
  chips exclude them by design (surfaced in the footnote, not hidden). **Significance is binary** (`critical` /
  none); sparse criticals reflect the backend `importance_score` threshold, not a client bug.
- **Pattern mode is per-year dots** (People/Places/Significant across the axis), not per-entity spans — the old
  `AnchorStore` span rails can't be rebuilt from `/timeline/visual` (it has no entity start/end spans). This is
  the interpretation you approved.
- Bare `/timeline/visual` path (no `/api/v1`) as specified.

## No git.
