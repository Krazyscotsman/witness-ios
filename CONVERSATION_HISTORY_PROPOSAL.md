# Witness — Conversation history (Ask Scarlett + Talk) → read-only text transcripts — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Read-only, no audio/TTS.
Endpoints (all under `/api/v1/jarvis`, Bearer): memory list `GET /memories/{memory_id}/conversations`; Talk list
`GET /conversations/recent?limit=50` (MIXED scopes); shared transcript `GET /conversations/{id}/turns`.

## Read-first
- Ask Scarlett = a sheet from MemoryDetailView (`AskScarlettView(memory: vm.detail, auth:)`), has `memory?.id`.
  Header `[✕] · "Ask {companion}" · [End/Done]`, no NavigationStack. Entry → clock button next to ✕ (only if
  memory id present).
- Talk = the Talk tab. Header `[COMPANION/Talk] · [Save & exit / New]`, no NavigationStack. Entry → clock button
  before Save & exit.
- Both reuse ChatMessage / CompanionBubble(text:name:) / UserBubble(text:). History presented as a sheet owning
  its own NavigationStack (list → push transcript).

## The two traps (pre-empted)
1. `memory_id` can be the literal string "None" → decode `String?` (NEVER UUID?); `normNone("None") == nil`.
2. Whole-life filter = `memory_title == nil` (NOT memory_id); title hardened against "None"/empty too.

---

## APIModels.swift — DTOs (append; snake_case via convertFromSnakeCase; two SEPARATE list models)
```swift
// MARK: - Jarvis conversation history (read-only). Two list shapes (don't force one struct):
//  • memory-scoped: has ended_at, no memory fields.  • recent (mixed): has memory fields, no ended_at.
nonisolated struct MemoryConversationsResponse: Decodable { let conversations: [MemoryConvSummary]? }
nonisolated struct MemoryConvSummary: Decodable, Identifiable {
    let id: String
    let startedAt: String?
    let endedAt: String?
    let turnCount: Int?
    let summary: String?
    let status: String?
}
nonisolated struct RecentConversationsResponse: Decodable { let conversations: [RecentConvSummary]? }
nonisolated struct RecentConvSummary: Decodable, Identifiable {
    let id: String
    let memoryId: String?      // ⚠️ can be the literal "None" — decoded as String?, normalized below
    let memoryTitle: String?
    let status: String?
    let startedAt: String?
    let turnCount: Int?
    let summary: String?

    // "None"/""/nil → nil (same backend quirk that made context_summary crash as an object).
    static func normNone(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s != "None" else { return nil }
        return s
    }
    var memoryIdNorm: String? { Self.normNone(memoryId) }
    var isWholeLife: Bool { Self.normNone(memoryTitle) == nil }   // discriminate by memory_title, NOT memory_id
}
nonisolated struct ConversationTurnsResponse: Decodable { let turns: [ConversationTurn]? }
nonisolated struct ConversationTurn: Decodable {
    let turnNumber: Int?
    let role: String?          // "jarvis" | "user"
    let content: String?
    let phase: String?
    let turnType: String?
    let createdAt: String?
}
```

## New file: ConversationHistory.swift
```swift
import SwiftUI
import Combine

// A unified display row (built from EITHER list DTO) — keeps the two wire models separate.
struct ConvRow: Identifiable, Hashable {
    let id: String
    let dateText: String
    let turnCount: Int
    let summary: String?
    let status: String?
}

enum ConvFormat {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let out: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy · h:mm a"; return f
    }()
    static func dateTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        if let d = iso.date(from: raw) ?? isoPlain.date(from: raw) { return out.string(from: d) }
        return raw   // fallback: show whatever the server sent
    }
}

@MainActor
final class ConversationHistoryViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, empty, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var rows: [ConvRow] = []

    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func loadMemory(memoryId: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }   // fetch-once; retry allowed from .failed/.empty
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/jarvis/memories/\(memoryId)/conversations", timeout: 20, decoder: Self.snake, as: MemoryConversationsResponse.self)
            }
            let list = (r.conversations ?? []).map {
                ConvRow(id: $0.id, dateText: ConvFormat.dateTime($0.startedAt), turnCount: $0.turnCount ?? 0, summary: $0.summary, status: $0.status)
            }
            rows = list; state = list.isEmpty ? .empty : .loaded
        } catch { state = Self.fail(error) }
    }

    func loadTalk(auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/jarvis/conversations/recent?limit=50", timeout: 20, decoder: Self.snake, as: RecentConversationsResponse.self)
            }
            let list = (r.conversations ?? [])
                .filter { $0.isWholeLife }                                   // whole-life only (memory_title == nil)
                .map { ConvRow(id: $0.id, dateText: ConvFormat.dateTime($0.startedAt), turnCount: $0.turnCount ?? 0, summary: $0.summary, status: $0.status) }
            rows = list; state = list.isEmpty ? .empty : .loaded
        } catch { state = Self.fail(error) }
    }

    private static func fail(_ e: Error) -> LoadState {
        if case SessionError.sessionEnded = e { return .failed("Your session has ended. Please sign in again.") }
        return .failed("We couldn’t load your conversations. Check your connection and try again.")
    }
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}

@MainActor
final class TranscriptViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, empty, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var messages: [ChatMessage] = []
    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(conversationId: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/jarvis/conversations/\(conversationId)/turns", timeout: 20, decoder: Self.snake, as: ConversationTurnsResponse.self)
            }
            let msgs: [ChatMessage] = (r.turns ?? []).compactMap { t in
                let text = (t.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ChatMessage(role: (t.role == "user") ? .user : .companion, text: text)   // jarvis/other → companion
            }
            messages = msgs; state = msgs.isEmpty ? .empty : .loaded
        } catch {
            if case SessionError.sessionEnded = error { state = .failed("Your session has ended. Please sign in again.") }
            else { state = .failed("We couldn’t load this conversation. Check your connection and try again.") }
        }
    }
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}

struct ConversationHistoryView: View {
    enum Scope: Equatable { case memory(String), talk }
    let scope: Scope
    @ObservedObject var auth: AuthManager
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ConversationHistoryViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                switch vm.state {
                case .idle, .loading: loading
                case .empty:          empty
                case .failed(let m):  failed(m)
                case .loaded:         list
                }
            }
            .navigationTitle("Past conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(WV.teal) } }
            .navigationDestination(for: ConvRow.self) { row in
                TranscriptView(conversationId: row.id, header: row, auth: auth)
            }
            .task { await reload() }
        }
    }
    private func reload() async {
        switch scope {
        case .memory(let id): await vm.loadMemory(memoryId: id, auth: auth)
        case .talk:           await vm.loadTalk(auth: auth)
        }
    }
    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(vm.rows) { row in
                    NavigationLink(value: row) { rowCard(row) }.buttonStyle(.plain)
                }
            }.padding(20)
        }
    }
    private func rowCard(_ r: ConvRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.dateText.isEmpty ? "Conversation" : r.dateText).font(.serif(16)).foregroundStyle(WT.ink)
                Spacer()
                Text("\(r.turnCount) turn\(r.turnCount == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            }
            if let s = r.summary, !s.isEmpty {
                Text(s).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }
    private var loading: some View { VStack(spacing: 12) { ProgressView().tint(WV.teal); Text("Loading conversations…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No past conversations yet").font(.serif(19)).foregroundStyle(WT.ink)
            Text(scope == .talk ? "Conversations you have in Talk will appear here." : "Conversations about this memory will appear here.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func failed(_ m: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(WV.danger.opacity(0.8))
            Text(m).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await reload() } } label: { Text("Try again").font(.system(size: 15, weight: .medium)).foregroundStyle(WV.teal) }.witnessPress()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TranscriptView: View {
    let conversationId: String
    let header: ConvRow
    @ObservedObject var auth: AuthManager
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @StateObject private var vm = TranscriptViewModel()

    var body: some View {
        ZStack {
            ParchmentBackground()
            switch vm.state {
            case .idle, .loading: ProgressView().tint(WV.teal)
            case .empty:          Text("This conversation has no messages.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).padding()
            case .failed(let m):  VStack(spacing: 12) { Text(m).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).multilineTextAlignment(.center); Button { Task { await vm.load(conversationId: conversationId, auth: auth) } } label: { Text("Try again").foregroundStyle(WV.teal) } }.padding(40)
            case .loaded:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(spacing: 3) {
                            Text(header.dateText.isEmpty ? "Conversation" : header.dateText).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(WV.gold)
                            Text("\(header.turnCount) turn\(header.turnCount == 1 ? "" : "s") · read-only").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
                        }.padding(.top, 8)
                        ForEach(vm.messages) { m in
                            if m.role == .companion { CompanionBubble(text: m.text, name: companion) } else { UserBubble(text: m.text) }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(conversationId: conversationId, auth: auth) }
        // NO composer, NO audio/TTS — read-only.
    }
}
```

## AskScarlettView.swift — header history entry
```diff
     @StateObject private var vm = WitnessSessionViewModel()
     @State private var draft = ""
+    @State private var showHistory = false
     @FocusState private var composerFocused: Bool
@@ body
         .task { await begin() }
+        .sheet(isPresented: $showHistory) {
+            ConversationHistoryView(scope: .memory(memory?.id ?? ""), auth: auth)
+        }
@@ header — add a clock button next to close (only when a memory id exists)
             Button { dismiss() } label: { Image(systemName: "chevron.down")… }.witnessPress()
+            if let id = memory?.id, !id.isEmpty {
+                Button { showHistory = true } label: {
+                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).foregroundStyle(WV.teal).frame(width: 40, height: 44)
+                }.witnessPress().witnessHint("Review past conversations about this memory.")
+            }
             Spacer()
             VStack(spacing: 2) { … name … }
```

## TalkView.swift — header history entry
```diff
     @State private var draft = ""
+    @State private var showHistory = false
     @FocusState private var composerFocused: Bool
@@ body
         .task { await begin() }
+        .sheet(isPresented: $showHistory) { ConversationHistoryView(scope: .talk, auth: auth) }
@@ header trailing group — clock before Save & exit / New
             Spacer()
+            Button { showHistory = true } label: {
+                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).foregroundStyle(WV.teal).frame(height: 44)
+            }.witnessPress().witnessHint("Review past conversations with \(companion).")
             if vm.phase == .ended { Button { newConversation() } … "New" … }
             else { Button { Task { await vm.end(auth: auth) } } … "Save & exit" … }
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live history round-trips (memory list, recent+filter, turns)
are a device/backend check. Traps handled: `memory_id`="None"→nil (String?, never UUID?), whole-life filter by
`memory_title`==nil (hardened vs "None"/empty). role jarvis→companion / user→user. Read-only, no audio. No git.

## Residual note
List `summary` is typed `String?` per the verified contract. We already have `JSONValue` in the codebase, so if
a `summary` ever comes back as an object (the context_summary bug class), hardening it is a one-line change —
flagging since it's the one field with object-risk precedent.
