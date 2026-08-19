# Witness — Memoir feature wired (config → atmosphere → generate → PDF) — Result

Date: 2026-08-18. **Build: "The project built successfully" (0 errors).** Per-file live diagnostics **0/0**.
No git. iOS-only (generation is server-side).

## Applied
- **APIModels.swift** — `MemoirGenerateRequest` (root generate; omits nil start/end/dedication; snake CodingKeys),
  `MemoirGenerateResponse` (reads `status`/`message`; pdf_url/download_url/chapter_count/word_count/memories_used),
  `MemoirAtmospherePromptsResponse` + `MemoirPeriodDTO` + `MemoirPromptDTO` (snake decoder), `MemoirAtmosphereRequest`
  (snake CodingKeys). All `nonisolated`.
- **MemoirViewModel.swift (NEW)** — `generate()` → **ROOT** `POST /memoir/generate`, **900s**, 401→refresh,
  **double-tap guarded**; **reads `status` from the body** (200 can still be `{status:"error"}`). `preparePDF()`
  downloads (prefer `download_url`, Bearer iff host==base), caches on-device (caches/Memoirs), exposes a local
  file URL for viewer + share. `reset()`.
- **MemoirAtmosphereViewModel.swift (NEW)** — `load()` → `GET /api/v1/memoir/atmosphere-prompts`, filters
  `has_atmosphere_data == false` (fallback all); `submit()` best-effort POSTs each non-empty answer to
  `POST /api/v1/memoir/atmosphere`. Degrades to skip on failure/empty.
- **PDFKitView.swift (NEW)** — `UIViewRepresentable` around `PDFView` (continuous vertical, auto-scale), loads
  the cached local file.
- **MemoirView.swift** — VM-driven phases `config / generating / ready / failed`. Config defaults per spec:
  title **"My Life Story"**, `include_images` **true**, **four** length presets (short 3000 / medium 20000 /
  long 40000 / book 70000; default book). `startGenerate()` loads prompts first when atmosphere is toggled and
  only presents the interview if there are periods (else generates directly; button shows "Preparing…").
  **Generating** = honest indeterminate spinner + copy (no progress bar, no fake chapter count); the Insights
  back button is **disabled while generating** (guard nav). **Ready** = real stats (words / chapters /
  memories), inline **PDFKitView**, **ShareLink** (download/share), "Create another". **Failed** = message +
  "Try again" (config preserved) / "Back to settings".
- **AtmosphereModal.swift** — reworked to consume the real `MemoirPeriodDTO`s: one period at a time, dot
  progress, multi-line fields, "optional but encouraged", Back/Next, Skip-All; collects answers and POSTs the
  non-empty ones (with life_period/location/year_start/year_end/prompt_category/prompt_text/response_text)
  before generating. Sample models removed.
- **InsightsView.swift:33** — `case "memoir": MemoirView(auth: auth)`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors, ~7s).
- Live diagnostics **0 issues**: APIModels, MemoirViewModel, MemoirAtmosphereViewModel, PDFKitView, MemoirView,
  AtmosphereModal, InsightsView.
- New files auto-included by the synchronized Xcode group.

## Honest caveats (device + backend checks — cannot run here)
- The multi-minute (≤900s) **synchronous** generate, the **{status:"error"}** path, the **atmosphere-prompts
  JSON shape** (assumed `{ periods: [...] }` from the frontend — if it mismatches, the interview degrades to
  skip, non-breaking, and the DTO is a localized change), the PDF download/cache + PDFKit render, and ShareLink
  are runtime checks.
- Per approved decisions: `/memoir/preview` **not** wired (config keeps the local manuscript estimate); one
  downloaded PDF file serves both the inline viewer and the share sheet; four length presets (dropped the
  shell's Standard/Epic).

## No git.
