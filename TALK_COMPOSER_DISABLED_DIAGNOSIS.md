# Witness iOS — Talk composer disabled at launch — Diagnosis

**Date:** 2026-08-15
**Symptom:** In the Talk tab, the message TextField is disabled (greyed, no keyboard/cursor) from the start —
before any message is sent.
**Scope:** Report only — no code changed, no fix applied.

---

## (a) What disables the TextField — exact condition

`TalkView.composer`:
```swift
TextField("Message", text: $draft, axis: .vertical)
    …
    .disabled(!vm.canSend)          // ← the disable (also on the send button)
```
VM (`AskScarlettView.swift:20`):
```swift
var canSend: Bool { phase == .idle }
```
So the field is disabled whenever **`phase != .idle`** (i.e. `.starting`, `.sending`, `.ending`). It is **not** a
separate sending/starting flag — it is derived purely from `phase`.

The footer only renders the composer when phase is neither `.ended` nor `.failed`:
```swift
@ViewBuilder private var footer: some View {
    if vm.phase == .ended { … saved note }
    else if case .failed = vm.phase { EmptyView() }   // composer REMOVED; startRetryRow shown instead
    else { composer }                                 // .starting/.idle/.sending/.ending → composer visible
}
```

**At launch `phase == .starting`** (the VM default, `AskScarlettView.swift:10`), so the composer is shown but
disabled — greyed, no cursor. **This is by design** (don't let the user type before the session exists); it
should flip to enabled the moment `startWholeLife()` reaches `phase = .idle`. **The real defect is upstream: the
field staying greyed means the session start never reached `.idle`.**

## (b) Does `startWholeLife()` succeed? — what's confirmable vs. not

Flow (`AskScarlettView.swift:50–65`): `begin()` fires from `.task` → guard passes (phase `.starting`, messages
empty) → greeting appended → `postStartWholeLife()` = `POST /api/v1/jarvis/witness/sessions` body `{}`,
**60s** timeout. Terminal states:
- **200 + non-empty `session_id`** → `phase = .idle` → **field enables** (good).
- **200 but missing/empty `session_id`** → `throw badResponse` → generic `catch` → `phase = .failed`.
- **non-2xx / decode / transport / timeout** → `phase = .failed`.
- **401 → refresh fails** → `sessionEnded` → `phase = .failed`.

**The live HTTP result cannot be captured from this environment** (no device or backend on this machine). Static
analysis narrows it to two on-screen signatures:

| On screen | Implied phase | Meaning |
|---|---|---|
| Greyed field **persists**, no "Try again" | stuck at **`.starting`** | `POST …/sessions {}` **hasn't returned** — in-flight/hung; flips to `.failed` only after the **60s** timeout |
| Greyed briefly, then replaced by a **"Try again"** button (greeting still above) | **`.failed`** | start **errored** (non-2xx / decode / 401) — `startRetryRow` renders, composer hidden |

Because the report describes a **greyed field (not a retry button)**, the most consistent reading is **`phase` is
stuck in `.starting` — the start POST is not completing** (hanging up to 60s, or not reaching a reachable
server). If a "Try again" appears within a minute, it's `.failed` instead.

## (c) Could the server-side opening-message parse issue cause this? — yes

Although the client discards `opening_message`, the backend generates it **during session creation**. If that
generation throws the witness JSON-parse error server-side, the **`POST …/sessions` response itself is non-2xx**
→ client `start` lands in `catch` → **`phase = .failed`**. So discarding `opening_message` on the client does
**not** protect against a start failure caused by opening-message generation; it would surface here as the
**`.failed` / "Try again"** signature. Note this is a *start* failure, unrelated to the in-memory-session
restart (which only affects *turns*/`end` via the 404 restart path).

## (d) Any @FocusState / overlay issue independent of phase?

**No.** `composerFocused` starts `false` and nothing sets it true on appear; there is no overlay over the field.
A **disabled** `TextField` cannot take focus or raise a keyboard regardless — so "no keyboard/cursor" is fully
explained by `.disabled(!vm.canSend)` while `phase == .starting`. Enablement is 100% phase-driven; there is no
focus/overlay bug masking a working field.

## Summary

- **Disable condition:** `.disabled(!vm.canSend)` with `canSend = (phase == .idle)` → disabled in `.starting`
  at launch (by design).
- **Actual start HTTP result:** **not observable from this environment.** Static analysis: persistent grey ⇒
  `phase == .starting` ⇒ `POST /jarvis/witness/sessions {}` isn't returning (hang/unreachable; ≤60s → `.failed`).
  A "Try again" button ⇒ `.failed` (start errored — strong candidate: the **server-side opening-message
  JSON-parse error during session creation**, which fails the start response even though the client ignores
  `opening_message`).
- **Final phase:** whichever you observe — **`.starting` (hung)** or **`.failed` (errored)**; it is **not**
  reaching `.idle`, the only condition that re-enables the composer.

## Next step to get the definitive result (not yet applied)

A small, reversible instrumentation, offered as a proposal:
1. In `postStartWholeLife()` / `startWholeLife()`, log the request URL, the caught `APIError` case + HTTP status,
   and the resulting `phase`.
2. Launch Talk and read the Xcode device console — **or** check the server log for the response to
   `POST /api/v1/jarvis/witness/sessions`.

This distinguishes hang (`.starting`, no server log line / no response) from error (`.failed`, e.g. a 500 from
the opening-message generation). No fix until the result is known.
