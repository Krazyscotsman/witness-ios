# Witness iOS — Talk / Ask Scarlett canned-line diagnosis

**Date:** 2026-08-13
**Question:** Is iOS masking a backend parse-failure with a friendly canned line? Specifically, does the string
`"That stays with you, I can tell. What happened next?"` exist client-side, and is there logic that substitutes
a placeholder assistant message when a turn (or session-start) response is empty, fails to decode, or errors?
**Method:** Full-repo search (`*.swift`) + read of both Talk surfaces. **Report only — no code changed.**

---

## (a) Does that exact line exist client-side?

**Yes — exactly once.** `TalkView.swift:245`, inside a private `sampleReply()` helper:

```swift
private func sampleReply() -> String {
    [
        "That stays with you, I can tell. What happened next?",   // line 245
        "I'm here for it — tell me more about that.",             // line 246
        "Say more. What did that feel like in the moment?"        // line 247
    ].randomElement() ?? "Tell me more."                          // line 248
}
```

Those three lines (plus the `"Tell me more."` fallback) are the only canned assistant lines in the codebase.
They exist **only** in `TalkView` — not in the real backend client.

---

## (b) Is there placeholder-substitution logic masking a backend failure?

There are **two separate Talk surfaces**, and the answer differs between them.

### 1. `TalkView` — the "Talk" tab. Pure mock; no backend call at all.
- Wired in `MainTabView` as `case .talk: TalkView()`.
- `send()` (`TalkView.swift:223`) does **not** call the backend. It appends the user's text, runs a hardcoded
  fake delay `DispatchQueue.main.asyncAfter(deadline: .now() + 1.3)`, then appends `sampleReply()` (a random
  canned line). Inline comments explicitly mark the real endpoint as **not yet wired**
  (`// Real: POST /api/v1/jarvis/witness/sessions/{id}/turns { content: text }`).
- **Conclusion:** the canned line is emitted **unconditionally on every turn**. There is no network request,
  no response, and no decode here — therefore **nothing that could fail, and nothing being masked.** It is the
  mock itself, not error-handling.

### 2. `AskScarlettView` + `WitnessSessionViewModel` — the REAL, backend-wired client (memory-scoped Ask Scarlett).
Presented from the memory detail screen. Contains **no** canned friendly substitution:

| Case | Behavior (file:line) | Masks a parse failure? |
|---|---|---|
| Turn: empty/missing `response` | `reply = (r.response ?? "").trimmed`; appends `reply.isEmpty ? "…" : reply` → shows a literal **"…"** (`AskScarlettView.swift:61–62`) | No — an ellipsis, only when `response` decoded successfully but is empty |
| Turn: decode / network / non-2xx error | generic `catch` → `errorText = "That didn't go through. Tap to try again."`, phase `.idle`; **no assistant message appended** — shows a visible retryable error row (`:66–69`, `errorRow` `:249`) | No — the failure is surfaced, not hidden |
| Session start error | `phase = .failed(...)` → "Try again" panel (`startFailed` `:257`) | No |
| Start: empty `opening_message` | appended **only if non-empty** (`:33–34`) | No canned line |
| End: `closing_message` / `summary` | appended **only if non-empty** (`:95–98`) | No canned line |
| Session died (HTTP 404) | one transparent restart+replay; a second 404 → soft retryable error (`turnWithRestart` `:75–87`) | No |

---

## Diagnosis

- The friendly line **"That stays with you, I can tell. What happened next?"** originates **only from the mock
  Talk tab (`TalkView.sampleReply()`)**, which performs **no backend call or decoding**. It therefore **cannot
  be masking a backend parse-failure** — it always emits a random canned reply by design while that tab is
  un-wired.
- The **real** Ask Scarlett path (`AskScarlettView` / `WitnessSessionViewModel`) does **not** substitute a
  friendly line for a missing/empty/undecodable response:
  - an empty-but-decoded `response` renders as **"…"**;
  - a decode / transport / HTTP error renders as an explicit **error row** ("That didn't go through. Tap to
    try again."), never a fake assistant message.
- **If the friendly line is being observed, it is the un-wired Talk tab — not a masked parse failure.**
- The only place the real client could show a benign-looking reply for an empty backend body is the **`"…"`**
  fallback at `AskScarlettView.swift:62`, and that fires **only** when `response` decodes successfully but is
  an empty string — not on a decode failure.

### Suggested next checks (if the concern is a real parse failure)
1. Confirm which surface the line appears on. If it's the **Talk tab**, that's expected mock output, unrelated
   to the backend.
2. In the **real** Ask Scarlett flow, a genuine parse failure would appear as the **red retry error row**, not
   as a friendly reply. Seeing **"…"** there would indicate a successfully-decoded turn with an **empty
   `response` field** (a backend-side empty body), which is worth investigating server-side.
