# Witness — Wire real login flow (auth only) — Proposal

Status: **PROPOSED — nothing written to the project. Awaiting approval + decisions A–E.** No git.
Scope: auth only. No memories/feature data wired.

## Read-first findings
1. LoginView: fields name(register)/email/password. Primary button AND all OAuth provider
   buttons call onAuthenticated() directly — TEMP bypass, no real auth, no error UI, no network.
2. Root: WitnessApp → ContentView, a manual Route state machine starting at .threshold
   (threshold → login → onboarding → main). Auth check belongs in ContentView at launch.
3. No logged-in state today: nothing reads the token; everything shows regardless of auth.
   @AppStorage profile.onboarded only gates onboarding (TEMP-reset on sign out).

## Decisions to confirm
A. Launch validation via GET /auth/me (real check) vs optimistic token-present. Recommend /auth/me.
B. /auth/refresh request contract UNKNOWN — assuming POST + current bearer + empty body → { token }.
   Confirm, or leave refresh() a marked stub (re-login on all 401s) until contract known.
C. OAuth + Create account: disable ("coming soon") so they can't bypass the gate. Confirm.
D. Sign-out → threshold/door (then login), per door rule. Or straight to login?
E. Remove TEMP onboarded=false reset on sign out (returning user shouldn't re-onboard). OK?

---

## AuthManager.swift (new)
```swift
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var narratorId: String?
    @Published private(set) var userName: String?

    private let api = APIClient.shared
    private let keychain = KeychainStore.shared

    /// Launch gate: no token → false; token present → validate via /auth/me (200 = valid).
    /// A 401 (no code, per contract) or any error clears the token and requires re-login.
    func bootstrapAndValidate() async -> Bool {
        guard keychain.token() != nil else { return false }
        do {
            _ = try await api.get("/api/v1/auth/me", as: MeResponse.self)
            return true
        } catch {
            keychain.clear(); narratorId = nil; userName = nil
            return false
        }
    }

    /// Real login. Throws APIError on failure (view shows the 401 {detail}).
    func login(email: String, password: String) async throws {
        let r: LoginResponse = try await api.post(
            "/api/v1/auth/login",
            body: LoginRequest(email: email, password: password),
            authorized: false)
        keychain.save(token: r.token)
        narratorId = r.user.narratorId
        userName = r.user.name
    }

    func logout() {
        keychain.clear(); narratorId = nil; userName = nil
    }

    /// Expiry handling for GUARDED endpoints (call when a guarded request throws .unauthorized).
    /// token_expired → refresh + retry (returns true); invalid_token / auth_required / nil → re-login.
    @discardableResult
    func handleUnauthorized(code: String?) async -> Bool {
        switch code {
        case "token_expired":
            return await refresh()
        default:
            logout()
            return false
        }
    }

    /// PLACEHOLDER contract (Decision B): assumes POST /api/v1/auth/refresh with the current
    /// bearer + empty body returns { token }. Refresh's own 401 has no code → re-login.
    private func refresh() async -> Bool {
        do {
            let r: RefreshResponse = try await api.post("/api/v1/auth/refresh", body: EmptyBody(), authorized: true)
            keychain.save(token: r.token)
            return true
        } catch {
            logout(); return false
        }
    }
}
```

## APIModels.swift — additions
```swift
struct MeResponse: Decodable {}          // permissive: 200 = valid token (shape ignored)
struct RefreshResponse: Decodable { let token: String }
struct EmptyBody: Encodable {}
```

## APIClient.swift — enrich 401 to carry {detail, code}
```diff
-    case unauthorized                       // 401 (token expiry handling later)
+    case unauthorized(detail: String?, code: String?)   // 401; detail/code from body
```
```diff
         case .unauthorized: return "Unauthorized (401)."
+        case .unauthorized(let d, let c):
+            return "Unauthorized (401)\(c.map { " · \($0)" } ?? "")\(d.map { ": \($0)" } ?? "")"
```
```diff
-        if http.statusCode == 401 { throw APIError.unauthorized }
+        if http.statusCode == 401 {
+            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
+            throw APIError.unauthorized(detail: body?.detail, code: body?.code)
+        }
```
Add near the enum:
```swift
private struct ErrorBody: Decodable { let detail: String?; let code: String? }
```
(BackendTestView already prints errorDescription, so it keeps compiling; the .unauthorized
message now includes code/detail.)

## ContentView.swift — auth gate + launching splash
```diff
 struct ContentView: View {
-    private enum Route { case threshold, login, onboarding, main }
-    @State private var route: Route = .threshold
+    private enum Route { case launching, threshold, login, onboarding, main }
+    @State private var route: Route = .launching
+    @StateObject private var auth = AuthManager()
     @AppStorage("profile.onboarded") private var onboarded: Bool = false
     ...
     var body: some View {
         ZStack {
             switch route {
+            case .launching:
+                ZStack { ParchmentBackground(); CompassMark(color: WV.gold).frame(width: 46, height: 46) }
+                    .transition(pageTransition)
             case .threshold:
                 ThresholdView(onEnter: { withAnimation(.easeInOut(duration: 0.6)) { route = .login } })
                     .transition(pageTransition)
             case .login:
                 LoginView(
+                    auth: auth,
                     onBack: { withAnimation(.easeInOut(duration: 0.6)) { route = .threshold } },
                     onAuthenticated: {
-                        withAnimation(.easeInOut(duration: 0.6)) { route = .onboarding }   // TEMP
+                        withAnimation(.easeInOut(duration: 0.6)) { route = onboarded ? .main : .onboarding }
                     }
                 )
                 .transition(pageTransition)
             case .onboarding:
                 OnboardingView(onFinish: { onboarded = true; withAnimation { route = .main } })
                     .transition(pageTransition)
             case .main:
                 MainTabView(onSignOut: {
-                    onboarded = false   // TEMPORARY
-                    withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
+                    auth.logout()
+                    withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
                 })
                 .transition(pageTransition)
             }
         }
+        .task {
+            let valid = await auth.bootstrapAndValidate()
+            withAnimation(.easeInOut(duration: 0.4)) {
+                route = valid ? (onboarded ? .main : .onboarding) : .threshold
+            }
+        }
     }
 }
```

## LoginView.swift — real login + error + disable OAuth/register
```diff
 struct LoginView: View {
+    @ObservedObject var auth: AuthManager
     var onBack: () -> Void
     var onAuthenticated: () -> Void
     @State private var isRegistering = false
     @State private var name = ""
     @State private var email = ""
     @State private var password = ""
+    @State private var busy = false
+    @State private var errorText: String?
```
Primary button now submits real login (Sign-in mode); shows error; disabled while busy/empty:
```diff
-                    primaryButton(isRegistering ? "Create account" : "Sign in")
-                        .padding(.top, 18)
+                    primaryButton(isRegistering ? "Create account" : "Sign in")
+                        .padding(.top, 18)
+                        .disabled(busy || email.isEmpty || password.isEmpty)
+                    if let errorText {
+                        Text(errorText).font(.system(size: 13)).foregroundStyle(WV.danger)
+                            .multilineTextAlignment(.center).padding(.top, 10)
+                    }
```
```diff
     private func primaryButton(_ title: String) -> some View {
-        Button {
-            // TEMPORARY: advance to Home. Real: POST /api/v1/auth/login (or /register), then onAuthenticated().
-            onAuthenticated()
-        } label: {
-            Text(title) ...
+        Button { submit() } label: {
+            (busy ? Text("Signing in…") : Text(title)) ...
         }
         .buttonStyle(.plain)
     }
+
+    private func submit() {
+        guard !isRegistering else { errorText = "Account creation isn’t available yet."; return }
+        let e = email.trimmingCharacters(in: .whitespaces)
+        guard !e.isEmpty, !password.isEmpty else { return }
+        busy = true; errorText = nil
+        Task {
+            do { try await auth.login(email: e, password: password); onAuthenticated() }
+            catch { errorText = Self.message(for: error); busy = false }
+        }
+    }
+
+    private static func message(for error: Error) -> String {
+        if let api = error as? APIError {
+            if case .unauthorized(let detail, _) = api { return detail ?? "Incorrect email or password." }
+            return api.errorDescription ?? "Something went wrong."
+        }
+        return error.localizedDescription
+    }
```
OAuth provider buttons: disabled for now (can't produce a real token; must not bypass the gate):
```diff
     private func providerButton<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
-        Button { onAuthenticated() } label: { ... }
-        .buttonStyle(.plain)
+        Button { } label: { ... }
+        .buttonStyle(.plain)
+        .disabled(true).opacity(0.5)   // OAuth not wired yet (later item); no tokenless entry
     }
```
(Register toggle stays; submitting in register mode shows the "not available yet" note.)

## YouView.swift — no change
Sign out already calls onSignOut(); the ContentView closure now does auth.logout() + route=.threshold.

## After approval
Create AuthManager.swift; edit APIClient/APIModels/ContentView/LoginView; build 0/0; report.
On-device: cold launch with no token → threshold/login; login with bad creds → shows {detail};
good creds → into app; kill+relaunch → straight in (valid token via /auth/me); Sign out → back to door.
No git.
