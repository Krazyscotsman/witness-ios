import SwiftUI
import Combine

/// AI image generation + listing for one memory. generate() is SYNCHRONOUS server-side (~20–90s). Reuses the
/// gallery's presigned-URL resolve/refresh so the hero image behaves like the gallery.
@MainActor
final class MemoryVisualizeViewModel: ObservableObject {
    enum Phase: Equatable { case idle, generating, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var images: [MediaItemDTO] = []   // ai_generated only, newest first

    private static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }
    var hasAIImage: Bool { !images.isEmpty }

    /// Load existing AI images for the memory (called on appear and after a successful generate).
    func loadExisting(memoryId: String, auth: AuthManager) async {
        if let list = try? await withAuth(auth, {
            try await APIClient.shared.get("/api/v1/memories/\(memoryId)/media", timeout: 30,
                                           decoder: Self.snake, as: MemoryMediaResponse.self)
        }) {
            images = (list.media ?? []).filter { $0.isAIGenerated }
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }   // newest first
        }
    }

    /// POST /visualize/{id}. Reads `success` from the body (a 200 can still be a failure). Guards double-tap.
    func generate(memoryId: String, auth: AuthManager) async {
        guard phase != .generating else { return }
        phase = .generating
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/visualize/\(memoryId)?view_angle=from_behind",
                    body: EmptyBody(), timeout: 120, as: VisualizeResponse.self)
            }
            guard r.success == true else {
                let msg = (r.error?.isEmpty == false) ? r.error! : "Image generation didn’t complete. Please try again."
                phase = .failed(msg)
                return
            }
            await loadExisting(memoryId: memoryId, auth: auth)   // canonical item (with metadata + presigned url)
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("We couldn’t generate the image just now. Please try again.")
        }
    }

    // Presigned-URL helpers (mirror MediaViewModel so the hero loader behaves like the gallery).
    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
    }
    func refreshURL(mediaId: String, auth: AuthManager) async -> String? {
        (try? await withAuth(auth, {
            try await APIClient.shared.get("/api/v1/media/\(mediaId)/url", timeout: 20,
                                           decoder: Self.snake, as: MediaURLResponse.self)
        }))?.url
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
