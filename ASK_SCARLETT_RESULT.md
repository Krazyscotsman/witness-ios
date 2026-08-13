# Witness — Ask Scarlett → real Jarvis witness-session engine (memory-scoped) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIModels.swift** — `WitnessStartRequest`/`WitnessStartResponse`, `WitnessTurnRequest`/`WitnessTurnResponse`
  (discoveries/new_entities intentionally NOT modeled), `WitnessEndResponse`. All `nonisolated`, snake_case.
- **AskScarlettView.swift (new)** — `WitnessSessionViewModel` (`@MainActor`): start/send/end, phases
  (starting/idle/sending/ending/ended/failed), `reconnecting`, `errorText`, `summary`. `turnWithRestart`/
  `endWithRestart` do a single transparent 404 restart + replay (fresh opening suppressed; capped at one).
  401→refresh→retry-once wrapper. Calls `APIClient.shared.post` (start 60s, turn/end 45s). `AskScarlettView`
  renders the thread (reused CompanionBubble/UserBubble), companion name from `@AppStorage`, "{Name} is
  thinking…/reflecting…", subtle "Reconnecting…", soft summary line, best-effort end, debounced send.
- **MemoryDetailView.swift** — Ask sheet repointed to `AskScarlettView(memory: vm.detail, auth: auth)`.
  Standalone `TalkView` tab untouched.

## Verified
- Build **0 errors / 0 warnings**; per-file diagnostics clean (AskScarlettView, APIModels, MemoryDetailView).
- State machine reviewed: 404 → one restart+replay (no loop), 401 wrapper, `canSend` gate (no concurrent
  turns), best-effort end (finalizes to .ended even on failure).

## Iteration (honest)
One build error on the first pass (0 warnings): `WitnessSessionViewModel` is an `ObservableObject` but the new
file only had `import SwiftUI` — needed **`import Combine`** (the same class of miss noted in a prior memory).
Added it; rebuilt clean.

## Honest scope / caveats
- **This is a live conversational path against the Jarvis engine — NOT exercised here** (no backend on this
  machine). Verified: build 0/0 and the state machine by reading. Unverified until a device pass: the heavy
  start round-trip, per-turn Gemini latency, an actual backend-restart 404 triggering the seamless
  restart+replay, and the real closing_message / summary shapes. Recommend a device pass: open a memory → Ask
  → confirm opening arrives, a turn replies, "thinking…" shows during each call; force/observe a 404 →
  "Reconnecting…" then the reply lands on a fresh session; End → closing + soft summary → Done.
- `summary` decoded as `String?` (shape assumption). If the backend returns an object, end still finalizes
  locally to `.ended` (best-effort), so no trap — but the summary line wouldn't render.
- No per-turn discoveries/entities UI (always null). No Anchor Registry refresh triggered from here
  (memory-scoped; async lag understood). No voice, no Door 3, no history this pass.

## No git.
