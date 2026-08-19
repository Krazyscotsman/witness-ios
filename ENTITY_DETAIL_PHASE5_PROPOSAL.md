# Witness — Entity Detail Phase 5 of 5 (final): remaining attributes.* sections — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** All via shared `records()` + primitives. Every section a
collapsed `EDSection` that renders only when non-empty. Propose-and-wait.

## Read-first findings
- `records(_ key:)` = shared dict-or-array parser → `[PersonMemoryDetail{memoryId, obj}]`. Currently `private func`
  on the VM → **make internal** so the view can call it per-section (only VM change).
- `detailField(label, JSONValue)`, `EDSection`, `EDPill`, `EDPillWrap`, `humanize` reused.
- `vm.entityNames [uuid:name]` already loaded (Phase 2) → resolve person/entity UUIDs, else omit.
- Insert after `romanticDynamicsSection`, before `linkedMemoriesSection`, in the listed order.

## Decisions / flags (recommendation first)
1. **Data-driven engine**: one `attrSection(spec)` renders any section from a declarative `AttrSectionSpec`
   (quote/lead/pills/fields). Keeps 9 sections DRY and primitive-based. *Recommend.*
2. **`resolvedPerson`**: name from `entityNames`; keep plain-name strings; **drop values that parse as `UUID` and
   aren't in the map** (`UUID(uuidString:) != nil` ⇒ omit) — never a raw UUID. *Recommend.*
3. **Field "kinds"**: `.text` (→ `detailField`), `.entity` (single UUID → resolved row / omit), `.entityArray`
   (participants etc. → resolved pills). *Recommend.*

---

## Proposed diffs

### EntityDetailSupport.swift — spec types
```swift
enum EDFieldKind { case text, entity, entityArray }

struct EDField: Identifiable {
    let key: String
    let label: String
    var kind: EDFieldKind = .text
    var id: String { key }
}

struct EDPillSpec {
    let key: String
    var icon: String? = nil
    var tone: Color = WV.teal
    var resolveEntity: Bool = false     // value is an entity UUID → resolve or omit
    var prefix: String = ""
}

/// Declarative section: lead text (quote = italic, plain = serif), a pills row, then field rows. Rendered over
/// records(key); empty records → the section is omitted entirely.
struct AttrSectionSpec: Identifiable {
    let title: String
    let key: String
    var quoteKeys: [String] = []        // first non-empty → italic “quote”
    var leadKeys: [String] = []         // first non-empty → serif body
    var pills: [EDPillSpec] = []
    var fields: [EDField] = []
    var id: String { key }
}

struct EDPillData: Identifiable { let id = UUID(); let text: String; let icon: String?; let tone: Color }
```

### EntityDetailPage.swift — VM
```swift
// was `private func records` → make callable from the view
func records(_ key: String) -> [PersonMemoryDetail] { … unchanged … }
```

### EntityDetailPage.swift — loaded branch
```swift
case .loaded:
    heroCards
    summaryCards
    dialogueSection
    acrossMemoriesSection
    relationshipEvolutionSection
    romanticDynamicsSection
    phase5Sections               // ← the 9 remaining sections, in order
    linkedMemoriesSection
```

### EntityDetailPage.swift — engine + specs
```swift
// Person/entity resolution: name from the map, keep plain names, drop unknown UUIDs (never render a raw UUID).
private func resolvedPerson(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    if let n = vm.entityNames[raw] { return n }
    return UUID(uuidString: raw) == nil ? raw : nil
}

private func pillData(_ r: PersonMemoryDetail, _ spec: AttrSectionSpec) -> [EDPillData] {
    var out: [EDPillData] = []
    for p in spec.pills {
        let raw = p.resolveEntity ? resolvedPerson(r.obj[p.key]?.stringValue) : r.obj[p.key]?.displayString
        if let v = raw?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            out.append(EDPillData(text: p.prefix + v, icon: p.icon, tone: p.tone))
        }
    }
    let mem = r.memoryId.flatMap { vm.memoryTitles[$0] } ?? r.obj["memory_title"]?.displayString
    if let mem, !mem.isEmpty { out.append(EDPillData(text: mem, icon: "book.closed", tone: WV.teal)) }
    return out
}

@ViewBuilder private func edField(_ label: String, _ v: JSONValue?, kind: EDFieldKind) -> some View {
    switch kind {
    case .text:   detailField(label, v)
    case .entity: EDFieldRow(label: label, value: resolvedPerson(v?.stringValue))   // nil → renders nothing
    case .entityArray:
        let names = (v?.arrayValue ?? []).compactMap { resolvedPerson($0.stringValue) }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                EDPillWrap(values: names)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
    }
}

private func attrCard(_ r: PersonMemoryDetail, _ spec: AttrSectionSpec) -> some View {
    let quote = spec.quoteKeys.lazy.compactMap { r.obj[$0]?.displayString }.first
    let lead  = spec.leadKeys.lazy.compactMap { r.obj[$0]?.displayString }.first
    let pills = pillData(r, spec)
    return VStack(alignment: .leading, spacing: 8) {
        if let quote { Text("“\(quote)”").font(.serif(17)).italic().foregroundStyle(WT.ink.opacity(0.9)).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
        if let lead  { Text(lead).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
        if !pills.isEmpty { FlowLayout(spacing: 8, lineSpacing: 8) { ForEach(pills) { EDPill(text: $0.text, icon: $0.icon, tone: $0.tone) } } }
        VStack(alignment: .leading, spacing: 0) { ForEach(spec.fields) { f in edField(f.label, r.obj[f.key], kind: f.kind) } }
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
}

@ViewBuilder private func attrSection(_ spec: AttrSectionSpec) -> some View {
    let rows = vm.records(spec.key)
    if !rows.isEmpty {
        EDSection(spec.title, count: rows.count, defaultExpanded: false) {
            VStack(spacing: 12) { ForEach(rows) { attrCard($0, spec) } }
        }
    }
}

@ViewBuilder private var phase5Sections: some View {
    ForEach(Self.phase5Specs) { attrSection($0) }
}

// Specs — order per the brief. Person/entity fields marked .entity / .entityArray so they resolve-or-omit.
private static let phase5Specs: [AttrSectionSpec] = [
    .init(title: "Notable lines", key: "dialogue_and_quotes",
          quoteKeys: ["quote_text", "quote"],
          pills: [.init(key: "significance", icon: "star", tone: WV.gold),
                  .init(key: "significance_type"),
                  .init(key: "emotional_tone", icon: "heart", tone: WV.gold),
                  .init(key: "context")]),
    .init(title: "Emotions across memories", key: "emotions_by_memory",
          pills: [.init(key: "emotion_type", icon: "heart", tone: WV.gold),
                  .init(key: "intensity", prefix: "Intensity ")],
          fields: [.init(key: "trigger_description", label: "Trigger")]),
    .init(title: "Emotional truths", key: "emotional_truths",
          leadKeys: ["truth_statement", "truth", "description"],
          pills: [.init(key: "truth_type"), .init(key: "weight", prefix: "Weight ")],
          fields: [.init(key: "still_held", label: "Still held")]),
    .init(title: "Life impacts", key: "life_impacts",
          leadKeys: ["description"],
          pills: [.init(key: "impact_type"), .init(key: "severity", icon: "star", tone: WV.gold)],
          fields: [.init(key: "still_affecting", label: "Still affecting")]),
    .init(title: "Activities", key: "activities",
          leadKeys: ["description"],
          pills: [.init(key: "activity_type"), .init(key: "location", icon: "mappin.and.ellipse")],
          fields: [.init(key: "participants", label: "Participants", kind: .entityArray)]),
    .init(title: "Place details", key: "places_details",
          pills: [.init(key: "location_type", icon: "mappin.and.ellipse")],
          fields: [.init(key: "setting_description", label: "Setting"),
                   .init(key: "sensory_details", label: "Sensory details"),
                   .init(key: "emotional_significance", label: "Emotional significance")]),
    .init(title: "Triangulation", key: "triangulation_dynamics",
          pills: [.init(key: "triangle_type"), .init(key: "significance_level", icon: "star", tone: WV.gold)],
          fields: [.init(key: "person_pulling", label: "Person pulling", kind: .entity),
                   .init(key: "person_against", label: "Person against", kind: .entity),
                   .init(key: "dynamic_description", label: "Dynamic"),
                   .init(key: "tactics_used", label: "Tactics"),
                   .init(key: "emotional_impact", label: "Emotional impact"),
                   .init(key: "narrator_response", label: "Your response"),
                   .init(key: "still_active", label: "Still active")]),
    .init(title: "Cultural practices", key: "cultural_practices",
          leadKeys: ["description"],
          pills: [.init(key: "practice_name"), .init(key: "practice_type"), .init(key: "cultural_origin")],
          fields: [.init(key: "significance", label: "Significance"),
                   .init(key: "personal_meaning", label: "Personal meaning")]),
    .init(title: "Events & entertainment", key: "events_and_entertainment",
          leadKeys: ["description"],
          pills: [.init(key: "event_name"), .init(key: "event_type"),
                  .init(key: "venue_name", icon: "mappin.and.ellipse"),
                  .init(key: "significance", icon: "star", tone: WV.gold)],
          fields: [.init(key: "memorable_moments", label: "Memorable moments"),
                   .init(key: "emotional_impact", label: "Emotional impact")]),
]
```

---

## After approval
Apply, then **BuildProject → 0/0** + diagnostics: EntityDetailSupport, EntityDetailPage. Honest caveats: every
`attributes.*` key name, shape (dict vs array), and which fields are entity UUIDs are device/backend checks.
Parsing is fully defensive — missing/renamed keys → skipped rows/pills; unknown shape → section omitted;
person/entity UUIDs resolve to a name or are dropped (never rendered raw); empties skip. Header `date` pill stays
provisional pending the still-absent spec. This completes the 5-phase Entity Detail page. No git.
```
