# Witness iOS — Talk/Ask Scarlett start: DEBUG logging applied

**Date:** 2026-08-15. Build **0 errors / 0 warnings**. No git. Reversible (DEBUG-only) instrumentation.

## Context
Backend confirms `POST /api/v1/jarvis/witness/sessions` returns **200 OK** with a valid session (real Gemini
opening ~13–15K chars). So iOS is failing **after** a successful 200 → almost certainly a **decode mismatch on
`WitnessStartResponse`**. This logging captures the exact 200 body + the caught error so we can see why it
doesn't decode.

## Applied (4 DEBUG blocks, all scoped/reversible)
- **APIClient.swift → `request()`**, right after the `HTTPURLResponse` guard — logs every call whose URL
  contains `/jarvis/witness/sessions`:
  ```
  🩺[WitnessStart] POST <url> → <status>  bytes=<n>  body=<first 600 chars>
  ```
- **APIClient.swift → the `data(for:)` transport catch** — logs a true transport failure + URLError code:
  ```
  🩺[WitnessStart] TRANSPORT error: <error>  urlCode=<n>
  ```
- **AskScarlettView.swift → `startWholeLife()` generic catch** (Talk tab):
  ```
  🩺[WitnessStart] caught: <error>
  ```
- **AskScarlettView.swift → `start()` generic catch** (memory-scoped Ask Scarlett) — added because you'll test
  via Ask Scarlett; same reversible one-liner so that path also prints the decode-error detail.

All four are `#if DEBUG` and gated to the witness sessions path (the transport/request logs) — remove the blocks
to revert.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: APIClient,
  AskScarlettView (0 issues each).

## What you'll see (open Ask Scarlett, watch the Xcode console)
1. `🩺[WitnessStart] POST …/sessions → 200  bytes=…  body={…}` — the **raw 200 body** (first 600 chars). This
   shows the real field names/shape the server returns.
2. `🩺[WitnessStart] caught: decoding(Swift.DecodingError.keyNotFound/…)` — the **exact decode failure**
   (which key/type mismatched) confirming the `WitnessStartResponse` mismatch.

Compare (2)'s missing/typed key against `WitnessStartResponse` (currently expects, snake→camel:
`session_id`, `conversation_id`, `opening_message`, `context_summary` — all optional). If the server uses
different names (e.g. `id`/`session`/`greeting`) or nests them, the body in (1) will show it and (2) will name it.

## Honest note
- Logging only — no behavior change; the start still fails until we fix the DTO. `body=` is truncated to 600
  chars (enough to see the JSON keys; the ~13–15K Gemini opening is intentionally not fully printed).
- Next step after you paste the console line: propose the `WitnessStartResponse` (and likely
  `WitnessTurnResponse`/`WitnessEndResponse`) CodingKeys/shape fix, then remove this logging.

## No git.
