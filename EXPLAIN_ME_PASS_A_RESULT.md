# Witness — Explain Me Pass A (Overview + VM + helpers) — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIModels.swift** — `ExplainOverview` (+ nested `Summary`/`DataAvailable`) and the 4 preview element DTOs
  `ExForceDTO`/`ExPatternDTO`/`ExBreakingDTO`/`ExContradictionDTO`. All `nonisolated`, camelCase (decoded via
  `.convertFromSnakeCase`, no CodingKeys), descriptive text optional, arrays `[String]?`.
- **ExplainViewModel.swift (new)** — `@MainActor` + `import Combine`; `overviewState`/`overview`; `loadOverview`
  (GET /overview, 30s, lazy guard, 401→refresh→retry), `retryOverview`; shared `.convertFromSnakeCase` decoder.
- **ExplainView.swift (rewritten)** — takes `auth` + `@StateObject vm`; `.task { loadOverview }`. Overview
  renders real data: headline hero, **stat cards from `data_available.*_count` (true totals, independent of the
  top-5 previews)**, preview cards from `summary.*`; `has_enough_data == false` (or nothing) → gentle
  "still forming"; loading spinner; failed → retry. The 4 preview card renderers rewired to the DTOs. The six
  detail tabs show a neutral "coming together…" placeholder (Pass B). Removed `ExplainSample` + 8 sample structs
  + `ExConfidence`/`confidenceBadge`. Defensive `safeArr`/`pretty`(=AnchorText.titleCase)/`orDash`.
- **InsightsView.swift** — `case "explain": ExplainView(auth: auth)`.

## Verified
- Build **0/0**; per-file diagnostics clean (ExplainView, ExplainViewModel, APIModels, InsightsView).
  (ExplainView hit the transient SourceEditor error 5 once; cleared on retry.)

## Honest scope
- **Live /overview round-trip NOT exercised here** (no backend). The slow Gemini headline, real counts vs
  top-5 previews, and null-heavy fields are a device check. Overview decode is fully lenient (no field can
  crash it). The six detail tabs are placeholders until Pass B.

## No git. Pass B proposed next.
