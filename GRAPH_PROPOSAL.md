# Witness — Graph → GET /api/v1/graph (into the existing native force-directed engine) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Read-only.

## Read-first
- Engine is a HAND-WRITTEN force-directed layout (`GraphLayout` in GraphView.swift), NOT Grape. 60fps step()
  (repulsion/spring/center-pull/damping), drag-pin, ego/web modes. Keep it.
- Models: `GNode {id,label,primaryRel(color),isAnchor,isNarrator,memoryCount,aliases,born,died,+pos/vel/pinned}`
  (radius from memoryCount); `GEdge {source,target,relType,strength}`. Data = GNode.samples/GEdge.samples.
- Render: Canvas edges (RelGroup.color(for: relType), width from strength); node circles by RelGroup (narrator
  teal+star, anchor gold ring), label below. RelGroup = the app palette (5 groups).
- Node tap → in-place bottom sheet (nodeDetail). NO entity-detail-by-id screen exists → keep the info sheet.
- Narrator id hardcoded `GNode.narratorID = "you"` (only visibleEdges ego filter) → generalize to real id.

## Decisions (recommended defaults; change any)
1. App-palette styling (RelGroup + WV/WT); ignore server precomputed color/size/width.
2. Node tap → existing info sheet (no entity-detail nav reachable).
3. No canvas edge labels (Canvas has no label support; type shown via legend + detail). edge.label decoded, unused.
4. Relabel header stat "People" → "Nodes".
5. Leave GNode.samples/GEdge.samples in place (now unused) — no deletion without asking.

---

## APIModels.swift — DTOs (append)
```swift
// MARK: - Graph (GET /api/v1/graph) — relationship/entity map. .convertFromSnakeCase. Precomputed styling
// (color/border_color/size/line_style/width) is decoded but UNUSED — the app palette (RelGroup + WV/WT) drives
// rendering. `nonisolated`: decoded off-main.
nonisolated struct GraphResponse: Decodable {
    let narratorId: String?
    let narratorNodeId: String?
    let nodes: [GraphNode]?
    let edges: [GraphEdge]?
    let stats: GraphStats?
}
nonisolated struct GraphNode: Decodable {
    let id: String
    let label: String?
    let type: String?
    let isAnchor: Bool?
    let isNarrator: Bool?
    let memoryCount: Int?
    let aliases: [String]?
    let nameComplete: String?
    let anchorRelType: String?
    let birthDate: String?
    let deathDate: String?
    let color: String?; let borderColor: String?; let size: Double?     // precomputed; unused
}
nonisolated struct GraphEdge: Decodable {
    let id: String?
    let source: String
    let target: String
    let relationshipType: String?
    let strength: Double?
    let memoryCount: Int?
    let lineStyle: String?; let color: String?; let width: Double?       // precomputed; unused
    let label: String?
}
nonisolated struct GraphStats: Decodable {
    let totalNodes: Int?; let totalEdges: Int?; let anchorCount: Int?
}
```

## New file: GraphViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class GraphViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, empty, unavailable, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var nodes: [GNode] = []
    @Published private(set) var edges: [GEdge] = []
    @Published private(set) var narratorId: String?

    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(auth: AuthManager) async { if state == .loading || state == .loaded { return }; await fetch(auth: auth) }
    func refresh(auth: AuthManager) async { if state == .loading { return }; await fetch(auth: auth) }

    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/graph", timeout: 30, decoder: Self.snake, as: GraphResponse.self)
            }
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
        // Derive each node's primaryRel (color): anchor_rel_type → edge-to-narrator type → strongest incident → neutral.
        var primary: [String: String] = [:]
        if let nid {
            for e in mappedEdges {
                if e.source == nid { primary[e.target] = e.relType }
                else if e.target == nid { primary[e.source] = e.relType }
            }
        }
        for n in rawNodes { if let a = n.anchorRelType, !a.isEmpty { primary[n.id] = a } }
        for n in rawNodes where primary[n.id] == nil {
            if let e = mappedEdges.first(where: { $0.source == n.id || $0.target == n.id }) { primary[n.id] = e.relType }
        }

        let mappedNodes: [GNode] = rawNodes.map { n in
            GNode(id: n.id,
                  label: n.label ?? n.nameComplete ?? "Unknown",
                  primaryRel: (n.isNarrator == true) ? "self" : (primary[n.id] ?? ""),
                  isAnchor: n.isAnchor ?? false,
                  isNarrator: n.isNarrator ?? false,
                  memoryCount: n.memoryCount ?? 0,
                  aliases: n.aliases ?? [],
                  born: n.birthDate, died: n.deathDate)
        }
        nodes = mappedNodes; edges = mappedEdges
        state = (mappedNodes.count <= 1 || mappedEdges.isEmpty) ? .empty : .loaded
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
```

## GraphLayout — minimal extension (no physics rebuild)
```diff
 final class GraphLayout: ObservableObject {
     @Published var nodes: [GNode]
-    let edges: [GEdge]
+    private(set) var edges: [GEdge]
+    private(set) var narratorID: String?
     var mode: GraphMode = .ego
     ...
     init(nodes: [GNode], edges: [GEdge]) { self.nodes = nodes; self.edges = edges }
+
+    /// Swap in a freshly loaded graph and re-seed the layout (keeps the existing physics engine).
+    func setGraph(nodes: [GNode], edges: [GEdge]) {
+        self.nodes = nodes
+        self.edges = edges
+        self.narratorID = nodes.first { $0.isNarrator }?.id
+        self.seeded = false
+        self.calm = 0
+        if size != .zero { configure(size: size); wake() }
+    }
```

## GraphView.swift — targeted edits
```diff
 struct GraphView: View {
     @Environment(\.dismiss) private var dismiss
-    @StateObject private var layout = GraphLayout(nodes: GNode.samples, edges: GEdge.samples)
+    @ObservedObject var auth: AuthManager
+    @StateObject private var layout = GraphLayout(nodes: [], edges: [])
+    @StateObject private var vm = GraphViewModel()
     @State private var enabled: Set<String> = ["family","romantic","friend","professional","pet"]
     @State private var selected: GNode?

     var body: some View {
         ZStack(alignment: .top) {
             ParchmentBackground()
-            VStack(spacing: 0) {
-                Color.clear.frame(height: 52)
-                header
-                canvas
-                controls
-            }
+            Group {
+                switch vm.state {
+                case .idle, .loading: centered { loadingBlock }
+                case .empty:          centered { emptyBlock }
+                case .unavailable:    centered { unavailableBlock }
+                case .failed(let m):  centered { failedBlock(m) }
+                case .loaded:
+                    VStack(spacing: 0) { Color.clear.frame(height: 52); header; canvas; controls }
+                }
+            }
             navBar
         }
         .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
         .sheet(item: $selected) { nodeDetail($0) }
         .onChange(of: enabled) { _, _ in layout.wake() }
+        .task { await vm.load(auth: auth); applyIfLoaded() }
     }
+
+    private func applyIfLoaded() { if vm.state == .loaded { layout.setGraph(nodes: vm.nodes, edges: vm.edges) } }
+    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
+        VStack { Spacer(); content(); Spacer() }.frame(maxWidth: .infinity).padding(.top, 52)
+    }
```
Header stat relabel + real anchor count stay computed from `layout.nodes`:
```diff
-            stat("\(layout.nodes.count)", "People")
+            stat("\(layout.nodes.count)", "Nodes")
```
`visibleEdges` — generalize the narrator id:
```diff
     private var visibleEdges: [GEdge] {
         layout.edges.filter { e in
             guard enabled.contains(RelGroup.key(for: e.relType)) else { return false }
-            if layout.mode == .ego { return e.source == GNode.narratorID || e.target == GNode.narratorID }
+            if layout.mode == .ego { guard let nid = layout.narratorID else { return false }; return e.source == nid || e.target == nid }
             return true
         }
     }
```
New state blocks (added to the struct; match app design — spinner / icons / retry):
```swift
private var loadingBlock: some View { VStack(spacing: 12) { ProgressView().tint(WV.teal); Text("Mapping your connections…").font(.serif(18)).foregroundStyle(WT.ink.opacity(0.7)) } }
private var emptyBlock: some View { infoBlock(icon: "point.3.connected.trianglepath.dotted", title: "Not enough connections yet", body: "As you record memories with the people in them, your relationship map will take shape here.") }
private var unavailableBlock: some View { infoBlock(icon: "point.3.connected.trianglepath.dotted", title: "Graph unavailable", body: "This view isn’t available right now. Please try again later.") }
private func failedBlock(_ m: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(WV.danger.opacity(0.8))
        Text(m).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.7)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
        Button { Task { await vm.refresh(auth: auth); applyIfLoaded() } } label: {
            HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)); Text("Try again").font(.system(size: 15, weight: .medium)) }.foregroundStyle(WV.teal)
        }.witnessPress()
    }
}
private func infoBlock(icon: String, title: String, body: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
        Text(title).font(.serif(20)).foregroundStyle(WT.ink)
        Text(body).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 36)
    }
}
```
(Everything else — canvas, nodeView, controls, RelGroup, physics — unchanged. `GNode.samples`/`GEdge.samples`
kept but unused.)

## InsightsView.swift — pass auth
```diff
-                case "graph":    GraphView()
+                case "graph":    GraphView(auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live graph round-trip (real nodes/edges into the physics
engine, ego/web filtering by the real narrator id, 404→unavailable, empty vs loaded, node-tap sheet) is a
device/backend check. App-palette styling; server precomputed styling + canvas edge labels intentionally
unused. No git.
