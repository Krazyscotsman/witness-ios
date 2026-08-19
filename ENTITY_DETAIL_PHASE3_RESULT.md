# Witness — Entity Detail Phase 3: `people_details_by_memory` + hero cards — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Applied
- **EntityDetailSupport.swift** — added `PersonMemoryDetail { memoryId, obj: [String: JSONValue] }` (next to
  `DialogueLine`). Phase-2 primitives reused unchanged.
- **EntityDetailPage.swift — VM:** `memoryDates` (`[id:date]` from linked_memories); `peopleDetails` — parses
  `attributes.people_details_by_memory` as **dict-keyed-by-memory-id** (ordered by linked_memories) **or array**
  (order preserved), unknown shape → []; `derivedAge`/`derivedRelationship`/`derivedSignificance` (first non-empty
  across cards); `heroAppearance` (first `physical_description`) and `heroQuote`
  (`dialogue_and_quotes[0].quote_text`), each carrying its source memory id.
- **Header enriched:** relationship kicker + meta pills now prefer real people_details (`Age`, relationship,
  significance), falling back to the Phase-1 provisional `attrString`; `date` stays provisional.
- **Hero cards** (loaded branch, first): 2-col grid, shown only when a pick exists — Appearance + In-their-words
  (italic, quoted). Each captioned **From "{title}"** or **"source unattributed"** when the memory is unresolved.
  Titled "BEST PICK — NOT DEFINITIVE".
- **"Across memories" section** (`EDSection`, count, collapsed): one `personMemoryCard` per memory — title/date +
  `is_public_figure` → "Public figure" pill, then `detailField` rows for `physical_description`→Appearance,
  `role_in_scene`, `relationship_type`→Relationship, `age_in_memory`→Age, `significance`, `personality_traits`,
  `clothing`, `scents`, `emotional_state_in_memory`→Emotional state, `health_status`→Health, `abilities_skills`,
  `voice_description`→Voice, `mannerisms`, `family_relationships`→Family, plus humanized `extended_attributes`
  (dynamic keys). `detailField` renders arrays as pills, scalars as rows, empties skip.

## Verified
- **BuildProject → 0 errors**; **0 warnings** on EntityDetailPage + EntityDetailSupport.
- Three build fixes en route to 0/0: added the missing `PersonMemoryDetail` type; corrected `LazyVGrid`
  (`alignment:` precedes `spacing:`, `.leading` not `.top`).

## Honest caveats (device/backend — not runnable here)
- Live `people_details_by_memory` shape (dict vs array), the renamed keys (`physical_description`, `role_in_scene`,
  `relationship_type`, `age_in_memory`, `emotional_state_in_memory`), `is_public_figure`, `extended_attributes`,
  and `dialogue_and_quotes[].quote_text` are device/backend checks. Parsing is fully defensive: missing/renamed
  keys → skipped rows; unknown shape → empty section; unresolved memory → "A memory" / "source unattributed"; a
  raw UUID is never shown.
- Header `date` pill remains provisional pending the spec.

## Next (Phases 4–5, not started)
romantic / relationship-arc heroes + arcs, then the remaining sections — all reusing the same primitives.

## No git.
