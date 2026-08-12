import Foundation
import Combine

/// Owns auth/session state: the launch gate, real login, logout, and the code-based 401
/// expiry handling. The JWT itself lives in the Keychain (KeychainStore); this holds only
/// in-memory session info (narratorId/userName).
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var narratorId: String?
    @Published private(set) var userName: String?
    @Published private(set) var isLoggedIn = false
    /// Backend onboarding flag, hydrated at launch / after login. nil = unknown (fetch not done or failed).
    @Published private(set) var onboardingCompleted: Bool?

    private let api = APIClient.shared
    private let keychain = KeychainStore.shared

    /// Launch gate — three outcomes:
    ///   1. no token                      -> false (show login)
    ///   2. token + /auth/me 200          -> true  (enter app)
    ///   3. token + /auth/me 401/any err  -> clear + false (EXPIRED or invalid -> re-login)
    /// /auth/me's 401 is code-less (per contract), so an expired 24h token lands in outcome 3:
    /// cleared and sent to login — the user never enters the app with a bad token.
    func bootstrapAndValidate() async -> Bool {
        guard keychain.token() != nil else { return false }
        do {
            // 8s timeout so an unreachable/down backend fails to login within seconds, not a ~60s hang.
            _ = try await api.get("/api/v1/auth/me", timeout: 8, as: MeResponse.self)   // 200 = valid
            isLoggedIn = true
            return true
        } catch {
            keychain.clear()
            narratorId = nil; userName = nil
            isLoggedIn = false
            return false
        }
    }

    /// Real login. Throws APIError on failure; the view reads .unauthorized(detail:) for the message.
    func login(email: String, password: String) async throws {
        let r: LoginResponse = try await api.post(
            "/api/v1/auth/login",
            body: LoginRequest(email: email, password: password),
            authorized: false)
        keychain.save(token: r.token)
        narratorId = r.user.narratorId
        userName = r.user.name
        isLoggedIn = true
    }

    func logout() {
        keychain.clear()
        narratorId = nil; userName = nil
        isLoggedIn = false
        onboardingCompleted = nil
    }

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

    /// Onboarding save. POST /settings/profile persists the profile AND flips onboarding_completed
    /// server-side (single call — no /auth/complete-onboarding). Any 2xx is success; the ack body isn't
    /// depended on for the flag (the launch profile-fetch confirms it). Throws APIError; the view maps it
    /// to friendly copy.
    func saveOnboardingProfile(_ body: ProfileCreateRequest) async throws {
        _ = try await api.post("/api/v1/settings/profile", body: body, timeout: 20, as: ProfileCreateResponse.self)
        onboardingCompleted = true
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

    /// Runtime expiry handling for GUARDED endpoints. Call when a guarded request throws
    /// APIError.unauthorized(_, code). Returns true if refreshed (caller retries), false if the
    /// session ended (caller routes to login).
    ///   token_expired                     -> refresh + retry
    ///   invalid_token/auth_required/nil    -> re-login
    /// (Dormant until a guarded endpoint is wired to call it — memories lands next.)
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

    /// POST /api/v1/auth/refresh sends the current bearer + no body, returns {status, token}.
    /// Its own 401 is code-less -> caught here -> logout -> re-login.
    private func refresh() async -> Bool {
        do {
            let r: RefreshResponse = try await api.post(
                "/api/v1/auth/refresh", body: EmptyBody(), authorized: true)
            keychain.save(token: r.token)
            return true
        } catch {
            logout()
            return false
        }
    }
}
