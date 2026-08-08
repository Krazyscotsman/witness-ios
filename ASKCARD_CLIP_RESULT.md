# Witness — MemoryDetailView "Ask Scarlett" clipping fix — Result

Date: 2026-08-07

## Bug
On the memory detail screen, the "Ask Scarlett" card (askCard, the last element in the
scrolling content) was cut off at the bottom under the tab bar.

## Cause analysis (verified by reading the current file)
- MemoryDetailView's scroll content had `.padding(.bottom, 64)` (comment claimed it
  "clears the tab bar" — it did not). The earlier audit's assumption that this screen used
  110–120 was wrong; it was actually 64.
- MemoryDetailView is pushed from MemoriesView's NavigationStack, so the tab bar remains
  visible below it. NavStack-pushed content does not receive the tab bar's auto safe-area
  inset, so it must pad ~110 to clear the bar (same class as the Insights fix).
- 64pt was latently short of ~110 — askCard was already near the edge. The recently-added
  Listen player + empty-state line pushed askCard down past that too-small margin, turning
  a latent under-padding into a visible clip. So the Listen player was the trigger, not the
  root cause.

## Fix applied (one line, MemoryDetailView.swift)
```diff
                     .padding(.horizontal, 24)
                     .padding(.top, hasCoverPhoto ? 6 : 22)
-                    .padding(.bottom, 64)   // clears the tab bar so Ask card is fully visible
+                    .padding(.bottom, 110)  // clears the tab bar so Ask card is fully visible
```
110 matches the proven value the sibling pushed sub-screens use (Anchors/Timeline/EntityAtlas).
Everything else on the screen is untouched (Listen player, actions row, narrative,
metadata, cover, top controls). No restyle.

## Build result
`The project built successfully.` — 0 errors.
MemoryDetailView.swift diagnostics: no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + successful full build + per-file diagnostics.
- NOT run interactively. "Ask Scarlett" fully clearing the tab bar is expected from the
  110pt inset (proven value) but was not observed on device/simulator here.

## Not done
- No git.
