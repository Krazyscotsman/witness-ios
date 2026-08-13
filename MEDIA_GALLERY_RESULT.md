# Witness — Media Gallery (read side) → GET /api/v1/media/gallery — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git. Read-only.

## Applied
- **APIModels.swift** — `MediaGalleryResponse`, `MediaItemDTO` (`metadata` left unmodeled), `MediaURLResponse`.
  `nonisolated`, `.convertFromSnakeCase`.
- **MediaViewModel.swift** (NEW, `@MainActor` + `import Combine`) — `load()` → `GET /media/gallery?limit=50&
  offset=0` (30s, fetch-once, 401→refresh→retry), `refresh()`, `resolvedURL(_:)` (absolute as-is / relative
  prefixed with `APIClient.baseURL`), `refreshURL(for:auth:)` → `GET /media/{id}/url`.
- **MediaView.swift** (rewritten) — real gallery grouped by memory (`memory_title` + `memory_date`·age; nil →
  "Unlinked media"); tiles render by `file_type`: image → `MediaThumb` (AsyncImage), video → tone placeholder +
  play glyph → lightbox, audio → card → inline `AudioPlayer`, document → icon + name. `MediaThumb` uses the
  AsyncImage phase API: **failure → `refreshURL` once → retry** (`didRefresh` guard). Client type filter
  (incl. Documents, off the `fileType` string) + search; grid/rows toggle; read-only lightbox; loading / empty
  ("No media yet") / failed-retry.
- **Kept untouched:** capture `+`, "Recently added" local staging (`MediaStore`), and the shared `MediaKind`
  enum (restored into MediaView.swift — it lives here and is used by `CapturedMedia`/`CaptureControl`/Record/
  Memories). **Removed:** sample data + local `MediaItem`/`MediaGroup`, Select mode + selection bar + delete,
  the lightbox delete + "Open file" TODO.
- **InsightsView.swift** — `case "media": MediaView(auth: auth)`.
- **MemoriesView.swift** — updated its `MediaView()` call site to `MediaView(auth: auth)` (second entry point;
  the build caught this, then clean).

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: MediaView,
  MediaViewModel, APIModels, MemoriesView (0 issues each). No transient error 5 this pass.
- Two self-caught breaks before final green: (1) my rewrite had dropped the shared `MediaKind` enum — restored;
  (2) `MediaView()` is called from **two** places (Insights + MemoriesView) — both now pass `auth`.
- `resolvedURL` (absolute scheme → as-is; relative → prefixed) and the audio path (fresh presigned first, since
  AVAudioPlayer can't send Bearer) match the approved design.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the load/state
  machine + URL-resolve/refresh logic + defensive decode. A device pass confirms: real items, presigned-vs-
  relative urls, the **AsyncImage-fail → refresh → retry** recovery, grouping, and playback.
- **Remote audio via `AudioPlayer`** as specced — `AVAudioPlayer(contentsOf:)` is built for local files, so a
  remote presigned url may not stream reliably until a download-to-temp step is added (out of scope here).
- **First page only** (`limit=50`); load-more pagination is a follow-up (`vm.total` is captured for it).
- **Select/delete removed** (write, separate/later); **upload/capture** stays local-staging only.
- Video shows a placeholder (no thumbnail field in the contract; first-frame-from-url is heavy) + tap; no
  in-app video player yet.

## No git.
