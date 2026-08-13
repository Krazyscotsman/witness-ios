import SwiftUI
import Combine

@MainActor
final class ExplainViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var overviewState: LoadState = .idle
    @Published private(set) var overview: ExplainOverview?
    @Published private(set) var forcesState: LoadState = .idle
    @Published private(set) var forces: [ExForceDTO] = []
    @Published private(set) var patternsState: LoadState = .idle
    @Published private(set) var patterns: [ExPatternDTO] = []
    @Published private(set) var breakingState: LoadState = .idle
    @Published private(set) var breaking: [ExBreakingDTO] = []
    @Published private(set) var contradictionsState: LoadState = .idle
    @Published private(set) var contradictions: [ExContradictionDTO] = []
    @Published private(set) var identityState: LoadState = .idle
    @Published private(set) var identity: ExIdentity?
    @Published private(set) var beliefsState: LoadState = .idle
    @Published private(set) var beliefs: ExBeliefs?

    static let snake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
    private enum SessionError: Error { case sessionEnded }

    func loadOverview(auth: AuthManager) async {
        if overviewState == .loading || overviewState == .loaded { return }
        overviewState = .loading
        do {
            overview = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/explain-me/overview", timeout: 30, decoder: Self.snake, as: ExplainOverview.self)
            }
            overviewState = .loaded
        } catch SessionError.sessionEnded {
            overviewState = .failed("Your session has ended. Please sign in again.")
        } catch {
            overviewState = .failed("We couldn’t load this yet. Check your connection and try again.")
        }
    }
    func retryOverview(auth: AuthManager) async { overviewState = .idle; await loadOverview(auth: auth) }

    // Unified lazy entry — the view calls this on each tab's first appearance (task id: tab).
    func load(_ tab: ExplainView.ExTab, auth: AuthManager) async {
        switch tab {
        case .overview:       await loadOverview(auth: auth)
        case .forces:         await loadForces(auth: auth)
        case .patterns:       await loadPatterns(auth: auth)
        case .breaking:       await loadBreaking(auth: auth)
        case .contradictions: await loadContradictions(auth: auth)
        case .identity:       await loadIdentity(auth: auth)
        case .beliefs:        await loadBeliefs(auth: auth)
        }
    }
    func retry(_ tab: ExplainView.ExTab, auth: AuthManager) async {
        switch tab {
        case .overview:       overviewState = .idle
        case .forces:         forcesState = .idle
        case .patterns:       patternsState = .idle
        case .breaking:       breakingState = .idle
        case .contradictions: contradictionsState = .idle
        case .identity:       identityState = .idle
        case .beliefs:        beliefsState = .idle
        }
        await load(tab, auth: auth)
    }

    private func loadForces(auth: AuthManager) async {
        if forcesState == .loading || forcesState == .loaded { return }
        forcesState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/active-forces?limit=50", timeout: 20, decoder: Self.snake, as: ExForcesResponse.self) }
            forces = r.forces ?? []; forcesState = .loaded
        } catch { forcesState = Self.fail(error) }
    }
    private func loadPatterns(auth: AuthManager) async {
        if patternsState == .loading || patternsState == .loaded { return }
        patternsState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/patterns?limit=50", timeout: 20, decoder: Self.snake, as: ExPatternsResponse.self) }
            patterns = r.patterns ?? []; patternsState = .loaded
        } catch { patternsState = Self.fail(error) }
    }
    private func loadBreaking(auth: AuthManager) async {
        if breakingState == .loading || breakingState == .loaded { return }
        breakingState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/breaking-points?limit=50", timeout: 20, decoder: Self.snake, as: ExBreakingResponse.self) }
            breaking = r.breakingPoints ?? []; breakingState = .loaded
        } catch { breakingState = Self.fail(error) }
    }
    private func loadContradictions(auth: AuthManager) async {
        if contradictionsState == .loading || contradictionsState == .loaded { return }
        contradictionsState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/contradictions?limit=50", timeout: 20, decoder: Self.snake, as: ExContradictionsResponse.self) }
            contradictions = r.contradictions ?? []; contradictionsState = .loaded
        } catch { contradictionsState = Self.fail(error) }
    }
    private func loadIdentity(auth: AuthManager) async {
        if identityState == .loading || identityState == .loaded { return }
        identityState = .loading
        do {
            identity = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/identity", timeout: 20, decoder: Self.snake, as: ExIdentity.self) }
            identityState = .loaded
        } catch { identityState = Self.fail(error) }
    }
    private func loadBeliefs(auth: AuthManager) async {
        if beliefsState == .loading || beliefsState == .loaded { return }
        beliefsState = .loading
        do {
            beliefs = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/beliefs", timeout: 20, decoder: Self.snake, as: ExBeliefs.self) }
            beliefsState = .loaded
        } catch { beliefsState = Self.fail(error) }
    }

    // task(id:) cancels an in-flight load on a fast tab switch → don't show a false error.
    private static func fail(_ error: Error) -> LoadState {
        if error is CancellationError { return .idle }
        if case let APIError.network(e) = error, (e as? URLError)?.code == .cancelled { return .idle }
        return .failed("We couldn’t load this yet. Check your connection and try again.")
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
