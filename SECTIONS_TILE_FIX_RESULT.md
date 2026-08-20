# Witness — "Sections" tile fix (count + tap target) — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Root cause (confirmed by the DEBUG dump)
`populatedSectionCount` counted **all non-empty top-level keys** of the flattened `attributes` object (≈39). ~31
of those are loose sub-fields of sections we already render (`arc_summary`, `quote`, `tone`, `to`, `phases`,
`milestones`, `physical_description`, `responder_entity_id`, `what_they_meant_to_me`, …) — not real sections. So
"39" was meaningless, and the tap target was hardcoded to prefer `people_details` ("Across Memories").

## Applied
- **Single source of truth** for the real sections: `EntityDetailViewModel.renderedSections` — the 13 known
  section types in on-screen order, each with an `anchorID` (scroll id + expand key; differs from the attributes
  key for the four fixed sections: `people_details_by_memory→across`, `relationship_arcs_by_memory→arcs`,
  `romantic_dynamics→romantic`, `dialogue_spoken→dialogue`; the 9 Phase-5 keys use their own key).
- **`hasSection(_:)`** — true only when that section actually renders (`dialogue_spoken` → `!dialogueLines.isEmpty`;
  all others → `!records(key).isEmpty`), matching exactly what draws on screen.
- **Sections tile number → `renderedSectionCount`** = count of the 13 that are non-empty (≈10 for Katie), so the
  tile matches the page. `populatedSectionCount` + its `isEmptyValue` helper **removed** (no longer surfaced).
- **Tap target → `firstRenderedAnchorID`** = first rendered section in on-screen order (generic). For Katie that's
  now "Everything they said" (dialogue) — the first section on screen — not hardcoded "Across Memories".
  `openReview` scrolls to + auto-expands it via the existing `forceExpand`/`.id` mechanism. The view's old
  `reviewTargetKey` (structured-first, hardcoded) is removed.
- **Removed** the temporary `#if DEBUG` key-dump logging.

## Verified
- **BuildProject → 0 errors / 0 warnings**; diagnostics clean on EntityDetailPage.
- Grep confirms **no remaining references** to `populatedSectionCount`, `reviewTargetKey`, or the `🧩` debug log.

## Honest caveats (device)
- `renderedSectionCount` and `firstRenderedAnchorID` are derived from the same presence checks the sections use to
  render, so the number and the on-screen sections stay in lockstep by construction. The exact count/first-section
  for a given entity is a device check (depends on that entity's data) — for Katie it should read ~10 and open the
  first visible section. The 31 loose sub-field keys are intentionally **not** surfaced or catch-all-rendered.

## No git.
