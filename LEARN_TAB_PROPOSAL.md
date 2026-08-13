# Witness — Learn tab → POST /api/v1/learn/chat (single-shot, cited sources) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Stateless single-shot Q&A (no session/lifecycle).

## Read-first
- InsightsView → `case "learn": LearnView()`. LearnView is a fake shell: header, mode selector (5), ask box,
  8 lens presets, reflection cards (answer + confidence meter + memory/entity source chips via FlowWrap),
  ask()→1.6s fake→LearnReflection.sample. Local models: LearnModeOption/InsightLens/LearnSource/LearnReflection/FlowWrap.
- Memory tap-through REACHABLE: MemoryDetailView(listItem: MemoryDTO, auth:) — build a MemoryDTO from {id,title,date}.
- Entity tap-through NOT reachable (no entity-detail-by-id screen; anchors is category→typed detail; EntityAtlas is
  sample). → entity sources = plain chips.
- LearnView needs `auth` (VM + memory push). InsightsView has it.

## Decisions (baked in; change any)
1. Remove the mode selector (endpoint takes no mode → would mislead). Keep the 8 lens presets (preset questions).
2. Remove the confidence meter (decode confidence, don't render — spec).
3. Entity sources = plain chips (no reachable entity detail); memory sources tappable → MemoryDetailView.
4. Add MemoryDTO(id:title:exactDate:) convenience init. Timeout 45s. Client-side history is cosmetic (server stateless).

---

## APIModels.swift — request/response DTOs + MemoryDTO convenience init
```swift
nonisolated struct LearnChatRequest: Encodable { let message: String }   // only message — no mode, no session_id

nonisolated struct LearnResponse: Decodable {
    let answer: String?
    let confidence: Double?        // decoded, NOT rendered
    let queryType: String?
    let subject: String?
    let sources: [LearnSourceDTO]?
    let mode: String?
    let processingTimeMs: Int?
    enum CodingKeys: String, CodingKey {
        case answer, confidence, queryType = "query_type", subject, sources, mode, processingTimeMs = "processing_time_ms"
    }
}
// Heterogeneous by `type`: memory → {type,id,title,date}; entity → {type,id,name,entity_type}.
nonisolated struct LearnSourceDTO: Decodable, Identifiable {
    let type: String?
    let id: String?
    let title: String?
    let date: String?
    let name: String?
    let entityType: String?
    enum CodingKeys: String, CodingKey { case type, id, title, date, name, entityType = "entity_type" }
    var uid: String { (type ?? "") + "|" + (id ?? UUID().uuidString) }   // stable-ish ForEach id
}
```
```swift
// Build a light MemoryDTO from a Learn memory source so a source tap can open the real memory detail.
extension MemoryDTO {
    init(id: String, title: String?, exactDate: String?) {
        self.init(id: id, title: title, narrative: nil, narrativeSnippet: nil, exactDate: exactDate,
                  timeGranularity: nil, exactDateEstimated: nil, narratorAge: nil, qualityScore: nil,
                  importanceScore: nil, people: nil, location: nil, createdAt: nil, updatedAt: nil)
    }
}
```

## New file: LearnViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class LearnViewModel: ObservableObject {
    enum Phase: Equatable { case idle, asking, failed(String) }
    struct Reflection: Identifiable { let id = UUID(); let question: String; let answer: String; let sources: [LearnSourceDTO] }

    @Published private(set) var reflections: [Reflection] = []   // client-side, cosmetic (server is stateless)
    @Published private(set) var phase: Phase = .idle
    private var pendingRetry: String?
    private enum SessionError: Error { case sessionEnded }

    var canAsk: Bool { phase != .asking }

    func ask(_ text: String, auth: AuthManager) async {
        let msg = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !msg.isEmpty, canAsk else { return }
        phase = .asking; pendingRetry = nil
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/api/v1/learn/chat", body: LearnChatRequest(message: msg), timeout: 45, as: LearnResponse.self)
            }
            let answer = (r.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            reflections.insert(Reflection(question: msg, answer: answer.isEmpty ? "—" : answer, sources: r.sources ?? []), at: 0)
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            pendingRetry = msg
            phase = .failed("We couldn’t answer that just now. Please try again.")
        }
    }
    func retryLast(auth: AuthManager) async { if let q = pendingRetry { await ask(q, auth: auth) } }
    func clear() { reflections.removeAll(); phase = .idle; pendingRetry = nil }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
```

## LearnView.swift — rewrite (drop mode selector + confidence + sample; wire the VM; source branching)
Keep: headerBlock copy, askBox, lensesSection (8 InsightLens presets), FlowWrap, InsightLens.
Remove: LearnModeOption + modeSelector, confidenceMeter, LearnSource(local)/LearnReflection(local)/sample, the
"Read"/tts button.
```swift
struct LearnView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LearnViewModel()
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    askBox
                    if case .failed(let m) = vm.phase { errorRow(m) }
                    if vm.phase == .asking { thinkingCard }
                    if vm.reflections.isEmpty && vm.phase != .asking { lensesSection }
                    else { reflectionsSection }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 120)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            if !vm.reflections.isEmpty {
                Button { vm.clear() } label: { Text("Clear").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)).frame(height: 44) }.witnessPress()
            }
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASK THE PATTERN LAYER").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            Text("Learn").font(.serif(28)).foregroundStyle(WT.ink)
            Text("Ask your life a question. Unlike Scarlett, who explores one memory, this reaches across your whole story — and shows you the memories and people it drew from.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var askBox: some View {
        HStack(spacing: 10) {
            TextField("Ask the Pattern Layer…", text: $query, axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).lineLimit(1...4).focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                .disabled(!vm.canAsk)
            Button { submit(query) } label: {
                ZStack { Circle().fill(canSubmit ? WV.teal : WV.teal.opacity(0.4)); Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }
                    .frame(width: 50, height: 50)
            }.witnessPress().disabled(!canSubmit)
        }
    }
    private var canSubmit: Bool { vm.canAsk && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func submit(_ text: String) { let t = text; query = ""; focused = false; Task { await vm.ask(t, auth: auth) } }

    private var thinkingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(WV.teal)
            Text("Pattern finding across memory…").font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.55))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }
    private func errorRow(_ m: String) -> some View {
        VStack(spacing: 8) {
            Text(m).font(.system(size: 13)).foregroundStyle(WV.danger).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { Task { await vm.retryLast(auth: auth) } } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)); Text("Try again").font(.system(size: 14, weight: .medium)) }.foregroundStyle(WV.teal)
            }.witnessPress()
        }
        .padding(14).frame(maxWidth: .infinity).background(WV.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var lensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTERPRETIVE PATHS").font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
            Text("Tap a path to ask, or write your own question above.").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            ForEach(InsightLens.all) { lens in
                Button { submit(lens.question) } label: {
                    HStack(spacing: 12) {
                        ZStack { Circle().fill(lens.tone.opacity(0.12)); Image(systemName: "arrow.triangle.branch").font(.system(size: 15, weight: .medium)).foregroundStyle(lens.tone) }.frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lens.title).font(.serif(17)).foregroundStyle(WT.ink)
                            Text(lens.desc).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                    .shadow(color: WT.ink.opacity(0.04), radius: 7, y: 3)
                }.witnessPress()
            }
        }
    }

    private var reflectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(vm.reflections) { r in reflectionCard(r) }
        }
    }
    private func reflectionCard(_ r: LearnViewModel.Reflection) -> some View {
        let mems = r.sources.filter { ($0.type ?? "") == "memory" }
        let ents = r.sources.filter { ($0.type ?? "") == "entity" }
        return VStack(alignment: .leading, spacing: 12) {
            Text(r.question).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            Text("ACROSS YOUR MEMORIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WV.gold)
            Text(r.answer).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.9)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)

            if !mems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REFERENCED MEMORIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
                    ForEach(mems) { s in memorySource(s) }
                }
            }
            if !ents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REFERENCED PEOPLE & ENTITIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
                    FlowWrap(ents) { s in entityChip(s) }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.05), radius: 10, y: 5)
    }

    // memory source → tap opens real memory detail (needs a valid id)
    @ViewBuilder private func memorySource(_ s: LearnSourceDTO) -> some View {
        let label = memoryChipLabel(s)
        if let id = s.id, !id.isEmpty {
            NavigationLink { MemoryDetailView(listItem: MemoryDTO(id: id, title: s.title, exactDate: s.date), auth: auth) } label: { memoryChip(label, tappable: true) }.buttonStyle(.plain)
        } else { memoryChip(label, tappable: false) }
    }
    private func memoryChipLabel(_ s: LearnSourceDTO) -> String {
        let t = (s.title ?? "").trimmingCharacters(in: .whitespaces)
        let d = (s.date ?? "").trimmingCharacters(in: .whitespaces)
        let base = t.isEmpty ? "Untitled memory" : t
        return d.isEmpty ? base : "\(base) · \(d)"
    }
    private func memoryChip(_ text: String, tappable: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed").font(.system(size: 12)).foregroundStyle(WV.teal)
            Text(text).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.8)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if tappable { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    // entity source → plain chip (no entity-detail screen reachable yet)
    private func entityChip(_ s: LearnSourceDTO) -> some View {
        let name = (s.name ?? "").trimmingCharacters(in: .whitespaces)
        let kind = AnchorText.titleCase(s.entityType)
        return HStack(spacing: 5) {
            Image(systemName: "person").font(.system(size: 10)).foregroundStyle(WV.teal)
            Text(name.isEmpty ? "Someone" : name).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75))
            if !kind.isEmpty { Text("· \(kind)").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.45)) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
    }
}

// KEEP (unchanged): InsightLens (8 presets) + FlowWrap.
// REMOVE: LearnModeOption, LearnSource (local), LearnReflection (local), FlowWrap unchanged.
```

## InsightsView.swift — pass auth
```diff
-                case "learn":    LearnView()
+                case "learn":    LearnView(auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live POST /learn/chat round-trip (seconds-long external call,
real answer + heterogeneous sources, 500 handling, memory tap-through opening /detail) is a device/backend
check. Entity chips are intentionally non-tappable (no entity-detail screen). No confidence UI; no mode/session.
No git.
