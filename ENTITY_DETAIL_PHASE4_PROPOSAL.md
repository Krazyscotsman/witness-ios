# Witness — Entity Detail Phase 4 of 5: relationship arcs + romantic dynamics — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Reuses the primitives. Both sections collapsed by
default (emotionally weighty). Propose-and-wait.

## Read-first findings
- Primitives reused unchanged: `EDSection`/`EDPill`/`EDPillWrap`/`EDFieldRow`/`EDFormat`, `JSONValue` accessors,
  and `PersonMemoryDetail { memoryId, obj }` (generic memory-scoped record — reused for arcs + romantic rows).
- Page helpers reused: `detailField(label, JSONValue)`, `humanize`, `heroCard(...)`, `memoryTitles`/`memoryDates`,
  and the Phase-3 dict-or-array parser (generalized into `records(_:)`).
- Loaded branch order: `heroCards → summaryCards → dialogueSection → acrossMemoriesSection →
  linkedMemoriesSection`. New sections go after `acrossMemoriesSection`; arc heroes fold into `heroCards`.

## Decisions / flags (recommendation first)
1. **Generalize the Phase-3 parser to `records(_ key:)`** and derive `peopleDetails` / `relationshipArcs` /
   `romanticDynamics` from it (same dict-or-array tolerance). *Recommend* (refactors only code written this session).
2. **Hero arc = highest-significance arc** via a small `sigRank` (critical/defining > high/major > medium/moderate
   > low/minor > 0), first-of-max deterministic. *Recommend.*
3. **Pill type/subtype keys tried defensively** (`arc_type`||`type`, `arc_subtype`||`subtype`). *Recommend.*
4. **Romantic "any others present"**: after the known field set, a dynamic humanized pass over remaining keys
   (excluding known + `partner_name`/`memory_id`/`date`/`memory_date`). *Recommend.*

---

## Proposed diffs

### EntityDetailSupport.swift — hero model
```swift
/// A single hero card spec (best-pick surfaces at the top of the page).
struct EDHero: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let memoryId: String?
    var quoted: Bool = false
}
```

### EntityDetailPage.swift — VM (generalize parser + arcs/romantic + hero arc)
Replace the Phase-3 `peopleDetails` computed with:
```swift
/// attributes[key] → memory-scoped records. Dict (keyed by memory_id, ordered by linked_memories) OR array
/// (order preserved). Defensive: unknown shape → [].
private func records(_ key: String) -> [PersonMemoryDetail] {
    guard let v = detail?.attributes?[key] else { return [] }
    if let dict = v.objectValue {
        let order = Dictionary(linkedMemories.enumerated().compactMap { (i, lm) in lm.id.map { ($0, i) } },
                               uniquingKeysWith: { a, _ in a })
        return dict.map { PersonMemoryDetail(memoryId: $0.key, obj: $0.value.objectValue ?? [:]) }
            .sorted { (order[$0.memoryId ?? ""] ?? Int.max) < (order[$1.memoryId ?? ""] ?? Int.max) }
    }
    if let arr = v.arrayValue {
        return arr.compactMap { el in
            guard let o = el.objectValue else { return nil }
            return PersonMemoryDetail(memoryId: o["memory_id"]?.stringValue, obj: o)
        }
    }
    return []
}
var peopleDetails: [PersonMemoryDetail]     { records("people_details_by_memory") }
var relationshipArcs: [PersonMemoryDetail]  { records("relationship_arcs_by_memory") }
var romanticDynamics: [PersonMemoryDetail]  { records("romantic_dynamics") }

private func sigRank(_ s: String?) -> Int {
    switch (s ?? "").lowercased() {
    case "critical", "defining": return 4
    case "high", "major":        return 3
    case "medium", "moderate":   return 2
    case "low", "minor":         return 1
    default:                     return 0
    }
}
/// Highest-significance arc (first of the max) — source for the deferred arc hero cards.
var heroArc: PersonMemoryDetail? {
    var best: PersonMemoryDetail?; var bestRank = Int.min
    for a in relationshipArcs {
        let r = sigRank(a.obj["significance"]?.displayString)
        if r > bestRank { bestRank = r; best = a }
    }
    return best
}
```

### EntityDetailPage.swift — loaded branch
```swift
case .loaded:
    heroCards
    summaryCards
    dialogueSection
    acrossMemoriesSection
    relationshipEvolutionSection      // ← new
    romanticDynamicsSection           // ← new
    linkedMemoriesSection
```

### EntityDetailPage.swift — heroCards now include arc heroes
Replace the Phase-3 `heroCards` body:
```swift
@ViewBuilder private var heroCards: some View {
    var heroes: [EDHero] = []
    if let a = vm.heroAppearance { heroes.append(EDHero(title: "Appearance", body: a.text, memoryId: a.memoryId)) }
    if let q = vm.heroQuote { heroes.append(EDHero(title: "In their words", body: "“\(q.text)”", memoryId: q.memoryId, quoted: true)) }
    if let arc = vm.heroArc {                                   // deferred from Phase 3
        let m = arc.memoryId
        if let v = arc.obj["arc_summary"]?.displayString { heroes.append(EDHero(title: "Relationship arc", body: v, memoryId: m)) }
        if let v = arc.obj["what_they_meant_to_me"]?.displayString { heroes.append(EDHero(title: "What they meant to me", body: v, memoryId: m)) }
        if let v = arc.obj["what_i_meant_to_them"]?.displayString { heroes.append(EDHero(title: "What I meant to them", body: v, memoryId: m)) }
        if let v = arc.obj["life_impact_summary"]?.displayString { heroes.append(EDHero(title: "Life impact", body: v, memoryId: m)) }
    }
    if !heroes.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEST PICK — NOT DEFINITIVE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
            let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                ForEach(heroes) { h in heroCard(title: h.title, body: h.body, memoryId: h.memoryId, quoted: h.quoted) }
            }
        }
    }
}
```

### EntityDetailPage.swift — new sections
```swift
// MARK: Relationship evolution (relationship_arcs_by_memory) — collapsed.
@ViewBuilder private var relationshipEvolutionSection: some View {
    let arcs = vm.relationshipArcs
    if !arcs.isEmpty {
        EDSection("Relationship evolution", count: arcs.count, defaultExpanded: false) {
            VStack(spacing: 12) { ForEach(arcs) { arcCard($0) } }
        }
    }
}
private func arcCard(_ a: PersonMemoryDetail) -> some View {
    let title = a.memoryId.flatMap { vm.memoryTitles[$0] }
    return VStack(alignment: .leading, spacing: 8) {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            if let t = firstStr(a.obj, "arc_type", "type") { EDPill(text: humanize(t)) }
            if let st = firstStr(a.obj, "arc_subtype", "subtype") { EDPill(text: humanize(st)) }
            if let s = a.obj["significance"]?.displayString { EDPill(text: s.capitalized, icon: "star", tone: WV.gold) }
            if let title { EDPill(text: title, icon: "book.closed") }
        }
        VStack(alignment: .leading, spacing: 0) {
            detailField("Summary", a.obj["arc_summary"])
            detailField("Description", a.obj["arc_description"])
            detailField("Started", a.obj["start_date"])
            detailField("Ongoing", a.obj["is_ongoing"])
            detailField("What they meant to me", a.obj["what_they_meant_to_me"])
            detailField("What I meant to them", a.obj["what_i_meant_to_them"])
            detailField("Life impact", a.obj["life_impact_summary"])
        }
        arcPhases(a.obj["phases"])
        arcMilestones(a.obj["milestones"])
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
}
@ViewBuilder private func arcPhases(_ v: JSONValue?) -> some View {
    if let arr = v?.arrayValue, !arr.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHASES").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4)).padding(.top, 4)
            ForEach(Array(arr.enumerated()), id: \.offset) { _, el in
                if let o = el.objectValue {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let t = o["phase_type"]?.displayString { EDPill(text: humanize(t)) }
                            if let e = o["primary_emotion"]?.displayString { EDPill(text: e.capitalized, icon: "heart", tone: WV.gold) }
                        }
                        if let d = o["emotional_description"]?.displayString {
                            Text(d).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
@ViewBuilder private func arcMilestones(_ v: JSONValue?) -> some View {
    if let arr = v?.arrayValue {
        let labels = arr.compactMap { el -> String? in
            guard let o = el.objectValue else { return nil }
            return o["milestone_label"]?.displayString ?? o["milestone_type"]?.displayString ?? o["description"]?.displayString
        }
        if !labels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("MILESTONES").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4)).padding(.top, 4)
                EDPillWrap(values: labels)
            }
        }
    }
}

// MARK: Romantic dynamics (romantic_dynamics) — collapsed.
@ViewBuilder private var romanticDynamicsSection: some View {
    let rows = vm.romanticDynamics
    if !rows.isEmpty {
        EDSection("Romantic dynamics", count: rows.count, defaultExpanded: false) {
            VStack(spacing: 12) { ForEach(rows) { romanticCard($0) } }
        }
    }
}
private static let romanticKnown: [(String, String)] = [
    ("relationship_stage", "Relationship stage"),
    ("emotional_intimacy_level", "Emotional intimacy"),
    ("physical_intimacy_level", "Physical intimacy"),
    ("physical_intimacy_progression", "Physical intimacy progression"),
    ("communication_patterns", "Communication patterns"),
    ("communication_style", "Communication style"),
    ("conflict_resolution_style", "Conflict resolution"),
    ("trust_level", "Trust"),
    ("commitment_level", "Commitment"),
    ("attachment_style", "Attachment style"),
    ("love_languages", "Love languages"),
    ("how_met", "How they met"),
    ("first_impression", "First impression"),
    ("turning_points", "Turning points"),
    ("challenges", "Challenges"),
    ("growth_areas", "Growth areas"),
    ("shared_activities", "Shared activities"),
    ("dynamic_description", "Dynamic"),
    ("emotional_impact", "Emotional impact"),
    ("significance", "Significance"),
]
private func romanticCard(_ r: PersonMemoryDetail) -> some View {
    let title = r.memoryId.flatMap { vm.memoryTitles[$0] }
    let date = r.memoryId.flatMap { vm.memoryDates[$0] } ?? EDFormat.value(r.obj["date"]) ?? EDFormat.value(r.obj["memory_date"])
    let known = Set(Self.romanticKnown.map { $0.0 })
    let reserved: Set<String> = known.union(["partner_name", "memory_id", "date", "memory_date"])
    let extraKeys = r.obj.keys.filter { !reserved.contains($0) }.sorted()
    return VStack(alignment: .leading, spacing: 8) {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            if let p = r.obj["partner_name"]?.displayString { EDPill(text: p, icon: "heart") }
            if let title { EDPill(text: title, icon: "book.closed") }
            if let date { EDPill(text: date, icon: "calendar") }
        }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.romanticKnown, id: \.0) { key, label in detailField(label, r.obj[key]) }
            ForEach(extraKeys, id: \.self) { k in detailField(humanize(k), r.obj[k]) }   // any others present
        }
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
}

/// First non-empty scalar among the given keys.
private func firstStr(_ o: [String: JSONValue], _ keys: String...) -> String? {
    for k in keys { if let v = o[k]?.displayString { return v } }
    return nil
}
```

---

## After approval
Apply, then **BuildProject → 0/0** + diagnostics: EntityDetailPage, EntityDetailSupport. Honest caveats: the live
`relationship_arcs_by_memory` / `romantic_dynamics` shapes, all field/phase/milestone key names, and the
significance vocabulary are device/backend checks — parsing is fully defensive (missing/renamed keys → skipped
rows/pills; unknown shape → empty section; no arc → no arc heroes; unresolved memory → "source unattributed").
No git.
```
