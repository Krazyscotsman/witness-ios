# Witness — "Ask Scarlett" wiring (Option B shell) — Result

Date: 2026-08-08

## Applied
### TalkView.swift (scoped context added; standalone tab unchanged)
- Added `var memory: SampleMemory? = nil` (nil = Talk tab, so `TalkView()` is unchanged) and
  `@Environment(\.dismiss) private var dismiss`.
- `.onAppear` now seeds the opener via `openingText()` and carries a PLACEHOLDER comment for
  the backend session start (`POST /api/v1/jarvis/witness/sessions { memory_id }`, using
  `memory?.id` — client-side UUID now → server id later). No network call.
- New `openingText()`: memory-scoped opener naming the memory
  ("Let's talk about “<title>.” …") when `memory != nil`, else the standalone greeting.
  Doc comment marks the real loop (questions, voice answers, transcription, transcript
  storage, dedup, graph) as backend-owned / connected later.
- `saveAndExit()` now calls `dismiss()` at the end — dismisses the sheet; no-op in the tab.
- Voice-answer + transcription seam already marked by the existing mic-button TODO.

### MemoryDetailView.swift (button wired)
- Added `@State private var showAsk = false`.
- `askCard` action changed from the empty TODO stub to `showAsk = true`.
- Added `.sheet(isPresented: $showAsk) { TalkView(memory: memory) }` with a comment noting
  the memory is passed for its title (opener) + id (session handoff, client UUID → server id).

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: TalkView.swift and MemoryDetailView.swift both report no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics.
- NOT run interactively. Expected: tapping "Ask Scarlett" opens TalkView as a sheet with an
  opening line naming the memory; "Save & exit" or swipe dismisses it; the standalone Talk
  tab still shows the generic greeting. Simulator/device-checkable.

## Not built (shell only, as instructed)
- No questions, voice record/playback loop, transcription, transcript storage, dedup, or
  graph enrichment — each seam is a placeholder citing the existing backend endpoint.
- Standalone Talk tab behavior unchanged.
- No git.
