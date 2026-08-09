import Foundation
import Combine

/// Loads a single memory's rich detail (GET /api/v1/memories/{id}/detail) and pre-splits its
/// narrative into render-safe paragraphs OFF the main thread. Mirrors MemoriesViewModel's
/// 401 → refresh → retry-once path. Created fresh per detail push (detail is per-id, not cached).
@MainActor
final class MemoryDetailViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }

    @Published private(set) var detail: MemoryDetailDTO?
    @Published private(set) var paragraphs: [String] = []   // pre-split narrative chunks (render-safe)
    @Published private(set) var state: LoadState = .idle

    /// Fetch-once for this view instance: no-op if already loaded or loading.
    func load(id: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        await fetch(id: id, auth: auth)
    }

    /// Retry from the failed state.
    func retry(id: String, auth: AuthManager) async {
        if state == .loading { return }
        await fetch(id: id, auth: auth)
    }

    private func fetch(id: String, auth: AuthManager) async {
        state = .loading
        do {
            let d = try await request(id)
            await apply(d)
            state = .loaded
        } catch let APIError.unauthorized(_, code) {
            if await auth.handleUnauthorized(code: code) {
                do {
                    let d = try await request(id)          // retry once after refresh
                    await apply(d)
                    state = .loaded
                } catch {
                    state = .failed(message: Self.message(for: error))
                }
            } else {
                state = .failed(message: "Your session ended. Please sign in again.")
            }
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    private func apply(_ d: MemoryDetailDTO) async {
        let text = d.narrative ?? ""
        // Split off the main thread — scales to the densest (~174K-char) narrative without hitching.
        let chunks = await Task.detached(priority: .userInitiated) { Self.splitNarrative(text) }.value
        detail = d
        paragraphs = chunks
    }

    private func request(_ id: String) async throws -> MemoryDetailDTO {
        try await APIClient.shared.get("/api/v1/memories/\(id)/detail", timeout: 20, as: MemoryDetailDTO.self)
    }

    /// Splits a narrative into render-safe chunks. PRIMARY boundary = paragraph breaks (blank lines /
    /// double newlines) so paragraphs stay intact and readable; FALLBACK = word-boundary hard-wrap for
    /// any single paragraph longer than `maxChars` (and a character hard-cut for a pathological
    /// space-less token) so no chunk is ever large enough to blank a single SwiftUI Text.
    nonisolated static func splitNarrative(_ text: String, maxChars: Int = 4000) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [String] = []
        // A blank line (two-or-more consecutive newlines) is a paragraph break. Trimming each piece
        // collapses runs of 3+ newlines cleanly; single newlines inside a paragraph are preserved.
        for piece in normalized.components(separatedBy: "\n\n") {
            let para = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if para.isEmpty { continue }
            if para.count <= maxChars {
                paragraphs.append(para)
            } else {
                paragraphs.append(contentsOf: hardWrap(para, maxChars: maxChars))
            }
        }
        return paragraphs
    }

    nonisolated private static func hardWrap(_ para: String, maxChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for word in para.split(separator: " ", omittingEmptySubsequences: false) {
            // Pathological single token longer than the cap: flush, then hard-cut by characters.
            if word.count > maxChars {
                if !current.isEmpty { result.append(current); current = "" }
                var idx = word.startIndex
                while idx < word.endIndex {
                    let end = word.index(idx, offsetBy: maxChars, limitedBy: word.endIndex) ?? word.endIndex
                    result.append(String(word[idx..<end]))
                    idx = end
                }
                continue
            }
            if !current.isEmpty && current.count + word.count + 1 > maxChars {
                result.append(current); current = ""
            }
            current += (current.isEmpty ? "" : " ") + word
        }
        if !current.isEmpty { result.append(current) }
        return result
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
