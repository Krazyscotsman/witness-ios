import SwiftUI
import Combine

struct MemoirConfig {
    var title: String
    var style: String
    var tone: String
    var wordTarget: Int
    var includeImages: Bool
    var startYear: Int?
    var endYear: Int?
    var dedication: String?
}

struct MemoirResult {
    let pdfURL: String?
    let downloadURL: String?
    let chapters: Int?
    let words: Int?
    let memories: Int?
}

/// Drives memoir generation: POST /memoir/generate (ROOT, multi-minute, synchronous), then downloads + caches
/// the PDF for the inline viewer and share sheet. Honest indeterminate wait — no fake progress (the backend
/// reports none). Reads `status` from the body (a 200 can still be an error).
@MainActor
final class MemoirViewModel: ObservableObject {
    enum Phase: Equatable { case config, generating, ready, failed(String) }
    @Published private(set) var phase: Phase = .config
    @Published private(set) var result: MemoirResult?
    @Published private(set) var localPDFURL: URL?     // downloaded + cached; used by viewer + ShareLink
    @Published private(set) var downloading = false

    private enum SessionError: Error { case sessionEnded }

    func generate(_ cfg: MemoirConfig, auth: AuthManager) async {
        guard phase != .generating else { return }        // guard double-tap
        phase = .generating; result = nil; localPDFURL = nil
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/memoir/generate", body: MemoirGenerateRequest(
                    title: cfg.title, style: cfg.style, tone: cfg.tone, wordTarget: cfg.wordTarget,
                    includeImages: cfg.includeImages, startYear: cfg.startYear, endYear: cfg.endYear,
                    dedication: cfg.dedication), timeout: 900, as: MemoirGenerateResponse.self)
            }
            if r.status == "error" {
                phase = .failed(r.message?.isEmpty == false ? r.message! : "Memoir generation failed. Please try again.")
                return
            }
            result = MemoirResult(pdfURL: r.pdfUrl, downloadURL: r.downloadUrl,
                                  chapters: r.chapterCount, words: r.wordCount, memories: r.memoriesUsed)
            phase = .ready
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("We couldn’t generate your memoir just now. Please try again.")
        }
    }
    func reset() { phase = .config; result = nil; localPDFURL = nil }

    /// Download (prefer download_url), cache on-device, expose a local file URL for the viewer + share sheet.
    func preparePDF(auth: AuthManager) async {
        guard localPDFURL == nil, !downloading,
              let raw = result?.downloadURL ?? result?.pdfURL, let url = resolvedURL(raw) else { return }
        downloading = true; defer { downloading = false }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memoirs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(abs(raw.hashValue)).pdf")
        if FileManager.default.fileExists(atPath: file.path) { localPDFURL = file; return }
        var req = URLRequest(url: url)
        if url.host == APIClient.baseURL.host, let token = KeychainStore.shared.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")   // relative /file needs Bearer
        }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
           !data.isEmpty {
            try? data.write(to: file, options: .atomic)
            localPDFURL = file
        }
    }

    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
    }
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
