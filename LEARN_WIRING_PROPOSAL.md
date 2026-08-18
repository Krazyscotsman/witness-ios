# Witness — Wire the Learn tab (whole-life Q&A) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only (endpoint exists). Propose-and-wait per CLAUDE.md.

---

## Read-first findings

**Current Learn is fully mock.**
- `LearnView.ask()` (LearnView.swift:199–211) never hits the network: sets `thinking=true`, waits 1.6s via
  `DispatchQueue.main.asyncAfter`, then inserts `LearnReflection.sample(question:)` — a hardcoded answer with a
  **fake `confidence: 0.82`** and sample sources. `// Real: POST /api/v1/learn/chat` comment at :204.
- UI: a **mode selector** (5 modes, `LearnModeOption.all`), **8 interpretive lenses** (preset questions that call
  `ask`), a **thinking card**, `reflectionCard` (question + confidence meter + answer + source groups), source
  chips split "Referenced memories" / "Referenced people and entities" (`FlowWrap`), and a dead **"Read" (TTS)
  TODO** button (:159).
- Models in this file: `LearnSource { kind, label }`, `LearnReflection` (+ `.sample` factory), `LearnModeOption`,
  `InsightLens`, `FlowWrap`.

**Entry + auth.** Insights → Learn: `InsightsView.swift:34` → `case "learn": LearnView()` — **no `auth`**. Learn is
pushed inside `InsightsView`'s `NavigationStack(path:)` (registers `navigationDestination(for: InsightItem.self)`).

**Memory-detail tap-through is reachable — confirmed.** A destination-closure
`NavigationLink { MemoryDetailView(listItem: MemoryDTO(id:title:exactDate:), auth: auth) }` pushes onto that same
stack with no extra registration — exactly how `TimelineView.swift:197` opens a memory. `MemoryDTO` already has
the light `init(id:title:exactDate:)`. Requires **threading `auth` into `LearnView`**.

**Decode note.** `APIClient.post` uses the **default** `JSONDecoder` (no snake-case), so the response DTO needs
**explicit CodingKeys** for `query_type` / `processing_time_ms` / `entity_type`. **No `APIClient` change needed.**

**DEBUG logging** (`🩺[Graph]`/`🩺[WitnessStart]`): project-wide search returns **0 matches** — already removed in
the prior turn; build is 0/0. Nothing to do.

---

## Endpoint contract (as given)
`POST /api/v1/learn/chat`, Bearer. Single-shot, stateless, seconds-long, no streaming, 500 on failure.
- Request: `{ message }` — **omit `mode`; never rely on `session_id`**.
- Response: `{ answer, confidence?, query_type?, subject?, sources[], mode?, processing_time_ms? }`.
- `sources` heterogeneous by `type`:
  - memory → `{ type:"memory", id, title?, date? }`
  - entity → `{ type:"entity", id, name?, entity_type? }`

---

## Decisions to confirm (recommendation first)
1. **Mode selector → REMOVE** (recommended). Since `mode` isn't sent, a visible selector is a dead control that
   misleads. Keep the 8 interpretive lenses (real preset questions). *Alt: keep it as a visual-only no-op.*
2. **"Read" (TTS) button → REMOVE** (recommended). It's a no-op TODO and TTS wiring isn't part of this task; drop
   it so there's no visible dead control (can be a later task). *Alt: keep as-is.*
3. **Confidence meter → show only when the backend returns `confidence`** (recommended); drop the fake 0.82.
4. **Q&A history stays client-side cosmetic** (in the VM; cleared by "Clear"; not persisted) — matches spec.
5. **Timeout 60s** for the single-shot call.

*(The diffs below assume 1=Remove, 2=Remove. If you keep either, I'll adjust before applying.)*

---

## Proposed diffs

### APIModels.swift — append
```swift
// MARK: - Learn (POST /api/v1/learn/chat) — whole-life single-shot Q&A with cited sources. Request is just
// { message } (mode/session_id intentionally omitted — stateless). Decoded by the DEFAULT decoder, so explicit
// CodingKeys map the snake_case keys. `sources` is a heterogeneous union branched on `type`.
nonisolated struct LearnChatRequest: Encodable { let message: String }

nonisolated struct LearnResponse: Decodable {
    let answer: String?
    let confidence: Double?
    let queryType: String?
    let subject: String?
    let sources: [LearnSourceDTO]?
    let mode: String?
    let processingTimeMs: Double?
    enum CodingKeys: String, CodingKey {
        case answer, confidence, subject, sources, mode
        case queryType = "query_type"
        case processingTimeMs = "processing_time_ms"
    }
}

/// One cited source. UNION branched on `type`: "memory" → id/title/date; "entity" → id/name/entity_type. Every
/// field optional so a shape wobble on an unused branch never fails the whole answer.
nonisolated struct LearnSourceDTO: Decodable {
    let type: String?
    let id: String?
    let title: String?
    let date: String?
    let name: String?
    let entityType: String?
    enum CodingKeys: String, CodingKey {
        case type, id, title, date, name
        case entityType = "entity_type"
    }
}
```

### New file: LearnViewModel.swift
```swift
import SwiftUI
import Combine

/// Whole-life Q&A against POST /api/v1/learn/chat. Single-shot + stateless (sends only { message }; no
/// session_id, no mode). Holds a client-side cosmetic history of answers. 401 → refresh → retry-once; any other
/// failure keeps the question so the UI can offer a one-tap retry.
@MainActor
final class LearnViewModel: ObservableObject {
    enum Phase: Equatable { case idle, asking, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var reflections: [LearnReflection] = []
    @Published private(set) var pendingQuestion: String?

    private enum SessionError: Error { case sessionEnded, badResponse }
    var isAsking: Bool { phase == .asking }

    func ask(_ text: String, auth: AuthManager) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, phase != .asking else { return }   // debounce: one in-flight at a time
        pendingQuestion = q
        phase = .asking
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/api/v1/learn/chat",
                    body: LearnChatRequest(message: q), timeout: 60, as: LearnResponse.self)
            }
            let answer = (r.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw SessionError.badResponse }
            reflections.insert(
                LearnReflection(question: q, answer: answer, confidence: r.confidence,
                                sources: Self.mapSources(r.sources)),
                at: 0)
            pendingQuestion = nil
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("That didn’t go through. Tap to try again.")   // question preserved for retry
        }
    }
    func retry(auth: AuthManager) async { if let q = pendingQuestion { await ask(q, auth: auth) } }
    func clear() { reflections.removeAll(); pendingQuestion = nil; phase = .idle }

    // Map the union sources → view models. Unknown types are dropped (never fabricated).
    private static func mapSources(_ dtos: [LearnSourceDTO]?) -> [LearnSource] {
        (dtos ?? []).compactMap { d in
            switch (d.type ?? "").lowercased() {
            case "memory":
                let title = clean(d.title) ?? "Untitled memory"
                let label = clean(d.date).map { "\(title) · \($0)" } ?? title
                return LearnSource(kind: .memory, label: label,
                                   memoryId: clean(d.id), memoryTitle: clean(d.title), memoryDate: clean(d.date))
            case "entity":
                let name = clean(d.name) ?? "Someone"
                let label = clean(d.entityType).map { "\(name) · \($0)" } ?? name
                return LearnSource(kind: .entity, label: label,
                                   memoryId: nil, memoryTitle: nil, memoryDate: nil)
            default:
                return nil
            }
        }
    }
    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
```

### LearnView.swift — model changes
```swift
struct LearnSource: Identifiable {
    let id = UUID()
    enum Kind { case memory, entity }
    let kind: Kind
    let label: String
    let memoryId: String?      // memory tap-through payload (nil for entity)
    let memoryTitle: String?
    let memoryDate: String?
}

struct LearnReflection: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let confidence: Double?     // nil → no meter (no fabricated confidence)
    let sources: [LearnSource]
    var memorySources: [LearnSource] { sources.filter { $0.kind == .memory } }
    var entitySources: [LearnSource] { sources.filter { $0.kind == .entity } }
}
```
- **Remove** `LearnReflection.sample(...)` and `struct LearnModeOption` (decision 1 = Remove).
- Keep `InsightLens` and `FlowWrap` unchanged.

### LearnView.swift — view changes
- Signature + state:
```swift
struct LearnView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager
    @StateObject private var vm = LearnViewModel()
    @State private var query = ""
    @FocusState private var focused: Bool
    ...
}
```
  (Remove `@State mode`, `@State thinking`, `@State reflections`.)
- Body: drop `modeSelector`; drive off the VM:
```swift
VStack(alignment: .leading, spacing: 18) {
    headerBlock
    askBox
    if vm.isAsking { thinkingCard }
    if case .failed(let msg) = vm.phase { errorCard(msg) }
    if vm.reflections.isEmpty && !vm.isAsking { lensesSection }
    else { reflectionsSection }
}
```
- `askBox`: `canAsk = !query.trimmed.isEmpty && !vm.isAsking`; button → `Task { await vm.ask(query, auth: auth); query = "" }`
  (clear on submit; focused = false).
- `lensesSection` tap → `Task { await vm.ask(lens.question, auth: auth) }`.
- `reflectionsSection` iterates `vm.reflections`.
- `navBar` "Clear" → `vm.clear()` (shown when `!vm.reflections.isEmpty`).
- `reflectionCard(_ r:)`:
  - Confidence meter only when `let c = r.confidence` (decision 3).
  - **Remove** the "Read" TODO button (decision 2).
  - Memory sources → tappable; entity sources → plain chips:
```swift
if !r.memorySources.isEmpty { memorySourceGroup(r.memorySources) }
if !r.entitySources.isEmpty { entitySourceGroup(r.entitySources) }
```
- New source groups (memory = NavigationLink → MemoryDetailView; entity = plain chip):
```swift
private func memorySourceGroup(_ sources: [LearnSource]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("REFERENCED MEMORIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
        FlowWrap(sources) { s in
            NavigationLink {
                MemoryDetailView(listItem: MemoryDTO(id: s.memoryId ?? "", title: s.memoryTitle, exactDate: s.memoryDate), auth: auth)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed").font(.system(size: 10)).foregroundStyle(WV.teal)
                    Text(s.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled((s.memoryId ?? "").isEmpty)
        }
    }
}
private func entitySourceGroup(_ sources: [LearnSource]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("REFERENCED PEOPLE AND ENTITIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
        FlowWrap(sources) { s in
            HStack(spacing: 5) {
                Image(systemName: "person").font(.system(size: 10)).foregroundStyle(WV.teal)
                Text(s.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
        }
    }
}
```
- New `errorCard(_:)` — friendly retry that re-asks the preserved question:
```swift
private func errorCard(_ message: String) -> some View {
    Button { Task { await vm.retry(auth: auth) } } label: {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
            Text(message).font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(WV.danger)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.2), lineWidth: 1))
    }
    .witnessPress()
}
```
- `ask(_:)` and the `DispatchQueue`/sample path are deleted (replaced by `vm.ask`).

### InsightsView.swift — thread auth (:34)
```diff
-                case "learn":    LearnView()
+                case "learn":    LearnView(auth: auth)
```

---

## After approval
Apply, then **BuildProject → 0/0** + per-file live diagnostics on: APIModels, LearnViewModel (new), LearnView,
InsightsView. Honest caveats I can't run here: the live `learn/chat` round-trip, the seconds-long wait, the
401→refresh path, and memory tap-through are device/backend checks. No git.
