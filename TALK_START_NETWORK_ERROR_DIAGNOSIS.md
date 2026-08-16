# Witness iOS — Talk whole-life session start "network error" — Diagnosis

**Date:** 2026-08-15
**Symptom:** Talk shows a "network error" on session start (no Scarlett message). Auth works (app reaches the
backend) and the web frontend works (backend healthy). iOS-specific to the whole-life (open-mode) start.
**Scope:** Report only — no code changed, no fix applied.

---

## 1. Exact request construction — postStartWholeLife() vs postStart()
```swift
// AskScarlettView.swift:158 — whole-life (failing)
private func postStartWholeLife() async throws -> WitnessStartResponse {
    try await APIClient.shared.post("/api/v1/jarvis/witness/sessions",
        body: EmptyBody(), timeout: 60, as: WitnessStartResponse.self)   // {} → open mode
}
// AskScarlettView.swift:154 — memory-scoped (working)
private func postStart(_ memoryId: String) async throws -> WitnessStartResponse {
    try await APIClient.shared.post("/api/v1/jarvis/witness/sessions",
        body: WitnessStartRequest(memoryId: memoryId, voiceMode: false), timeout: 60, as: WitnessStartResponse.self)
}
```
Both flow through `APIClient.post → request(...)` (APIClient.swift:54, :125):
```swift
req.httpMethod = method                                   // "POST"
req.setValue("application/json", forHTTPHeaderField: "Accept")
if let body {                                             // EmptyBody() is non-nil →
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(body)         // {} → the 2 bytes `{}`
}
if authorized, let token = tokenProvider() {             // authorized defaults true →
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
}
```
`EmptyBody` = `struct EmptyBody: Encodable {}` (APIModels.swift:32) → encodes to a REAL `{}` body (2 bytes, not
nil/empty), with Content-Type: application/json and the Bearer token attached.

**Conclusion:** the empty-body request is built CORRECTLY and is byte-for-byte identical to the working
memory-scoped start except the body payload (`{}` vs `{"memory_id":…,"voice_mode":false}`). No client-side
malformed/empty-body bug.

## 2. What error surfaces as "network error"
The message is the VM's GENERIC catch copy (AskScarlettView.swift:62–64):
```swift
} catch {
    phase = .failed("We couldn’t start the conversation. Please check your connection and try again.")
}
```
It fires for EVERY non-`sessionEnded` error — `APIError.http(4xx/5xx)`, `APIError.decoding`, `badResponse`
(200 but no session_id), AND true `APIError.network`. So the "check your connection" wording is ambiguous and
may be MASKING an HTTP 500 or a decode error. The concrete case isn't logged today.

## 3. Base URL / transport comparison — auth vs this call
- Auth: `api.post("/api/v1/auth/login")`, `api.get("/api/v1/auth/me")` (AuthManager.swift:41, :28).
- Whole-life start: `APIClient.shared.post("/api/v1/jarvis/witness/sessions")`.

Same `APIClient.shared`, same `baseURL` (http://192.168.1.115:8000), same `/api/v1` prefix, same header logic.
No hardcoded URL, no alternate prefix, no separate transport. Since auth reaches the host and the memory-scoped
start uses the identical path, a TRUE transport `.network` error is unlikely — the failure is almost certainly
application-layer (HTTP status or response-shape decode), despite the connection-sounding copy.

## Leading hypotheses (only two things differ: the `{}` body + the open-mode server path)
| # | Cause | Caught as | Timing tell |
|---|---|---|---|
| A | Backend open-mode REJECTS a bare `{}` (expects a field the web client sends, e.g. voice_mode) → 4xx/422 | APIError.http(422,…) | immediate |
| B | Server-side open-mode start error (e.g. opening-message JSON-parse) → 500 | APIError.http(500,…) | immediate-ish |
| C | 200 but different response shape in open mode → decode fails | APIError.decoding(…) | immediate |
| D | 200 but missing/empty session_id | badResponse | immediate |
| E | Server hangs on open-mode generation | APIError.network(URLError.timedOut) | ~60s delay |

Immediate ⇒ A/B/C/D (application layer). ~60s ⇒ E (timeout). **A is the standout** — the web client works and
iOS sends literally `{}`; the web frontend may POST a non-empty open-mode body.

## 4. Proposed temporary logging (reversible) — NOT applied, awaiting approval
Per CLAUDE.md, edits are proposed-and-waited; "no fix yet." Ready-to-apply instrumentation, recommended scoped
to the witness path (captures URL + status + raw bytes even on a decode failure):
```swift
// APIClient.swift — inside request(), right after `guard let http = response as? HTTPURLResponse …`
#if DEBUG
if url.absoluteString.contains("/jarvis/witness/sessions") {
    let raw = String(data: data, encoding: .utf8)?.prefix(600) ?? ""
    print("🩺[WitnessStart] \(method) \(url.absoluteString) → \(http.statusCode)  bytes=\(data.count)  body=\(raw)")
}
#endif
```
```swift
// APIClient.swift — the data(for:) transport catch
do { (data, response) = try await session.data(for: req) }
catch {
    #if DEBUG
    if url.absoluteString.contains("/jarvis/witness/sessions") {
        print("🩺[WitnessStart] TRANSPORT error: \(error)  urlCode=\((error as? URLError)?.code.rawValue ?? -1)")
    }
    #endif
    throw APIError.network(error)
}
```
```swift
// AskScarlettView.swift — startWholeLife() generic catch
} catch {
    #if DEBUG
    print("🩺[WitnessStart] caught: \(error)")
    #endif
    phase = .failed("We couldn’t start the conversation. Please check your connection and try again.")
}
```
Prints on Talk launch: method + URL, HTTP status + byte count + raw server body (422 vs 500 vs decodable 200),
any transport error + URLError code, and the final caught APIError case. Reversible — remove the three
`#if DEBUG` blocks.

## Summary
- Request is well-formed: real `{}` body, Content-Type json, Bearer token — identical transport to the working
  auth and memory-scoped-start calls (same client/base/`/api/v1` prefix).
- "Network error" is the VM's generic catch copy, which masks HTTP/decode/badResponse as well as true transport
  failures — the actual cause CANNOT be read from the message.
- Most likely application-layer (top candidate: open-mode rejecting a bare `{}` → 4xx/422; runner-up: 500 from
  opening-message generation; or a 200 decode-shape mismatch), NOT a real transport failure — confirm via the
  logging above or the server log for POST /api/v1/jarvis/witness/sessions.
- No fix applied. On approval: apply the logging patch (build 0/0), read the console/server line, pinpoint it.
