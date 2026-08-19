# Witness — AI image generation for memories — Result

Date: 2026-08-18. **Build: "The project built successfully" (0 errors).** Per-file live diagnostics **0/0**.
No git. iOS-only (generation is server-side).

## Applied
- **APIModels.swift**
  - `MediaItemDTO` gains `metadata: JSONValue?` (opaque → decode-safe for any shape) + `aiSource` / `isAIGenerated`
    (reads `metadata.source == "ai_generated"`, **not** file_type).
  - New `MemoryMediaResponse { media: [MediaItemDTO]? }` and `VisualizeResponse { success, media_id (CodingKeys),
    url, error }`.
- **AIImageCache.swift (NEW)** — id-keyed image cache (NSCache + disk in caches/AIImages), keyed by `media_id`
  so a generated image re-displays instantly and survives presigned-URL rotation.
- **MemoryVisualizeViewModel.swift (NEW)** — `@MainActor`, `import Combine`.
  - `generate(memoryId:auth:)` → `POST /visualize/{id}?view_angle=from_behind` (**root path**, `EmptyBody`,
    **120s**, 401→refresh). **Reads `success` from the 200 body**; failure → `.failed(error)`. **Double-tap
    guarded** (`phase != .generating`). On success reloads the memory's media.
  - `loadExisting` → `GET /api/v1/memories/{id}/media` → keep `isAIGenerated` items, newest first (`created_at`
    desc).
  - `resolvedURL` / `refreshURL` mirror `MediaViewModel` (presign refresh via `/api/v1/media/{id}/url`).
- **CachedRemoteImage.swift (NEW)** — cache-first by `media_id`; on miss loads the presigned URL via URLSession
  (adds Bearer only when the host is our base, for relative `/file` urls), refreshes once on failure, caches on
  success; graceful placeholder otherwise.
- **MemoryDetailView.swift** — added `visualizeVM`; loads existing AI images on appear; new **"Picture this
  memory"** section (after quotes, before Ask card): newest AI image as a hero with an **AI/sparkle badge**, a
  **"Generate image" / "Regenerate image"** button, an honest **"Generating… up to a minute"** spinner, and a
  failure line. Button disabled while generating.
- **MediaView.swift** — gallery tiles show a small **AI/sparkle badge** where `item.isAIGenerated`; presign
  refresh (`MediaThumb`) unchanged; AI images already appear as `image` rows.

## Verified
- **BuildProject → "The project built successfully"** (0 errors, ~6s).
- Live diagnostics **0 issues**: APIModels, AIImageCache, MemoryVisualizeViewModel, CachedRemoteImage,
  MemoryDetailView, MediaView.
- New files auto-included by the synchronized Xcode group (no manual target step).

## Honest caveats (device + backend checks — cannot run here)
- The 20–90s **synchronous** generate, the **200-with-`{success:false}`** failure path, the presigned image
  fetch/refresh + id-cache survival across expiry, and the **exact `/api/v1/memories/{id}/media` JSON shape**
  (assumed `{ media: [...] }`, same service as the gallery) are runtime checks. If that endpoint returns a bare
  array or a different wrapper, `MemoryMediaResponse` is a one-line change.
- `view_angle` is hardcoded `from_behind` for v1; v1 appends + shows newest (no DELETE/replace).
- `VisualizeResponse.url` is decoded but unused — the hero renders from the reloaded media item (canonical,
  carries metadata + a fresh presigned url).

## No git.
