# Witness — device-test triage (3 issues)

Date: 2026-08-19. Applied #2 only. Build **0 errors / 0 warnings**. No git.

---

## 1. Anchor edit not persisting (death date reappears) — REPORT (likely BACKEND)

**Write path (confirmed same source as read):**
- `RelationshipDetailView.save()` → `auth.updateRelationship(id: row.id, body)` →
  **`PUT /timeline/relationships/{id}`** (`AuthManager.updateRelationship`, `putIgnoringResponseBody`).
- Body = `RelationshipDraft.writeRequest()` → `RelationshipWriteRequest` (APIModels). **All fields are
  non-optional `String` and always encoded** (CodingKeys map snake_case). Clearing the death date sends
  **`person_death_date: ""`** (`RelSanitize.string(nil)` → `""`; `RelationshipEditor.swift:71`). Per the DTO's own
  comment: *"'' for blanks → server NULL."* So iOS explicitly transmits an empty string intending the column to
  be nulled — the field is NOT omitted.

**Read path:**
- The anchor record detail renders `row` (a `RelationshipRow`) from `AnchorRegistryViewModel`, loaded via
  **`GET /timeline/relationships`** → `RelationshipRow.personDeathDate`. After save, iOS also does an optimistic
  local clear (`applyOptimistic` sets `row.personDeathDate = nil`) **and** `vm.refresh(auth:)`.

**Verdict — SAME source of truth, so this is not an iOS two-sources mismatch on the anchor screen.** iOS writes
`person_death_date=""` to `/timeline/relationships/{id}` and reads back from the same `/timeline/relationships`
(the `narrator_relationships` table). If the value returns on a fresh fetch, the **backend is not nulling the
column when it receives an empty string** (it likely treats `""` as "no change", or rejects/ignores an empty date
and keeps the prior value). That's a backend PUT-clear semantics issue, not iOS.

**What would confirm on the backend:** send `PUT /timeline/relationships/{id}` with `person_death_date: ""` (or
`null`) and check whether the column is set NULL. If the backend needs `null` (not `""`) to clear, that's a
1-line iOS change (send `null` for cleared dates) — but the current contract we were given is `""`→NULL, so the
fix belongs server-side unless you tell us the contract changed.

**Caveat (different surfaces, different sources — expected lag, not this bug):** the **graph node** "Died"
(`NodeDetailSheet`/`GNode.died`) comes from **`GET /api/v1/graph`**, and any entity `attributes` death value comes
from **`GET /api/v1/entities/{id}`** — both are *separate* backend projections that won't reflect a relationship
edit until the backend recomputes them. If "returning" meant the graph card or the entity page (not the anchor
record), that staleness is by-design cross-source, still backend-side.

---

## 2. Home "Talk it through with Scarlett" clipped — FIXED ✅

- Cause: `HomeView` scroll content used `.padding(.bottom, 40)`; the button is the last inline element in
  `readyContent`, so the Insights/Home tab bar (~83pt) covered it.
- Fix applied: `.padding(.bottom, 40)` → **`.padding(.bottom, 110)`** (same convention as the entity-detail fix).
  Build 0/0.

---

## 3. "39 Sections" vs ~10 rendered; tile opens "Across Memories" — REPORT (we're under-displaying)

**(a) What the number counts vs. what renders.**
- `populatedSectionCount` (EntityDetailPage:83) = **count of non-empty TOP-LEVEL keys in `attributes`**
  (`attributes.object.values.filter { !isEmpty }.count`) → **39**.
- The page renders a **fixed set of 13 attribute-backed section types**, each shown only if its key is non-empty:
  `dialogue_spoken` (Everything they said), `people_details_by_memory` (Across memories),
  `relationship_arcs_by_memory` (Relationship evolution), `romantic_dynamics` (Romantic dynamics), and the 9
  Phase-5 keys: `dialogue_and_quotes`, `emotions_by_memory`, `emotional_truths`, `life_impacts`, `activities`,
  `places_details`, `triangulation_dynamics`, `cultural_practices`, `events_and_entertainment`.
- So the page can render **at most 13** attribute-keyed sections; ~10 are non-empty for Katie. The tile counts
  **all 39** populated top-level keys. **Confirmed gap: ~26–29 populated `attributes` keys have NO rendered
  section** — we are under-displaying the entity's data. The "Sections" number and the page's sections are
  measuring different things.

**(b) Which populated keys are undisplayed — cannot enumerate exactly from here (honest).**
- I can't list the precise 39 keys without the live `/entities/{id}` payload (no backend/spec on this machine),
  and I won't guess key names. What I can state precisely: **any non-empty top-level `attributes` key that is NOT
  one of the 13 listed above is currently invisible.** Beyond header/summary-derived values (e.g. relationship_
  type/significance/age via `people_details`, and `date`/`first_seen` probed for the header), everything else is
  dropped.
- To get the exact list, quickest is a one-line DEBUG enumeration (not applied — this is report-only): log
  `attributes.object.keys.sorted()` minus the 13 rendered keys, once, on device. I can add that behind `#if
  DEBUG` when you want the definitive list, or you can read the payload directly.

**(c) Why the tile lands on "Across Memories".**
- The tap target is `reviewTargetKey` (EntityDetailPage), whose priority is: `people_details_by_memory` →
  `relationship_arcs_by_memory` → `romantic_dynamics` → the 9 Phase-5 keys → `dialogue`. Katie has
  `people_details_by_memory` populated, so it returns **"across"** first — **independent of the 39 count**. The
  tile's number (all top-level keys) and its jump target (first populated *rendered* section) are derived from
  two unrelated computations, which is exactly why it feels wrong.

**Recommendation (for a follow-up, not applied):** either (i) make the tile's number reflect *rendered* sections
(count of the 13 keys that are non-empty) so the label matches reality, and/or (ii) add a generic
"Everything else" renderer for the remaining populated top-level keys (the engine + `records()`/`detailField`
primitives can already do this) so we stop dropping ~26 keys of real data. Confirm the exact undisplayed keys
first (via the DEBUG dump) to decide which deserve first-class sections vs. a generic catch-all.

---

## Applied this pass
- #2 only: HomeView bottom padding 40 → 110. Build 0/0. No git.
