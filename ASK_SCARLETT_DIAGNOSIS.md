# Witness — "Ask Scarlett" does nothing (item 5) — diagnosis + scope decision

Status: **DIAGNOSIS ONLY — no code changed. Awaiting scope decision (A/B/C).** No git.

## Finding 1 — what the button does today
`askCard` action is an empty stub (MemoryDetailView.swift:235):
`Button { /* TODO: open Talk anchored to this memory */ } label: { … }`.
The tap does nothing — witnessPress gives the dip/haptic, but there's no navigation or
presentation. That's the entire cause.

## Finding 2 — what conversation surface exists
`TalkView` exists ONLY as the standalone Talk tab. Signature: `struct TalkView: View` with
`@AppStorage(companion)` + internal @State (messages/draft/composer). It has NO initializer
parameter and NO memory-context mode — there is no "discuss this memory" conversation
anywhere. Opening TalkView would be a generic, UNSCOPED conversation.

Wrinkles:
- No modal dismiss on TalkView. Its only exit is "Save & exit", which RESETS messages but
  does NOT dismiss (no @Environment(\.dismiss)). Presented as fullScreenCover it would trap
  the user → needs a close control added. (A sheet could be swiped away.)
- MemoryDetailView is pushed inside MemoriesView's NavigationStack, so it can't switch to
  the Talk tab without plumbing a tab-selection binding up from MainTabView.

## Scope options (user decides)
- A — Unscoped open (minimal): askCard presents TalkView() (generic). Small, but needs a
  close button added to TalkView so it's dismissable. Not memory-scoped.
- B — Memory-scoped open: add an optional memory/opening-line context to TalkView, then
  present it ("Let's talk about '<title>'…"). Touches TalkView; still no backend logic.
- C — Switch to Talk tab: thread a tab-selection binding MainTabView → MemoriesView →
  MemoryDetailView. Most invasive; also unscoped.

Recommendation: A if the goal is just "open the conversation now" (present TalkView as a
fullScreenCover + add a small close control), memory-scoping later once backend sessions are
wired. B if it should reference the memory today (modifies TalkView).

No Scarlett conversation logic will be built (backend-gated) — this is navigation/opening
only. Awaiting: A/B/C, and for A/B fullScreenCover vs sheet.
