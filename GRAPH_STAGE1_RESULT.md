# Witness — Memory Graph Stage 1 (memory tap-through) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. Read-only fetch. (Stages 2–4 later.)

## Applied
- **NodeDetailSheet.swift** (NEW) —
  - `EntityMemoriesViewModel` (`@MainActor` + `import Combine`): `load(entityId:auth:)` → `GET /api/v1/entities/
    {id}` (**plain decoder** — EntityDetailDTO's explicit CodingKeys; 30s heavy endpoint), `memories =
    linkedMemories ?? []`; states idle/loading/loaded/empty/failed; **fetch-once per open** (loaded/loading
    guard + fresh `@StateObject` per sheet → never per-node); 401→refresh→retry.
  - `NodeDetailSheet(node:auth:)`: own **NavigationStack**; identity header + facts card (moved from GraphView) +
    a **Memories** section — spinner while fetching / "No linked memories." / failed+Try-again / a list of
    tappable **title + date** rows. Each row `NavigationLink(value: MemoryDTO(id:title:exactDate:))` →
    `.navigationDestination(for: MemoryDTO.self) { MemoryDetailView(listItem:$0, auth:) }`; rows without an id
    render non-tappable. `ScrollView` + `.presentationDetents([.medium, .large])` + drag indicator (expands to
    fit; long lists scroll). `node.memoryCount` shown as-is in the facts card, independent of the fetched list.
- **GraphView.swift** — `.sheet(item: $selected) { NodeDetailSheet(node: $0, auth: auth) }`; removed the moved
  `nodeDetail(_:)`, `detailRow(_:_:)`, and `humanize(_:)` (now in NodeDetailSheet). `visibleEdges`/`isVisible`
  and the engine untouched.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**:
  NodeDetailSheet, GraphView (0 issues each). No transient error 5.
- Confirmed the moved helpers had no other callers in GraphView before removing them.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the fetch/state
  machine + the push wiring + defensive decode. A device pass confirms: real `/entities/{id}` → linked_memories,
  the spinner/empty/failed states, and tapping a row opening the real MemoryDetailView.
- Fetch runs **on card-open only** (heavy endpoint); `node.memoryCount` and the fetched list are shown
  independently — no assertion they match (they legitimately can differ).
- Plain decoder used (no convertFromSnakeCase) because EntityDetailDTO relies on explicit CodingKeys.
- Memory pushes inside the sheet's own NavigationStack; at the `.medium` detent the pushed MemoryDetailView is
  compact but scrollable — the user can drag to `.large`. (Layout polish/zoom is Stage 3.)
- DEBUG 🩺[Graph] logging left in, per request.

## No git.
