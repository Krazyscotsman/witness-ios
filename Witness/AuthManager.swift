import Foundation
import Combine

/// Owns auth/session state: the launch gate, real login, logout, and the code-based 401
/// expiry handling. The JWT itself lives in the Keychain (KeychainStore); this holds only
/// in-memory session info (narratorId/userName).
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var narratorId: String?
    @Published private(set) var userName: String?

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
            return true
        } catch {
            keychain.clear()
            narratorId = nil; userName = nil
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
    }

    func logout() {
        keychain.clear()
        narratorId = nil; userName = nil
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
