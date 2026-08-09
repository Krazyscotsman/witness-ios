import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case network(Error)                    // transport failure (offline, timeout, refused)
    case http(status: Int, body: String?)  // non-2xx
    case unauthorized(detail: String?, code: String?)   // 401; detail/code parsed from body
    case encoding(Error)                    // failed to encode request body
    case decoding(Error)                    // failed to decode response

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

/// Reusable networking layer. Cloud swap later = change `baseURL` (one line).
final class APIClient {
    static let shared = APIClient()

    // ┌─────────────────────────────────────────────────────────────────────────────┐
    // │ DEV-ONLY: local dev backend (pinned LAN IP). This is the ONE place the host   │
    // │ lives — change this single line for the HTTPS cloud swap. Paired with the     │
    // │ DEV-ONLY ATS exception in Info.plist (scoped to 192.168.1.115).               │
    // └─────────────────────────────────────────────────────────────────────────────┘
    static let baseURL = URL(string: "http://192.168.1.115:8000")!

    private let session: URLSession
    private let tokenProvider: () -> String?

    init(session: URLSession = .shared,
         tokenProvider: @escaping () -> String? = { KeychainStore.shared.token() }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    private struct Empty: Encodable {}

    func get<Response: Decodable>(_ path: String, authorized: Bool = true, timeout: TimeInterval? = nil,
                                  as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "GET", body: Optional<Empty>.none, authorized: authorized, timeout: timeout)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authorized: Bool = true,
                                                     timeout: TimeInterval? = nil,
                                                     as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "POST", body: body, authorized: authorized, timeout: timeout)
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?, authorized: Bool, timeout: TimeInterval? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }   // caps hangs (e.g. dev server down)
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
        if http.statusCode == 401 {
            // /auth/login bad-creds carry {detail}; guarded endpoints carry {code}; /auth/me and
            // /auth/refresh are code-less (nil code -> re-login, handled by AuthManager).
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
