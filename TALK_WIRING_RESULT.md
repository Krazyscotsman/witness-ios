# Witness — Real whole-life Talk (open-mode witness session) — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git. Same witness endpoints as Ask Scarlett.

## Applied
- **AskScarlettView.swift → WitnessSessionViewModel (additive only):**
  - `startWholeLife(greeting:auth:)` — posts body `{}` (`EmptyBody`), seeds the CLIENT greeting, discards the
    backend `opening_message`; `memoryId` stays nil. `retryStartWholeLife(auth:)` and `reset()` (for the tab's
    "New" conversation).
  - `postStartWholeLife()` (posts `{}`) + `postStartCurrent()` (memory-scoped when `memoryId` set, else
    whole-life).
  - `turnWithRestart` / `endWithRestart`: the 404 restart now calls `postStartCurrent()` (dropped the
    `guard let memoryId` so whole-life 404s re-post `{}`). **Ask Scarlett's memory path is unchanged** —
    `memoryId` is always set there, so it still restarts via `postStart(memoryId)`.
  - `postTurn` / `postEnd` / `send` / `end` / 401→refresh: untouched.
- **TalkView.swift (rewritten):** takes `auth` + `@StateObject WitnessSessionViewModel`; `.task` composes the
  greeting (`"Good {morning|afternoon|evening}{, FirstName}. How are you? {invitation}"`, first name from
  `Profile.firstNameKey`, omitted when empty) and calls `startWholeLife`. `send` → `vm.send` (real turn);
  thinking/reconnecting/error rows driven by the VM (honest retry, no canned lines); 404 transparent restart.
  "Save & exit" → `vm.end()` → shows `closing_message` (+ summary) then a **"New"** action → `reset()` + fresh
  start. Mic kept visible but stubbed.
  - **Removed:** `sampleReply()`, the fake-delay `send()`, `saveAndExit()`, the phantom `anchorGate`
    (+ `showAnchorGate`/`gateUsed`/`pendingDiscovery`), the old `openingText`/`greetingText`, and the unused
    `memory: MemoryDetailDTO?` param. `ChatMessage`/`CompanionBubble`/`UserBubble` kept (still shared with
    AskScarlettView).
- **MainTabView.swift** — `case .talk: TalkView(auth: auth)`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: TalkView,
  AskScarlettView, MainTabView (0 issues each). No transient error 5.
- Confirmed `TalkView(` is only built in MainTabView (no memory-scoped caller), and the narrator first name is a
  real stored value (`@AppStorage(Profile.firstNameKey)`), before removing the `memory` param / wiring the
  greeting.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the additive
  whole-life start / mode-aware restart / reset logic + reuse of the unchanged turn/end paths. A device pass
  confirms: empty-body start, real turns, closing on Save & exit, the 404 transparent restart re-posting `{}`,
  and honest turn-failure retry.
- **Voice/mic deferred** — the mic button is visible but a no-op stub.
- **No save-as-anchor** in open mode (endpoint doesn't exist); discoveries/new_entities ignored, phantom
  anchor gate removed.
- The repeating `"That stays with you…"` mock line is gone — turns now come from the real engine (an empty but
  decoded turn response still renders as `"…"`, and decode/transport errors surface a visible retry row).

## No git.
