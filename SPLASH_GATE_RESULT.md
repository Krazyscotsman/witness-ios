# Witness — Branded launch splash / auth-validation gate — Result

Date: 2026-08-09

## Applied
- NEW SplashView.swift: parchment bg, Playfair serif "Your story begins…", a flat teal circle
  (WV.teal @0.12, no glow) growing gently from center over ~3s. Completes only when BOTH the ~3s
  floor AND isAuthResolved are true (holds gracefully if auth lags). At resolution: text crossfades
  to "Now.", the circle completes (scale 1.3), ~0.9s beat, then onComplete(). Timing decided via
  @State minElapsed + onChange(minElapsed)/onChange(isAuthResolved) → tryResolve (reads current
  values; no stale-capture from the sleep Task).
- ContentView.swift: added @State authValid: Bool?; .launching now renders
  SplashView(isAuthResolved: authValid != nil) { finishLaunch() }; .task now only sets
  authValid = await bootstrapAndValidate(); new finishLaunch() does the real routing
  (valid ? onboarded?.main:.onboarding : .threshold) with a 0.6s dissolve. Auth routing logic
  otherwise unchanged.
- Auth timeout (the requested fix): APIClient.get/post/request gained an optional
  `timeout: TimeInterval?` that sets URLRequest.timeoutInterval. bootstrapAndValidate() calls
  /auth/me with timeout: 8 → a down/unreachable backend fails to login within ~8s instead of the
  ~60s default hang. Connection-refused (server not running on a reachable host) already fails fast.

## Timing behavior (all four paths)
- No token: bootstrap returns false immediately, but the ~3s floor still runs → full splash → login.
- Valid token: /auth/me 200 → true; splash holds to 3s → "Now." → dissolve to app (or onboarding).
- Slow auth (<8s): splash holds past 3s until it resolves, then reveals — no early cut, no flash.
- Down/unreachable backend: /auth/me times out at 8s → false → dissolve to login (no freeze).

## Build result
`The project built successfully.` — 0 errors.
Diagnostics: SplashView / ContentView / APIClient / AuthManager all report no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0); timing/timeout logic
  confirmed by code reasoning.
- NOT run interactively. On-device: cold launch shows the ~3s reveal → dissolves to app (valid
  token) or login (no/expired token); with the dev server OFF, it should reach login within ~8s,
  not hang.

## Notes / choices
- Circle style: flat teal @0.12 opacity + teal serif text (legible, calm, no glow) — the default
  I flagged; say the word to switch to a solid disc + parchment text.
- No git.
