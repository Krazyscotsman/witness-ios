# Witness — Polish Result: Bottom-button safe area (Fix 1) + Tab haptic (Fix 2)

Date: 2026-08-07

## Applied
Fix 1 — 4 pinned full-width bottom buttons moved into `.safeAreaInset(edge: .bottom)`,
trailing padding changed to `.padding(.bottom, 10)`:
- OnboardingView "Continue" (bottomButton)
- OnboardingView "Begin your witness" (completionView)
- RecordView savedView "Done"
- RecordView typeMode "Save memory"
Fix 2 — MainTabView tab button fires `Haptics.tap()` only on an actual tab switch
(`if t != selection { Haptics.tap() }`).
Left untouched (as agreed): the 5 sheet "Done"/merge buttons, MemoirView "Generate"
(scrolls), LoginView (scrolls), ThresholdView "Enter" (`.bottom, 44` already clears).

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: OnboardingView, RecordView, MainTabView all report no issues.
**0 errors, 0 warnings.**

## Verification status — honest
- VERIFIED: clean compile + successful full build + per-file diagnostics.
- NOT run interactively. The items below are layout reasoning, not observed behavior.

### ~10pt shift on previously-fine screens
Expected/minor. Buttons that sat 20/24pt above the safe area now sit 10pt above the home
indicator (the inset provides indicator clearance). Bottom gap tightens slightly; button
moves down a few points. Most noticeable reflow is Begin/Done: the button is now pinned to
the bottom with the flexible Spacer above it (previously floated at the end of the centered
stack). Reads as more anchored; not broken, but it is a real reflow.

### typeMode "Save memory" vs. keyboard — NOT confirmed from a build
Reasoning only: `.safeAreaInset(edge: .bottom)` participates in SwiftUI keyboard avoidance,
so the Save button should ride above the keyboard when the editor is focused, with the
`maxHeight: .infinity` TextEditor filling the space above it. This is the expected result,
but the safeAreaInset+keyboard interaction can misbehave (button jump / editor resize) and
was NOT observed running. Needs eyes on a running app (device, or Simulator drive-through).

## Not done
- No git.
- Haptics not verifiable in Simulator (no Taptic hardware) — device confirms the tab tick.
