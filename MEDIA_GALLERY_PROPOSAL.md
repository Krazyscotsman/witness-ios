# Witness — Media Gallery (read side) → GET /api/v1/media/gallery — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Read-only (upload/delete = separate/later).

## Read-first
- MediaView renders `MediaGroup.samples` (hardcoded). No networking today — tiles use a local `UIImage?`
  (`item.image`) or a gradient+SF Symbol placeholder. NO `AsyncImage` anywhere yet. Current `delete` is
  LOCAL-only (mutates the sample array + MediaStore) — never calls the backend.
- API base: `APIClient.baseURL = URL(string: "http://192.168.1.115:8000")!` (the one host line).
- ⚠️ SHARED: `MediaKind`, `MediaStore`, `CapturedMedia`, `CaptureControl` are used by RecordView (:323) and
  MemoriesView (:62). MUST NOT remove/rename. Only local `MediaItem`/`MediaGroup` (MediaView-private) are safe
  to replace.
- ⚠️ AsyncImage can't send Bearer → a relative `/media/{id}/file` url fails first, then the refresh→presigned
  fallback recovers it. This is both the spec's retry and the auth workaround.

## Decisions (recommended defaults; change any)
1. REMOVE Select mode + selection bar + delete (grid + lightbox) — local/fake vs real data; real delete = write,
   later. (Deletes existing code — approval requested.)
2. KEEP capture `+` + "Recently added" local staging (MediaStore) untouched — working, used elsewhere, honest
   pending-upload staging above the backend gallery.
3. Lightbox → read-only viewer (image / audio / video+doc info); drop delete + "Open file" TODO.
4. First page only (limit=50); pagination later.
5. Remote audio via AudioPlayer per spec; honest caveat: AVAudioPlayer is local-file-oriented (remote may need
   download-to-temp later).

---

## APIModels.swift — DTOs (append)
```swift
// MARK: - Media gallery (GET /api/v1/media/gallery) — read side. .convertFromSnakeCase; `metadata` is an
// untyped/loose dict, intentionally NOT modeled. `url` is absolute presigned OR relative /api/v1/media/{id}/file.
nonisolated struct MediaGalleryResponse: Decodable {
    let media: [MediaItemDTO]?
    let total: Int?
    let limit: Int?
    let offset: Int?
}
nonisolated struct MediaItemDTO: Decodable, Identifiable {
    let id: String
    let memoryId: String?
    let fileName: String?
    let fileType: String?     // image | video | audio | document
    let fileSize: Int?
    let mimeType: String?
    let url: String
    let createdAt: String?
    let memoryTitle: String?
    let memoryDate: String?
    let narratorAge: Int?
    // `metadata` omitted on purpose (loose/untyped).
}
nonisolated struct MediaURLResponse: Decodable { let url: String? }   // GET /api/v1/media/{id}/url (presign refresh)
```

## New file: MediaViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class MediaViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var items: [MediaItemDTO] = []
    @Published private(set) var total = 0

    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(auth: AuthManager) async {
        if state == .loading || state == .loaded { return }
        await fetch(auth: auth)
    }
    func refresh(auth: AuthManager) async { if state == .loading { return }; await fetch(auth: auth) }

    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/media/gallery?limit=50&offset=0", timeout: 30, decoder: Self.snake, as: MediaGalleryResponse.self)
            }
            items = r.media ?? []
            total = r.total ?? items.count
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load your media. Check your connection and try again.")
        }
    }

    /// Absolute (has scheme) → as-is; relative → prefixed with the API base.
    func resolvedURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: APIClient.baseURL)?.absoluteURL
    }

    /// Presigned urls expire (~15 min). On an image load error we fetch a fresh one.
    func refreshURL(for id: String, auth: AuthManager) async -> String? {
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/media/\(id)/url", timeout: 20, decoder: Self.snake, as: MediaURLResponse.self)
            }
            return r.url
        } catch { return nil }
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

## MediaView.swift — proposed full rewrite (read-only gallery)
KEEP (untouched, shared): MediaKind, MediaStore, CapturedMedia, CaptureControl, CameraPicker (in MediaCapture.swift).
KEEP in MediaView: header, type filter (+Documents), search, grid/rows toggle, capture `+`, "Recently added"
(local staging), read-only lightbox.
REMOVE from MediaView: sample `MediaGroup.samples` + local `MediaItem`/`MediaGroup`, Select mode + selection bar
+ deleteSelected + delete, the lightbox delete + "Open file" TODO.
```swift
import SwiftUI
import UIKit

struct MediaView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MediaStore.shared
    @StateObject private var vm = MediaViewModel()
    @StateObject private var audio = AudioPlayer()

    @State private var typeFilter: String? = nil     // nil=All, else "image"/"video"/"audio"/"document"
    @State private var rows = false
    @State private var search = ""
    @State private var lightbox: MediaItemDTO?
    @State private var playingID: String?

    private var cols: [GridItem] { [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: loadingState
                case .failed(let m):  failedState(m)
                case .loaded:         content
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(auth: auth) }
        .overlay { if let item = lightbox { lightboxView(item) } }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerBlock
                typeFilterRow
                controlsRow
                if let rec = recentlyAdded { localSection(rec) }             // local staging (pending upload)
                let sections = visibleSections
                if sections.isEmpty && recentlyAdded == nil { emptyState }
                else { ForEach(sections) { section($0) } }
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    // MARK: nav + header (unchanged design; delete/select removed)
    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            }.witnessPress()
            Spacer()
            CaptureControl(style: .addButton) { store.add($0) }   // local staging; upload wired later
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View { /* unchanged: "EVERYTHING YOU'VE KEPT" / Media Gallery / subtitle */ EmptyView() }

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: typeFilter == nil) { typeFilter = nil }
                chip("Photos", active: typeFilter == "image") { typeFilter = "image" }
                chip("Video", active: typeFilter == "video") { typeFilter = "video" }
                chip("Audio", active: typeFilter == "audio") { typeFilter = "audio" }
                chip("Documents", active: typeFilter == "document") { typeFilter = "document" }
            }
        }
    }
    private func chip(_ text: String, active: Bool, _ tap: @escaping () -> Void) -> some View { /* unchanged chip */ EmptyView() }
    private var controlsRow: some View { /* unchanged: search field + grid/rows toggle */ EmptyView() }

    // MARK: sections (grouped by memory)
    struct MediaSection: Identifiable { let id: String; let title: String; let subtitle: String?; let items: [MediaItemDTO] }
    private var visibleSections: [MediaSection] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = vm.items.filter { it in
            (typeFilter == nil || (it.fileType ?? "") == typeFilter) &&
            (q.isEmpty || (it.fileName ?? "").lowercased().contains(q) || (it.memoryTitle ?? "").lowercased().contains(q))
        }
        var order: [String] = []; var buckets: [String: [MediaItemDTO]] = [:]
        for it in filtered {
            let k = it.memoryId ?? "__unlinked__"
            if buckets[k] == nil { buckets[k] = []; order.append(k) }
            buckets[k]?.append(it)
        }
        return order.map { k in
            let items = buckets[k] ?? []
            let title = items.first?.memoryTitle ?? "Unlinked media"
            return MediaSection(id: k, title: title, subtitle: subtitle(items.first), items: items)
        }
    }
    private func subtitle(_ it: MediaItemDTO?) -> String? {
        guard let it else { return nil }
        switch (it.memoryDate, it.narratorAge) {
        case let (d?, a?): return "\(d) · age \(a)"
        case let (d?, nil): return d
        case let (nil, a?): return "age \(a)"
        default: return nil
        }
    }

    private func section(_ s: MediaSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.serif(20)).foregroundStyle(WT.ink)
                if let sub = s.subtitle { Text(sub).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
            }
            if rows { VStack(spacing: 10) { ForEach(s.items) { tile($0, big: true) } } }
            else { LazyVGrid(columns: cols, spacing: 8) { ForEach(s.items) { tile($0, big: false) } } }
        }
    }

    // MARK: tile — render by file_type
    @ViewBuilder private func tile(_ item: MediaItemDTO, big: Bool) -> some View {
        let h: CGFloat = big ? 180 : 110
        Button { onTap(item) } label: {
            ZStack(alignment: .bottomLeading) {
                switch (item.fileType ?? "") {
                case "image":
                    MediaThumb(item: item, vm: vm, auth: auth, height: h)
                case "video":
                    placeholderFill(tone: Color(hex: 0x6b5b95), icon: "play.rectangle.fill", big: big)
                    Image(systemName: "play.circle.fill").font(.system(size: big ? 34 : 22)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case "audio":
                    placeholderFill(tone: Color(hex: 0xb08828), icon: "waveform", big: big)
                    if playingID == item.id {
                        Image(systemName: "pause.circle.fill").font(.system(size: big ? 34 : 22)).foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                default:
                    placeholderFill(tone: WT.ink.opacity(0.4), icon: "doc.fill", big: big)
                }
                if big, (item.fileType ?? "") != "image", let name = item.fileName {
                    Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .padding(8).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }
            }
            .frame(height: h).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: big ? 18 : 12))
            .overlay(RoundedRectangle(cornerRadius: big ? 18 : 12).stroke(WT.ink.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    private func placeholderFill(tone: Color, icon: String, big: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [tone.opacity(0.30), tone.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: big ? 40 : 26, weight: .light)).foregroundStyle(tone.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onTap(_ item: MediaItemDTO) {
        switch (item.fileType ?? "") {
        case "audio": Task { await toggleAudio(item) }
        default: lightbox = item
        }
    }
    private func toggleAudio(_ item: MediaItemDTO) async {
        if playingID == item.id { audio.stop(); playingID = nil; return }
        // Prefer a fresh presigned url (AVAudioPlayer can't send Bearer for a relative /file url).
        let raw = await vm.refreshURL(for: item.id, auth: auth) ?? item.url
        guard let u = vm.resolvedURL(raw) else { return }
        audio.load(u); audio.play(); playingID = item.id
    }

    // MARK: local staging ("Recently added") — existing UIImage tiles, unchanged behavior
    private var recentlyAdded: [CapturedMedia]? { store.captured.isEmpty ? nil : store.captured }
    private func localSection(_ items: [CapturedMedia]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently added").font(.serif(20)).foregroundStyle(WT.ink)
            Text("On this device — pending upload.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(items) { c in localTile(c) }
            }
        }
    }
    private func localTile(_ c: CapturedMedia) -> some View { /* item.image UIImage fill, else kind placeholder */ EmptyView() }

    // MARK: read-only lightbox (image full / video info / doc info; audio plays inline from the tile)
    private func lightboxView(_ item: MediaItemDTO) -> some View { /* dark cover: AsyncImage(scaledToFit) for
        image via MediaThumb-style loader, else kind icon; fileName + "from “memory”"; close button. NO delete,
        NO write "Open file". */ EmptyView() }

    // MARK: states
    private var loadingState: some View { /* spinner + "Gathering your media…" */ EmptyView() }
    private func failedState(_ m: String) -> some View { /* icon + message + Try again → vm.refresh */ EmptyView() }
    private var emptyState: some View { /* photo icon + "No media yet" + hint */ EmptyView() }
}

// MARK: - Auth-free presigned thumb with one refresh-on-error retry
private struct MediaThumb: View {
    let item: MediaItemDTO
    @ObservedObject var vm: MediaViewModel
    let auth: AuthManager
    let height: CGFloat
    @State private var url: URL?
    @State private var didRefresh = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: shimmer(loading: true)
                    case .failure: shimmer(loading: false).task { await refreshOnce() }
                    @unknown default: shimmer(loading: false)
                    }
                }
            } else { shimmer(loading: false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        .onAppear { if url == nil { url = vm.resolvedURL(item.url) } }
    }
    private func refreshOnce() async {
        guard !didRefresh else { return }
        didRefresh = true
        if let fresh = await vm.refreshURL(for: item.id, auth: auth), let u = vm.resolvedURL(fresh) { url = u }
    }
    private func shimmer(loading: Bool) -> some View {
        ZStack {
            WV.teal.opacity(0.06)
            if loading { ProgressView().tint(WV.teal) }
            else { Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(WT.ink.opacity(0.25)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```
(EmptyView() placeholders keep this doc short — the applied file writes headerBlock/chip/controlsRow/localTile/
lightboxView/loading/failed/empty in full, matching the current design. The MediaThumb loader is reused inside
the lightbox for the full-size image.)

## InsightsView.swift — pass auth
```diff
-                case "media":    MediaView()
+                case "media":    MediaView(auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live gallery round-trip (real items, presigned vs relative
urls, the AsyncImage-fail→refresh→retry path, remote audio via AVAudioPlayer) is a device/backend check.
Removed select/delete (write, later); kept local capture staging; first page only. No git.
