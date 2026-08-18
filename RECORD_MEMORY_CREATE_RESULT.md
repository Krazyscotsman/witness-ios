# Witness — Wire real memory creation + debug cleanup + Info.plist check — Result

Date: 2026-08-18. **Build: "The project built successfully" (0 errors).** Per-file live diagnostics **0/0**
across all touched/new files. No git. iOS-only (endpoints already exist).

---

## 1) RecordView now really saves (POST /memories + best-effort media)

### New / changed files
- **APIModels.swift** — added `MemoryCreateRequest` (custom `encode` → **omits** nil `title`/`memory_date`;
  `session_id` snake key) and `MemoryCreateResponse` (`memory_id` via CodingKeys, decoded by the default
  decoder; `resolved_entities` intentionally unmodeled). Both `nonisolated`.
- **APIClient.swift** — added `postMultipart(_:fileData:fileName:mimeType:fieldName:authorized:timeout:)`
  (multipart/form-data, single file part, any-2xx = success, 401 surfaced for refresh+retry). Same error
  shape as the other methods.
- **MemoryCreateViewModel.swift (NEW)** — `@MainActor`, `import Combine`. `save(text:sessionID:title:memoryDate:
  audioURL:auth:) -> String?`:
  1. `POST /api/v1/memories` — **120s** timeout (blocks on extraction), **401 → refresh → retry-once**, returns
     `memory_id`.
  2. If audio: `POST /api/v1/memories/{id}/media` multipart — **best-effort** (`try?`; text memory valid if it
     fails).
  - **Rotating processing copy** ("Saving…" → "Understanding it…" → "Finding the people and places…" →
     "Weaving it into your story…" → "Almost there…", ~7s cadence, cancelled on resolve).
  - On failure returns **nil** + sets `errorText` ("…Your recording is safe — tap to try again.").
- **RecordView.swift** — stage machine `compose → reviewing (Speak) → processing → done | failed`:
  - Takes `auth: AuthManager` + `onSaved: (() -> Void)?`.
  - `session_id` UUID minted at **capture start** (Speak `beginRecording`) / at **submit** (Type).
  - Speak stop → auto on-device transcribe → **REVIEW screen**: editable transcript (auto-fills while
     recognizing, then hands off to the user), Title/date fields, playback bar, "Save memory"; "Re-record"
     returns to capture. Status line covers running/denied/unavailable/no-speech (falls back to typing).
  - `submit` validates non-empty, sends `memory_date` **only if strict yyyy-MM-dd** (else omitted), title if
     non-empty; disables re-entry while processing.
  - **Processing screen** has **no dismiss control** → guards navigation-away / double-submit.
  - **Failure screen** preserves transcript + recording; "Try again" re-submits the same; "Back" returns to
     review (Speak) / compose (Type).
  - Success → "Saved" confirmation + **`onSaved?()`** and Done dismisses.
  - **Removed** the temporary "Transcribe (temp)" scaffold.
- **Call sites** — `HomeView` and `MemoriesView` pass `RecordView(auth: auth) { refresh Memories }`;
  `TimelineView` passes `RecordView(auth: auth)` (closes on save; no list to refresh).

### Decisions (as approved)
- Review-then-save screen added; temp scaffold removed.
- `memory_date` omitted unless strict `yyyy-MM-dd` (backend extracts from text). A date picker would be
  cleaner later; not required now.
- `/memories/voice` deliberately **not** used (keeps the on-device transcript).
- New memory surfaced via Memories refresh; direct navigate-to-detail deferred.

## 2) DEBUG logging removed (graph + witness confirmed working)
- **APIClient.swift** — removed both `🩺[WitnessStart]`/`🩺[Graph]` `#if DEBUG` print blocks in `request(...)`
  (transport-error + response-body logging).
- **GraphViewModel.swift** — removed `🩺[Graph] caught:` print.
- **AskScarlettView.swift** — removed both `🩺[WitnessStart] caught:` prints (start + whole-life start).

## 3) Info.plist — already correct (no edit needed)
- **:6 `CFBundleIdentifier`** = `$(PRODUCT_BUNDLE_IDENTIFIER)` — **not blank**.
- **:28 `UIAppFonts`** = `PlayfairDisplay-SemiBold.ttf` — **no leading space**.
- Both were fixed in a prior session; the PRE_TEST_AUDIT note is stale. Confirmed against the live file + a
  clean build. No change made.

---

## Verified
- **BuildProject → "The project built successfully"** (0 errors).
- Live diagnostics **0 issues**: RecordView, MemoryCreateViewModel, APIClient, APIModels, HomeView,
  MemoriesView, TimelineView, GraphViewModel, AskScarlettView.
- New file compiled + linked (synchronized Xcode group auto-included it — no manual target step).

## Honest caveats (device + backend checks — cannot run here)
- The **120s blocking create**, the **multipart media upload**, and the **on-device Speech transcription**
  (permission prompt + quality) are runtime behaviors verified only by compile + logic read-through. A device
  pass confirms: the ~minute wait with rotating copy, the transcript round-trip into the create call, the
  media attach, the 401→refresh path, and the failure-preserves-recording flow.
- `resolved_entities` in the create response is not surfaced (untyped, unused).

## No git.
