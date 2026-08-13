import SwiftUI
import Combine

// MARK: - Timeline data (GET /timeline/visual). BARE path (no /api/v1), Bearer, NO params — all filtering is
// client-side. The endpoint is N+1 (many memories) → slow, so a spinner covers the first load. Fetch-once:
// re-entry (mode/filter changes) reuses the loaded years; pull-to-refresh re-fetches.
@MainActor
final class TimelineViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var years: [TimelineYear] = []
    @Published private(set) var birthdate: String?
    @Published private(set) var totalMemories = 0
    @Published private(set) var totalYears = 0

    static let snake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
    private enum SessionError: Error { case sessionEnded }

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
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/timeline/visual", timeout: 60, decoder: Self.snake, as: TimelineResponse.self)
            }
            years = (r.years ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }   // newest first
            birthdate = r.birthdate
            totalMemories = r.totalMemories ?? 0
            totalYears = r.totalYears ?? 0
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load your timeline. Check your connection and try again.")
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
