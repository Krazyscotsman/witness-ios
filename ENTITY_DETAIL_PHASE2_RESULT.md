# Witness — Entity Detail Phase 2: `dialogue_spoken` verbatim quotes — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Applied
- **EntityDetailSupport.swift (NEW)** — reusable primitives for Phases 2–5:
  - `JSONValue` accessors: `objectValue`, `arrayValue`, `doubleValue`, `boolValue`, `intValue` (number OR
    numeric-string), `subscript(key)`, `displayString`, `stringArray`.
  - `EDFormat.value(_:)` — the bool/number/string value formatter.
  - `EDSection` (collapsible card + count badge, collapsed by default), `EDPill`, `EDPillWrap` (arrays→pills,
    empties skipped, hidden when empty), `EDFieldRow` (renders nothing when empty; String or JSONValue init).
  - `DialogueLine` model.
- **EntityDetailPage.swift — VM:** `loadEntityNames` (one cached `GET /api/v1/entities?limit=1000&offset=0` →
  `[uuid:name]`; failure leaves it empty), `memoryTitles` (`[id:title]` from Phase-1 `linkedMemories`), and
  `dialogueLines` (defensive parse of `attributes.dialogue_spoken`; empty-quote rows skipped; backend order
  preserved; quote kept verbatim).
- **EntityDetailPage.swift — view:** new **"Everything they said"** section (collapsed by default, count = true
  total N), inserted after the summary cards. Grouped by memory — uppercase title header when `memory_id` changes
  from the previous row (title via `memoryTitles`, neutral **"A memory"** when unresolved). Each line: **verbatim
  quote** (serif italic, in quotes) + optional `Scene {n}` pill + `to {responder}` pill (**resolved name only —
  UUID never rendered; pill omitted if unresolved**). Windowed **50**: "Show 50 more — showing X of N", then
  "Showing all N". Second `.task` loads the entity-name map in parallel.

## Verified
- **BuildProject → 0 errors**; **0 warnings** on EntityDetailSupport (new) and EntityDetailPage.
- New file auto-included by the synchronized Xcode group.

## Honest caveats (device/backend — not runnable here)
- The live `attributes.dialogue_spoken` shape (`quote` / `memory_id` / `responder_entity_id` / `scene_number` /
  `dialogue_order`) and responder/title resolution are device/backend checks. Parsing is fully defensive:
  missing/renamed keys → skipped rows or omitted pills; a raw UUID is never shown; empty quotes are dropped.
- Entity list is a single 1000-row page (approved for v1); a responder beyond that page → pill omitted
  (pagination noted for later).
- Header pills from Phase 1 (`relationship_type`/`significance`/`date`) remain provisional pending the spec.

## Next (Phases 3–5, not started)
people_details, romantic/arcs, remaining sections — each reusing the `EDSection`/`EDPill`/`EDPillWrap`/
`EDFieldRow`/`EDFormat` primitives.

## No git.
