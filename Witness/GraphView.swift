import SwiftUI
import Combine

// MARK: - Memory Graph — native force-directed relationship map (no external package).
// GET /api/v1/graph -> { nodes, edges, stats }. Sample graph here.
struct GraphView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager
    @StateObject private var layout = GraphLayout(nodes: [], edges: [])
    @StateObject private var vm = GraphViewModel()
    @State private var selectedBucket: RelBucket? = nil          // nil = All
    @State private var selected: GNode?

    // Stage 3 — view transform (virtual → screen), zoom/pan, node-drag/hit-test.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var draggingNodeID: String?
    @State private var fitScale: CGFloat = 1
    @State private var contentCenter: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero

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
            Button { fitToView(canvasSize) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(WV.teal).frame(width: 44, height: 44)
            }.witnessPress().witnessHint("Reset zoom and fit the graph to the screen.")
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

    // MARK: - Render (single immediate-mode Canvas; positions live in plain storage, `tick` drives redraw)
    private var liveScale: CGFloat { fitScale * zoom * pinch }
    private func screen(_ v: CGPoint, _ geo: CGSize) -> CGPoint {
        CGPoint(x: geo.width/2 + (v.x - contentCenter.x)*liveScale + pan.width,
                y: geo.height/2 + (v.y - contentCenter.y)*liveScale + pan.height)
    }
    private func virtual(_ p: CGPoint, _ geo: CGSize) -> CGPoint {
        CGPoint(x: contentCenter.x + (p.x - geo.width/2 - pan.width)/liveScale,
                y: contentCenter.y + (p.y - geo.height/2 - pan.height)/liveScale)
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { ctx, _ in
                _ = layout.tick                                   // dependency → redraw while running
                drawEdges(ctx, geo.size)
                for nd in layout.nodes where isVisible(nd) { drawNode(ctx, nd, geo.size) }
            } symbols: {
                Image(systemName: "star.fill").foregroundStyle(.white).tag("star")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(nodeOrPanDrag(geo.size))
            .simultaneousGesture(MagnificationGesture().updating($pinch) { v, s, _ in s = v }
                .onEnded { v in zoom = min(max(zoom * v, 0.3), 4) })
            .simultaneousGesture(SpatialTapGesture().onEnded { ev in
                if let id = nearestVisibleNode(to: ev.location, geo: geo.size) { selected = layout.node(id) }
            })
            .onAppear { canvasSize = geo.size; fitToView(geo.size) }
            .onChange(of: geo.size) { _, s in canvasSize = s; fitToView(s) }
            .onChange(of: layout.settled) { _, done in if done { fitToView(geo.size) } }
            .onChange(of: selectedBucket) { _, _ in fitToView(geo.size); layout.wake() }
            .onChange(of: layout.mode) { _, _ in fitToView(geo.size) }
            .onDisappear { layout.stop() }
        }
        .background(Color.white.opacity(0.4))
    }

    private func drawEdges(_ ctx: GraphicsContext, _ geo: CGSize) {
        for e in visibleEdges {
            guard let a = layout.pos(of: e.source), let b = layout.pos(of: e.target) else { continue }
            var path = Path(); path.move(to: screen(a, geo)); path.addLine(to: screen(b, geo))
            ctx.stroke(path, with: .color(RelBucket.bucket(for: e.relType).color.opacity(0.4)),
                       lineWidth: max(1, CGFloat(e.strength) * 2.2))
        }
    }
    private func drawNode(_ ctx: GraphicsContext, _ nd: GNode, _ geo: CGSize) {
        let p = screen(nd.pos, geo)
        let r = nd.radius * liveScale
        let col: Color = nd.isNarrator ? WV.teal : RelBucket.bucket(for: nd.primaryRel).color
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r)), with: .color(col))
        if nd.isAnchor {
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x-r-3, y: p.y-r-3, width: 2*r+6, height: 2*r+6)), with: .color(WV.gold), lineWidth: 2)
        }
        if nd.id == selected?.id {
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x-r-6, y: p.y-r-6, width: 2*r+12, height: 2*r+12)), with: .color(WV.teal), lineWidth: 2)
        }
        if nd.isNarrator, let star = ctx.resolveSymbol(id: "star") { ctx.draw(star, at: p) }
        let show = nd.isNarrator || nd.id == selected?.id || r >= 15
        if show {
            let op: Double = (nd.isNarrator || nd.id == selected?.id) ? 1.0 : min(1.0, max(0.25, (Double(r) - 10) / 14))
            var txt = ctx.resolve(Text(nd.label).font(.system(size: 10, weight: nd.isNarrator ? .semibold : .regular)))
            txt.shading = .color(WT.ink.opacity(0.85 * op))
            ctx.draw(txt, at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
        }
    }

    private func nodeOrPanDrag(_ geo: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if draggingNodeID == nil && panStart == nil {
                    if let id = nearestVisibleNode(to: v.startLocation, geo: geo) { draggingNodeID = id }
                    else { panStart = pan }
                }
                if let id = draggingNodeID { layout.drag(id, toVirtual: virtual(v.location, geo)) }
                else if let base = panStart { pan = CGSize(width: base.width + v.translation.width, height: base.height + v.translation.height) }
            }
            .onEnded { _ in
                if let id = draggingNodeID { layout.endDrag(id) }
                draggingNodeID = nil; panStart = nil
            }
    }

    private func nearestVisibleNode(to p: CGPoint, geo: CGSize) -> String? {
        var best: (String, CGFloat)?
        for nd in layout.nodes where isVisible(nd) {
            let sp = screen(nd.pos, geo); let d = hypot(sp.x - p.x, sp.y - p.y)
            let hit = max(22, nd.radius * liveScale + 10)
            if d <= hit, best == nil || d < best!.1 { best = (nd.id, d) }
        }
        return best?.0
    }

    private func fitToView(_ geo: CGSize) {
        guard geo != .zero else { return }
        let pts = layout.nodes.filter { isVisible($0) }.map { $0.pos }
        guard let first = pts.first else { return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let bw = max(1, maxX - minX), bh = max(1, maxY - minY), margin: CGFloat = 90
        contentCenter = CGPoint(x: (minX + maxX)/2, y: (minY + maxY)/2)
        fitScale = min(max(min((geo.width - margin)/bw, (geo.height - margin)/bh), 0.15), 2.2)
        zoom = 1; pan = .zero
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text("Tap anyone to explore their connections").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    bucketChip(nil)                                   // All
                    ForEach(RelBucket.selectable, id: \.self) { bucketChip($0) }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 10).background(WV.parchment)
    }
    @ViewBuilder private func bucketChip(_ b: RelBucket?) -> some View {
        let on = (selectedBucket == b)
        let tint = b?.color ?? WV.teal
        HStack(spacing: 6) {
            if let b { Circle().fill(b.color).frame(width: 10, height: 10) }
            Text(b?.label ?? "All").font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? WT.ink : WT.ink.opacity(0.45))
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(on ? tint.opacity(0.12) : Color.white, in: Capsule())
        .overlay(Capsule().stroke(on ? tint.opacity(0.5) : WT.ink.opacity(0.1), lineWidth: 1))
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selectedBucket = (selectedBucket == b) ? nil : b } }
    }

    // MARK: helpers
    private var matchingIDs: Set<String> {
        guard let b = selectedBucket else { return Set(layout.nodes.map { $0.id }) }       // All
        var s = Set<String>()
        for n in layout.nodes where n.isNarrator || RelBucket.bucket(for: n.primaryRel) == b { s.insert(n.id) }
        return s
    }
    private var visibleEdges: [GEdge] {
        let ids = matchingIDs
        return layout.edges.filter { e in
            guard ids.contains(e.source), ids.contains(e.target) else { return false }
            if layout.mode == .ego { guard let nid = layout.narratorID else { return false }; return e.source == nid || e.target == nid }
            return true
        }
    }
    private func isVisible(_ n: GNode) -> Bool {
        if n.isNarrator { return true }
        guard matchingIDs.contains(n.id) else { return false }
        if layout.mode == .web { return true }
        return visibleEdges.contains { $0.source == n.id || $0.target == n.id }            // ego: connected to narrator
    }
}

// MARK: - Modes
enum GraphMode: CaseIterable { case ego, web
    var label: String { self == .ego ? "My Circle" : "Web" }
}

// MARK: - Relationship buckets (client-side classification; drives filter chips AND node/edge color).
// Mapped from the RAW relationship_type string — the server's precomputed colors are incomplete and unused.
enum RelBucket: String, CaseIterable {
    case romantic, family, professional, friends, other

    var label: String {
        switch self {
        case .romantic: return "Romantic"; case .family: return "Family"; case .professional: return "Professional"
        case .friends: return "Friends"; case .other: return "Other"
        }
    }
    var color: Color {
        switch self {
        case .romantic:     return Color(hex: 0xA32D2D)
        case .family:       return Color(hex: 0x534AB7)
        case .professional: return Color(hex: 0x5F5E5A)
        case .friends:      return Color(hex: 0x0F6E56)
        case .other:        return Color(hex: 0x854F0B)
        }
    }
    static let selectable: [RelBucket] = [.romantic, .family, .professional, .friends, .other]

    private static let values: [RelBucket: Set<String>] = [
        .romantic: ["spouse","romantic","partner","ex_spouse","ex_partner"],
        .family: ["parent_child","child_of","siblings","half_siblings","step_parent","step_child",
                  "grandparent_grandchild","great_grandparent","aunt_uncle_niece_nephew","great_aunt_uncle",
                  "cousins","in_law_parent","in_law_sibling","in_law_child","partners_parent","partners_sibling",
                  "family","twin","adopted_parent","adopted_child","foster_parent","foster_child","godparent","godchild"],
        .professional: ["professional","colleague","boss","subordinate","mentor","mentee","client","classmate"],
        .friends: ["friend","best_friend","close_friend","acquaintance","neighbor","roommate"],
        // .other = participated_in, pet_owner, + anything unrecognized (fallback)
    ]
    static func bucket(for relType: String) -> RelBucket {
        let key = relType.lowercased()
        for b in [RelBucket.romantic, .family, .professional, .friends] where values[b]?.contains(key) == true { return b }
        return .other
    }
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

// MARK: - Force-directed layout engine (cooling → settles & stops; virtual space; plain-storage positions)
final class GraphLayout: ObservableObject {
    // Positions/edges in PLAIN storage (no per-frame array @Published). A tiny `tick` drives one Canvas.
    private(set) var nodes: [GNode] = []
    private(set) var edges: [GEdge] = []
    private(set) var narratorID: String?
    private var index: [String: Int] = [:]
    var mode: GraphMode = .ego { didSet { if oldValue != mode { restart() } } }

    @Published private(set) var tick: Int = 0        // bumped each simulated frame; stops when settled
    @Published private(set) var settled: Bool = false

    private(set) var virtualSize: CGSize = .zero
    private var alpha: Double = 1
    private let alphaDecay = 0.98, alphaMin = 0.02
    private var timer: AnyCancellable?

    init(nodes: [GNode], edges: [GEdge]) {
        if !nodes.isEmpty { setGraph(nodes: nodes, edges: edges) }
    }

    // MARK: data
    func setGraph(nodes: [GNode], edges: [GEdge]) {
        self.nodes = nodes; self.edges = edges
        self.narratorID = nodes.first { $0.isNarrator }?.id
        self.index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        seed(); restart()
    }
    func node(_ id: String) -> GNode? { index[id].map { nodes[$0] } }
    func pos(of id: String) -> CGPoint? { index[id].map { nodes[$0].pos } }
    func setMode(_ m: GraphMode) { mode = m }   // didSet restarts

    // MARK: seeding — bucket sectors + outward spiral (no single ring)
    private func seed() {
        let n = nodes.count; guard n > 0 else { return }
        let side = max(1000, CGFloat(Double(n).squareRoot() * 260))
        virtualSize = CGSize(width: side, height: side)
        let c = CGPoint(x: side/2, y: side/2)
        let buckets = RelBucket.selectable
        var perCount: [RelBucket: Int] = [:], perIdx: [RelBucket: Int] = [:]
        for nd in nodes where !nd.isNarrator { perCount[RelBucket.bucket(for: nd.primaryRel), default: 0] += 1 }
        for i in nodes.indices {
            nodes[i].vel = .zero; nodes[i].pinned = false
            if nodes[i].isNarrator { nodes[i].pos = c; continue }
            let b = RelBucket.bucket(for: nodes[i].primaryRel)
            let sector = buckets.firstIndex(of: b) ?? 0
            let k = perIdx[b, default: 0]; perIdx[b] = k + 1
            let count = max(1, perCount[b] ?? 1)
            let span = 2 * Double.pi / Double(buckets.count)
            let ang = Double(sector) * span + (Double(k) + 0.5) / Double(count) * span
            let radius = 200.0 + Double(k) * 52.0
            nodes[i].pos = CGPoint(x: c.x + CGFloat(cos(ang) * radius), y: c.y + CGFloat(sin(ang) * radius))
        }
    }

    // MARK: sim lifecycle
    private func restart() { alpha = 1; settled = false; start() }
    func start() { if timer == nil { timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.step() } } }
    func stop() { timer?.cancel(); timer = nil }
    func wake() { if settled { alpha = max(alpha, 0.3) }; settled = false; start() }
    func reseed() { seed(); restart() }

    func drag(_ id: String, toVirtual p: CGPoint) {
        guard let i = index[id] else { return }
        nodes[i].pos = p; nodes[i].vel = .zero; nodes[i].pinned = true
        wake(); tick &+= 1
    }
    func endDrag(_ id: String) { wake() }   // stays pinned where dropped

    // MARK: one cooled step (+ collision separation)
    private func step() {
        let n = nodes.count; guard n > 0, virtualSize != .zero else { return }
        let c = CGPoint(x: virtualSize.width/2, y: virtualSize.height/2)
        let kRep = 14000.0, kSpring = 0.035, rest = 160.0, pull = 0.018, damping = 0.85, labelPad = 18.0
        var fx = [Double](repeating: 0, count: n), fy = [Double](repeating: 0, count: n)

        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = Double(nodes[i].pos.x - nodes[j].pos.x), dy = Double(nodes[i].pos.y - nodes[j].pos.y)
                var d2 = dx*dx + dy*dy; if d2 < 1 { d2 = 1 }
                let d = d2.squareRoot(), f = kRep / d2, ux = dx/d, uy = dy/d
                fx[i] += f*ux; fy[i] += f*uy; fx[j] -= f*ux; fy[j] -= f*uy
            }
        }
        for e in edges {
            guard let a = index[e.source], let b = index[e.target] else { continue }
            let dx = Double(nodes[b].pos.x - nodes[a].pos.x), dy = Double(nodes[b].pos.y - nodes[a].pos.y)
            let d = max(1, (dx*dx+dy*dy).squareRoot()), f = kSpring * (d - rest), ux = dx/d, uy = dy/d
            fx[a] += f*ux; fy[a] += f*uy; fx[b] -= f*ux; fy[b] -= f*uy
        }
        var maxDisp = 0.0
        for i in 0..<n {
            if mode == .ego && nodes[i].isNarrator { nodes[i].pos = c; nodes[i].vel = .zero; continue }
            if nodes[i].pinned { continue }
            fx[i] += Double(c.x - nodes[i].pos.x) * pull
            fy[i] += Double(c.y - nodes[i].pos.y) * pull
            var vx = (Double(nodes[i].vel.dx) + fx[i]) * damping
            var vy = (Double(nodes[i].vel.dy) + fy[i]) * damping
            vx = min(max(vx, -60), 60); vy = min(max(vy, -60), 60)
            nodes[i].vel = CGVector(dx: vx, dy: vy)
            let ddx = vx * alpha, ddy = vy * alpha
            nodes[i].pos.x += CGFloat(ddx); nodes[i].pos.y += CGFloat(ddy)
            maxDisp = max(maxDisp, abs(ddx) + abs(ddy))
        }
        // collision: resolve overlaps to (r_i + r_j + labelPad)
        for _ in 0..<2 {
            for i in 0..<n {
                for j in (i+1)..<n {
                    let minGap = Double(nodes[i].radius + nodes[j].radius) + labelPad
                    let dx = Double(nodes[j].pos.x - nodes[i].pos.x), dy = Double(nodes[j].pos.y - nodes[i].pos.y)
                    var d = (dx*dx+dy*dy).squareRoot(); if d < 0.01 { d = 0.01 }
                    if d < minGap {
                        let push = (minGap - d) / 2, ux = dx/d, uy = dy/d
                        let iFixed = (mode == .ego && nodes[i].isNarrator) || nodes[i].pinned
                        let jFixed = (mode == .ego && nodes[j].isNarrator) || nodes[j].pinned
                        if !iFixed { nodes[i].pos.x -= CGFloat(ux*push); nodes[i].pos.y -= CGFloat(uy*push) }
                        if !jFixed { nodes[j].pos.x += CGFloat(ux*push); nodes[j].pos.y += CGFloat(uy*push) }
                    }
                }
            }
        }
        alpha *= alphaDecay; tick &+= 1
        if alpha < alphaMin || maxDisp < 0.08 { settled = true; stop() }
    }
}
