# Witness — Wire real memory detail (/detail) + retire adapter + fix large-narrative blank — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval + decisions 1–5.** No git.

## Read-first findings
- MemoryDetailView: `let memory: SampleMemory`; renders header (date/title/peopleChips via FlowLayout),
  the FULL narrative as one `Text(...).fixedSize(vertical:true)` (the blank bug), metadataRow
  (wordCount/texture), actionsRow, listenPlayer, readAloudControl, askCard→TalkView(memory:); has
  resolveMemoryAudioURL(for: SampleMemory), Speaker, AudioPlayer.
- Pushed via MemoriesView `.navigationDestination(for: MemoryDTO.self) { dto in
  MemoryDetailView(memory: SampleMemory(dto)) }` (temp adapter) on the lifted NavigationPath.
- SampleMemory used ONLY by: the adapter (MemoriesView), MemoryDetailView (memory +
  resolveMemoryAudioURL param + TalkView push), TalkView (`var memory: SampleMemory?`). SampleMemory.samples
  has NO remaining consumers → dead. Other `.samples` are unrelated types. So retiring SampleMemory =
  retype TalkView param + rebuild detail, then delete SampleMemory/.samples/adapter.

## Decisions
1. Push list MemoryDTO (id + instant header) vs bare id. Recommend MemoryDTO.
2. Move Read aloud + Listen ABOVE the narrative (reachability on 174K). Recommend yes.
3. TalkView.memory : SampleMemory? → MemoryDetailDTO?. Recommend yes.
4. Detail fetched per-open (not cached). Recommend acceptable.
5. Read-aloud on 174K narrative impractical/untested — leave passing full text, flag; cap later. Defer.

## Large-narrative fix (acceptance: April 28 renders scrollable, no blank)
- VM splits narrative OFF main (Task.detached) into <=~1500-char chunks: by blank lines, hard-wrapping
  long paragraphs at word boundaries.
- View renders chunks as individual Text in a LazyVStack, NO .fixedSize → only near-viewport laid out.
- Drop the main-thread wordCount split entirely.

---

## APIModels.swift — detail models
```swift
struct MemoryDetailDTO: Decodable, Hashable {
    let id: String?
    let title: String?
    let narrative: String?
    let narrativeSnippet: String?
    let exactDate: String?
    let timeGranularity: String?
    let exactDateEstimated: Bool?      // three-state
    let narratorAge: Int?
    let qualityScore: Double?
    let importanceScore: Double?
    let location: String?
    let createdAt: String?
    let updatedAt: String?
    let people: [MemoryPerson]?        // OBJECTS here (anchors-first), not [String] like the list
    let emotions: [MemoryEmotion]?
    let quotes: [MemoryQuote]?

    enum CodingKeys: String, CodingKey {
        case id, title, narrative, location, emotions, quotes, people
        case narrativeSnippet = "narrative_snippet"
        case exactDate = "exact_date"
        case timeGranularity = "time_granularity"
        case exactDateEstimated = "exact_date_estimated"
        case narratorAge = "narrator_age"
        case qualityScore = "quality_score"
        case importanceScore = "importance_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MemoryPerson: Decodable, Hashable {
    let id: String?
    let canonicalName: String?
    let entityType: String?
    let isAnchor: Bool?
    let roleInMemory: String?
    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case entityType = "entity_type"
        case isAnchor = "is_anchor"
        case roleInMemory = "role_in_memory"
    }
}

struct MemoryEmotion: Decodable, Hashable {
    let emotionType: String?
    let intensity: Double?
    let triggerDescription: String?
    enum CodingKeys: String, CodingKey {
        case emotionType = "emotion_type"
        case intensity
        case triggerDescription = "trigger_description"
    }
}

struct MemoryQuote: Decodable, Hashable {
    let quoteText: String?
    let emotionalTone: String?
    let speakerName: String?
    enum CodingKeys: String, CodingKey {
        case quoteText = "quote_text"
        case emotionalTone = "emotional_tone"
        case speakerName = "speaker_name"
    }
}
```

## MemoryDetailViewModel.swift (new)
```swift
import Foundation
import Combine

@MainActor
final class MemoryDetailViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }

    @Published private(set) var detail: MemoryDetailDTO?
    @Published private(set) var paragraphs: [String] = []   // pre-split narrative chunks
    @Published private(set) var state: LoadState = .idle

    func load(id: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        await fetch(id: id, auth: auth)
    }
    func retry(id: String, auth: AuthManager) async {
        if state == .loading { return }
        await fetch(id: id, auth: auth)
    }

    private func fetch(id: String, auth: AuthManager) async {
        state = .loading
        do {
            let d = try await request(id)
            await apply(d)
            state = .loaded
        } catch let APIError.unauthorized(_, code) {
            if await auth.handleUnauthorized(code: code) {
                do { let d = try await request(id); await apply(d); state = .loaded }
                catch { state = .failed(message: Self.message(for: error)) }
            } else { state = .failed(message: "Your session ended. Please sign in again.") }
        } catch { state = .failed(message: Self.message(for: error)) }
    }

    private func apply(_ d: MemoryDetailDTO) async {
        let text = d.narrative ?? ""
        // Split off the main thread — scales to ~174K chars without hitching the UI.
        let chunks = await Task.detached(priority: .userInitiated) { Self.splitNarrative(text) }.value
        detail = d
        paragraphs = chunks
    }

    private func request(_ id: String) async throws -> MemoryDetailDTO {
        try await APIClient.shared.get("/api/v1/memories/\(id)/detail", timeout: 20, as: MemoryDetailDTO.self)
    }

    static func splitNarrative(_ text: String, maxChars: Int = 1500) -> [String] {
        guard !text.isEmpty else { return [] }
        var result: [String] = []
        for rawPara in text.components(separatedBy: "\n") {
            if rawPara.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if rawPara.count <= maxChars { result.append(rawPara); continue }
            var current = ""
            for word in rawPara.split(separator: " ", omittingEmptySubsequences: false) {
                if !current.isEmpty && current.count + word.count + 1 > maxChars {
                    result.append(current); current = ""
                }
                current += (current.isEmpty ? "" : " ") + word
            }
            if !current.isEmpty { result.append(current) }
        }
        return result
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .network: return "Can’t reach the server. Check your connection and try again."
            case .http(let s, _): return "The server responded with an error (\(s))."
            case .decoding: return "The server sent something unexpected."
            default: return api.errorDescription ?? "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}
```

## MemoryDetailView.swift (rebuilt — key structure; full body follows the existing visual system)
```swift
struct MemoryDetailView: View {
    let listItem: MemoryDTO                 // instant header + id
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @StateObject private var vm = MemoryDetailViewModel()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var speaker = Speaker()
    @State private var audioURL: URL?
    @State private var showAsk = false

    private var title: String { vm.detail?.title ?? listItem.title ?? "Untitled memory" }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header                    // date + title + people chips (FlowLayout)
                    controlsRow               // Read aloud + Listen (moved above narrative)
                    switch vm.state {
                    case .idle, .loading: loadingBlock
                    case .failed(let m):  failedBlock(m)
                    case .loaded:         loadedBody
                    }
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ignoresSafeArea(edges: .top)
            topControls
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(id: listItem.id, auth: auth) }
        .onAppear { audioURL = resolveMemoryAudioURL(); if let u = audioURL { audioPlayer.load(u) } }
        .onDisappear { audioPlayer.stop(); speaker.stop() }
        .sheet(isPresented: $showAsk) { TalkView(memory: vm.detail) }
    }

    private var loadedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVStack(alignment: .leading, spacing: 14) {          // narrative: lazy chunks, no fixedSize
                ForEach(Array(vm.paragraphs.enumerated()), id: \.offset) { _, p in
                    Text(p).font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(7)
                }
            }
            if let emotions = vm.detail?.emotions, !emotions.isEmpty { emotionsSection(emotions) }
            if let quotes = vm.detail?.quotes, !quotes.isEmpty { quotesSection(quotes) }
            if audioURL != nil { listenPlayer.padding(.top, 4) }
            askCard.padding(.top, 4)
        }
    }
    // header/controlsRow/emotionsSection/quotesSection/listenPlayer/readAloud/askCard/topControls:
    // same visual system (FlowLayout people chips from detail.people.canonicalName, teal cards,
    // Playfair). Full bodies in the applied diff.
}
```

## MemoriesView.swift — destination + delete adapter/SampleMemory
```diff
             .navigationDestination(for: MemoryDTO.self) { dto in
-                MemoryDetailView(memory: SampleMemory(dto))   // TEMP adapter (see extension below)
+                MemoryDetailView(listItem: dto, auth: auth)
             }
```
Delete: `extension SampleMemory { init(_ dto:) }`, `struct SampleMemory { … }`, and `static let samples`.
Keep MemoryCard + MemoryFormat.

## TalkView.swift — retype param
```diff
-    var memory: SampleMemory? = nil
+    var memory: MemoryDetailDTO? = nil
```
openingText uses `memory.title`; session placeholder uses `memory?.id` (now the real server id).

## After approval
Apply all; build 0/0; report. Acceptance: April 28, 1993 renders its full narrative, scrollable, no
blank; failed/loading states are friendly; adapter + SampleMemory gone. No git.
