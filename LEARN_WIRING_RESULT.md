# Witness — Learn tab wired to POST /api/v1/learn/chat — Result

Date: 2026-08-18. **Build: "The project built successfully" (0 errors).** Per-file live diagnostics **0/0**.
No git. iOS-only (endpoint already exists).

## Applied
- **APIModels.swift** — added `LearnChatRequest { message }`, `LearnResponse` (explicit CodingKeys for
  `query_type` / `processing_time_ms`; `answer/confidence/subject/sources/mode`), and `LearnSourceDTO`
  (union: `type`, `id`, `title`, `date`, `name`, `entity_type` — all optional). All `nonisolated`.
- **LearnViewModel.swift (NEW)** — `@MainActor`, `import Combine`.
  - `ask(_:auth:)` → `POST /api/v1/learn/chat` body `{ message }` only (no mode, no session_id), **60s**,
    **401 → refresh → retry-once**. Empty/blank answer treated as a failure.
  - **Debounce**: guarded to one in-flight ask at a time.
  - **Failure preserves the question** (`pendingQuestion`); `retry(auth:)` re-asks it. `clear()` resets.
  - `mapSources`: `memory` → tappable source with id/title/date; `entity` → chip with name (+ type); unknown
    types **dropped** (never fabricated).
  - Client-side cosmetic history (`reflections`), newest first.
- **LearnView.swift**
  - Threaded `auth`; drives off `@StateObject vm`. Removed local `mode`/`thinking`/`reflections` state.
  - **Removed the mode selector** (+ `LearnModeOption`) and the **dead "Read"/TTS button** (both approved).
  - **Confidence meter shows only when the backend returns `confidence`** (fake 0.82 gone).
  - Kept the memories/entities split with **real data**: memory sources are `NavigationLink →
    MemoryDetailView(listItem: MemoryDTO(id:title:exactDate:), auth:)` (same pattern as Timeline; disabled if
    id missing); entity sources are plain chips.
  - Added a soft **error card** (retryable) and a `submit(_:)` that clears the field and calls `vm.ask`.
  - Removed the mock `ask()` (DispatchQueue fake delay) and `LearnReflection.sample`; `LearnReflection.confidence`
    is now `Double?`; `LearnSource` carries the memory tap-through payload.
  - Interpretive lenses (preset questions) kept — they now call the real `submit`.
- **InsightsView.swift:34** — `case "learn": LearnView(auth: auth)`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors).
- Live diagnostics **0 issues**: LearnView, LearnViewModel, APIModels, InsightsView.
- New file auto-included by the synchronized Xcode group (no manual target step).
- DEBUG logging (`🩺[Graph]`/`🩺[WitnessStart]`) confirmed **0 matches** project-wide (already removed prior).

## Honest caveats (device + backend checks — cannot run here)
- The live `learn/chat` round-trip, the seconds-long single-shot wait, the 401→refresh path, and memory
  source tap-through into `MemoryDetailView` are runtime behaviors verified only by compile + logic
  read-through. A device pass confirms the answer + cited sources render and memory chips open the right detail.
- `query_type` / `subject` / `mode` / `processing_time_ms` are decoded but not surfaced in the UI (available
  if we later want to show them).

## No git.
