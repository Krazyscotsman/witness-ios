import SwiftUI
import Combine

/// Loads the atmosphere prompts and best-effort saves answers. Optional feature — degrades to "skip" on any
/// failure/empty so the generate flow is never blocked.
@MainActor
final class MemoirAtmosphereViewModel: ObservableObject {
    @Published private(set) var periods: [MemoirPeriodDTO] = []
    @Published private(set) var loaded = false

    private static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(auth: AuthManager) async {
        loaded = false
        let resp = try? await withAuth(auth) {
            try await APIClient.shared.get("/api/v1/memoir/atmosphere-prompts", timeout: 30,
                                           decoder: Self.snake, as: MemoirAtmospherePromptsResponse.self)
        }
        let all = resp?.periods ?? []
        let needing = all.filter { $0.hasAtmosphereData == false }
        periods = needing.isEmpty ? all : needing         // fallback to all if none flagged
        loaded = true
    }

    /// Best-effort: POST each non-empty answer. Failures are swallowed (the interview is optional).
    func submit(_ answers: [MemoirAtmosphereRequest], auth: AuthManager) async {
        for a in answers where !a.responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try? await withAuth(auth) {
                try await APIClient.shared.postIgnoringResponseBody("/api/v1/memoir/atmosphere", body: a, timeout: 30)
            }
        }
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
