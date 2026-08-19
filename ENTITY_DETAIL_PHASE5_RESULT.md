# Witness — Entity Detail Phase 5 (final): remaining attributes.* sections — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings** (first try). No git. **Completes the 5-phase Entity Detail page.**

## Applied
- **EntityDetailSupport.swift** — added the declarative section engine types: `EDFieldKind`
  (`.text`/`.entity`/`.entityArray`), `EDField`, `EDPillSpec`, `AttrSectionSpec`, `EDPillData`.
- **EntityDetailPage.swift — VM:** `records(_:)` made internal so the view drives sections from it.
- **EntityDetailPage.swift — engine:** `resolvedPerson` (name from `entityNames`; keep plain names; **drop any
  value that parses as a `UUID` but isn't in the map** — never renders raw), `pillData`, `edField`
  (text→`detailField`, entity→resolved row/omit, entityArray→resolved pills), `attrCard`, `attrSection`, and
  `phase5Sections` (`ForEach` over the specs).
- **9 spec-driven sections** (each a collapsed `EDSection`, omitted when empty), in order **after Romantic
  dynamics, before Linked Memories**:
  1. **Notable lines** (`dialogue_and_quotes`) — curated quote (`quote_text`/`quote`) + significance /
     significance_type / emotional_tone / context / memory pills. (Distinct from Phase-2 `dialogue_spoken`.)
  2. **Emotions across memories** (`emotions_by_memory`) — emotion_type / intensity pills + trigger row.
  3. **Emotional truths** (`emotional_truths`) — statement lead + truth_type / weight pills + still_held row.
  4. **Life impacts** (`life_impacts`) — description lead + impact_type / severity + still_affecting.
  5. **Activities** (`activities`) — description + activity_type / location + participants (**.entityArray**).
  6. **Place details** (`places_details`) — location_type + setting / sensory / emotional significance.
  7. **Triangulation** (`triangulation_dynamics`) — triangle_type / significance_level + person_pulling /
     person_against (**.entity**) / dynamic / tactics / emotional_impact / narrator_response / still_active.
  8. **Cultural practices** (`cultural_practices`) — practice_name / type / origin + description + significance /
     personal_meaning.
  9. **Events & entertainment** (`events_and_entertainment`) — event_name / type / venue / significance +
     description + memorable_moments / emotional_impact.

## Verified
- **BuildProject → 0 errors / 0 warnings** (first build), confirmed on EntityDetailPage + EntityDetailSupport.

## Honest caveats (device/backend — not runnable here)
- Every `attributes.*` key name, shape (dict vs array), and which fields carry entity UUIDs are device/backend
  checks. Parsing is fully defensive: missing/renamed keys → skipped rows/pills; unknown shape → section omitted;
  person/entity UUIDs resolve to a name or are dropped (never rendered raw); empties skip.
- Header `date` pill remains provisional (the `Witness_Entity_Detail_Page_Spec.md` is still absent from the repo).

## The complete page (Phases 1–5)
Enable-Details gate + entry points (graph "Show more" / people-anchor "See everything") → header (pills, name,
Read Aloud) → hero cards (appearance / quote / arc heroes, "best pick — not definitive") → summary cards →
**Everything they said** → **Across memories** → **Relationship evolution** → **Romantic dynamics** → the 9
Phase-5 sections → **Linked Memories** — all opaque-`JSONValue`, defensive, UUID-safe, collapsed-by-default for
the weighty sections.

## No git.
