import SwiftUI
import Combine

/// Whole-life Q&A against POST /api/v1/learn/chat. Single-shot + stateless (sends only { message }; no
/// session_id, no mode). Holds a client-side cosmetic history of answers. 401 → refresh → retry-once; any other
/// failure keeps the question so the UI can offer a one-tap retry.
@MainActor
final class LearnViewModel: ObservableObject {
    enum Phase: Equatable { case idle, asking, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var reflections: [LearnReflection] = []
    @Published private(set) var pendingQuestion: String?

    private enum SessionError: Error { case sessionEnded, badResponse }
    var isAsking: Bool { phase == .asking }

    func ask(_ text: String, auth: AuthManager) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, phase != .asking else { return }   // debounce: one in-flight at a time
        pendingQuestion = q
        phase = .asking
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/api/v1/learn/chat",
                    body: LearnChatRequest(message: q), timeout: 60, as: LearnResponse.self)
            }
            let answer = (r.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw SessionError.badResponse }
            reflections.insert(
                LearnReflection(question: q, answer: answer, confidence: r.confidence,
                                sources: Self.mapSources(r.sources)),
                at: 0)
            pendingQuestion = nil
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("That didn’t go through. Tap to try again.")   // question preserved for retry
        }
    }
    func retry(auth: AuthManager) async { if let q = pendingQuestion { await ask(q, auth: auth) } }
    func clear() { reflections.removeAll(); pendingQuestion = nil; phase = .idle }

    // Map the union sources → view models. Unknown types are dropped (never fabricated).
    private static func mapSources(_ dtos: [LearnSourceDTO]?) -> [LearnSource] {
        (dtos ?? []).compactMap { d in
            switch (d.type ?? "").lowercased() {
            case "memory":
                let title = clean(d.title) ?? "Untitled memory"
                let label = clean(d.date).map { "\(title) · \($0)" } ?? title
                return LearnSource(kind: .memory, label: label,
                                   memoryId: clean(d.id), memoryTitle: clean(d.title), memoryDate: clean(d.date))
            case "entity":
                let name = clean(d.name) ?? "Someone"
                let label = clean(d.entityType).map { "\(name) · \($0)" } ?? name
                return LearnSource(kind: .entity, label: label,
                                   memoryId: nil, memoryTitle: nil, memoryDate: nil)
            default:
                return nil
            }
        }
    }
    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
