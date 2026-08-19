# Witness — Entity Detail Phase 3 of 5: `people_details_by_memory` + hero cards — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Reuses Phase-2 primitives. Propose-and-wait.

## Read-first findings
- Phase-2 primitives reused unchanged: `EDSection`, `EDPill`, `EDPillWrap`, `EDFieldRow`, `EDFormat`, and the
  `JSONValue` accessors (`objectValue`/`arrayValue`/`stringArray`/`displayString`/`intValue`/`boolValue`/subscript).
- Header (`EntityDetailPage.swift:163`): kicker pills + name + meta pills (`linked`, provisional `significance`,
  provisional `date`) + Read Aloud; `relationship` computed at `:124` is the provisional scalar to enrich.
- Loaded branch (`:135`): `summaryCards → dialogueSection → linkedMemoriesSection`.
- `vm.memoryTitles [id:title]` exists; add parallel `memoryDates`.

## Decisions / flags (recommendation first)
1. **Parse `people_details_by_memory` as dict-keyed-by-memory-id OR array** (defensive). Dict order = the
   `linked_memories` order (stable); array order preserved. *Recommend.*
2. **`detailField(label, JSONValue)`**: array → label + `EDPillWrap`; scalar → `EDFieldRow`; empty → nothing.
   Used for the fixed fields AND humanized `extended_attributes`. *Recommend.*
3. **Header enrichment from people_details** (first non-empty across memory cards): `Age` = `age_in_memory`,
   relationship = `relationship_type`, `significance` — falling back to the Phase-1 provisional `attrString`.
   *Recommend.*
4. **Hero cards** = "best pick — not definitive": Appearance (first non-empty `physical_description`) + In-their-
   words (`dialogue_and_quotes[0].quote_text`); each notes its source memory, or **"source unattributed"** when
   the memory can't be resolved. *Recommend.* (Relationship-arc heroes deferred to Phase 4.)

---

## Proposed diffs

### EntityDetailPage.swift — VM additions
```swift
/// One per-memory people-detail record (dict value or array element).
struct PersonMemoryDetail: Identifiable {
    let id = UUID()
    let memoryId: String?
    let obj: [String: JSONValue]
}

var memoryDates: [String: String] {
    var m: [String: String] = [:]
    for lm in linkedMemories {
        if let id = lm.id, let d = lm.date?.trimmingCharacters(in: .whitespaces), !d.isEmpty { m[id] = d }
    }
    return m
}

/// attributes.people_details_by_memory → per-memory cards. Dict (keyed by memory_id, ordered by linked_memories)
/// OR array (order preserved). Defensive: unknown shape → [].
var peopleDetails: [PersonMemoryDetail] {
    guard let pd = detail?.attributes?["people_details_by_memory"] else { return [] }
    if let dict = pd.objectValue {
        let order = Dictionary(linkedMemories.enumerated().compactMap { (i, lm) in lm.id.map { ($0, i) } },
                               uniquingKeysWith: { a, _ in a })
        return dict.map { PersonMemoryDetail(memoryId: $0.key, obj: $0.value.objectValue ?? [:]) }
            .sorted { (order[$0.memoryId ?? ""] ?? Int.max) < (order[$1.memoryId ?? ""] ?? Int.max) }
    }
    if let arr = pd.arrayValue {
        return arr.compactMap { el in
            guard let o = el.objectValue else { return nil }
            return PersonMemoryDetail(memoryId: o["memory_id"]?.stringValue, obj: o)
        }
    }
    return []
}

private func firstDetailString(_ key: String) -> String? {
    for d in peopleDetails { if let v = d.obj[key]?.displayString { return v } }
    return nil
}
var derivedAge: String? { firstDetailString("age_in_memory") }
var derivedRelationship: String? { firstDetailString("relationship_type") }
var derivedSignificance: String? { firstDetailString("significance") }

/// Hero picks — first non-empty across the memory cards; carries the source memory id (may be unresolved).
var heroAppearance: (text: String, memoryId: String?)? {
    for d in peopleDetails { if let v = d.obj["physical_description"]?.displayString { return (v, d.memoryId) } }
    return nil
}
var heroQuote: (text: String, memoryId: String?)? {
    for d in peopleDetails {
        if let q = d.obj["dialogue_and_quotes"]?.arrayValue?.first?.objectValue?["quote_text"]?.displayString {
            return (q, d.memoryId)
        }
    }
    return nil
}
```

### EntityDetailPage.swift — header enrichment
`relationship` computed (`:124`):
```swift
private var relationship: String? { vm.derivedRelationship ?? seed.relationship ?? vm.attrString("relationship_type") }
```
Meta-pills `FlowLayout` (replace the provisional block):
```swift
FlowLayout(spacing: 8, lineSpacing: 8) {
    pill("\(vm.linkedMemories.count) linked", "book.closed")
    if let age = vm.derivedAge { pill("Age \(age)", "number") }
    if let s = vm.derivedSignificance ?? vm.attrString("significance") { pill(s.capitalized, "star") }
    if let d = vm.attrString("date") ?? vm.attrString("first_seen") { pill(d, "calendar") }   // date still provisional
}
```

### EntityDetailPage.swift — loaded branch
```swift
case .loaded:
    heroCards
    summaryCards
    dialogueSection
    acrossMemoriesSection
    linkedMemoriesSection
```

### EntityDetailPage.swift — new views
```swift
// Hero cards (2-col; only when present). "Best pick — not definitive."
@ViewBuilder private var heroCards: some View {
    let appear = vm.heroAppearance
    let quote = vm.heroQuote
    if appear != nil || quote != nil {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEST PICK — NOT DEFINITIVE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
            let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: cols, spacing: 12, alignment: .leading) {
                if let a = appear { heroCard(title: "Appearance", body: a.text, memoryId: a.memoryId, quoted: false) }
                if let q = quote { heroCard(title: "In their words", body: "“\(q.text)”", memoryId: q.memoryId, quoted: true) }
            }
        }
    }
}
private func heroCard(title: String, body: String, memoryId: String?, quoted: Bool) -> some View {
    let source = memoryId.flatMap { vm.memoryTitles[$0] }
    return VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(WV.gold)
        Text(body).font(.serif(16)).italic(quoted).foregroundStyle(WT.ink.opacity(0.9))
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        if let source, !source.isEmpty {
            Text("From “\(source)”").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.45))
        } else {
            Text("source unattributed").font(.system(size: 11)).italic().foregroundStyle(WT.ink.opacity(0.4))
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
    .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
}

// "Across memories" — one card per memory (collapsed by default).
@ViewBuilder private var acrossMemoriesSection: some View {
    let people = vm.peopleDetails
    if !people.isEmpty {
        EDSection("Across memories", count: people.count, defaultExpanded: false) {
            VStack(spacing: 12) { ForEach(people) { personMemoryCard($0) } }
        }
    }
}
private func personMemoryCard(_ d: PersonMemoryDetail) -> some View {
    let title = d.memoryId.flatMap { vm.memoryTitles[$0] } ?? "A memory"
    let date = d.memoryId.flatMap { vm.memoryDates[$0] }
    let isPublic = d.obj["is_public_figure"]?.boolValue ?? false
    return VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                if let date { Text(date).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
            }
            Spacer()
            if isPublic { EDPill(text: "Public figure", icon: "star", tone: WV.gold) }
        }
        VStack(alignment: .leading, spacing: 0) {
            detailField("Appearance", d.obj["physical_description"])
            detailField("Role in scene", d.obj["role_in_scene"])
            detailField("Relationship", d.obj["relationship_type"])
            detailField("Age", d.obj["age_in_memory"])
            detailField("Significance", d.obj["significance"])
            detailField("Personality", d.obj["personality_traits"])
            detailField("Clothing", d.obj["clothing"])
            detailField("Scents", d.obj["scents"])
            detailField("Emotional state", d.obj["emotional_state_in_memory"])
            detailField("Health", d.obj["health_status"])
            detailField("Abilities & skills", d.obj["abilities_skills"])
            detailField("Voice", d.obj["voice_description"])
            detailField("Mannerisms", d.obj["mannerisms"])
            detailField("Family", d.obj["family_relationships"])
            extendedAttributes(d.obj["extended_attributes"])       // dynamic keys → humanized labels
        }
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
}

/// Array → label + pills; scalar → EDFieldRow; empty → nothing.
@ViewBuilder private func detailField(_ label: String, _ value: JSONValue?) -> some View {
    if let arr = value?.stringArray, !arr.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
            EDPillWrap(values: arr)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    } else {
        EDFieldRow(label: label, value: EDFormat.value(value))
    }
}
@ViewBuilder private func extendedAttributes(_ v: JSONValue?) -> some View {
    if let o = v?.objectValue, !o.isEmpty {
        ForEach(o.keys.sorted(), id: \.self) { k in detailField(humanize(k), o[k]) }
    }
}
```
(`humanize` already exists on the page; `Color(hex:)`, `FlowLayout`, all Phase-2 primitives already in the module.)

---

## After approval
Apply, then **BuildProject → 0/0** + diagnostics: EntityDetailPage (EntityDetailSupport unchanged). Honest caveats:
the live `people_details_by_memory` shape (dict vs array), the renamed keys (`physical_description`, `role_in_scene`,
`relationship_type`, `age_in_memory`, `emotional_state_in_memory`), `is_public_figure`, `extended_attributes`, and
`dialogue_and_quotes[].quote_text` are device/backend checks. Parsing is fully defensive — missing/renamed keys →
skipped rows, unknown shape → empty section, unresolved memory → "A memory" / "source unattributed". No git.
```
