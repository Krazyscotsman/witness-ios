# Witness — AI image generation for memories — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only (generation is server-side). Propose-and-wait.

---

## Read-first findings

**MemoryDetailView** — `loadedBody` order: `listenSurface → narrative → emotions → quotes → askCard`. New
"Picture this memory" section goes **after quotes, before the Ask card**. `cover` band is gated by
`hasCoverPhoto == false` (left untouched). The detail VM fetches `/detail` only — no media.

**Presigned-URL handling (reuse)** — `MediaViewModel.resolvedURL(_:)` (absolute→as-is / relative→base-prefixed)
and `refreshURL(for:auth:)` (GET `/api/v1/media/{id}/url`, 401→refresh). `MediaThumb` = AsyncImage + one
refresh-on-`.failure` (`didRefresh` guard). Gallery groups by memory, renders by `file_type`.

**Local image cache** — NONE. AsyncImage/URLCache is keyed by URL, so it won't survive presigned rotation. Need
a NEW id-keyed cache + a custom loader (AsyncImage can't populate an id cache).

**`MediaItemDTO.metadata` is NOT modeled.** Both the gallery badge and per-memory render filter on
`metadata.source == "ai_generated"`. Decode `metadata` via the existing opaque `JSONValue` so a non-object
metadata can never fail the whole decode.

**Root-path POST already works** — base is `http://192.168.1.115:8000` (no `/api/v1`), so
`post("/visualize/{id}?view_angle=from_behind", …)` hits host root. 200-with-`{success:false}` is fine: `post`
decodes the 200 body → read `success` from it. **No APIClient change.**

---

## Endpoint gotchas honored
- `POST /visualize/{memory_id}?view_angle=from_behind` — **root path**, Bearer, **≥120s** timeout (synchronous
  ~20–90s). Read `success` from the **body**, not HTTP status. Success → `{success:true, media_id, url, …}`.
- Render/refresh via the existing `/api/v1/memories/{id}/media` + `/api/v1/media/{id}/url` presign path.

## Decisions / flags (recommendation first)
1. **`view_angle` hardcoded `from_behind`** for v1 (single button). Angle picker later. *Recommend.*
2. **Per-memory media response assumed `{ media: [MediaItemDTO] }`** (same service as the gallery). If the
   backend returns a bare array or different wrapper, it's a one-line DTO change — **verify on device.**
3. **v1 = append + show newest** (no DELETE/replace). Newest by `created_at` desc.
4. **Hero uses a new id-keyed cached loader** (satisfies "cache by media_id + survive expiry"); **gallery keeps
   AsyncImage/MediaThumb** (spec: reuse gallery presign-refresh) and only gains the badge.
5. **`metadata` via opaque `JSONValue`** (robust) — read `source` from the object.

---

## Proposed diffs

### APIModels.swift
Add `metadata` to `MediaItemDTO` (+ helpers), and the two new DTOs.
```swift
nonisolated struct MediaItemDTO: Decodable, Identifiable {
    let id: String
    let memoryId: String?
    let fileName: String?
    let fileType: String?
    let fileSize: Int?
    let mimeType: String?
    let url: String
    let createdAt: String?
    let memoryTitle: String?
    let memoryDate: String?
    let narratorAge: Int?
    let metadata: JSONValue?          // opaque — decode-safe regardless of shape

    // AI images are tagged by metadata.source == "ai_generated" (NOT file_type).
    var aiSource: String? {
        if case .object(let o)? = metadata, case .string(let s)? = o["source"] { return s }
        return nil
    }
    var isAIGenerated: Bool { aiSource == "ai_generated" }
}

/// GET /api/v1/memories/{id}/media — media rows for one memory (same item shape as the gallery).
nonisolated struct MemoryMediaResponse: Decodable { let media: [MediaItemDTO]? }

/// POST /visualize/{id}?view_angle=… — SYNCHRONOUS. ⚠️ Failure is HTTP 200 with {success:false,error};
/// read `success` from the body. Decoded by the DEFAULT decoder (APIClient.post) → CodingKeys map media_id.
nonisolated struct VisualizeResponse: Decodable {
    let success: Bool?
    let mediaId: String?
    let url: String?
    let error: String?
    enum CodingKeys: String, CodingKey { case success, url, error; case mediaId = "media_id" }
}
```
*(`MediaItemDTO` is decoded with the snake decoder in both VMs; `JSONValue.init` never throws, and dictionary
keys like `source` are untouched by convertFromSnakeCase.)*

### New file: AIImageCache.swift
```swift
import UIKit

/// Tiny id-keyed image cache (memory + disk) so a generated image re-displays instantly and survives presigned
/// URL expiry. Keyed by media_id (stable), unlike URLCache (keyed by the rotating presigned URL).
final class AIImageCache {
    static let shared = AIImageCache()
    private let mem = NSCache<NSString, UIImage>()
    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("AIImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    private func file(_ id: String) -> URL { dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_")) }

    func image(for id: String) -> UIImage? {
        if let m = mem.object(forKey: id as NSString) { return m }
        guard let data = try? Data(contentsOf: file(id)), let img = UIImage(data: data) else { return nil }
        mem.setObject(img, forKey: id as NSString)
        return img
    }
    func store(_ data: Data, image: UIImage, for id: String) {
        mem.setObject(image, forKey: id as NSString)
        try? data.write(to: file(id), options: .atomic)
    }
}
```

### New file: MemoryVisualizeViewModel.swift
```swift
import SwiftUI
import Combine

/// AI image generation + listing for one memory. generate() is SYNCHRONOUS server-side (~20–90s). Reuses the
/// gallery's presigned-URL resolve/refresh so the hero image behaves like the gallery.
@MainActor
final class MemoryVisualizeViewModel: ObservableObject {
    enum Phase: Equatable { case idle, generating, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var images: [MediaItemDTO] = []   // ai_generated only, newest first

    private static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }
    var hasAIImage: Bool { !images.isEmpty }

    /// Load existing AI images for the memory (called on appear and after a successful generate).
    func loadExisting(memoryId: String, auth: AuthManager) async {
        if let list = try? await withAuth(auth) {
            try await APIClient.shared.get("/api/v1/memories/\(memoryId)/media", timeout: 30,
                                           decoder: Self.snake, as: MemoryMediaResponse.self)
        } {
            images = (list.media ?? []).filter { $0.isAIGenerated }
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }   // newest first
        }
    }

    /// POST /visualize/{id}. Reads success from the body (200 can still be a failure). Guards double-tap.
    func generate(memoryId: String, auth: AuthManager) async {
        guard phase != .generating else { return }
        phase = .generating
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.post("/visualize/\(memoryId)?view_angle=from_behind",
                    body: EmptyBody(), timeout: 120, as: VisualizeResponse.self)
            }
            guard r.success == true else {
                phase = .failed(r.error?.isEmpty == false ? r.error! : "Image generation didn’t complete. Please try again.")
                return
            }
            await loadExisting(memoryId: memoryId, auth: auth)   // canonical item (with metadata + presigned url)
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            phase = .failed("We couldn’t generate the image just now. Please try again.")
        }
    }

    // Presigned-URL helpers (mirror MediaViewModel so the hero loader behaves like the gallery).
    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
    }
    func refreshURL(mediaId: String, auth: AuthManager) async -> String? {
        (try? await withAuth(auth) {
            try await APIClient.shared.get("/api/v1/media/\(mediaId)/url", timeout: 20,
                                           decoder: Self.snake, as: MediaURLResponse.self)
        })?.url
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

### New file: CachedRemoteImage.swift
```swift
import SwiftUI

/// Loads a media image by media_id with an on-disk id cache (instant re-display + survives presigned expiry).
/// Cache-first; on miss loads the presigned URL, refreshing once via /media/{id}/url on failure; caches on
/// success. (AsyncImage can't populate an id cache, so this is a small URLSession loader.)
struct CachedRemoteImage: View {
    let mediaId: String
    let rawURL: String
    @ObservedObject var vm: MemoryVisualizeViewModel
    let auth: AuthManager

    @State private var image: UIImage?
    @State private var state: LoadState = .loading
    private enum LoadState { case loading, failed }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if state == .loading {
                ZStack { WV.teal.opacity(0.06); ProgressView().tint(WV.teal) }
            } else {
                ZStack { WV.teal.opacity(0.06); Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(WT.ink.opacity(0.25)) }
            }
        }
        .task(id: mediaId) { await load() }
    }

    private func load() async {
        if let cached = AIImageCache.shared.image(for: mediaId) { image = cached; return }
        await fetch(vm.resolvedURL(rawURL), allowRefresh: true)
    }
    private func fetch(_ url: URL?, allowRefresh: Bool) async {
        guard let url else { state = .failed; return }
        var req = URLRequest(url: url)
        if url.host == APIClient.baseURL.host, let token = KeychainStore.shared.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")   // relative /file needs Bearer
        }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
           let img = UIImage(data: data) {
            AIImageCache.shared.store(data, image: img, for: mediaId)
            image = img
            return
        }
        if allowRefresh, let fresh = await vm.refreshURL(mediaId: mediaId, auth: auth) {
            await fetch(vm.resolvedURL(fresh), allowRefresh: false)
        } else {
            state = .failed
        }
    }
}
```

### MemoryDetailView.swift
- Add the VM:
```swift
@StateObject private var visualizeVM = MemoryVisualizeViewModel()
```
- Load existing AI images when the memory loads (alongside the existing `.task`):
```swift
.task { await visualizeVM.loadExisting(memoryId: listItem.id, auth: auth) }
```
- Insert the section in `loadedBody`, after quotes, before `askCard`:
```swift
if let quotes = vm.detail?.quotes, !quotes.isEmpty { quotesSection(quotes) }
aiImageSection            // ← new
askCard.padding(.top, 4)
```
- New section:
```swift
private var aiImageSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        sectionLabel("Picture this memory")
        if let hero = visualizeVM.images.first {
            CachedRemoteImage(mediaId: hero.id, rawURL: hero.url, vm: visualizeVM, auth: auth)
                .frame(maxWidth: .infinity).frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.06), lineWidth: 1))
                .overlay(alignment: .topLeading) { aiBadge.padding(10) }
        }
        generateControl
        switch visualizeVM.phase {
        case .generating:
            HStack(spacing: 10) {
                ProgressView().tint(WV.teal)
                Text("Generating your image… this can take up to a minute.")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let m):
            Text(m).font(.system(size: 12)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }
    .padding(.top, 4)
}

private var generateControl: some View {
    Button { Task { await visualizeVM.generate(memoryId: listItem.id, auth: auth) } } label: {
        HStack(spacing: 7) {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .medium))
            Text(visualizeVM.hasAIImage ? "Regenerate image" : "Generate image").font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(WV.teal).padding(.horizontal, 14).frame(height: 38)
        .background(WV.teal.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
    }
    .disabled(visualizeVM.phase == .generating)
    .opacity(visualizeVM.phase == .generating ? 0.45 : 1)
    .witnessPress()
    .witnessHint("Generate an AI image that pictures this memory.")
}

private var aiBadge: some View {
    HStack(spacing: 4) {
        Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
        Text("AI").font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
}
```

### MediaView.swift — badge AI items in the gallery
In `tile(_:big:)`, add an overlay when `item.isAIGenerated` (inside the existing ZStack, top-leading):
```swift
if item.isAIGenerated {
    HStack(spacing: 3) {
        Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
        Text("AI").font(.system(size: 9, weight: .semibold))
    }
    .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
    .background(.ultraThinMaterial, in: Capsule())
    .padding(6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
```
(Gallery presign-refresh via `MediaThumb` is unchanged; AI images already appear as `image` rows.)

---

## After approval
Apply, then **BuildProject → 0/0** + per-file diagnostics: APIModels, AIImageCache (new), MemoryVisualizeViewModel
(new), CachedRemoteImage (new), MemoryDetailView, MediaView.

Honest caveats I can't run here: the 20–90s synchronous generate, the 200-with-`{success:false}` path, presigned
image fetch/refresh + id-cache survival, and the exact `/memories/{id}/media` JSON shape (decision 2) are
device/backend checks. No git.
