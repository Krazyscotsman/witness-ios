# Witness — Wire the Memoir feature (config → atmosphere → generate → PDF) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only (generation is server-side). Propose-and-wait.

---

## Read-first findings
- **MemoirView** = mock. Phases config/generating/ready exist; `runGenerate()` (line 342) fakes 2.2s →
  `.ready`; Download button (307) is TODO. Rich reusable config UI (title, length presets, styles, tones,
  year wheel, includeImages **default false**, dedication, atmosphere toggle). No auth, no network.
- **AtmosphereModal** = sample-driven (`AtmospherePeriod.samples`); right shape (period-at-a-time, dots,
  multiline, Skip All), but models lack `prompt_category`/`prompt_text`/year fields, and Save/Skip are no-ops.
- **Entry:** `InsightsView.swift:33 → MemoirView()` — needs `auth`.
- **APIClient:** `post` = default decoder (→ CodingKeys for snake); `postIgnoringResponseBody` for atmosphere
  save; `get(decoder:)` for prompts. No raw-Data download → use URLSession (Bearer iff host==base). Root paths
  resolve against base host — **no APIClient change.**
- **PDFKit** available (`PDFView`/`PDFDocument`). Confirmed via DocumentationSearch.

## Path prefixes (each matched exactly)
- `GET /api/v1/memoir/atmosphere-prompts`, `POST /api/v1/memoir/atmosphere`
- `POST /memoir/generate` (**ROOT**, no /api/v1). (`/memoir/preview` also root — see decision 4.)

## Decisions / flags (recommendation first)
1. **Length presets → the four canonical** (short 3000 / medium 20000 / long 40000 / book 70000); drop the
   shell's extra Standard 10k + Epic 150k. Default **book 70000** (matches current). *Recommend.*
2. **`include_images` default → true**; **title default → "My Life Story"** (per spec). *Recommend.*
3. **Atmosphere prompts response assumed `{ periods: [...] }`** with per-period `life_period, location,
   year_start, year_end, has_atmosphere_data, prompts:[{prompt_category, prompt_text}]`. If the real shape
   differs (bare array / different keys), it's a localized DTO change — **verify on device.**
4. **`/memoir/preview` NOT wired** in v1 (the Build steps only require generate); the config keeps its **local**
   manuscript estimate. Easy follow-up. *Recommend.*
5. **One downloaded PDF file** (prefer `download_url`, fallback `pdf_url`) used for BOTH the inline viewer and
   `ShareLink`, cached on-device. *Recommend.*

---

## Proposed diffs

### APIModels.swift — append
```swift
// MARK: - Memoir (config → optional atmosphere interview → generate → PDF)

/// POST /memoir/generate (ROOT). start_year/end_year/dedication omitted when nil. Decoded response via default
/// decoder → CodingKeys map snake_case. `nonisolated`: encoded/decoded off-main.
nonisolated struct MemoirGenerateRequest: Encodable {
    let title: String
    let style: String
    let tone: String
    let wordTarget: Int
    let includeImages: Bool
    let startYear: Int?
    let endYear: Int?
    let dedication: String?
    enum CodingKeys: String, CodingKey {
        case title, style, tone, dedication
        case wordTarget = "word_target", includeImages = "include_images"
        case startYear = "start_year", endYear = "end_year"
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title); try c.encode(style, forKey: .style); try c.encode(tone, forKey: .tone)
        try c.encode(wordTarget, forKey: .wordTarget); try c.encode(includeImages, forKey: .includeImages)
        try c.encodeIfPresent(startYear, forKey: .startYear); try c.encodeIfPresent(endYear, forKey: .endYear)
        try c.encodeIfPresent(dedication, forKey: .dedication)
    }
}

/// Generate result. ⚠️ Failure can arrive as {status:"error", message}. Read `status` from the body.
nonisolated struct MemoirGenerateResponse: Decodable {
    let status: String?
    let message: String?
    let pdfUrl: String?
    let downloadUrl: String?
    let chapterCount: Int?
    let wordCount: Int?
    let memoriesUsed: Int?
    enum CodingKeys: String, CodingKey {
        case status, message
        case pdfUrl = "pdf_url", downloadUrl = "download_url"
        case chapterCount = "chapter_count", wordCount = "word_count", memoriesUsed = "memories_used"
    }
}

/// GET /api/v1/memoir/atmosphere-prompts (decoded with the snake decoder → camelCase, no CodingKeys).
nonisolated struct MemoirAtmospherePromptsResponse: Decodable { let periods: [MemoirPeriodDTO]? }
nonisolated struct MemoirPeriodDTO: Decodable, Identifiable {
    var id: String { "\(lifePeriod ?? "")|\(yearStart ?? 0)|\(yearEnd ?? 0)" }
    let lifePeriod: String?
    let location: String?
    let yearStart: Int?
    let yearEnd: Int?
    let hasAtmosphereData: Bool?
    let prompts: [MemoirPromptDTO]?
}
nonisolated struct MemoirPromptDTO: Decodable, Identifiable {
    var id: String { "\(promptCategory ?? "")|\(promptText ?? "")" }
    let promptCategory: String?
    let promptText: String?
}

/// POST /api/v1/memoir/atmosphere (one per non-empty answer). Default encoder → CodingKeys map snake_case.
nonisolated struct MemoirAtmosphereRequest: Encodable {
    let lifePeriod: String
    let location: String
    let yearStart: Int?
    let yearEnd: Int?
    let promptCategory: String
    let promptText: String
    let responseText: String
    enum CodingKeys: String, CodingKey {
        case location
        case lifePeriod = "life_period", yearStart = "year_start", yearEnd = "year_end"
        case promptCategory = "prompt_category", promptText = "prompt_text", responseText = "response_text"
    }
}
```

### New file: MemoirViewModel.swift
```swift
import SwiftUI
import Combine

struct MemoirConfig {
    var title: String; var style: String; var tone: String; var wordTarget: Int
    var includeImages: Bool; var startYear: Int?; var endYear: Int?; var dedication: String?
}
struct MemoirResult { let pdfURL: String?; let downloadURL: String?; let chapters: Int?; let words: Int?; let memories: Int? }

@MainActor
final class MemoirViewModel: ObservableObject {
    enum Phase: Equatable { case config, generating, ready, failed(String) }
    @Published private(set) var phase: Phase = .config
    @Published private(set) var result: MemoirResult?
    @Published private(set) var localPDFURL: URL?     // downloaded + cached; used by viewer + ShareLink
    @Published private(set) var downloading = false

    private enum SessionError: Error { case sessionEnded }

    /// POST /memoir/generate (ROOT), 900s. Reads `status` from the body (a 200 can still be an error).
    func generate(_ cfg: MemoirConfig, auth: AuthManager) async {
        guard phase != .generating else { return }        // guard double-tap
        phase = .generating; result = nil; localPDFURL = nil
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/memoir/generate", body: MemoirGenerateRequest(
                    title: cfg.title, style: cfg.style, tone: cfg.tone, wordTarget: cfg.wordTarget,
                    includeImages: cfg.includeImages, startYear: cfg.startYear, endYear: cfg.endYear,
                    dedication: cfg.dedication), timeout: 900, as: MemoirGenerateResponse.self)
            }
            if r.status == "error" {
                phase = .failed(r.message?.isEmpty == false ? r.message! : "Memoir generation failed. Please try again.")
                return
            }
            result = MemoirResult(pdfURL: r.pdfUrl, downloadURL: r.downloadUrl,
                                  chapters: r.chapterCount, words: r.wordCount, memories: r.memoriesUsed)
            phase = .ready
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("We couldn’t generate your memoir just now. Please try again.")
        }
    }
    func reset() { phase = .config; result = nil; localPDFURL = nil }

    /// Download (prefer download_url), cache on-device, expose a local file URL for the viewer + share sheet.
    func preparePDF(auth: AuthManager) async {
        guard localPDFURL == nil, !downloading, let raw = result?.downloadURL ?? result?.pdfURL,
              let url = resolvedURL(raw) else { return }
        downloading = true; defer { downloading = false }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memoirs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(abs(raw.hashValue)).pdf")
        if FileManager.default.fileExists(atPath: file.path) { localPDFURL = file; return }
        var req = URLRequest(url: url)
        if url.host == APIClient.baseURL.host, let token = KeychainStore.shared.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
           !data.isEmpty {
            try? data.write(to: file, options: .atomic)
            localPDFURL = file
        }
    }

    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
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

### New file: MemoirAtmosphereViewModel.swift
```swift
import SwiftUI
import Combine

/// Loads the atmosphere prompts and best-effort saves answers. Optional feature — degrades to "skip" on any
/// failure/empty so the generate flow is never blocked.
@MainActor
final class MemoirAtmosphereViewModel: ObservableObject {
    @Published private(set) var periods: [MemoirPeriodDTO] = []
    @Published private(set) var loaded = false
    private static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(auth: AuthManager) async {
        loaded = false
        let resp = try? await withAuth(auth) {
            try await APIClient.shared.get("/api/v1/memoir/atmosphere-prompts", timeout: 30,
                                           decoder: Self.snake, as: MemoirAtmospherePromptsResponse.self)
        }
        let all = resp?.periods ?? []
        let needing = all.filter { $0.hasAtmosphereData == false }
        periods = needing.isEmpty ? all : needing         // fallback to all if none flagged
        loaded = true
    }

    /// Best-effort: POST each non-empty answer. Failures are swallowed (the interview is optional).
    func submit(_ answers: [MemoirAtmosphereRequest], auth: AuthManager) async {
        for a in answers where !a.responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try? await withAuth(auth) {
                try await APIClient.shared.postIgnoringResponseBody("/api/v1/memoir/atmosphere", body: a, timeout: 30)
            }
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
```

### New file: PDFKitView.swift
```swift
import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let fileURL: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = PDFDocument(url: fileURL)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != fileURL { v.document = PDFDocument(url: fileURL) }
    }
}
```

### MemoirView.swift — key changes
- Signature + VMs; config defaults per spec:
```swift
@ObservedObject var auth: AuthManager
@StateObject private var vm = MemoirViewModel()
@StateObject private var atmosphereVM = MemoirAtmosphereViewModel()
@State private var title = "My Life Story"
@State private var includeImages = true
@State private var preparingInterview = false
// words default 70000 (book); presets → the four canonical (see WordTarget change)
```
- Drive the body off `vm.phase` (replaces local `phase`): `config / generating / ready / failed`.
- `startGenerate()`:
```swift
private func startGenerate() {
    guard !preparingInterview, vm.phase != .generating else { return }
    if enrichWithAtmosphere {
        preparingInterview = true
        Task {
            await atmosphereVM.load(auth: auth)
            preparingInterview = false
            if atmosphereVM.periods.isEmpty { await runGenerate() } else { showAtmosphere = true }
        }
    } else { Task { await runGenerate() } }
}
private func runGenerate() async { await vm.generate(currentConfig, auth: auth); if vm.phase == .ready { await vm.preparePDF(auth: auth) } }
private var currentConfig: MemoirConfig {
    MemoirConfig(title: title.trimmed.isEmpty ? "My Life Story" : title.trimmed, style: style, tone: tone,
                 wordTarget: words, includeImages: includeImages,
                 startYear: Int(startYear), endYear: Int(endYear),
                 dedication: dedication.trimmed.isEmpty ? nil : dedication.trimmed)
}
```
- `fullScreenCover` passes the loaded interview VM + auth:
```swift
AtmosphereModal(vm: atmosphereVM, auth: auth,
                onComplete: { showAtmosphere = false; Task { await runGenerate() } },
                onCancel: { showAtmosphere = false })
```
- **Generating**: keep the honest spinner + copy (NO progress bar / no "chapter N of M"). The mock 2.2s
  `DispatchQueue` is removed. Disable the nav back button while `vm.phase == .generating` (guard nav).
- **Ready** (`readyBody`): real stats from `vm.result` (chapters / words / memories_used); inline
  `PDFKitView(fileURL:)` when `vm.localPDFURL != nil` (else a small "preparing your PDF…" spinner); a
  `ShareLink(item: url)` for download/share; "Create another memoir" → `vm.reset()`.
- **Failed**: `vm.phase == .failed(msg)` → message + "Try again" → `Task { await runGenerate() }` (config
  preserved in @State).
- `WordTarget.all` → the four canonical presets (short/medium/long/book); remove `needsBackend`/Epic/Standard.
- The Generate button shows a spinner while `preparingInterview`.

### AtmosphereModal.swift — real data + submit
- New signature: `AtmosphereModal(vm: MemoirAtmosphereViewModel, auth: AuthManager, onComplete: ..., onCancel: ...)`.
- Replace `AtmospherePeriod.samples` with `vm.periods` (`MemoirPeriodDTO`). Header shows `lifePeriod`,
  `location`, and the year span; keep the dot progress + one-period-at-a-time + Back/Next + "Skip All".
- Answers stored as `@State answers: [[String]]` sized to `periods[i].prompts` (built on appear); each question
  is a multi-line `TextEditor` with the "optional but encouraged" placeholder.
- On **Save & Generate** / **Skip All**: build `[MemoirAtmosphereRequest]` from non-empty answers
  (`life_period, location, year_start, year_end, prompt_category, prompt_text, response_text`), call
  `await vm.submit(_:auth:)`, then `onComplete()`. Skip-all submits nothing.
- Remove `AtmospherePeriod.samples` / `AtmospherePromptItem` sample models (superseded by the DTOs).

### InsightsView.swift:33 — thread auth
```diff
-                case "memoir":   MemoirView()
+                case "memoir":   MemoirView(auth: auth)
```

---

## After approval
Apply, then **BuildProject → 0/0** + per-file diagnostics: APIModels, MemoirViewModel (new),
MemoirAtmosphereViewModel (new), PDFKitView (new), MemoirView, AtmosphereModal, InsightsView.

Honest caveats I can't run here: the multi-minute (≤900s) synchronous generate, the {status:"error"} path, the
atmosphere prompts JSON shape (decision 3), the PDF download/cache + PDFKit render, and ShareLink are
device/backend checks. No git.
