import SwiftUI
import Combine

// MARK: - Media gallery data (GET /api/v1/media/gallery). Read-only. Fetch-once, 401→refresh→retry. Also owns
// URL resolution (absolute presigned as-is / relative prefixed with the API base) and presign refresh — used
// both to recover expired presigned urls (~15 min) AND as the Bearer workaround for relative /file urls that
// AsyncImage / AVAudioPlayer can't authenticate.
@MainActor
final class MediaViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var items: [MediaItemDTO] = []
    @Published private(set) var total = 0

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
                try await APIClient.shared.get("/api/v1/media/gallery?limit=50&offset=0", timeout: 30, decoder: Self.snake, as: MediaGalleryResponse.self)
            }
            items = r.media ?? []
            total = r.total ?? items.count
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load your media. Check your connection and try again.")
        }
    }

    /// Absolute (has a scheme) → as-is; relative → prefixed with the API base host.
    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
    }

    /// Fetch a fresh presigned url for this asset. Returns nil on failure (caller falls back to a placeholder).
    func refreshURL(for id: String, auth: AuthManager) async -> String? {
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/media/\(id)/url", timeout: 20, decoder: Self.snake, as: MediaURLResponse.self)
            }
            return r.url
        } catch { return nil }
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
