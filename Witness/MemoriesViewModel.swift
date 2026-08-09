import Foundation
import Combine

/// Owns the fetched memories so they survive tab switches (held as a @StateObject in MainTabView,
/// above the recreated MemoriesView). Fetch-once + pull-to-refresh, per the heavy /memories payload.
@MainActor
final class MemoriesViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }

    @Published private(set) var memories: [MemoryDTO] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var state: LoadState = .idle

    private let path = "/api/v1/memories?limit=100&offset=0"

    /// Fetch-once: no-op if already loaded or loading. Retries allowed from .failed.
    func load(auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        await fetch(auth: auth)
    }

    /// Force reload (pull-to-refresh / retry).
    func refresh(auth: AuthManager) async {
        if state == .loading { return }
        await fetch(auth: auth)
    }

    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            let resp = try await request()
            memories = resp.memories; total = resp.total
            state = .loaded
        } catch let APIError.unauthorized(_, code) {
            // Exercises the previously-dormant refresh/re-login path.
            if await auth.handleUnauthorized(code: code) {
                do {
                    let resp = try await request()          // retry once after refresh
                    memories = resp.memories; total = resp.total
                    state = .loaded
                } catch {
                    state = .failed(message: Self.message(for: error))
                }
            } else {
                // Session ended; AuthManager.logout() fired -> ContentView routes to login.
                state = .failed(message: "Your session ended. Please sign in again.")
            }
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    private func request() async throws -> MemoriesResponse {
        // 20s timeout: /memories is heavy (~282KB, N+1 server-side) but must not hang forever.
        try await APIClient.shared.get(path, timeout: 20, as: MemoriesResponse.self)
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .network: return "Can’t reach the server. Check your connection and try again."
            case .http(let s, _): return "The server responded with an error (\(s))."
            case .decoding: return "The server sent something unexpected."
            default: return api.errorDescription ?? "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}
