# Witness — Backend networking foundation (pipe + auth) — Proposal

Status: **PROPOSED — nothing written to the project. Awaiting approval + contract answers.** No git.
Scope: the pipe + auth ONLY. No feature screens wired to real data.

## Read-first
- Confirmed: NO existing networking anywhere (grep for URLSession/URLRequest/http/SecItem/Keychain
  found only the DOCTYPE URL in Info.plist). Greenfield — no conflict.
- ATS (verified against Apple docs): iOS 17+ no longer allows IP connections by default and
  REQUIRES listing individual IPs under NSExceptionDomains (NOT NSAllowsArbitraryLoads). So the
  host-scoped NSExceptionDomains approach is correct for iOS 26.

## Step 0 — Info.plist (DEV-ONLY ATS exception; user adds in Xcode or approve diff)
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <!-- DEV-ONLY: cleartext HTTP to the local dev backend at 192.168.1.115. iOS 17+ requires
         individual IPs under NSExceptionDomains (NOT NSAllowsArbitraryLoads). Scoped to this
         one host. REMOVE when the backend moves to HTTPS in the cloud. -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.1.115</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## Contract questions (confirm before writing; the point of this work is exactness)
1. `people` element type: [String] (names) or [object]?  <-- biggest decode risk
2. user_id / narrator_id: String (UUID) or Int?
3. Login request body: JSON { "email", "password" }? field names?
4. Nullability assumptions otherwise used: exact_date: String?, location: String?,
   quality_score/importance_score: Double?, created_at/updated_at: String, people: [String]?

Three critical fields locked EXACTLY per spec: exactDateEstimated: Bool? (three-state),
narratorAge: Int?, timeGranularity: String.

---

## APIClient.swift
```swift
import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case network(Error)                    // transport failure (offline, timeout, refused)
    case http(status: Int, body: String?)  // non-2xx
    case unauthorized                       // 401 (token expiry handling later)
    case encoding(Error)                    // failed to encode request body
    case decoding(Error)                    // failed to decode response

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .http(let s, let b): return "HTTP \(s)\(b.map { ": \($0)" } ?? "")"
        case .unauthorized: return "Unauthorized (401)."
        case .encoding(let e): return "Encoding error: \(e.localizedDescription)"
        case .decoding(let e): return "Decoding error: \(e)"
        }
    }
}

/// Reusable networking layer. Cloud swap later = change `baseURL` (one line).
final class APIClient {
    static let shared = APIClient()

    // DEV: local dev server (pinned IP). Change this one line for the cloud.
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
        if authorized, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.network(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
```

## KeychainStore.swift
```swift
import Foundation
import Security

/// Stores the JWT in the iOS Keychain (not UserDefaults). Token has a 24h expiry; for now this
/// is store/retrieve/clear — expiry metadata (e.g. a stored expiry date) can be layered on later
/// to support checking/refreshing without changing call sites.
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

## APIModels.swift
```swift
import Foundation

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct LoginResponse: Decodable {
    let status: String
    let user: User
    let token: String            // TOP-LEVEL, not under user

    struct User: Decodable {
        let userId: String       // ASSUMPTION: String (UUID). Confirm String vs Int.
        let narratorId: String
        let email: String
        let name: String
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case narratorId = "narrator_id"
            case email, name
        }
    }
}

struct HealthResponse: Decodable {
    let gitSha: String?          // show this to prove reachability
    enum CodingKeys: String, CodingKey { case gitSha = "git_sha" }
}

struct MemoriesResponse: Decodable {
    let memories: [MemoryDTO]
    let total: Int
    let sort: String
    let limit: Int
    let offset: Int
}

struct MemoryDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let narrative: String
    let narrativeSnippet: String
    let exactDate: String?           // ASSUMPTION: nullable date string
    let timeGranularity: String      // day/month/season/year/school_year/age_year/unknown
    let exactDateEstimated: Bool?    // THREE-STATE: null/false/true are distinct — never defaulted
    let narratorAge: Int?            // nullable
    let qualityScore: Double?        // ASSUMPTION: nullable number
    let importanceScore: Double?
    let people: [String]?            // ASSUMPTION: array of names — CONFIRM element type
    let location: String?            // ASSUMPTION: nullable string
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, narrative
        case narrativeSnippet = "narrative_snippet"
        case exactDate = "exact_date"
        case timeGranularity = "time_granularity"
        case exactDateEstimated = "exact_date_estimated"
        case narratorAge = "narrator_age"
        case qualityScore = "quality_score"
        case importanceScore = "importance_score"
        case people, location
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

## BackendTestView.swift (TEMPORARY scratch — not a shipped feature)
```swift
import SwiftUI

// TEMP: three isolatable backend connection tests. Remove once feature screens are wired.
struct BackendTestView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var health = "—"
    @State private var email = ""
    @State private var password = ""
    @State private var loginResult = "—"
    @State private var memoriesResult = "—"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Base URL") { Text(APIClient.baseURL.absoluteString).font(.system(.footnote, design: .monospaced)) }

                Section("1 · GET /health (no auth)") {
                    Button("Run health check") { runHealth() }.disabled(busy)
                    Text(health).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section("2 · POST /api/v1/auth/login") {
                    TextField("email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("password", text: $password)
                    Button("Log in & store token") { runLogin() }.disabled(busy || email.isEmpty || password.isEmpty)
                    Text(loginResult).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section("3 · GET /api/v1/memories (uses stored token)") {
                    Button("Fetch memories (one-shot)") { runMemories() }.disabled(busy)
                    Text(memoriesResult).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section {
                    Button("Clear stored token", role: .destructive) { KeychainStore.shared.clear(); loginResult = "token cleared" }
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle("Backend Test (temp)")
        }
    }

    private func runHealth() {
        busy = true; health = "…"
        Task {
            do { let r: HealthResponse = try await APIClient.shared.get("/health", authorized: false)
                 health = "OK · git_sha: \(r.gitSha ?? "nil")" }
            catch { health = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)" }
            busy = false
        }
    }

    private func runLogin() {
        busy = true; loginResult = "…"
        Task {
            do {
                let r: LoginResponse = try await APIClient.shared.post(
                    "/api/v1/auth/login", body: LoginRequest(email: email, password: password), authorized: false)
                KeychainStore.shared.save(token: r.token)
                loginResult = "OK · \(r.user.name) · token stored (\(r.token.count) chars)"
            } catch { loginResult = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)" }
            busy = false
        }
    }

    private func runMemories() {
        busy = true; memoriesResult = "…"
        Task {
            do {
                let r: MemoriesResponse = try await APIClient.shared.get("/api/v1/memories")
                let titles = r.memories.prefix(5).map { "• \($0.title)" }.joined(separator: "\n")
                memoriesResult = "OK · got \(r.memories.count) of \(r.total)\n\(titles)"
            } catch { memoriesResult = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)" }
            busy = false
        }
    }
}
```

## YouView.swift temp launch diff
```diff
     var onSignOut: () -> Void
+    @State private var showBackendTest = false   // TEMP: backend pipe test
```
```diff
                         signOutButton
+                        // TEMP (dev): opens the backend connection test scratch view.
+                        Button("DEV · Backend test") { showBackendTest = true }
+                            .font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.5))
                     }
                     .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 110)
                 }
             }
             .toolbar(.hidden, for: .navigationBar)
+            .sheet(isPresented: $showBackendTest) { BackendTestView() }
         }
```

## After approval
Add Info.plist keys (Xcode), create the 4 files, apply the YouView temp diff, build 0/0, report.
Then on-device: /health shows git_sha; login stores token; memories decodes (one-shot). No git.
```
