# Witness — Memory Graph Stage 3: layout polish (settle, no overlap) + zoom/pan — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Client-side only. Preserves Stage 1 + Stage 2.

## Read-first (current engine)
- `@Published var nodes:[GNode]` mutated EVERY frame; render = a `Canvas` (edges) + `ForEach(layout.nodes){nodeView}`
  → 95 SwiftUI node views re-diffed at 60fps (the jank).
- Seed: narrator center; all others on ONE ring r=110 + jitter (overlap at t=0).
- Forces: O(n²) repulsion (kRep 8500), edge springs (rest 86), center-pull 0.006, damping 0.8, vel ±12;
  positions HARD-CLAMPED to the phone screen.
- Settle: maxSpeed<0.4 ×40 → stop(); at 95 nodes rarely reached → runs forever.
- No zoom/pan; screen-space coords.

## Decisions (recommended; change any)
1. Replace ForEach node views with ONE immediate-mode Canvas + non-published positions (+ tiny `tick` publish
   that stops on settle). Only way to kill 60fps 95-view diffing.
2. Filter change = re-fit-to-view on the visible subset + gentle wake() (stable positions, not re-solved).
3. Label visibility = on-screen-radius threshold + size fade; always selected + narrator. No collision solver.

---

## GraphView.swift — NEW GraphLayout (replaces the old engine wholesale)
```swift
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

    init(nodes: [GNode], edges: [GEdge]) { setGraph(nodes: nodes, edges: edges) }

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
        var perCount: [RelBucket:Int] = [:], perIdx: [RelBucket:Int] = [:]
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
```
(`configure(size:)` is removed — the layout no longer depends on screen size. `GNode`/`GEdge`/samples unchanged.)

## GraphView.swift — new render layer (single Canvas + gestures + fit/zoom/pan)
```swift
// view state
@State private var zoom: CGFloat = 1
@GestureState private var pinch: CGFloat = 1
@State private var pan: CGSize = .zero
@State private var panStart: CGSize?
@State private var draggingNodeID: String?
@State private var fitScale: CGFloat = 1
@State private var contentCenter: CGPoint = .zero     // virtual centroid the view is fit around
@State private var canvasSize: CGSize = .zero

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
            let edges = visibleEdges
            for e in edges {
                guard let a = layout.pos(of: e.source), let b = layout.pos(of: e.target) else { continue }
                var path = Path(); path.move(to: screen(a, geo.size)); path.addLine(to: screen(b, geo.size))
                ctx.stroke(path, with: .color(RelBucket.bucket(for: e.relType).color.opacity(0.4)),
                           lineWidth: max(1, CGFloat(e.strength) * 2.2))
            }
            for nd in layout.nodes where isVisible(nd) {
                let p = screen(nd.pos, geo.size)
                let r = nd.radius * liveScale
                let col = nd.isNarrator ? WV.teal : RelBucket.bucket(for: nd.primaryRel).color
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r)), with: .color(col))
                if nd.isAnchor {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x-r-3, y: p.y-r-3, width: 2*r+6, height: 2*r+6)), with: .color(WV.gold), lineWidth: 2)
                }
                if nd.id == selected?.id {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x-r-6, y: p.y-r-6, width: 2*r+12, height: 2*r+12)), with: .color(WV.teal), lineWidth: 2)
                }
                if nd.isNarrator, let star = ctx.resolveSymbol(id: "star") { ctx.draw(star, at: p) }
                // label anti-overlap: only when big enough on-screen, or selected/narrator; fade by size
                let show = nd.isNarrator || nd.id == selected?.id || r >= 15
                if show {
                    let op = nd.isNarrator || nd.id == selected?.id ? 1.0 : min(1.0, max(0.25, (r - 10) / 14))
                    var txt = ctx.resolveText(Text(nd.label).font(.system(size: 10, weight: nd.isNarrator ? .semibold : .regular)))
                    txt.shading = .color(WT.ink.opacity(0.85 * op))
                    ctx.draw(txt, at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
                }
            }
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
        .onEnded { _ in if let id = draggingNodeID { layout.endDrag(id) }; draggingNodeID = nil; panStart = nil }
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
    for p in pts { minX = min(minX,p.x); maxX = max(maxX,p.x); minY = min(minY,p.y); maxY = max(maxY,p.y) }
    let bw = max(1, maxX - minX), bh = max(1, maxY - minY), margin: CGFloat = 90
    contentCenter = CGPoint(x: (minX+maxX)/2, y: (minY+maxY)/2)
    fitScale = min((geo.width - margin)/bw, (geo.height - margin)/bh)
    fitScale = min(max(fitScale, 0.15), 2.2)
    zoom = 1; pan = .zero                              // reset-to-fit
}
```
Removed: `nodeView(_:in:)` and the old `canvas` (edge-Canvas + ForEach). The nav-bar refresh button becomes
reset-to-fit:
```diff
-            Button { layout.reseed() } label: {
+            Button { fitToView(canvasSize) } label: {
                 Image(systemName: "arrow.clockwise")…
```
Preserved unchanged: `matchingIDs`, `visibleEdges`, `isVisible` (Stage 2), the `controls` chip row, the mode
toggle, `header` stats (read `layout.nodes.count` etc.; re-evaluated on `tick`), `.sheet(item: $selected)`
(Stage 1). `GraphViewModel`, `NodeDetailSheet`, DEBUG `🩺[Graph]` logging: untouched.

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: this is a full engine+render rewrite — compile-verifiable, but the
feel (clean settle, no overlap, smooth pinch/pan + node-drag + tap at ~95 nodes, label de-clutter) is a device
check I can't run here. Stage 4 (re-center on a node) builds on the transform added here. No git.
