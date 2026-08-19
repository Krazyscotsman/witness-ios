# Witness — Entity Detail Phase 4: relationship arcs + romantic dynamics — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Applied
- **EntityDetailSupport.swift** — added `EDHero { title, body, memoryId, quoted }` (hero card spec).
- **EntityDetailPage.swift — VM:** generalized the Phase-3 parser into shared **`records(_ key:)`** (dict-or-array,
  shape-tolerant) → `peopleDetails` / `relationshipArcs` / `romanticDynamics` (and ready for Phase 5); added
  `sigRank` + `heroArc` (highest-significance arc, first-of-max).
- **Hero cards** now fold in the deferred arc heroes from `heroArc` (Relationship arc / What they meant to me /
  What I meant to them / Life impact), alongside Phase-3 Appearance + In-their-words. Built via a plain
  `heroList` computed (imperative) consumed by the `@ViewBuilder`. Each card captioned with its source memory or
  "source unattributed".
- **"Relationship evolution"** section (collapsed): per-arc card — type/subtype/significance/memory pills +
  `EDFieldRow`s (`arc_summary`, `arc_description`, `start_date`, `is_ongoing`, `what_they_meant_to_me`,
  `what_i_meant_to_them`, `life_impact_summary`), then **Phases** (`phase_type` + `primary_emotion` pills +
  `emotional_description`) and **Milestones** (pills = `milestone_label || milestone_type || description`).
- **"Romantic dynamics"** section (collapsed): per-row card — `partner_name`/memory/date pills + `EDFieldRow`s
  over the full field set (`communication_patterns`/`love_languages` → pills via `detailField`), plus a
  **catch-all humanized pass** over any other populated keys. Empties skip.
- **Loaded branch:** `… → acrossMemoriesSection → relationshipEvolutionSection → romanticDynamicsSection →
  linkedMemoriesSection`. Both new sections collapsed by default.

## Verified
- **BuildProject → 0 errors**; **0 warnings** on EntityDetailPage + EntityDetailSupport.
- One build fix en route to 0/0: the hero-list building was imperative (`var`/`.append`) inside a `@ViewBuilder`
  ("Type '()' cannot conform to 'View'") → extracted into a plain `heroList` computed property.

## Honest caveats (device/backend — not runnable here)
- Live `relationship_arcs_by_memory` / `romantic_dynamics` shapes, all field / phase / milestone key names, and
  the significance vocabulary (`sigRank`) are device/backend checks. Parsing is fully defensive: missing/renamed
  keys → skipped rows/pills; unknown shape → empty section; no arc → no arc heroes; unresolved memory →
  "A memory" / "source unattributed".
- Header `date` pill still provisional pending the spec.

## Next (Phase 5, not started)
The remaining `attributes` sections — reusing `records(_:)` + the same primitives.

## No git.
