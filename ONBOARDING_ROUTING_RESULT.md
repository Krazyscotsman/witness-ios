# Witness — Onboarding routing from the real backend flag (read + route only) — Result

Date: 2026-08-09. Build **0 errors / 0 warnings**. No git.

## Applied
### APIModels.swift
- Added `ProfileDTO: Decodable` (lenient optionals): `id`, `onboardingCompleted` (`onboarding_completed`),
  `companionName` (`companion_name`), `companionVoice` (`companion_voice`). Unknown keys ignored by Decodable.

### AuthManager.swift
- Added `@Published private(set) var onboardingCompleted: Bool?` (nil = unknown).
- Added `loadLaunchProfile()`: `GET /api/v1/settings/profile` (8s timeout); on success applies companion
  name/voice + sets `onboardingCompleted`; on failure leaves `onboardingCompleted = nil` (decision a).
- `applyProfile(_:)` writes `Profile.companionNameKey` / `Profile.voiceKey` only when the backend provides a
  non-empty value (companion hydration never clobbers with blanks).
- `logout()` now also clears `onboardingCompleted`.

### ContentView.swift
- Removed the `@AppStorage("profile.onboarded")` local gate entirely.
- `.task`: validate → if valid, `await auth.loadLaunchProfile()` → then set `authValid`. Splash reveal stays
  gated on `authValid != nil`, so the onboarding route is known at reveal; both calls are 8s-bounded.
- `finishLaunch()`: `valid ? ((auth.onboardingCompleted ?? true) ? .main : .onboarding) : .threshold`.
- Post-login `onAuthenticated`: fetches the profile, then routes on the flag (unknown → main).
- `OnboardingView.onFinish`: routes to `.main` without writing any local flag (save step out of scope).

### Speaker.swift
- `voiceSelection()` parse hardened: full `<style>_<gender>` OR bare gender (`"female"`/`"male"`) → correct
  gender; unexpected value → female + default character. No crash.

## Verified
- Build: **0 errors, 0 warnings** (clean on first build). Per-file diagnostics: ContentView, AuthManager,
  APIModels, Speaker all report no issues.
- The backend flag is now the sole onboarding decider (grep confirmed `profile.onboarded` had no other users;
  it's fully removed).

## Honest scope / caveats
- NOT run against the live backend — the `/settings/profile` decode, the exact `onboarding_completed` /
  `companion_name` / `companion_voice` key names, and the launch route are wired per the agreed contract but
  unconfirmed against real JSON. Worth an on-device pass: (1) existing onboarded user → straight to main with
  their real companion name/voice hydrated; (2) a `onboarding_completed:false` account → onboarding; (3)
  backend down/hung → login (invalid) or main (valid token, profile fails) within the ~8s bound.
- Decision (d) as accepted: finishing onboarding does not persist yet, so until the save step is wired a
  relaunch re-routes per the backend flag. (Existing users route on their real flag and won't hit a dead-end.)
- Launch timing: worst realistic added delay ≤8s, and only if `/settings/profile` specifically hangs after a
  fast `/auth/me` 200 (a down backend fails `/auth/me` → login, no profile call).
- Did NOT wire the profile write / onboarding save (separate step, needs the write contract).

## No git.
