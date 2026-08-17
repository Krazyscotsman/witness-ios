import SwiftUI

// MARK: - Ego graph classification (frontend parity: §5 CATEGORY_COLORS, §4 FILTER_GROUPS + anchorCategoryMap,
// §2 compactRelType). Mapped from the RAW relationship_type string.
enum GraphCat: String, CaseIterable, Identifiable {
    case family, romantic, friend, professional, pet
    var id: String { rawValue }
    var label: String { self == .friend ? "Friends" : self == .pet ? "Pets" : rawValue.capitalized }
    var bg: Color { switch self {
        case .family: return Color(hex: 0xEEEDFE); case .romantic: return Color(hex: 0xFCEBEB)
        case .friend: return Color(hex: 0xE1F5EE); case .professional: return Color(hex: 0xF1EFE8); case .pet: return Color(hex: 0xFAEEDA) } }
    var text: Color { switch self {
        case .family: return Color(hex: 0x534AB7); case .romantic: return Color(hex: 0xA32D2D)
        case .friend: return Color(hex: 0x0F6E56); case .professional: return Color(hex: 0x5F5E5A); case .pet: return Color(hex: 0x854F0B) } }
    var border: Color { switch self {
        case .family: return Color(hex: 0xAFA9EC); case .romantic: return Color(hex: 0xF09595)
        case .friend: return Color(hex: 0x5DCAA5); case .professional: return Color(hex: 0xB4B2A9); case .pet: return Color(hex: 0xEF9F27) } }
}

enum GraphClassify {
    // §4 FILTER_GROUPS — filter membership + edge/focused coloring.
    static let groupTypes: [GraphCat: Set<String>] = [
        .family: ["parent_child","grandparent_grandchild","siblings","step_parent","in_law_parent","in_law_sibling","partners_parent","partners_sibling","aunt_uncle_niece_nephew","half_siblings","cousins"],
        .romantic: ["spouse","romantic"],
        .friend: ["friend","best_friend","close_friend"],
        .professional: ["colleague","mentor","classmate","acquaintance","neighbor","professional"],
        .pet: ["pet_owner"],
    ]
    static func edgeCategory(_ relType: String) -> GraphCat {
        let k = relType.lowercased()
        for c in GraphCat.allCases where groupTypes[c]?.contains(k) == true { return c }
        return .professional
    }
    // §4 anchorCategoryMap — root ring inclusion; skip set → nil (excluded); unmapped → professional.
    private static let skip: Set<String> = ["in_law_parent","in_law_sibling","partners_parent","partners_sibling","acquaintance","classmate","neighbor","associated_with","other"]
    private static let anchorMap: [String: GraphCat] = [
        "parent_child": .family, "grandparent_grandchild": .family, "siblings": .family, "step_parent": .family,
        "aunt_uncle_niece_nephew": .family, "half_siblings": .family, "cousins": .family,
        "spouse": .romantic, "romantic": .romantic,
        "friend": .friend, "best_friend": .friend, "close_friend": .friend,
        "colleague": .professional, "mentor": .professional, "professional": .professional,
        "pet_owner": .pet,
    ]
    static func anchorCategory(_ relType: String) -> GraphCat? {
        let k = relType.lowercased()
        if skip.contains(k) { return nil }
        return anchorMap[k] ?? .professional
    }
    // §2 compactRelType (snake → compact); fallback = titleCase.
    private static let compact: [String: String] = [
        "parent_child":"Parent","grandparent_grandchild":"Grandparent","aunt_uncle_niece_nephew":"Aunt/Uncle",
        "half_siblings":"Half-sibling","siblings":"Sibling","step_parent":"Step-parent",
        "in_law_parent":"In-law","in_law_sibling":"In-law","partners_parent":"In-law","partners_sibling":"In-law",
        "cousins":"Cousin","spouse":"Spouse","romantic":"Romantic","friend":"Friend","best_friend":"Best friend",
        "close_friend":"Friend","colleague":"Colleague","mentor":"Mentor","classmate":"Classmate",
        "acquaintance":"Acquaintance","neighbor":"Neighbor","professional":"Professional","pet_owner":"Pet",
    ]
    static func compactRelType(_ relType: String) -> String { compact[relType.lowercased()] ?? AnchorText.titleCase(relType) }
    static func significanceRank(_ s: String?) -> Int {
        switch (s ?? "").lowercased() { case "critical": return 0; case "high": return 1; case "moderate": return 2; case "low": return 3; default: return 4 }
    }
    static func initials(_ name: String) -> String { name.split(separator: " ").compactMap { $0.first }.prefix(2).map { String($0).uppercased() }.joined() }
    static func firstLast(_ name: String) -> String {   // "Katie Paulson" → "Katie P."
        let p = name.split(separator: " ").map(String.init); guard let f = p.first else { return name }
        if p.count > 1, let li = p.last?.first { return "\(f) \(li)." }
        return f
    }
    static func truncate(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(max(1, n - 1))) + "…" }
}

// MARK: - Placed nodes + field (virtual coords in the cx=420 space, per spec §1/§5)
struct EgoPlaced: Identifiable {
    let id: String; let name: String; let initials: String; let relLabel: String?
    let cat: GraphCat; var pos: CGPoint; let radius: CGFloat; let ring: Int
    let parentPos: CGPoint?; let node: GNode; let isNarrator: Bool; let isAnchor: Bool
}
struct EgoField {
    var center: EgoPlaced?
    var ring1: [EgoPlaced] = []
    var ring2: [EgoPlaced] = []
    var ring1R: CGFloat = 150
    var ring2R: CGFloat = 260
    let cx: CGFloat = 420
    var cy: CGFloat = 240
    var viewBoxH: CGFloat = 480
}

// MARK: - Deterministic radial layout (pure trig — no physics)
enum EgoLayout {
    private struct Cand { let id: String; let name: String; let rel: String?; let cat: GraphCat; let node: GNode; let mc: Int; let sig: Int }

    static func compute(nodes: [GNode], nodeByID: [String: GNode], edges: [GEdge],
                        narratorID: String?, focusedID: String?, filters: Set<GraphCat>,
                        anchors: [RelationshipRow]) -> EgoField {
        var f = EgoField()
        let centerNode: GNode? = (focusedID.flatMap { nodeByID[$0] }) ?? (narratorID.flatMap { nodeByID[$0] }) ?? nodes.first { $0.isNarrator }

        var ring1c: [Cand] = [], ring2c: [Cand] = []

        if let fid = focusedID, nodeByID[fid] != nil {                      // FOCUSED: graph edges
            var adj: [(String, String)] = []
            for e in edges {
                let cat = GraphClassify.edgeCategory(e.relType); guard filters.contains(cat) else { continue }
                if e.source == fid { adj.append((e.target, e.relType)) } else if e.target == fid { adj.append((e.source, e.relType)) }
            }
            var seen: Set<String> = [fid]
            let r1 = adj.compactMap { (nid, rel) -> Cand? in
                guard !seen.contains(nid), let n = nodeByID[nid] else { return nil }
                seen.insert(nid)
                return Cand(id: nid, name: n.label, rel: nil, cat: GraphClassify.edgeCategory(rel), node: n, mc: n.memoryCount, sig: 0)
            }.sorted { $0.mc > $1.mc }.prefix(14)
            ring1c = Array(r1)
            var r2: [Cand] = []
            outer: for parent in ring1c {
                for e in edges {
                    let other = e.source == parent.id ? e.target : (e.target == parent.id ? e.source : nil)
                    guard let oid = other, !seen.contains(oid), let n = nodeByID[oid] else { continue }
                    let cat = GraphClassify.edgeCategory(e.relType); guard filters.contains(cat) else { continue }
                    seen.insert(oid); r2.append(Cand(id: oid, name: n.label, rel: nil, cat: cat, node: n, mc: n.memoryCount, sig: 0))
                    if r2.count >= 8 { break outer }
                }
            }
            ring2c = r2
        } else {                                                            // ROOT: anchors
            var best: [String: Cand] = [:]
            for a in anchors {
                let rel = a.relationshipType ?? "other"
                guard let cat = GraphClassify.anchorCategory(rel), filters.contains(cat) else { continue }
                let nid = a.personEntityId ?? a.id
                let node = nodeByID[nid] ?? GNode(id: nid, label: a.displayName, primaryRel: rel,
                                                  isAnchor: true, isNarrator: false, memoryCount: 0, aliases: [], born: nil, died: nil)
                let cand = Cand(id: nid, name: node.label.isEmpty ? a.displayName : node.label,
                                rel: GraphClassify.compactRelType(rel), cat: cat, node: node,
                                mc: node.memoryCount, sig: GraphClassify.significanceRank(a.significance))
                if let e = best[nid], e.sig <= cand.sig { continue }        // dedupe by id, keep top significance
                best[nid] = cand
            }
            ring1c = Array(best.values.sorted { $0.sig < $1.sig }.prefix(20))
        }

        // radii / node sizes / label truncation by count (spec §5)
        let c1 = ring1c.count, c2 = ring2c.count
        let r1R: CGFloat = c1 <= 6 ? 150 : c1 <= 10 ? 190 : c1 <= 15 ? 230 : 270
        let r2R = r1R + 110
        let r1NodeR: CGFloat = c1 <= 6 ? 30 : c1 <= 10 ? 26 : c1 <= 15 ? 23 : 20
        let maxLbl = c1 <= 8 ? 16 : c1 <= 14 ? 13 : 11
        let cx: CGFloat = 420
        let cy = (c2 > 0 ? r2R : r1R) + 90
        f.ring1R = r1R; f.ring2R = r2R; f.cy = cy
        f.viewBoxH = cy + (c2 > 0 ? r2R : r1R) + 100

        if let cn = centerNode {
            f.center = EgoPlaced(id: cn.id, name: cn.label, initials: GraphClassify.initials(cn.label), relLabel: nil,
                                 cat: .professional, pos: CGPoint(x: cx, y: cy), radius: 40, ring: 0,
                                 parentPos: nil, node: cn, isNarrator: cn.isNarrator, isAnchor: cn.isAnchor)
        }
        f.ring1 = ring1c.enumerated().map { (i, c) in
            let ang = 2 * Double.pi * Double(i) / Double(max(c1, 1)) - .pi / 2      // top, clockwise
            let p = CGPoint(x: cx + CGFloat(cos(ang)) * r1R, y: cy + CGFloat(sin(ang)) * r1R)
            return EgoPlaced(id: c.id, name: GraphClassify.truncate(GraphClassify.firstLast(c.name), maxLbl),
                             initials: GraphClassify.initials(c.name), relLabel: c.rel, cat: c.cat, pos: p,
                             radius: r1NodeR, ring: 1, parentPos: nil, node: c.node, isNarrator: false, isAnchor: c.node.isAnchor)
        }
        f.ring2 = ring2c.enumerated().map { (i, c) in
            let ang = 2 * Double.pi * Double(i) / Double(max(c2, 1)) - .pi / 4      // offset −π/4
            let p = CGPoint(x: cx + CGFloat(cos(ang)) * r2R, y: cy + CGFloat(sin(ang)) * r2R)
            return EgoPlaced(id: c.id, name: (c.name.split(separator: " ").first.map(String.init) ?? c.name),
                             initials: GraphClassify.initials(c.name), relLabel: nil, cat: c.cat, pos: p,
                             radius: 18, ring: 2, parentPos: f.center?.pos, node: c.node, isNarrator: false, isAnchor: c.node.isAnchor)
        }
        return f
    }
}
