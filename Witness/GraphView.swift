import SwiftUI

// MARK: - Memory Graph — deterministic radial "ego" layout (frontend parity; pure trig, no physics).
// Data: GET /api/v1/graph (nodes/edges) + GET /timeline/relationships (anchors → the root ring + rel labels),
// fetched once by GraphViewModel. Root ring = anchors; focused ring (after "Explore connections") = graph edges.
// Zoom/pan/fit reused from Stage 3; positions come from EgoLayout.compute.
struct GraphView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager
    @StateObject private var vm = GraphViewModel()
    @State private var selected: GNode?
    @State private var focusedEntityId: String?
    @State private var filters: Set<GraphCat> = Set(GraphCat.allCases)

    // View transform (virtual → screen), zoom/pan.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var fitScale: CGFloat = 1
    @State private var contentCenter: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero

    private var field: EgoField {
        EgoLayout.compute(nodes: vm.nodes, nodeByID: vm.nodeByID, edges: vm.edges,
                          narratorID: vm.narratorId, focusedID: focusedEntityId, filters: filters, anchors: vm.anchors)
    }
    private var narratorName: String { vm.nodes.first { $0.isNarrator }?.label ?? "you" }

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
                        canvas
                        controls
                    }
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { node in
            NodeDetailSheet(node: node, auth: auth) { n in
                selected = nil
                withAnimation { focusedEntityId = n.id }
            }
        }
        .task { await vm.load(auth: auth) }
    }

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
            Button { Task { await vm.refresh(auth: auth) } } label: {
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

    // MARK: - Transform (virtual cx=420 space → screen)
    private var liveScale: CGFloat { fitScale * zoom * pinch }
    private func screen(_ v: CGPoint, _ geo: CGSize) -> CGPoint {
        CGPoint(x: geo.width/2 + (v.x - contentCenter.x)*liveScale + pan.width,
                y: geo.height/2 + (v.y - contentCenter.y)*liveScale + pan.height)
    }

    // MARK: - Canvas (single immediate-mode draw of the radial field)
    private var canvas: some View {
        GeometryReader { geo in
            Canvas { ctx, _ in drawEgo(ctx, geo.size, field) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(panGesture(geo.size))
                .simultaneousGesture(MagnificationGesture().updating($pinch) { v, s, _ in s = v }
                    .onEnded { v in zoom = min(max(zoom * v, 0.3), 4) })
                .simultaneousGesture(SpatialTapGesture().onEnded { ev in
                    if let nd = nearestPlaced(to: ev.location, geo: geo.size, field) { selected = nd.node }
                })
                .onAppear { canvasSize = geo.size; fitToView(geo.size) }
                .onChange(of: geo.size) { _, s in canvasSize = s; fitToView(s) }
                .onChange(of: focusedEntityId) { _, _ in fitToView(geo.size) }
                .onChange(of: filters) { _, _ in fitToView(geo.size) }
                .onChange(of: vm.anchors.count) { _, _ in fitToView(geo.size) }
        }
        .background(Color.white.opacity(0.4))
    }

    private func drawEgo(_ ctx: GraphicsContext, _ geo: CGSize, _ f: EgoField) {
        guard let center = f.center else { return }
        let cpt = screen(center.pos, geo)
        drawGuide(ctx, cpt, f.ring1R * liveScale)
        if !f.ring2.isEmpty { drawGuide(ctx, cpt, f.ring2R * liveScale) }
        for nd in f.ring1 { spoke(ctx, cpt, screen(nd.pos, geo), nd.cat.border, dashed: false) }
        for nd in f.ring2 { spoke(ctx, (nd.parentPos.map { screen($0, geo) } ?? cpt), screen(nd.pos, geo), WV.gold, dashed: true) }
        for nd in f.ring2 { drawEgoNode(ctx, nd, geo, ring2: true) }
        for nd in f.ring1 { drawEgoNode(ctx, nd, geo, ring2: false) }
        drawCenter(ctx, center, cpt)
    }

    private func drawGuide(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r)),
                   with: .color(WV.gold.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
    }
    private func spoke(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, dashed: Bool) {
        var path = Path(); path.move(to: a); path.addLine(to: b)
        if dashed { ctx.stroke(path, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4])) }
        else { ctx.stroke(path, with: .color(color.opacity(0.42)), lineWidth: 1.7) }
    }
    private func drawEgoNode(_ ctx: GraphicsContext, _ nd: EgoPlaced, _ geo: CGSize, ring2: Bool) {
        let p = screen(nd.pos, geo)
        let r = nd.radius * liveScale
        let a: Double = ring2 ? 0.7 : 1.0
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r)
        ctx.fill(Path(ellipseIn: rect), with: .color(nd.cat.bg.opacity(a)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(nd.cat.border.opacity(a)), lineWidth: 2)
        if nd.node.id == selected?.id {
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x-r-5, y: p.y-r-5, width: 2*r+10, height: 2*r+10)), with: .color(WV.teal), lineWidth: 2)
        }
        drawText(ctx, nd.initials, at: p, size: (ring2 ? 10 : (nd.radius >= 26 ? 13 : 11)) * liveScale,
                 color: nd.cat.text.opacity(a), anchor: .center, weight: .semibold)
        let nameSize = (ring2 ? 9 : 11) * liveScale
        drawText(ctx, nd.name, at: CGPoint(x: p.x, y: p.y + r + 4 * liveScale), size: nameSize,
                 color: WT.ink.opacity(0.85 * a), anchor: .top, weight: ring2 ? .regular : .medium)
        if let rel = nd.relLabel, !ring2 {
            drawText(ctx, rel, at: CGPoint(x: p.x, y: p.y + r + 4 * liveScale + nameSize + 3 * liveScale),
                     size: 9 * liveScale, color: WV.gold, anchor: .top, weight: .regular)
        }
    }
    private func drawCenter(_ ctx: GraphicsContext, _ c: EgoPlaced, _ p: CGPoint) {
        let r = 40 * liveScale
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r)
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x0f172a)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(WV.gold), lineWidth: 2.5)
        drawText(ctx, c.initials, at: p, size: 16 * liveScale, color: .white, anchor: .center, weight: .semibold)
        if focusedEntityId == nil {
            drawText(ctx, "Click anyone to explore", at: CGPoint(x: p.x, y: p.y + r + 6 * liveScale),
                     size: 10 * liveScale, color: WT.ink.opacity(0.45), anchor: .top, weight: .regular)
        }
    }
    private func drawText(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat, color: Color, anchor: UnitPoint, weight: Font.Weight) {
        guard !s.isEmpty else { return }
        var t = ctx.resolve(Text(s).font(.system(size: max(6, size), weight: weight)))
        t.shading = .color(color)
        ctx.draw(t, at: p, anchor: anchor)
    }

    // MARK: - Gestures + fit
    private func panGesture(_ geo: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if panStart == nil { panStart = pan }
                if let b = panStart { pan = CGSize(width: b.width + v.translation.width, height: b.height + v.translation.height) }
            }
            .onEnded { _ in panStart = nil }
    }
    private func nearestPlaced(to p: CGPoint, geo: CGSize, _ f: EgoField) -> EgoPlaced? {
        var all = f.ring1 + f.ring2
        if let c = f.center { all.append(c) }
        var best: (EgoPlaced, CGFloat)?
        for nd in all {
            let sp = screen(nd.pos, geo); let d = hypot(sp.x - p.x, sp.y - p.y)
            let hit = max(20, nd.radius * liveScale + 8)
            if d <= hit, best == nil || d < best!.1 { best = (nd, d) }
        }
        return best?.0
    }
    private func fitToView(_ geo: CGSize) {
        guard geo != .zero else { return }
        let f = field
        var pts = f.ring1.map { $0.pos } + f.ring2.map { $0.pos }
        if let c = f.center { pts.append(c.pos) }
        guard let first = pts.first else { return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let bw = max(1, maxX - minX), bh = max(1, maxY - minY), margin: CGFloat = 120
        contentCenter = CGPoint(x: (minX + maxX)/2, y: (minY + maxY)/2)
        fitScale = min(max(min((geo.width - margin)/bw, (geo.height - margin)/bh), 0.2), 2.5)
        zoom = 1; pan = .zero
    }

    // MARK: - Controls: back / hint + "Visible bonds"
    private var controls: some View {
        VStack(spacing: 10) {
            if focusedEntityId != nil {
                Button { withAnimation { focusedEntityId = nil } } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)); Text("Back to \(narratorName)").font(.system(size: 14, weight: .medium)) }
                        .foregroundStyle(WV.teal)
                }.witnessPress()
            }
            HStack {
                Text("VISIBLE BONDS").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
                Spacer()
                Button { withAnimation { filters = Set(GraphCat.allCases) } } label: {
                    Text("Reset").font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
                }
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(GraphCat.allCases) { catChip($0) } }
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 10).background(WV.parchment)
    }
    private func catChip(_ c: GraphCat) -> some View {
        let on = filters.contains(c)
        return HStack(spacing: 6) {
            Image(systemName: on ? "eye" : "eye.slash").font(.system(size: 11)).foregroundStyle(on ? c.text : WT.ink.opacity(0.3))
            Circle().fill(c.border).frame(width: 10, height: 10)
            Text(c.label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? WT.ink : WT.ink.opacity(0.4))
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(on ? c.bg : Color.white, in: Capsule())
        .overlay(Capsule().stroke(on ? c.border : WT.ink.opacity(0.1), lineWidth: 1))
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { if on { filters.remove(c) } else { filters.insert(c) } } }
    }
}

// MARK: - Node / Edge models (populated by GraphViewModel from /api/v1/graph)
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
}

struct GEdge: Identifiable {
    let id = UUID()
    let source: String
    let target: String
    let relType: String
    let strength: Double
}
