import SwiftUI
import Combine

/// Owns the two-call "create a memory" flow for RecordView:
///   1. POST /api/v1/memories { text, session_id, title?, memory_date? } — Bearer, ~120s timeout. This BLOCKS
///      on the server extraction pipeline (~30–90s) and returns { status, memory_id, ... }.
///   2. If audio was recorded: POST /api/v1/memories/{id}/media (multipart `file`) — BEST-EFFORT. A failure
///      here never fails the memory: the text memory is already saved.
/// 401 → refresh → retry-once on the create call. On failure `save` returns nil and the caller keeps the
/// transcript + recording so nothing is lost. During the long wait `processingMessage` rotates so the UI is
/// honest, never a frozen spinner.
@MainActor
final class MemoryCreateViewModel: ObservableObject {
    @Published private(set) var processingMessage = "Saving…"
    @Published private(set) var errorText: String?

    private static let messages = [
        "Saving…",
        "Understanding it…",
        "Finding the people and places…",
        "Weaving it into your story…",
        "Almost there…"
    ]
    private var rotate: Task<Void, Never>?
    private enum CreateError: Error { case sessionEnded, badResponse }

    /// Returns the new memory_id on success, or nil on failure (caller preserves the transcript + recording).
    func save(text: String, sessionID: String, title: String?, memoryDate: String?,
              audioURL: URL?, auth: AuthManager) async -> String? {
        errorText = nil
        startRotating()
        defer { stopRotating() }
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post(
                    "/api/v1/memories",
                    body: MemoryCreateRequest(text: text, sessionId: sessionID, title: title, memoryDate: memoryDate),
                    timeout: 120, as: MemoryCreateResponse.self)
            }
            guard let id = r.memoryId, !id.isEmpty else { throw CreateError.badResponse }

            // Best-effort media attach — the text memory is valid whether or not this succeeds.
            if let url = audioURL, let data = try? Data(contentsOf: url) {
                _ = try? await withAuth(auth) {
                    try await APIClient.shared.postMultipart(
                        "/api/v1/memories/\(id)/media",
                        fileData: data, fileName: url.lastPathComponent,
                        mimeType: Self.mimeType(for: url), timeout: 120)
                }
            }
            return id
        } catch CreateError.sessionEnded {
            errorText = "Your session has ended. Please sign in again."
            return nil
        } catch {
            errorText = "We couldn’t save that just now. Your recording is safe — tap to try again."
            return nil
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp4": return "audio/mp4"
        default:    return "audio/m4a"
        }
    }

    // Rotating copy for the honest long wait; cancelled the moment the call resolves.
    private func startRotating() {
        processingMessage = Self.messages[0]
        rotate = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if Task.isCancelled { break }
                guard let self else { break }
                i = min(i + 1, Self.messages.count - 1)
                self.processingMessage = Self.messages[i]
            }
        }
    }
    private func stopRotating() { rotate?.cancel(); rotate = nil }

    // 401 → refresh → retry-once (same shape as the other view models).
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw CreateError.sessionEnded
        }
    }
}
