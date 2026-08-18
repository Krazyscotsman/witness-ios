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
                                  decoder: JSONDecoder = JSONDecoder(),
                                  as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "GET", body: Optional<Empty>.none, authorized: authorized, timeout: timeout, decoder: decoder)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authorized: Bool = true,
                                                     timeout: TimeInterval? = nil,
                                                     as: Response.Type = Response.self) async throws -> Response {
        try await request(path, method: "POST", body: body, authorized: authorized, timeout: timeout)
    }

    /// PUT that treats any 2xx as success and does NOT decode the response body (the PUT ack shape isn't
    /// guaranteed — could be {status,...}, empty, or 204). Throws APIError on 401 / non-2xx / transport,
    /// same as `request(...)`. Returns the raw bytes in case a caller wants to leniently try-decode.
    @discardableResult
    func putIgnoringResponseBody<Body: Encodable>(
        _ path: String, body: Body, authorized: Bool = true, timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.encoding(error) }
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
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data   // any 2xx = success
    }

    /// POST that treats any 2xx as success and does NOT decode the response body (INSERT acks vary:
    /// {status}, {id}, 201, etc.). Throws APIError on 401 / non-2xx / transport. Returns raw bytes.
    @discardableResult
    func postIgnoringResponseBody<Body: Encodable>(
        _ path: String, body: Body, authorized: Bool = true, timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.encoding(error) }
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
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data   // any 2xx = success
    }

    /// POST multipart/form-data with a single file part (e.g. the recorded audio attached to a memory). Any
    /// 2xx = success; the response body is NOT decoded (the media-attach ack shape isn't depended on). Throws
    /// APIError on 401 / non-2xx / transport, same as the other methods, so callers can refresh+retry.
    @discardableResult
    func postMultipart(_ path: String, fileData: Data, fileName: String, mimeType: String,
                       fieldName: String = "file", authorized: Bool = true,
                       timeout: TimeInterval? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let timeout { req.timeoutInterval = timeout }
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        add("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.network(error) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        if http.statusCode == 401 {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data   // any 2xx = success
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?, authorized: Bool, timeout: TimeInterval? = nil,
        decoder: JSONDecoder = JSONDecoder()
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
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
