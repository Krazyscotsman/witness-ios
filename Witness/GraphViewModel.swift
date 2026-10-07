import SwiftUI
import Combine

// MARK: - Graph data (GET /api/v1/graph). Read-only. Maps the response into the existing GNode/GEdge layout
// models and feeds them into the hand-written force-directed engine via GraphLayout.setGraph(). Each node's
// primaryRel (which drives RelBucket color/filter) is derived: anchor_rel_type → the relationship_type of its edge to
// the narrator → its strongest incident edge → neutral. `narratorRel` is the SAME chain stopped before that third
// rung, for anything that SAYS the word rather than colouring with it. 404 → .unavailable (graceful). Fetch-once + refresh,
// 401→refresh→retry.
@MainActor
final class GraphViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, empty, unavailable, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var nodes: [GNode] = []
    @Published private(set) var edges: [GEdge] = []
    @Published private(set) var narratorId: String?
    @Published private(set) var anchors: [RelationshipRow] = []   // /timeline/relationships — source of rel labels
    private(set) var nodeByID: [String: GNode] = [:]

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
                try await APIClient.shared.get("/api/v1/graph", timeout: 30, decoder: Self.snake, as: GraphResponse.self)
            }
            // /timeline/relationships — best-effort; supplies the ego ring + relationship labels. A failure here
            // leaves anchors empty (focused/edge view still works; root ring is just sparse).
            anchors = (try? await withAuth(auth) {
                try await APIClient.shared.get("/timeline/relationships", timeout: 20, decoder: Self.snake, as: [RelationshipRow].self)
            }) ?? []
            map(r)
        } catch APIError.http(let status, _) where status == 404 {
            state = .unavailable
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load your graph. Check your connection and try again.")
        }
    }

    private func map(_ r: GraphResponse) {
        let rawNodes = r.nodes ?? []
        let rawEdges = r.edges ?? []
        let nid = r.narratorNodeId ?? rawNodes.first(where: { $0.isNarrator == true })?.id
        narratorId = nid

        let mappedEdges: [GEdge] = rawEdges.map {
            GEdge(source: $0.source, target: $0.target, relType: $0.relationshipType ?? "", strength: $0.strength ?? 0.5)
        }

        // Derive primaryRel (color): anchor_rel_type → edge-to-narrator type → strongest incident → neutral.
        var primary: [String: String] = [:]
        if let nid {
            for e in mappedEdges {
                if e.source == nid { primary[e.target] = e.relType }
                else if e.target == nid { primary[e.source] = e.relType }
            }
        }
        for n in rawNodes { if let a = n.anchorRelType, !a.isEmpty { primary[n.id] = a } }
        // ⛔ THE NARRATOR-RELATIVE WORD IS A SNAPSHOT TAKEN *BEFORE* THE THIRD RUNG (2026-10-07).
        // Everything in `primary` so far came either from the node's own anchor row or from an edge
        // with HIM at one end, so every value is genuinely a word about him. The rung below widens
        // it to ANY incident edge, which is sound for a colour and false as a caption — so the
        // honest set is copied out here, and only `primary` goes on to be widened.
        let narratorOnly = primary
        for n in rawNodes where primary[n.id] == nil {
            if let e = mappedEdges.first(where: { $0.source == n.id || $0.target == n.id }) { primary[n.id] = e.relType }
        }

        let mappedNodes: [GNode] = rawNodes.map { n in
            GNode(id: n.id,
                  label: n.label ?? "Unknown",   // nameComplete is a Bool flag, not a display string
                  primaryRel: (n.isNarrator == true) ? "self" : (primary[n.id] ?? ""),
                  isAnchor: n.isAnchor ?? false,
                  isNarrator: n.isNarrator ?? false,
                  memoryCount: n.memoryCount ?? 0,
                  aliases: n.aliases ?? [],
                  born: n.birthDate, died: n.deathDate,
                  // "self" for him, exactly as `primaryRel` does: his own card captioned "Self"
                  // before this change and the server sends him no subject_label (measured: ''),
                  // so without this the fix would quietly delete a caption that was never wrong.
                  narratorRel: (n.isNarrator == true) ? "self" : (narratorOnly[n.id] ?? ""),
                  subjectLabel: n.subjectLabel)
        }

        nodes = mappedNodes
        edges = mappedEdges
        nodeByID = Dictionary(mappedNodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Ego view can render from anchors alone, so "loaded" if we have any nodes or anchors.
        state = (mappedNodes.isEmpty && anchors.isEmpty) ? .empty : .loaded
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
