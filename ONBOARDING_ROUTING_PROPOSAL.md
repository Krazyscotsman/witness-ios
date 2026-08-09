# Witness — Onboarding routing from the real backend flag (read + route only) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval.** No git.
Scope: replace the local `@AppStorage("profile.onboarded")` gate with `onboarding_completed` from
`GET /api/v1/settings/profile`, and hydrate companion name/voice at launch. Do NOT wire the profile write /
onboarding save side.

## Read-first findings
- Launch: WitnessApp → ContentView. `.task` → `authValid = await auth.bootstrapAndValidate()` (Keychain token
  guard; GET /auth/me, 8s timeout; 200 → isLoggedIn=true → true; else clear+false). SplashView reveals when
  minElapsed(~3s) AND isAuthResolved(authValid != nil), then calls finishLaunch().
- Onboarding decider today = local `@AppStorage("profile.onboarded")`, used in finishLaunch(), onAuthenticated
  (post-login), and set true in OnboardingView.onFinish. Only ContentView references it (verified by grep).
- Companion storage: @AppStorage(Profile.companionNameKey="profile.companionName"),
  Profile.voiceKey="profile.voice" (default playful_female). Profile enum in YouView.swift. Speaker reads
  profile.voice.
- APIClient.get(path, authorized:true, timeout:, as:); unknown JSON keys ignored by Decodable.

## Decisions (baked in; change any on request)
a. Profile fetch fails but token valid → main (onboardingCompleted nil → router treats as main).
b. Splash waits for the profile fetch (folded before authValid is set) so the route is known at reveal;
   bounded — profile runs only after a fast /auth/me 200, with its own 8s timeout.
c. Post-login also fetches the profile and routes on the backend flag (local gate removed).
d. onFinish routes to main WITHOUT persisting (save step out of scope) → until save is wired, a relaunch
   re-routes per the backend flag.
e. Profile timeout 8s (matches /auth/me).

---

## APIModels.swift — add ProfileDTO
```swift
// MARK: - Settings profile (GET /api/v1/settings/profile) — launch routing + companion identity.
// Lenient: keys may be absent/null; unknown keys are ignored. onboarding_completed is the routing source
// of truth; companion_name/companion_voice hydrate the app's stored companion identity at launch.
struct ProfileDTO: Decodable {
    let id: String?
    let onboardingCompleted: Bool?
    let companionName: String?
    let companionVoice: String?

    enum CodingKeys: String, CodingKey {
        case id
        case onboardingCompleted = "onboarding_completed"
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
    }
}
```

## AuthManager.swift — onboardingCompleted + launch profile
```diff
     @Published private(set) var narratorId: String?
     @Published private(set) var userName: String?
     @Published private(set) var isLoggedIn = false
+    /// Backend onboarding flag, hydrated at launch / after login. nil = unknown (fetch not done or failed).
+    @Published private(set) var onboardingCompleted: Bool?
```
```swift
    /// Launch profile: after the token validates, fetch GET /settings/profile (bounded 8s timeout so a hung
    /// call can't freeze launch). Applies companion name/voice to the app's stored values and records
    /// onboarding_completed for routing. On failure, onboardingCompleted stays nil — the router treats
    /// "valid token + unknown" as: proceed to the main app (don't block, don't re-onboard).
    func loadLaunchProfile() async {
        do {
            let p = try await api.get("/api/v1/settings/profile", timeout: 8, as: ProfileDTO.self)
            applyProfile(p)
            onboardingCompleted = p.onboardingCompleted
        } catch {
            onboardingCompleted = nil
        }
    }

    /// Hydrates the app's stored companion identity from the backend (source of truth at launch). Only
    /// overwrites when the backend actually provides a value.
    private func applyProfile(_ p: ProfileDTO) {
        if let name = p.companionName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            UserDefaults.standard.set(name, forKey: Profile.companionNameKey)
        }
        if let voice = p.companionVoice?.trimmingCharacters(in: .whitespaces), !voice.isEmpty {
            // Stored as-is; Speaker tolerates a bare gender ("female"/"male") or a full <style>_<gender> id.
            UserDefaults.standard.set(voice, forKey: Profile.voiceKey)
        }
    }
```
(`logout()` also clears the flag: add `onboardingCompleted = nil`.)

## ContentView.swift — backend flag becomes the decider
```diff
-    // Real: driven by the backend's narrator.onboarding_completed flag (deferred; local flag for now).
-    @AppStorage("profile.onboarded") private var onboarded: Bool = false
```
```diff
                     onAuthenticated: {
-                        withAnimation(.easeInOut(duration: 0.6)) { route = onboarded ? .main : .onboarding }
+                        // Fetch the backend profile, then route on onboarding_completed (decision a: unknown→main).
+                        Task {
+                            await auth.loadLaunchProfile()
+                            withAnimation(.easeInOut(duration: 0.6)) {
+                                route = (auth.onboardingCompleted ?? true) ? .main : .onboarding
+                            }
+                        }
                     }
```
```diff
             case .onboarding:
                 OnboardingView(onFinish: {
-                    onboarded = true
+                    // The backend onboarding_completed flag is written by the (not-yet-wired) save step.
+                    // Until then this only advances the session; a relaunch re-routes per the backend flag.
                     withAnimation(.easeInOut(duration: 0.6)) { route = .main }
                 })
```
```diff
         .task {
-            // Validate underneath the splash; the splash decides WHEN to reveal the result
-            // (min ~3s AND auth resolved). bootstrapAndValidate has an 8s timeout so a down
-            // backend resolves to false quickly rather than hanging the splash.
-            authValid = await auth.bootstrapAndValidate()
+            // Validate underneath the splash, THEN (if valid) fetch the profile so the onboarding route is
+            // known at reveal. Both calls are timeout-bounded (8s each) so a down/hung backend can't freeze
+            // launch. authValid is set only after the profile resolves (or times out) — the splash reveals on
+            // min ~3s AND authValid != nil.
+            let valid = await auth.bootstrapAndValidate()
+            if valid { await auth.loadLaunchProfile() }
+            authValid = valid
         }
```
```diff
     private func finishLaunch() {
         let valid = authValid ?? false
         withAnimation(.easeInOut(duration: 0.6)) {
-            route = valid ? (onboarded ? .main : .onboarding) : .threshold
+            // Decision (a): valid token but profile unknown/failed (onboardingCompleted == nil) → main.
+            route = valid ? ((auth.onboardingCompleted ?? true) ? .main : .onboarding) : .threshold
         }
     }
```

## Speaker.swift — tolerate a bare-gender companion_voice (no crash, right gender)
```diff
-        let parts = id.split(separator: "_").map(String.init)
-        let style = parts.first ?? "playful"
-        let gender = parts.count > 1 ? parts[1] : "female"
+        // Accepts a full "<style>_<gender>" id OR a bare gender ("female"/"male"); anything else → female,
+        // default character. Never crashes on an unexpected value.
+        let tokens = id.split(separator: "_").map(String.init)
+        let gender = (tokens.last == "male") ? "male" : "female"
+        let style = tokens.count >= 2 ? tokens[0] : "default"   // bare gender → neutral rate/pitch
```
(The existing `switch style { case warm/direct/playful ...; default: break }` already leaves a neutral
rate/pitch for "default"/unknown.)

---

## After approval
Apply all; build 0/0 + diagnostics; report honestly. Worst-case launch: /auth/me (≤8s) then, only on a 200,
/settings/profile (≤8s) — realistic added delay ≤8s and only if the profile endpoint hangs. Not wiring the
profile write/save. No git.
