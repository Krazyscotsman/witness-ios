# Witness iOS — Conversation end/save flow (Ask Scarlett + Talk) — Diagnosis

**Date:** 2026-08-16
**Question:** What triggers `end()` (POST /end)? What happens on abandonment (background / swipe / tab switch)?
Any onDisappear/scene-phase finalization? Does reopening start a new session?
**Scope:** Report only — no code changed. Verified by reading the VM + both views and grepping the whole project.

## 1. What triggers end() (POST /end)
ONLY two explicit taps — no other caller of `vm.end()` exists:
- Ask Scarlett: the **"End"** button (AskScarlettView.swift:242) → `Task { await vm.end(auth:) }`.
- Talk: the **"Save & exit"** button (TalkView.swift:71) → `Task { await vm.end(auth:) }`.

`end()` (WitnessSessionViewModel): guard `sessionId != nil && phase == .idle`; set `.ending`; `endWithRestart()`
→ `POST …/{id}/end`; append `closing_message` if non-empty; set `summary` (`summaryText`); **`phase = .ended`** —
inside a best-effort `catch {}` (finalizes locally even if /end fails). Confirmed.

Edge cases:
- The End / Save & exit button is `.disabled` only during `.starting`/`.ending` — NOT during `.sending`. If
  tapped mid-turn, `end()`'s `phase == .idle` guard fails → it flips to `.ended` locally and returns WITHOUT
  POSTing /end (no closing/summary; server session not ended).
- `endWithRestart` does one 404 restart: if the session 404'd it starts a fresh session and ends THAT, leaving
  the original orphaned.

## 2. Abandonment (no End tap)
GREP: NO `.onDisappear` and NO `scenePhase`/background handling on AskScarlettView or TalkView. The only
`.onDisappear` hits (Graph/Media/Record/MemoryDetail) are audio/layout cleanup — none touch the witness session.
No `scenePhase` anywhere in the app. So `end()` is not called on any abandonment path:

| Abandonment | Result |
|---|---|
| Swipe away the Ask Scarlett sheet (or tap ✕) | View + VM deallocated. No /end. Turns persisted per-turn; session left `status: active`, no closing/summary. |
| Switch tabs from Talk | MainTabView `switch tab` destroys TalkView (recreated on return). VM deallocated. No /end. Session abandoned active. |
| Background / app switcher / kill | No scene-phase hook → nothing fires. Session stays active. |

Turns are saved per-turn (each `POST …/turns` persists), but the session is abandoned with no clean end, no
`closing_message`, no `summary`.

## 3. Any finalization? Can a session stay active forever?
No finalization exists for witness sessions — no `.onDisappear`/`scenePhase`/`willResignActive` path calls
`end()`. YES, an abandoned conversation can remain `status: active` server-side indefinitely (until the backend
expires/reaps it — the in-memory-session restart is what later makes turns/end 404). These abandoned-active
conversations also appear in the new history lists (memory list / recent) with NO summary and likely
`status: active`.

## 4. Reopen after abandoning → new session?
Yes — a new session starts each time; the old one is orphaned but its turns are preserved.
- Ask Scarlett: reopening the sheet builds a fresh view + fresh `@StateObject vm` (phase `.starting`, empty) →
  `.task { begin() }` → `start(memoryId:)` → `POST /sessions {memory_id}` → new session (new conversation_id).
- Talk: returning to the tab recreates TalkView + fresh VM → `startWholeLife()` → `POST /sessions {}` → new
  whole-life session. (Within one live instance, the post-`.ended` "New" button does `reset()` + `begin()`.)

Matches the contract's "each open = new session, prior turns preserved" design; the trade-off is the
orphaned-active sessions from §2/§3.

## Summary
- `end()` fires ONLY on the explicit End / Save & exit buttons (best-effort /end → closing + `.ended`); it
  silently no-ops the network call if tapped during `.sending`.
- NO `.onDisappear` / scene-phase / background handling ends the session. Swipe-away, tab-switch, background, or
  kill → abandoned, left `status: active` server-side, turns preserved, no closing/summary.
- Reopening always starts a new session; the abandoned one is orphaned (and now visible in history without a
  summary).

## (No fix applied — report only.)
Potential future options if this matters: end() on `.onDisappear` / `scenePhase == .background` (best-effort),
and/or disable/allow End during `.sending`. Not implemented pending your call.
