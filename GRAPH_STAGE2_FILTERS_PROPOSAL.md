# Witness — Memory Graph Stage 2: relationship-classification filter chips — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Client-side only, no backend.

## Read-first
- State: `layout.nodes:[GNode]` / `layout.edges:[GEdge]`; `GNode.primaryRel` (Stage-1: anchor_rel_type →
  edge-to-narrator → strongest incident), `GEdge.relType` (raw), `layout.narratorID`.
- Existing filter (to replace): `@State enabled: Set<String>` of RelGroup keys + multi-toggle chip row;
  `visibleEdges` filters by `RelGroup.key(for:) ∈ enabled` then by mode; `isVisible` = web→all / ego→narrator or
  on a visible edge. RelGroup (incomplete 5-type map) also drives node/edge color.
- Mode: `layout.mode` (ego "My Circle" / web "Web"); filters compose with mode.
- RelGroup usages: GraphView (edge color, node color, chip row, visibleEdges, struct) + NodeDetailSheet:70
  (avatar). Two other hits are stale comments.

## Decisions (recommended; change any)
1. Replace RelGroup entirely with RelBucket (one classification for filter + color); update its 6 call sites
   incl. NodeDetailSheet.
2. Single-select chips (All + 5 buckets); tapping the selected bucket returns to All.
3. Node bucket = bucket(node.primaryRel) — reuses Stage-1 derivation ("rel to the center").
4. Adopt bucket coloring (the optional part) for consistency.
Perf/overlap at ~95 nodes is Stage 3 — untouched here (filter recompute is the same big-O as today).

---

## GraphView.swift — replace RelGroup with RelBucket (filter + palette)
```swift
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
```
(Delete the entire `struct RelGroup { … }`.)

### State + re-settle
```diff
-    @State private var enabled: Set<String> = ["family","romantic","friend","professional","pet"]
+    @State private var selectedBucket: RelBucket? = nil          // nil = All
     @State private var selected: GNode?
@@
-        .onChange(of: enabled) { _, _ in layout.wake() }
+        .onChange(of: selectedBucket) { _, _ in layout.wake() }
```

### Colors (canvas edge + node)
```diff
-                        ctx.stroke(path, with: .color(RelGroup.color(for: e.relType).opacity(0.45)), lineWidth: max(1, CGFloat(e.strength) * 2.5))
+                        ctx.stroke(path, with: .color(RelBucket.bucket(for: e.relType).color.opacity(0.45)), lineWidth: max(1, CGFloat(e.strength) * 2.5))
```
```diff
-        let g = node.isNarrator ? WV.teal : RelGroup.color(for: node.primaryRel)
+        let g = node.isNarrator ? WV.teal : RelBucket.bucket(for: node.primaryRel).color
```

### Chip row (single-select: All + 5 buckets)
```swift
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
```

### Filter logic (layered on the active mode; narrator always shown)
```swift
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
```

## NodeDetailSheet.swift — avatar color
```diff
-                Circle().fill(node.isNarrator ? WV.teal : RelGroup.color(for: node.primaryRel)).frame(width: 50, height: 50)
+                Circle().fill(node.isNarrator ? WV.teal : RelBucket.bucket(for: node.primaryRel).color).frame(width: 50, height: 50)
```

## Minor
- GraphViewModel.swift:6 comment ("drives RelGroup color") — update to RelBucket (one word) or leave; harmless.
- APIModels.swift:709 comment mentions RelGroup — historical, leaving as-is.

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: filtering + recolor are verifiable at compile; the live behavior
(chips filtering the real ~95/56 within My Circle / Web, re-settle on change, Other catching pet_owner/
participated_in/unknowns) is a device check. Layout perf/overlap remains Stage 3. DEBUG 🩺[Graph] logging left
in. No git.
