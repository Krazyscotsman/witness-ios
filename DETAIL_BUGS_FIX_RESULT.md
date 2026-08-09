# Witness — Detail bugs fixed (#1/#2 peopleChips, #3 pop-to-root all tabs) — Result

Date: 2026-08-09

## Applied
### Fix #1/#2 — MemoryDetailView.swift
- peopleChips: HStack → FlowLayout(spacing:8, lineSpacing:8); each name Text gets lineLimit(1).
- New `struct FlowLayout: Layout` appended: wraps chips onto multiple lines and returns a width
  ≤ the proposed width, clamping each chip to the container width. (Also removed a stray no-op edit
  I made by mistake mid-apply — reverted; final file is clean.)
- Structural guarantee: because FlowLayout never exceeds the proposed width, the people row can no
  longer be wider than the content column → the content VStack stays screen-width → the title and
  narrative are no longer dragged past the screen edges. #1 (tall bars) and #2 (text overflow) are
  fixed by this one change.

### Fix #3 — pop-to-root on active-tab re-tap (Memories, Insights, You)
- MainTabView: added @State memoriesPath/insightsPath/youPath = NavigationPath(), owned above the
  tabs (survive switches). Injected into the three pushing tabs. WitnessTabBar gained
  `onReselect: (Tab) -> Void`; the button now: t == selection → onReselect(t) (pop that tab to root);
  else → Haptics.tap() + selection = t (haptic-on-change unchanged). onReselect clears the matching
  path; home/talk = no-op (they don't push).
- MemoriesView: `@Binding var path`, `NavigationStack(path: $path)`.
- InsightsView: `@Binding var path`, `NavigationStack(path: $path)` (already value-based routing).
- YouView: `@Binding var path`, `NavigationStack(path: $path)`; converted the Settings push from a
  closure NavigationLink to value-based (`NavigationLink(value: YouRoute.settings)` +
  `.navigationDestination(for: YouRoute.self) { _ in SettingsView() }`) so the path controls it.

## Behavior change (intended, per approval)
Switching tabs now PRESERVES each pushing tab's navigation stack (standard iOS model); re-tapping the
already-active tab pops that tab to root. Previously, switching tabs reset via view recreation.

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: MemoryDetailView / MainTabView / MemoriesView / InsightsView / YouView all report no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0). The width-constraint fix is
  structural (FlowLayout returns ≤ proposed width), so title/narrative can no longer be pushed
  off-screen by the people row — confirmed by construction, not just hopefully.
- NOT run interactively. On-device: the many-people memory should show wrapped chips with title/
  narrative properly inset; re-tapping Memories/Insights/You while pushed should pop to root; tab
  switches should preserve each stack.
- One honest caveat on You: SettingsView's own deeper pushes (EntityAtlas/Legal/placeholders) are
  still closure-based NavigationLinks on the same stack; clearing youPath resets the NavigationStack
  to root, which pops the whole stack including those — this is the standard NavigationPath reset
  behavior, worth an eyeball on device (re-tap You while deep in Settings → should land at the You root).

## No git.
