# Witness — Entity Detail Page, Phase 1 of 5 (gate + entry + scaffold) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Propose-and-wait per CLAUDE.md.

⚠️ **Spec file missing.** `Witness_Entity_Detail_Page_Spec.md` is NOT in the repo (checked root + tree). This
proposal is built to the PROMPT's inline Phase-1 description only. Anything that maps entity `attributes` → header
pills / section counts is marked **(provisional)** and will be reconciled when the real spec is available.

---

## Read-first findings
- **Entry 1 — graph `NodeDetailSheet`** (GraphView.swift:50): real, fetches `/entities/{id}`; `node.id` = entity
  id, `node.primaryRel` = relationship, `node.isAnchor`/`label`. Ideal for "Show more".
- **Entry 2 — anchor detail `AnchorRecordDetailView`** (AnchorRegistryView.swift:262, read-only, generic over
  `AnchorRow`): only **`RelationshipRow.personEntityId`** exposes a graph entity id (AnchorRegistry.swift:52).
  The `AnchorRow` protocol guarantees only `id`; location/job/education/pet rows have **no entity id** → "Show
  more" can't be offered for them in Phase 1.
- **Name clash:** `EntityDetailView` already exists (Atlas, EntityAtlasView.swift:255) → new page =
  **`EntityDetailPage`**.
- **`EntityDetailDTO`**: default-decoder, reads `id/name/type/is_anchor/linked_memories`; `attributes` omitted.
- **No `enable_graph_view`** anywhere. `Profile` keys in YouView.swift; `ProfileDTO`/`ProfileUpdateRequest` in
  APIModels; `AuthManager.applyProfile`/`updateProfile` are the hooks.

## Decisions / flags (recommendation first)
1. **New page named `EntityDetailPage`** (avoids the Atlas `EntityDetailView` clash). *Recommend.*
2. **Anchor-detail "Show more" only when an entity id exists** — add `AnchorRow.entityIdForDetail` (default nil;
   `RelationshipRow` returns `personEntityId`). People anchors get it now; other categories don't until the
   backend exposes their entity id. *Recommend — flag.*
3. **`attributes` decoded opaquely** (`JSONValue?`) — never dumped; Phase 1 reads only a few known scalar keys
   for header pills **(provisional)** and counts non-empty top-level keys for "Populated sections". *Recommend.*
4. **Enable-Details toggle = optimistic local mirror + background PUT** (revert + inline note on failure).
   *Recommend.*
5. **Read Aloud reuses `Speaker`** (native TTS) — speaks name + type + summary line. *Recommend.*

---

## Proposed diffs

### YouView.swift — Profile key (local mirror)
```swift
static let enableDetailsKey = "settings.enableDetails"   // mirrors profile.enable_graph_view; Bool
```

### APIModels.swift — profile flag + entity attributes
`ProfileDTO` (read): add
```swift
let enableGraphView: Bool?
// CodingKeys: case enableGraphView = "enable_graph_view"
```
`ProfileUpdateRequest` (write): add
```swift
let enableGraphView: Bool?
// CodingKeys: case enableGraphView = "enable_graph_view"   (encodeIfPresent — synthesized)
```
`EntityDetailDTO`: add opaque attributes (safe; optional key, default decoder)
```swift
let attributes: JSONValue?
// CodingKeys: add `case attributes`
```

### AuthManager.swift — mirror the flag at launch
In `applyProfile(_:)` add:
```swift
if let on = p.enableGraphView {
    UserDefaults.standard.set(on, forKey: Profile.enableDetailsKey)
}
```
(Toggle writes go through the existing `updateProfile(_:)`.)

### SettingsView.swift — Advanced section (toggle)
```swift
@AppStorage(Profile.enableDetailsKey) private var enableDetails = false
@State private var savingDetails = false
@State private var detailsError = false
```
New section (placed after `privacySection`):
```swift
private var advancedSection: some View {
    sectionCard("Advanced", hint: "Extra detail surfaces for power users.") {
        Toggle(isOn: Binding(get: { enableDetails }, set: { setEnableDetails($0) })) {
            settingLabel("Enable Details View", "Show entity details and advanced panels.")
        }
        .tint(WV.teal).disabled(savingDetails).padding(.vertical, 6)
        if detailsError {
            Text("Couldn’t save that setting — check your connection.")
                .font(.system(size: 12)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
        }
    }
}
private func setEnableDetails(_ on: Bool) {
    let previous = enableDetails
    enableDetails = on                 // optimistic local mirror (instant UI)
    detailsError = false; savingDetails = true
    Task {
        do {
            try await auth.updateProfile(ProfileUpdateRequest(
                firstName: nil, lastName: nil, companionName: nil,
                companionVoice: nil, companionPersonality: nil, customVoiceName: nil,
                enableGraphView: on))
        } catch {
            enableDetails = previous; detailsError = true   // revert on failure
        }
        savingDetails = false
    }
}
```
(Add `advancedSection` to the `body` VStack.)

### New file: EntityDetailPage.swift
```swift
import SwiftUI

/// Phase 1 scaffold for the full entity detail page. Fetches GET /api/v1/entities/{id}; decodes `attributes`
/// opaquely (JSONValue). Renders Header + Summary + Linked Memories; later phases add the attribute sections.
struct EntitySeed {           // instant header context from the entry point (optional)
    var name: String? = nil
    var type: String? = nil
    var isAnchor: Bool? = nil
    var relationship: String? = nil
}

@MainActor
final class EntityDetailViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var detail: EntityDetailDTO?
    private enum SessionError: Error { case sessionEnded }

    func load(entityId: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        guard !entityId.isEmpty else { state = .failed("This entity isn’t available."); return }
        state = .loading
        do {
            detail = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/entities/\(entityId)", timeout: 30, as: EntityDetailDTO.self)
            }
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load these details. Please try again.")
        }
    }
    var linkedMemories: [LinkedMemory] { detail?.linkedMemories ?? [] }

    /// Count of non-empty top-level attribute keys (the "Populated sections" summary). Opaque — never dumped.
    var populatedSectionCount: Int {
        guard case .object(let o)? = detail?.attributes else { return 0 }
        return o.values.filter { !Self.isEmptyValue($0) }.count
    }
    private static func isEmptyValue(_ v: JSONValue) -> Bool {
        switch v {
        case .null: return true
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        case .bool, .number: return false
        }
    }
    /// Provisional: pull a scalar string attribute for a header pill (e.g. significance). Reconcile with spec.
    func attrString(_ key: String) -> String? {
        guard case .object(let o)? = detail?.attributes, case .string(let s)? = o[key],
              !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}

struct EntityDetailPage: View {
    let entityId: String
    var seed: EntitySeed = .init()
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = EntityDetailViewModel()
    @StateObject private var speaker = Speaker()

    private var name: String { vm.detail?.name ?? seed.name ?? "Entity" }
    private var type: String? { vm.detail?.type ?? seed.type }
    private var isAnchor: Bool { vm.detail?.isAnchor ?? seed.isAnchor ?? false }
    private var relationship: String? { seed.relationship ?? vm.attrString("relationship_type") }  // provisional

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    switch vm.state {
                    case .idle, .loading: loadingBlock
                    case .failed(let m):  failedBlock(m)
                    case .loaded:         summaryCards; linkedMemoriesSection
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MemoryDTO.self) { MemoryDetailView(listItem: $0, auth: auth) }
        .task { await vm.load(entityId: entityId, auth: auth) }
        .onDisappear { speaker.stop() }
    }

    // Header: kicker pills (Entity Detail / type / Anchor / relationship), name, meta pills, Read Aloud.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                kicker("Entity Detail", tone: WV.gold)
                if let t = type { kicker(t.capitalized, tone: WV.teal) }
                if isAnchor { kicker("Anchor", tone: WV.gold) }
                if let r = relationship, !r.isEmpty { kicker(humanize(r), tone: WV.teal) }
            }
            Text(name).font(.serif(30)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                pill("\(vm.linkedMemories.count) linked", "book.closed")
                if let s = vm.attrString("significance") { pill(s.capitalized, "star") }          // provisional
                if let d = vm.attrString("date") ?? vm.attrString("first_seen") { pill(d, "calendar") } // provisional
            }
            readAloud
        }
    }
    private var readAloud: some View {
        Button { toggleReadAloud() } label: {
            HStack(spacing: 7) {
                Image(systemName: speaker.isSpeaking ? "pause.fill" : "speaker.wave.2.fill").font(.system(size: 14, weight: .medium))
                Text(speaker.isSpeaking ? "Pause" : "Read aloud").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(WV.teal).padding(.horizontal, 14).frame(height: 38)
            .background(WV.teal.opacity(0.10), in: Capsule()).overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
        }.witnessPress()
    }
    private func toggleReadAloud() {
        if speaker.isSpeaking { speaker.pause() }
        else {
            let parts = [name, type?.capitalized, "\(vm.linkedMemories.count) linked memories"].compactMap { $0 }
            speaker.speak(parts.joined(separator: ". "))
        }
    }

    // Summary cards: Entity type · Anchor · Linked memories · Populated sections.
    private var summaryCards: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            summaryCard("Entity type", (type ?? "—").capitalized, "tag")
            summaryCard("Anchor", isAnchor ? "Yes" : "No", "star")
            summaryCard("Linked memories", "\(vm.linkedMemories.count)", "book.closed")
            summaryCard("Sections", "\(vm.populatedSectionCount)", "square.stack.3d.up")
        }
    }
    private func summaryCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(WV.teal)
            Text(value).font(.serif(20)).foregroundStyle(WT.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // Linked Memories (open by default) — reuses the NodeDetailSheet row style; tap → MemoryDetailView.
    private var linkedMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINKED MEMORIES").font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.4))
            if vm.linkedMemories.isEmpty {
                Text("No linked memories.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)).padding(.vertical, 6)
            } else {
                VStack(spacing: 8) { ForEach(Array(vm.linkedMemories.enumerated()), id: \.offset) { _, m in memoryRow(m) } }
            }
        }
    }
    @ViewBuilder private func memoryRow(_ m: LinkedMemory) -> some View {
        let title = (m.title ?? "").trimmingCharacters(in: .whitespaces)
        let display = title.isEmpty ? "Untitled memory" : title
        let sub = [ (m.date ?? "").trimmingCharacters(in: .whitespaces), (m.role ?? "").trimmingCharacters(in: .whitespaces) ]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        if let id = m.id, !id.isEmpty {
            NavigationLink(value: MemoryDTO(id: id, title: m.title, exactDate: m.date)) { memoryRowContent(display, sub, tappable: true) }
                .buttonStyle(.plain)
        } else { memoryRowContent(display, sub, tappable: false) }
    }
    // memoryRowContent / kicker / pill / navBar / loadingBlock / failedBlock / humanize — standard WV/WT styling.
}
```

### NodeDetailSheet.swift — "Show more" (graph entry)
```swift
@AppStorage(Profile.enableDetailsKey) private var enableDetails = false
```
Add above `memoriesSection` in the sheet's VStack:
```swift
if enableDetails {
    NavigationLink {
        EntityDetailPage(entityId: node.id,
                         seed: EntitySeed(name: node.label, type: nil, isAnchor: node.isAnchor,
                                          relationship: node.primaryRel), auth: auth)
    } label: {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.expand.vertical").font(.system(size: 14, weight: .semibold))
            Text("Show more").font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(WV.teal).frame(maxWidth: .infinity).frame(height: 46)
        .background(WV.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WV.teal.opacity(0.25), lineWidth: 1))
    }.buttonStyle(.plain)
}
```
(NodeDetailSheet already has a `NavigationStack` + `navigationDestination(for: MemoryDTO.self)`.)

### AnchorRegistry.swift + AnchorRegistryView.swift — "See everything" (anchor entry)
Protocol default so the generic detail can read an optional entity id:
```swift
// AnchorRegistry.swift — in `protocol AnchorRow`
var entityIdForDetail: String? { get }
extension AnchorRow { var entityIdForDetail: String? { nil } }        // default: none
// RelationshipRow:
var entityIdForDetail: String? { personEntityId }
```
`AnchorRecordDetailView` — gate on flag + id:
```swift
@AppStorage(Profile.enableDetailsKey) private var enableDetails = false
// in body, after the header block:
if enableDetails, let eid = row.entityIdForDetail, !eid.isEmpty {
    NavigationLink {
        EntityDetailPage(entityId: eid,
                         seed: EntitySeed(name: row.displayName, type: nil, isAnchor: true,
                                          relationship: row.typeLabel), auth: auth)
    } label: { /* "See everything" pill, same styling as above */ }
    .buttonStyle(.plain)
}
```
*(Requires `AnchorRecordDetailView` to have `auth` — it currently doesn't take it. Add `let auth: AuthManager`
and pass it at the call site AnchorRegistryView.swift:217. Flag: small signature change.)*

---

## Loading / empty / failed
`EntityDetailPage` has all three (spinner / "No linked memories." / failed + Try again), 401→refresh in the VM.

## After approval
Apply, then **BuildProject → 0/0** + per-file diagnostics: APIModels, AuthManager, YouView, SettingsView,
EntityDetailPage (new), NodeDetailSheet, AnchorRegistry(+View). Honest caveats: the live `/entities/{id}` shape
(esp. which `attributes` keys back the header pills / section count) is a device/backend check — those bits are
**provisional** until the missing spec is provided; the toggle's PUT round-trip is also a device check. No git.
```
