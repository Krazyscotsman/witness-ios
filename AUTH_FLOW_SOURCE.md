# Witness — Auth flow: verbatim security-critical source (FOR REVIEW)

Status: **REVIEW ONLY — written at repo root, OUTSIDE Witness/Witness/, so it is NOT compiled
or applied.** No git. Read (a)(b)(c)(d) annotations inline.

Expired-token-at-launch: handled by (b) — GET /auth/me returns 401 for an expired token
(code-less), which the launch gate treats as clear-token + re-login. The user never enters the
app with a bad token, so there is no in-app 401 storm.

---

## (a) Token store / read / clear — KeychainStore.swift (ALREADY in the project; shown verbatim)
```swift
import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()
    private init() {}

    private let service = "com.witness.auth"
    private let account = "jwt"

    @discardableResult
    func save(token: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)   // replace any existing
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    @discardableResult
    func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```
JWT lives in the iOS Keychain (generic password, accessible-after-first-unlock), never
UserDefaults. `token()` is what APIClient reads to attach the bearer.

---

## (c)+(d) 401 parsing — APIClient.swift (PROPOSED enriched version, verbatim)
```swift
import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case network(Error)
    case http(status: Int, body: String?)
    case unauthorized(detail: String?, code: String?)   // 401; detail/code parsed from body
    case encoding(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .http(let s, let b): return "HTTP \(s)\(b.map { ": \($0)" } ?? "")"
        case .unauthorized(let d, let c):
            return "Unauthorized (401)\(c.map { " · \($0)" } ?? "")\(d.map { ": \($0)" } ?? "")"
        case .encoding(let e): return "Encoding error: \(e.localizedDescription)"
        case .decoding(let e): return "Decoding error: \(e)"
        }
    }
}

private struct ErrorBody: Decodable { let detail: String?; let code: String? }

final class APIClient {
    static let shared = APIClient()

    // DEV-ONLY: local dev backend (pinned LAN IP). One place; change for the HTTPS cloud swap.
    static let baseURL = URL(string: "http://192.168.1.115:8000")!

    private let session: URLSession
    private let tokenProvider: () -> String?

    init(session: URLSession = .shared,
         tokenProvider: @escaping () -> String? = { KeychainStore.shared.token() }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    private struct Empty: Encodable {}

    func get<Response: Decodable>(_ path: String, authorized: Bool = true,
                                  as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "GET", body: Optional<Empty>.none, authorized: authorized)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authorized: Bool = true,
                                                     as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "POST", body: body, authorized: authorized)
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?, authorized: Bool
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { req.httpBody = try JSONEncoder().encode(body) }
            catch { throw APIError.encoding(error) }
        }
        // (a) bearer attached from Keychain when a token exists and the call is authorized.
        if authorized, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.network(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        // (c) 401 is surfaced distinctly WITH the parsed {detail, code}. `code` is nil when the
        // body has none — which is exactly the /auth/me and /auth/refresh case (d).
        if http.statusCode == 401 {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
```

---

## (b)+(c)+(d) AuthManager.swift (PROPOSED new file, complete verbatim)
```swift
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var narratorId: String?
    @Published private(set) var userName: String?

    private let api = APIClient.shared
    private let keychain = KeychainStore.shared

    // (b) LAUNCH GATE — three outcomes:
    //   1. no token                     -> false (show login)
    //   2. token + /auth/me 200         -> true  (enter app)
    //   3. token + /auth/me 401/any err -> clear + false (EXPIRED or invalid token -> re-login)
    // /auth/me's 401 is code-less (per contract), so an expired 24h token lands in outcome 3:
    // cleared and sent to login. The user never enters the app with a bad token.
    func bootstrapAndValidate() async -> Bool {
        guard keychain.token() != nil else { return false }
        do {
            _ = try await api.get("/api/v1/auth/me", as: MeResponse.self)   // 200 = valid
            return true
        } catch {
            keychain.clear()
            narratorId = nil; userName = nil
            return false
        }
    }

    // Real login. Throws APIError on failure; the view reads .unauthorized(detail:) for the message.
    func login(email: String, password: String) async throws {
        let r: LoginResponse = try await api.post(
            "/api/v1/auth/login",
            body: LoginRequest(email: email, password: password),
            authorized: false)
        keychain.save(token: r.token)          // (a) persist JWT to Keychain
        narratorId = r.user.narratorId
        userName = r.user.name
    }

    func logout() {
        keychain.clear()
        narratorId = nil; userName = nil
    }

    // (c) RUNTIME expiry handling for GUARDED endpoints. Call when a guarded request throws
    // APIError.unauthorized(_, code). Returns true if refreshed (caller retries), false if the
    // session ended (caller routes to login).
    //   token_expired            -> refresh + retry
    //   invalid_token/auth_required/nil -> re-login
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

    // (d) refresh. Its OWN 401 is code-less (per contract) -> caught here -> logout -> re-login.
    // PLACEHOLDER contract (Decision B): assumes POST /api/v1/auth/refresh with the current
    // bearer + empty body returns { token }. Confirm the real request/response shape.
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
```

### Supporting model additions (APIModels.swift)
```swift
struct MeResponse: Decodable {}                       // permissive: 200 = valid (shape ignored)
struct RefreshResponse: Decodable { let token: String }
struct EmptyBody: Encodable {}
```

---

## How a caller reads the 401 code (for when guarded endpoints are wired later)
```swift
do {
    let x = try await APIClient.shared.get("/some/guarded/endpoint", as: SomeType.self)
} catch let APIError.unauthorized(_, code) {
    if await auth.handleUnauthorized(code: code) {
        // refreshed -> retry the request once
    } else {
        // session ended -> route to login
    }
}
```

## Confirmation summary
- (a) token stored/read via Keychain only; bearer attached in APIClient from `tokenProvider()`.
- (b) launch decides logged-in by VALIDATING via /auth/me — expired token -> 401 -> clear -> login.
- (c) 401 carries {detail, code}; token_expired -> refresh, else -> re-login.
- (d) /auth/me and /auth/refresh code-less 401s resolve to re-login (bootstrap catch; refresh catch).
- Expired-at-launch path: HANDLED (outcome 3) — clean re-login, no 401 storm, no broken state.
- Not applied. Awaiting your OK + Decision B (/auth/refresh contract) before writing to the project.
