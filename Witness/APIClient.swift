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
