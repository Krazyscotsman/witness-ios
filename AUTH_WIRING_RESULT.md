# Witness — Real login flow wired (auth only) — Result

Date: 2026-08-08

## Applied
- NEW AuthManager.swift (@MainActor ObservableObject; import Foundation + Combine):
  - bootstrapAndValidate() launch gate — no token → false; token + /auth/me 200 → true;
    token + /auth/me 401/any error → clear token + false (expired/invalid → re-login).
  - login(email:password:) → POST /api/v1/auth/login, stores token in Keychain, keeps
    narratorId/userName; throws APIError on failure.
  - logout() → clears Keychain + session.
  - handleUnauthorized(code:) → token_expired → refresh; invalid_token/auth_required/nil → logout.
    refresh() → POST /api/v1/auth/refresh (bearer + EmptyBody) → RefreshResponse{token}; own
    code-less 401 → logout. (Dormant until a guarded endpoint calls it — memories next.)
- APIClient.swift — .unauthorized now carries (detail, code); 401 parses ErrorBody{detail,code};
  errorDescription updated; added `private struct ErrorBody`.
- APIModels.swift — added MeResponse (permissive), RefreshResponse{token}, EmptyBody.
- ContentView.swift — added .launching route + splash, @StateObject AuthManager, LoginView now
  gets `auth`, onAuthenticated routes onboarded ? .main : .onboarding, .main onSignOut → auth.logout(),
  and a .task launch gate that validates via /auth/me before choosing the route.
- LoginView.swift — injects AuthManager; Sign-in button → real auth.login (busy state, disabled
  when empty/busy), shows backend 401 {detail} on failure; Create-account shows "not available yet";
  OAuth provider buttons disabled (can't bypass the gate). onBack unchanged.
- YouView.swift — unchanged; Sign out already calls onSignOut, which now runs auth.logout().

## Build honesty
First build FAILED: AuthManager used @Published/ObservableObject but I imported only Foundation,
not Combine (3 errors + cascade). Fixed by adding `import Combine`. Rebuilt clean.
Final: `The project built successfully.` — 0 errors. Diagnostics on AuthManager / APIClient /
APIModels / ContentView / LoginView all report no issues. **0 errors, 0 warnings.**

## Expired-token-at-launch (confirmed)
Handled by the validating gate: an expired 24h token → /auth/me 401 (code-less) → token cleared →
route to threshold/login. No 401 storm, no broken state. (Launch = re-login on expiry, per the
code-less contract; mid-session token_expired on a guarded call = refresh — dormant until memories.)

## Honest testing scope
- VERIFIED: clean compile + full build + per-file diagnostics (0/0).
- NOT run. On-device (ATS key present): cold launch, no token → login; bad creds → shows the
  backend {detail}; good creds → into app + token in Keychain; kill/relaunch → straight in
  (valid token via /auth/me); Sign out → back to the door.

## Out of scope (as agreed)
- No memories/feature data wired. OAuth + registration not wired (disabled). Onboarding still on
  local @AppStorage (backend onboarding_completed deferred). refresh() dormant until a guarded
  endpoint exercises it. No git.
