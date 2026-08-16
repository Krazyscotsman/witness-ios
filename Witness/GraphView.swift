import SwiftUI
import Combine

// MARK: - Memory Graph — native force-directed relationship map (no external package).
// GET /api/v1/graph -> { nodes, edges, stats }. Sample graph here.
struct GraphView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager
    @StateObject private var layout = GraphLayout(nodes: [], edges: [])
    @StateObject private var vm = GraphViewModel()
    @State private var enabled: Set<String> = ["family","romantic","friend","professional","pet"]
    @State private var selected: GNode?

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: centered { loadingBlock }
                case .empty:          centered { emptyBlock }
                case .unavailable:    centered { unavailableBlock }
                case .failed(let m):  centered { failedBlock(m) }
                case .loaded:
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 52)
                        header
                        canvas
                        controls
                    }
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { NodeDetailSheet(node: $0, auth: auth) }
        .onChange(of: enabled) { _, _ in layout.wake() }
        .task { await vm.load(auth: auth); applyIfLoaded() }
    }

    private func applyIfLoaded() { if vm.state == .loaded { layout.setGraph(nodes: vm.nodes, edges: vm.edges) } }
    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack { Spacer(); content(); Spacer() }.frame(maxWidth: .infinity).padding(.top, 52)
    }

    private var loadingBlock: some View {
        VStack(spacing: 12) {
            ProgressView().tint(WV.teal)
            Text("Mapping your connections…").font(.serif(18)).foregroundStyle(WT.ink.opacity(0.7))
        }
    }
    private var emptyBlock: some View {
        infoBlock(icon: "point.3.connected.trianglepath.dotted", title: "Not enough connections yet",
                  body: "As you record memories with the people in them, your relationship map will take shape here.")
    }
    private var unavailableBlock: some View {
        infoBlock(icon: "point.3.connected.trianglepath.dotted", title: "Graph unavailable",
                  body: "This view isn’t available right now. Please try again later.")
    }
    private func failedBlock(_ m: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(WV.danger.opacity(0.8))
            Text(m).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.7)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth); applyIfLoaded() } } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)); Text("Try again").font(.system(size: 15, weight: .medium)) }.foregroundStyle(WV.teal)
            }.witnessPress()
        }
    }
    private func infoBlock(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text(title).font(.serif(20)).foregroundStyle(WT.ink)
            Text(body).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 36)
        }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            Text("Memory Graph").font(.serif(18)).foregroundStyle(WT.ink)
            Spacer()
            Button { layout.reseed() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold)).foregroundStyle(WV.teal).frame(width: 44, height: 44)
            }.witnessPress()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var header: some View {
        HStack(spacing: 14) {
            stat("\(layout.nodes.count)", "Nodes")
            stat("\(visibleEdges.count)", "Bonds")
            stat("\(layout.nodes.filter { $0.isAnchor }.count)", "Anchors")
            Spacer()
            modeToggle
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
    private func stat(_ n: String, _ l: String) -> some View {
        VStack(spacing: 1) { Text(n).font(.serif(18)).foregroundStyle(WV.teal); Text(l).font(.system(size: 10)).foregroundStyle(WT.ink.opacity(0.5)) }
    }
    private var modeToggle: some View {
        HStack(spacing: 3) {
            ForEach(GraphMode.allCases, id: \.self) { m in
                let sel = layout.mode == m
                Text(m.label).font(.system(size: 12, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(sel ? WV.teal : Color.clear, in: Capsule())
                    .onTapGesture { withAnimation { layout.setMode(m) } }
            }
        }
        .padding(3).background(WT.ink.opacity(0.06), in: Capsule())
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, _ in
                    for e in visibleEdges {
                        guard let a = layout.node(e.source), let b = layout.node(e.target) else { continue }
                        var path = Path(); path.move(to: a.pos); path.addLine(to: b.pos)
                        ctx.stroke(path, with: .color(RelGroup.color(for: e.relType).opacity(0.45)), lineWidth: max(1, CGFloat(e.strength) * 2.5))
                    }
                }
                ForEach(layout.nodes) { node in
                    if isVisible(node) { nodeView(node, in: geo) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear { layout.configure(size: geo.size); layout.start() }
            .onDisappear { layout.stop() }
        }
        .background(Color.white.opacity(0.4))
    }

    private func nodeView(_ node: GNode, in geo: GeometryProxy) -> some View {
        let g = node.isNarrator ? WV.teal : RelGroup.color(for: node.primaryRel)
        let r = node.radius
        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(g)
                if node.isAnchor { Circle().stroke(WV.gold, lineWidth: 2.5).frame(width: r * 2 + 5, height: r * 2 + 5) }
                if node.isNarrator { Image(systemName: "star.fill").font(.system(size: r * 0.7)).foregroundStyle(.white) }
            }
            .frame(width: r * 2, height: r * 2)
            Text(node.label).font(.system(size: 10, weight: node.isNarrator ? .semibold : .regular)).foregroundStyle(WT.ink.opacity(0.8))
                .lineLimit(1).fixedSize()
        }
        .position(node.pos)
        .gesture(DragGesture()
            .onChanged { layout.drag(node.id, to: $0.location, in: geo.size) }
            .onEnded { _ in layout.endDrag(node.id) })
        .onTapGesture { selected = node }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text("Tap anyone to explore their connections").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RelGroup.all, id: \.key) { grp in
                        let on = enabled.contains(grp.key)
                        HStack(spacing: 6) {
                            Circle().fill(grp.color).frame(width: 10, height: 10)
                            Text(grp.label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? WT.ink : WT.ink.opacity(0.4))
                        }
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(on ? grp.color.opacity(0.1) : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? grp.color.opacity(0.3) : WT.ink.opacity(0.1), lineWidth: 1))
                        .onTapGesture { if on { enabled.remove(grp.key) } else { enabled.insert(grp.key) } }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 10).background(WV.parchment)
    }

    // MARK: helpers
    private var visibleEdges: [GEdge] {
        layout.edges.filter { e in
            guard enabled.contains(RelGroup.key(for: e.relType)) else { return false }
            if layout.mode == .ego { guard let nid = layout.narratorID else { return false }; return e.source == nid || e.target == nid }
            return true
        }
    }
    private func isVisible(_ n: GNode) -> Bool {
        if layout.mode == .web { return true }
        if n.isNarrator { return true }
        return visibleEdges.contains { $0.source == n.id || $0.target == n.id }
    }
}

// MARK: - Modes
enum GraphMode: CaseIterable { case ego, web
    var label: String { self == .ego ? "My Circle" : "Web" }
}

// MARK: - Relationship groups (verbatim colors/types)
struct RelGroup {
    let key: String; let label: String; let color: Color; let types: [String]
    static let all: [RelGroup] = [
        .init(key: "family", label: "Family", color: Color(hex: 0x534AB7),
              types: ["parent_child","grandparent_grandchild","siblings","step_parent","in_law_parent","in_law_sibling","partners_parent","partners_sibling","aunt_uncle_niece_nephew","half_siblings","cousins"]),
        .init(key: "romantic", label: "Romantic", color: Color(hex: 0xA32D2D), types: ["spouse","romantic"]),
        .init(key: "friend", label: "Friends", color: Color(hex: 0x0F6E56), types: ["friend","best_friend","close_friend"]),
        .init(key: "professional", label: "Professional", color: Color(hex: 0x5F5E5A), types: ["colleague","mentor","classmate","acquaintance","neighbor","professional"]),
        .init(key: "pet", label: "Pets", color: Color(hex: 0x854F0B), types: ["pet_owner"]),
    ]
    static func key(for relType: String) -> String { all.first { $0.types.contains(relType) }?.key ?? "professional" }
    static func color(for relType: String) -> Color { all.first { $0.types.contains(relType) }?.color ?? Color(hex: 0x5F5E5A) }
}

// MARK: - Node / Edge models
struct GNode: Identifiable, Equatable {
    let id: String
    let label: String
    let primaryRel: String
    let isAnchor: Bool
    let isNarrator: Bool
    let memoryCount: Int
    let aliases: [String]
    let born: String?
    let died: String?
    var pos: CGPoint = .zero
    var vel: CGVector = .zero
    var pinned: Bool = false

    var radius: CGFloat { isNarrator ? 26 : max(14, min(24, 12 + CGFloat(memoryCount))) }
    static func == (l: GNode, r: GNode) -> Bool { l.id == r.id && l.pos == r.pos }

    static let narratorID = "you"
    static let samples: [GNode] = [
        .init(id: "you", label: "You", primaryRel: "self", isAnchor: false, isNarrator: true, memoryCount: 0, aliases: [], born: nil, died: nil),
        .init(id: "mother", label: "Mother", primaryRel: "parent_child", isAnchor: true, isNarrator: false, memoryCount: 12, aliases: [], born: "1948", died: nil),
        .init(id: "father", label: "Father", primaryRel: "parent_child", isAnchor: true, isNarrator: false, memoryCount: 10, aliases: [], born: "1945", died: "2019"),
        .init(id: "sister", label: "Sister", primaryRel: "siblings", isAnchor: false, isNarrator: false, memoryCount: 7, aliases: [], born: nil, died: nil),
        .init(id: "spouse", label: "Spouse", primaryRel: "spouse", isAnchor: true, isNarrator: false, memoryCount: 9, aliases: ["Partner"], born: nil, died: nil),
        .init(id: "bestfriend", label: "Best friend", primaryRel: "best_friend", isAnchor: true, isNarrator: false, memoryCount: 8, aliases: [], born: nil, died: nil),
        .init(id: "friend2", label: "Childhood friend", primaryRel: "friend", isAnchor: false, isNarrator: false, memoryCount: 4, aliases: [], born: nil, died: nil),
        .init(id: "mentor", label: "A mentor", primaryRel: "mentor", isAnchor: false, isNarrator: false, memoryCount: 5, aliases: [], born: nil, died: nil),
        .init(id: "colleague", label: "A colleague", primaryRel: "colleague", isAnchor: false, isNarrator: false, memoryCount: 3, aliases: [], born: nil, died: nil),
        .init(id: "neighbor", label: "A neighbor", primaryRel: "neighbor", isAnchor: false, isNarrator: false, memoryCount: 2, aliases: [], born: nil, died: nil),
        .init(id: "grandmother", label: "Grandmother", primaryRel: "grandparent_grandchild", isAnchor: false, isNarrator: false, memoryCount: 6, aliases: ["Nana"], born: "1920", died: "2005"),
        .init(id: "pet", label: "A pet", primaryRel: "pet_owner", isAnchor: false, isNarrator: false, memoryCount: 3, aliases: [], born: nil, died: nil),
    ]
}

struct GEdge: Identifiable {
    let id = UUID()
    let source: String
    let target: String
    let relType: String
    let strength: Double
    static let samples: [GEdge] = [
        .init(source: "you", target: "mother", relType: "parent_child", strength: 1.0),
        .init(source: "you", target: "father", relType: "parent_child", strength: 0.9),
        .init(source: "you", target: "sister", relType: "siblings", strength: 0.7),
        .init(source: "you", target: "spouse", relType: "spouse", strength: 1.0),
        .init(source: "you", target: "bestfriend", relType: "best_friend", strength: 0.8),
        .init(source: "you", target: "friend2", relType: "friend", strength: 0.5),
        .init(source: "you", target: "mentor", relType: "mentor", strength: 0.6),
        .init(source: "you", target: "colleague", relType: "colleague", strength: 0.4),
        .init(source: "you", target: "neighbor", relType: "neighbor", strength: 0.3),
        .init(source: "you", target: "grandmother", relType: "grandparent_grandchild", strength: 0.7),
        .init(source: "you", target: "pet", relType: "pet_owner", strength: 0.6),
        .init(source: "mother", target: "father", relType: "spouse", strength: 0.9),
        .init(source: "mother", target: "sister", relType: "parent_child", strength: 0.6),
        .init(source: "father", target: "grandmother", relType: "parent_child", strength: 0.6),
    ]
}

// MARK: - Force-directed layout engine
final class GraphLayout: ObservableObject {
    @Published var nodes: [GNode]
    private(set) var edges: [GEdge]
    private(set) var narratorID: String?
    var mode: GraphMode = .ego
    private(set) var size: CGSize = .zero
    private var timer: AnyCancellable?
    private var seeded = false
    private var calm = 0

    init(nodes: [GNode], edges: [GEdge]) { self.nodes = nodes; self.edges = edges }

    /// Swap in a freshly loaded graph and re-seed the layout — reuses the existing physics engine (no rebuild).
    func setGraph(nodes: [GNode], edges: [GEdge]) {
        self.nodes = nodes
        self.edges = edges
        self.narratorID = nodes.first { $0.isNarrator }?.id
        self.seeded = false
        self.calm = 0
        if size != .zero { configure(size: size); wake() }
    }

    func node(_ id: String) -> GNode? { nodes.first { $0.id == id } }
    private func idx(_ id: String) -> Int? { nodes.firstIndex { $0.id == id } }

    func configure(size: CGSize) {
        self.size = size
        guard !seeded else { return }
        seeded = true
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for i in nodes.indices {
            if nodes[i].isNarrator { nodes[i].pos = c }
            else {
                let a = Double(i) / Double(nodes.count) * 2 * .pi
                nodes[i].pos = CGPoint(x: c.x + cos(a) * 110 + .random(in: -20...20), y: c.y + sin(a) * 110 + .random(in: -20...20))
            }
        }
    }

    func start() { timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.step() } }
    func stop() { timer?.cancel(); timer = nil }
    func wake() { calm = 0; if timer == nil { start() } }
    func reseed() { seeded = false; for i in nodes.indices { nodes[i].pinned = false }; configure(size: size); wake() }
    func setMode(_ m: GraphMode) { mode = m; wake() }

    func drag(_ id: String, to point: CGPoint, in size: CGSize) {
        guard let i = idx(id) else { return }
        nodes[i].pos = point; nodes[i].vel = .zero; nodes[i].pinned = true; wake()
    }
    func endDrag(_ id: String) { wake() }

    private func step() {
        guard size != .zero else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let kRep: CGFloat = 8500, kSpring: CGFloat = 0.025, rest: CGFloat = 86, damping: CGFloat = 0.8, pull: CGFloat = 0.006
        var fx = [CGFloat](repeating: 0, count: nodes.count)
        var fy = [CGFloat](repeating: 0, count: nodes.count)

        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                let dx = nodes[i].pos.x - nodes[j].pos.x, dy = nodes[i].pos.y - nodes[j].pos.y
                var d2 = dx*dx + dy*dy; if d2 < 100 { d2 = 100 }
                let d = sqrt(d2), f = kRep / d2
                fx[i] += f*dx/d; fy[i] += f*dy/d; fx[j] -= f*dx/d; fy[j] -= f*dy/d
            }
        }
        for e in edges {
            guard let a = idx(e.source), let b = idx(e.target) else { continue }
            let dx = nodes[b].pos.x - nodes[a].pos.x, dy = nodes[b].pos.y - nodes[a].pos.y
            let d = max(1, sqrt(dx*dx + dy*dy)), f = kSpring * (d - rest)
            fx[a] += f*dx/d; fy[a] += f*dy/d; fx[b] -= f*dx/d; fy[b] -= f*dy/d
        }

        var maxSpeed: CGFloat = 0
        for i in 0..<nodes.count {
            if mode == .ego && nodes[i].isNarrator { nodes[i].pos = center; nodes[i].vel = .zero; continue }
            if nodes[i].pinned { continue }
            fx[i] += (center.x - nodes[i].pos.x) * pull
            fy[i] += (center.y - nodes[i].pos.y) * pull
            var vx = (nodes[i].vel.dx + fx[i]) * damping
            var vy = (nodes[i].vel.dy + fy[i]) * damping
            vx = min(max(vx, -12), 12); vy = min(max(vy, -12), 12)
            nodes[i].vel = CGVector(dx: vx, dy: vy)
            nodes[i].pos.x = min(max(nodes[i].pos.x + vx, 30), size.width - 30)
            nodes[i].pos.y = min(max(nodes[i].pos.y + vy, 30), size.height - 70)
            maxSpeed = max(maxSpeed, abs(vx) + abs(vy))
        }
        if maxSpeed < 0.4 { calm += 1; if calm > 40 { stop() } } else { calm = 0 }
    }
}
