import SwiftUI
import Combine

// MARK: - Home's slice of /explain-me/overview (read-only). Its own call rather than sharing ExplainViewModel,
// which is owned below the Insights tab (not above the tabs) — a second read-only overview call is acceptable.
// Reuses the ExplainOverview DTO + snake decoder. On failure, Home degrades to a memory-count-only state, so
// we swallow the error here (no user-facing error on the landing screen).
@MainActor
final class HomeViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var overview: ExplainOverview?

    static let snake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
    private enum SessionError: Error { case sessionEnded }

    var hasEnoughData: Bool { overview?.dataAvailable?.hasEnoughData ?? false }
    var headline: String? {
        let h = overview?.summary?.headline?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (h?.isEmpty == false) ? h : nil
    }
    var coreForces: [ExForceDTO] { overview?.summary?.coreForces ?? [] }

    func load(auth: AuthManager) async {
        if state == .loading || state == .loaded { return }
        await fetch(auth: auth)
    }
    func refresh(auth: AuthManager) async {
        if state == .loading { return }
        await fetch(auth: auth)
    }

    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            overview = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/explain-me/overview", timeout: 30, decoder: Self.snake, as: ExplainOverview.self)
            }
            state = .loaded
        } catch {
            state = .failed   // degrade to memory-count-only; no error surfaced on Home
        }
    }

    // 401 → refresh → retry-once
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
