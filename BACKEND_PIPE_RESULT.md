# Witness — Backend networking foundation (pipe + auth) — Result

Date: 2026-08-08

## Applied (4 new files + 1 temp launch diff)
- APIClient.swift — async/await GET/POST, Codable, typed APIError
  (.network / .http(status,body) / .unauthorized (401 distinct) / .encoding / .decoding /
  .invalidURL), Bearer token injected when present. Base URL in ONE DEV constant.
- KeychainStore.swift — SecItem generic-password save/retrieve/clear (JWT; not UserDefaults).
- APIModels.swift — LoginRequest, LoginResponse (+nested User; token TOP-LEVEL), HealthResponse
  (git_sha), MemoriesResponse, MemoryDTO (explicit CodingKeys).
- BackendTestView.swift — TEMP scratch view: 3 isolatable tests (health / login+store / memories),
  credentials typed in-UI (never hardcoded), typed-error display, clear-token + close.
- YouView.swift — TEMP "DEV · Backend test" button → .sheet { BackendTestView() }.

## Confirmation 1 — MemoryDTO optionality (which fields non-optional and why)
Only `id` is NON-optional. Every other field is optional:
- id: String (required) — primary key, always returned, and the Identifiable requirement. A
  missing id is a real contract violation worth surfacing, not graceful-degrade data.
- Optional (null/absent degrades gracefully, never throws): title, narrative, narrative_snippet,
  exact_date, time_granularity (kept String? — still a String type per the lock, just null-safe),
  exact_date_estimated (Bool?, THREE-STATE preserved), narrator_age (Int?), quality_score (Double?),
  importance_score (Double?), people ([String]?), location (String?), created_at, updated_at.
- LoginResponse.User fields (user_id/narrator_id/email/name) also optional for safety; token and
  status required (token is the point of login).
Residual note: `people` is typed [String]?. If the backend sends people as OBJECTS, that's a
type mismatch (not a null) and the memories test surfaces a clear .decoding error by design —
tell me the real shape and I'll adjust. Optionality only guards null/absent, per your ruling.

## Confirmation 2 — base URL + ATS are single, obvious, DEV-ONLY
- Base URL: one constant `APIClient.baseURL = "http://192.168.1.115:8000"` inside a boxed
  DEV-ONLY comment. Grep for 192.168.1.115 → 2 hits, BOTH in APIClient.swift (the constant + its
  comment). Nothing hardcoded elsewhere; all requests use relative paths off baseURL. Cloud swap
  = change that one line.
- ATS: a single DEV-ONLY commented block scoped to 192.168.1.115 only (NSExceptionDomains →
  NSExceptionAllowsInsecureHTTPLoads), NOT NSAllowsArbitraryLoads. NOTE: not added by me — you
  add it in Xcode (Step 0). Build succeeds without it; it's needed at RUNTIME (device) or /health
  will be blocked by ATS.

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: APIClient / APIModels / BackendTestView / YouView all report no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0).
- NOT run — no network call made from here. Real proof is on-device (with the ATS key added):
  1) You → DEV · Backend test → GET /health shows git_sha (phone can see laptop).
  2) Enter real credentials → login stores token in Keychain.
  3) Fetch memories → decodes MemoriesResponse/MemoryDTO (one-shot; 282KB, expensive — do NOT
     wire into a list). Typed errors distinguish network vs non-2xx vs 401 vs decode.

## Out of scope (as instructed)
- No feature screens wired to real data. No token-refresh/expiry logic yet (store/retrieve/clear
  only). No git.
