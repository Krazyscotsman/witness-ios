# Witness — Wire real memory creation (POST /memories + media) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only; endpoints exist.

## Read-first
- RecordView persists NOTHING today: Speak → stop → `saved=true` + savedView (with a TEMP manual "Transcribe"
  scaffold); Type → `saveMemory()` (:328) is a `// Real: POST …` comment + `saved=true`. TODO at :329.
- Audio file: `recorder.lastRecordingURL` (.m4a). Transcript: NOT auto-produced — `Transcriber.transcribe(url:)`
  (on-device SFSpeech, fire-and-forget, publishes `transcript`/`state`) is only run by the temp scaffold.
- APIClient: one baseURL; `post(_:body:timeout:as:)` supports per-call timeout (120s ok); NO multipart helper;
  `post` uses default JSONDecoder (response DTO needs explicit CodingKeys).
- RecordView presented as fullScreenCover from Home:61, Memories:32, Timeline:33 — all `RecordView()` no auth,
  no nav stack. Surface new memory via onSaved → MemoriesViewModel.refresh.
- Date field is FREE TEXT (not YYYY-MM-DD).

Flow: POST /api/v1/memories { text, session_id, title?, memory_date? } (Bearer, ~120s, BLOCKS on extraction) →
{ status, memory_id, resolved_entities, message }; 500 on failure. If audio: POST /memories/{id}/media
multipart file (≤50MB) best-effort. Do NOT use /memories/voice.

## Decisions (recommended; change any)
1. Speak: review-then-save screen (editable on-device transcript + Save) replaces the instant fake "Saved" + temp
   scaffold.
2. memory_date sent only if dateText is strict YYYY-MM-DD, else omitted (free-text field; backend extracts date
   from text).
3. Surface via onSaved → Memories refresh (Home/Memories); Timeline closes; direct nav deferred.
4. Media upload best-effort; text memory valid if it fails.
5. Do NOT use /memories/voice.

---

## APIModels.swift — request/response (append)
```swift
nonisolated struct MemoryCreateRequest: Encodable {
    let text: String
    let sessionId: String
    let title: String?
    let memoryDate: String?
    enum CodingKeys: String, CodingKey { case text; case sessionId = "session_id"; case title; case memoryDate = "memory_date" }
    func encode(to encoder: Encoder) throws {                       // omit nil title/memory_date
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(memoryDate, forKey: .memoryDate)
    }
}
nonisolated struct MemoryCreateResponse: Decodable {
    let status: String?
    let memoryId: String?
    let message: String?     // resolved_entities intentionally not modeled (untyped)
    enum CodingKeys: String, CodingKey { case status; case memoryId = "memory_id"; case message }
}
```

## APIClient.swift — multipart upload (append)
```swift
/// POST multipart/form-data with a single file part. Any 2xx = success; body ignored. Throws APIError on
/// 401 / non-2xx / transport (same shape as the other methods) so callers can refresh+retry.
@discardableResult
func postMultipart(_ path: String, fileData: Data, fileName: String, mimeType: String,
                   fieldName: String = "file", authorized: Bool = true, timeout: TimeInterval? = nil) async throws -> Data {
    guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
    var req = URLRequest(url: url); req.httpMethod = "POST"
    if let timeout { req.timeoutInterval = timeout }
    let boundary = "Boundary-\(UUID().uuidString)"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if authorized, let token = tokenProvider() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    var body = Data()
    func add(_ s: String) { body.append(s.data(using: .utf8)!) }
    add("--\(boundary)\r\n")
    add("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
    add("Content-Type: \(mimeType)\r\n\r\n")
    body.append(fileData)
    add("\r\n--\(boundary)--\r\n")
    req.httpBody = body
    let data: Data, response: URLResponse
    do { (data, response) = try await session.data(for: req) } catch { throw APIError.network(error) }
    guard let http = response as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }
    if http.statusCode == 401 {
        let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
        throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
    }
    guard (200..<300).contains(http.statusCode) else { throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8)) }
    return data
}
```

## New file: MemoryCreateViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class MemoryCreateViewModel: ObservableObject {
    @Published private(set) var processingMessage = "Saving…"
    @Published private(set) var errorText: String?

    private static let messages = ["Saving…", "Understanding it…", "Finding the people and places…",
                                   "Weaving it into your story…", "Almost there…"]
    private var rotate: Task<Void, Never>?
    private enum CreateError: Error { case badResponse, sessionEnded }

    /// Two calls: create (blocks ~30–90s on extraction) then best-effort media upload. Returns memory_id, or
    /// nil on failure (caller keeps the transcript + recording).
    func save(text: String, sessionID: String, title: String?, memoryDate: String?, audioURL: URL?, auth: AuthManager) async -> String? {
        errorText = nil
        startRotating()
        defer { stopRotating() }
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/api/v1/memories",
                    body: MemoryCreateRequest(text: text, sessionId: sessionID, title: title, memoryDate: memoryDate),
                    timeout: 120, as: MemoryCreateResponse.self)
            }
            guard let id = r.memoryId, !id.isEmpty else { throw CreateError.badResponse }
            if let url = audioURL, let data = try? Data(contentsOf: url) {
                _ = try? await withAuth(auth) {                       // best-effort — text memory still valid
                    try await APIClient.shared.postMultipart("/api/v1/memories/\(id)/media",
                        fileData: data, fileName: url.lastPathComponent, mimeType: Self.mime(url), timeout: 120)
                }
            }
            return id
        } catch CreateError.sessionEnded {
            errorText = "Your session has ended. Please sign in again."; return nil
        } catch {
            errorText = "We couldn’t save that just now. Your recording is safe — tap to try again."; return nil
        }
    }

    private static func mime(_ url: URL) -> String {
        switch url.pathExtension.lowercased() { case "wav": return "audio/wav"; case "mp4": return "audio/mp4"; default: return "audio/m4a" }
    }
    private func startRotating() {
        processingMessage = Self.messages[0]
        rotate = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if Task.isCancelled { break }
                i = min(i + 1, Self.messages.count - 1)
                processingMessage = Self.messages[i]
            }
        }
    }
    private func stopRotating() { rotate?.cancel(); rotate = nil }
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw CreateError.sessionEnded
        }
    }
}
```

## RecordView.swift — stage machine + real save (key diffs)
```diff
 struct RecordView: View {
     @Environment(\.dismiss) private var dismiss
     @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
+    @ObservedObject var auth: AuthManager
+    var onSaved: (() -> Void)? = nil
@@
     @StateObject private var transcriber = Transcriber()
+    @StateObject private var saver = MemoryCreateViewModel()
@@
-    @State private var saved = false
+    @State private var stage: Stage = .compose
+    @State private var sessionID = ""
+    @State private var reviewText = ""        // editable on-device transcript (Speak)

+    enum Stage: Equatable { case compose, reviewing, processing, done, failed(String) }
```
Body switches on `stage`: `.compose` → current topBar + ModeSwitcher + speak/type; `.reviewing` → review screen;
`.processing` → processing screen (no X); `.done` → savedView; `.failed` → failed screen.

Record start / stop:
```diff
-                micButton(systemName: "mic.fill") { recorder.startRecording() }
+                micButton(systemName: "mic.fill") { beginRecording() }
```
```diff
     private func stopRecording() {
         Haptics.recordStop()
         recorder.stopRecording()
         if let url = recorder.lastRecordingURL {
             MediaStore.shared.add(CapturedMedia(image: nil, kind: .audio, videoURL: nil, fileName: url.lastPathComponent))
+            transcriber.transcribe(url: url)            // auto-transcribe for the review screen
         }
-        withAnimation { saved = true }
+        reviewText = ""
+        withAnimation { stage = .reviewing }
     }
+    private func beginRecording() { sessionID = UUID().uuidString; recorder.startRecording() }
```
Type Save + review Save → submit:
```diff
-    private func saveMemory() {
-        // Real: POST /api/v1/memories { title?, memory_date?, content: bodyText }
-        withAnimation { saved = true }
-    }
+    private func saveMemory() { submit(text: bodyText, audio: nil) }   // Type mode
+    private func submit(text: String, audio: URL?) {
+        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
+        if sessionID.isEmpty { sessionID = UUID().uuidString }         // Type mode has no record start
+        let md = Self.strictYMD(dateText)
+        let ttl = title.trimmingCharacters(in: .whitespaces); let titleOpt = ttl.isEmpty ? nil : ttl
+        withAnimation { stage = .processing }
+        Task {
+            let id = await saver.save(text: t, sessionID: sessionID, title: titleOpt, memoryDate: md, audioURL: audio, auth: auth)
+            if id != nil { onSaved?(); withAnimation { stage = .done } }
+            else { withAnimation { stage = .failed(saver.errorText ?? "Couldn’t save.") } }
+        }
+    }
+    private static func strictYMD(_ s: String) -> String? {
+        let t = s.trimmingCharacters(in: .whitespaces)
+        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
+        return f.date(from: t) != nil ? t : nil                        // free-text prose → omitted
+    }
```
New screens (sketch — match existing design tokens):
- `reviewingView`: "Your words" + a TextEditor bound to `reviewText` (auto-filled from `transcriber.transcript`
  while `transcriber.isTranscribing`; editable after), the existing `playbackBar`, a "Save memory" button
  (disabled until non-empty) → `submit(text: reviewText, audio: recorder.lastRecordingURL)`, and a small status
  line ("Transcribing…" / "Couldn’t transcribe — type it above."). Type mode keeps its inline Save.
- `processingView`: spinner + `saver.processingMessage` (rotating) + "This can take up to a minute." — no X, no
  Save (blocks double-submit / navigation-away).
- `failedView`: message (`saver.errorText`) + "Try again" (re-`submit` with preserved `reviewText`/`bodyText` +
  audio) + "Back" (→ `.reviewing` for Speak, `.compose` for Type). Recording + text preserved in @State.
- `.done` → existing `savedView` (Done → `dismiss()`).
Remove `transcribeScaffold` (temp) entirely.

## Call sites — pass auth + onSaved
```diff
 // HomeView.swift:61
-            .fullScreenCover(isPresented: $showRecord) { RecordView() }
+            .fullScreenCover(isPresented: $showRecord) { RecordView(auth: auth) { Task { await memoriesVM.refresh(auth: auth) } } }
 // MemoriesView.swift:32
-        .fullScreenCover(isPresented: $showRecord) { RecordView() }
+        .fullScreenCover(isPresented: $showRecord) { RecordView(auth: auth) { Task { await vm.refresh(auth: auth) } } }
 // TimelineView.swift:33
-        .fullScreenCover(isPresented: $showRecord) { RecordView() }
+        .fullScreenCover(isPresented: $showRecord) { RecordView(auth: auth) }
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the 120s blocking create + multipart upload + on-device Speech
transcription are device/backend checks I can't run here. memory_date omitted unless strict YYYY-MM-DD;
`/memories/voice` deliberately unused; media upload best-effort; failure preserves transcript + recording;
direct navigate-to-new-memory deferred (Memories refresh instead). No git.
