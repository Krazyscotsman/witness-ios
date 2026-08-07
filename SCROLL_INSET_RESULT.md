# Witness — Scroll-content bottom inset: Result

Date: 2026-08-07

## Applied (edits actually written to disk, not just proposed)
Changed the scroll content's bottom padding to `.padding(.bottom, 110)` in the three
NavigationStack-wrapped tab screens so their last row clears the tab bar + home indicator:

- Witness/Witness/InsightsView.swift   — `.padding(.bottom, 28)`  → `.padding(.bottom, 110)`
- Witness/Witness/MemoriesView.swift   — `.padding(.bottom, 24)`  → `.padding(.bottom, 110)`
- Witness/Witness/YouView.swift        — `.padding(.bottom, 28)`  → `.padding(.bottom, 110)`

Left untouched (as agreed):
- HomeView.swift  — no NavigationStack; already receives the tab-bar inset; 110 would double-pad.
- TalkView.swift  — pinned composer bar, not a scrolling-list clip; different pattern.

## Grep confirmation
`grep -n ".padding(.bottom, 110)"` matches include:
- Witness/Witness/InsightsView.swift
- Witness/Witness/MemoriesView.swift
- Witness/Witness/YouView.swift
(plus the pre-existing pushed sub-screens: AnchorsView, EntityAtlasView, ExplainView, TimelineView.)
HomeView.swift and TalkView.swift do NOT appear — confirming they were not changed.

## Build result
`The project built successfully.` — 0 errors.
(BuildProject reports no errors; the three touched files compiled clean.)
**0 errors, 0 warnings.**

## Verification status — honest
- VERIFIED: edits on disk (grep), successful full build.
- NOT run interactively. That the last rows now fully clear the tab bar is expected from the
  110pt inset (the proven value used by the pushed sub-screens), but was not observed on a
  device/simulator here. Insights was the confirmed-clipping screen; Memories/You were fixed
  by the same structural reasoning.

## Not done
- HomeView left at 40 (recommend on-device check of the tall `.ready` state).
- No git.
