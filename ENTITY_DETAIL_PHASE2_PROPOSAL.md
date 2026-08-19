# Witness — Entity Detail Phase 2 of 5: `dialogue_spoken` verbatim quotes — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Adds to the Phase-1 page. Propose-and-wait.

## Read-first findings
- Phase-1 `EntityDetailViewModel`: `detail`, `linkedMemories: [LinkedMemory{id,title,date,role}]`, `attrString`,
  `populatedSectionCount`, `withAuth`. Loaded body = `summaryCards` → `linkedMemoriesSection`.
- Memory titles: from `linkedMemories` → `[id:title]`; neutral "A memory" when unresolved.
- Responder names: `EntitySummary{id,name?}` (default decoder); `GET /api/v1/entities` = top-level array →
  `[uuid:name]`; **omit** pill when unresolved (never show a UUID).
- `JSONValue` has only `stringValue` → add accessors in a new file (APIModels untouched).

## Decisions / flags (recommendation first)
1. **Entity list load = one page `?limit=1000&offset=0`, cached.** If a responder isn't on that page, the pill is
   omitted (graceful). *Recommend* — flag pagination for very large graphs.
2. **Preserve backend order** for dialogue (no re-sort); group header printed when `memory_id` changes from the
   previous row, exactly per spec. *Recommend.*
3. **Quote rendered verbatim** (trimmed only for the empty-skip check, never for display). *Recommend.*
4. **Reusable primitives** (`EDSection`/`EDPill`/`EDPillWrap`/`EDFieldRow`/`EDFormat`) built now for Phases 3–5.

---

## Proposed diffs

### New file: EntityDetailSupport.swift
```swift
import SwiftUI

// MARK: - Opaque JSONValue accessors (read attributes defensively; never dump)
extension JSONValue {
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var intValue: Int? {
        switch self {
        case .number(let d): return Int(d)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    subscript(_ key: String) -> JSONValue? { objectValue?[key] }
    /// Human display for a SCALAR (nil for empty / arrays / objects). bool→Yes/No, number→trimmed, string→trimmed.
    var displayString: String? {
        switch self {
        case .string(let s): let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }
}

// MARK: - Reusable detail primitives (Phases 2–5)

/// Collapsible titled card with an optional count badge. Collapsed by default unless `defaultExpanded`.
struct EDSection<Content: View>: View {
    let title: String
    var count: Int? = nil
    @State private var expanded: Bool
    @ViewBuilder let content: () -> Content
    init(_ title: String, count: Int? = nil, defaultExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.count = count; self.content = content
        _expanded = State(initialValue: defaultExpanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WV.gold)
                    if let count { Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.55))
                        .padding(.horizontal, 7).padding(.vertical, 2).background(WT.ink.opacity(0.06), in: Capsule()) }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.4))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded { content() }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }
}

struct EDPill: View {
    let text: String; var icon: String? = nil; var tone: Color = WV.teal
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tone) }
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(tone.opacity(0.10), in: Capsule())
    }
}

/// [String] → wrapping pills; empties skipped, whole thing hidden when nothing remains.
struct EDPillWrap: View {
    let values: [String]
    var body: some View {
        let vals = values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !vals.isEmpty {
            FlowLayout(spacing: 8, lineSpacing: 8) { ForEach(Array(vals.enumerated()), id: \.offset) { _, v in EDPill(text: v) } }
        }
    }
}

/// Label + value; renders NOTHING when the value is empty.
struct EDFieldRow: View {
    let label: String; let value: String?
    var body: some View {
        if let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                Text(v).font(.system(size: 15)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}

/// One verbatim line of dialogue parsed from attributes.dialogue_spoken.
struct DialogueLine: Identifiable {
    let id = UUID()
    let quote: String
    let memoryId: String?
    let responderId: String?
    let scene: Int?
    let order: Int?
}
```

### EntityDetailPage.swift — VM additions
```swift
@Published private(set) var entityNames: [String: String] = [:]   // uuid → name (responder resolution)
private var namesLoaded = false

/// Load the entity list once (cache) for responder-name resolution. Failure leaves the map empty → pills omit.
func loadEntityNames(auth: AuthManager) async {
    if namesLoaded { return }
    namesLoaded = true
    if let list = try? await withAuth(auth, {
        try await APIClient.shared.get("/api/v1/entities?limit=1000&offset=0", timeout: 30, as: [EntitySummary].self)
    }) {
        var map: [String: String] = [:]
        for e in list {
            if let n = e.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { map[e.id] = n }
        }
        entityNames = map
    }
}

var memoryTitles: [String: String] {
    var m: [String: String] = [:]
    for lm in linkedMemories {
        if let id = lm.id, let t = lm.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { m[id] = t }
    }
    return m
}

/// attributes.dialogue_spoken → ordered lines; empty-quote rows skipped; order preserved.
var dialogueLines: [DialogueLine] {
    guard let arr = detail?.attributes?["dialogue_spoken"]?.arrayValue else { return [] }
    return arr.compactMap { el in
        guard let o = el.objectValue,
              let raw = o["quote"]?.stringValue,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DialogueLine(quote: raw,
                            memoryId: o["memory_id"]?.stringValue,
                            responderId: o["responder_entity_id"]?.stringValue,
                            scene: o["scene_number"]?.intValue,
                            order: o["dialogue_order"]?.intValue)
    }
}
```
(`withAuth` needs to accept an escaping op — it already does.)

### EntityDetailPage.swift — view
Add state + a second load task, and render the section:
```swift
@State private var shownDialogue = 50
```
```swift
.task { await vm.load(entityId: entityId, auth: auth) }
.task { await vm.loadEntityNames(auth: auth) }        // ← new (parallel; for responder names)
```
Loaded branch:
```swift
case .loaded:
    summaryCards
    dialogueSection            // ← the centerpiece
    linkedMemoriesSection
```
```swift
@ViewBuilder private var dialogueSection: some View {
    let all = vm.dialogueLines
    let total = all.count
    if total > 0 {
        EDSection("Everything they said", count: total, defaultExpanded: false) {
            let shown = Array(all.prefix(shownDialogue))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, line in
                    if i == 0 || line.memoryId != shown[i - 1].memoryId {     // header when memory changes
                        Text(memoryHeader(line.memoryId).uppercased())
                            .font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, i == 0 ? 0 : 6)
                    }
                    dialogueRow(line)
                }
                if shownDialogue < total {
                    Button { shownDialogue = min(shownDialogue + 50, total) } label: {
                        Text("Show 50 more — showing \(min(shownDialogue, total)) of \(total)")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(WV.teal)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(WV.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }.witnessPress()
                } else {
                    Text("Showing all \(total)").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                }
            }
        }
    }
}
private func memoryHeader(_ memId: String?) -> String {
    if let id = memId, let t = vm.memoryTitles[id], !t.isEmpty { return t }
    return "A memory"      // neutral when unresolved
}
private func dialogueRow(_ line: DialogueLine) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("“\(line.quote)”")                                  // verbatim — their actual voice
            .font(.serif(17)).italic().foregroundStyle(WT.ink.opacity(0.9))
            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        let responder = line.responderId.flatMap { vm.entityNames[$0] }?.trimmingCharacters(in: .whitespaces)
        if line.scene != nil || (responder?.isEmpty == false) {
            HStack(spacing: 8) {
                if let s = line.scene { EDPill(text: "Scene \(s)", icon: "film") }
                if let r = responder, !r.isEmpty { EDPill(text: "to \(r)", icon: "arrow.turn.up.right") }
                // responder pill shows the resolved NAME only; a raw UUID is never rendered
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
}
```

---

## After approval
Apply, then **BuildProject → 0/0** + diagnostics: EntityDetailSupport (new), EntityDetailPage, APIModels
(unchanged, sanity). Honest caveats: the live `attributes.dialogue_spoken` shape (keys `quote`/`memory_id`/
`responder_entity_id`/`scene_number`/`dialogue_order`), the entities-list pagination (>1000), and responder/title
resolution are device/backend checks — parsing is defensive (missing/renamed keys degrade to skipped rows or
omitted pills, never a crash or a UUID). No git.
```
