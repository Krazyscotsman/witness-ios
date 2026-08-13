# Witness — Jobs & Career anchor category (view + edit + create) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git. Group A (POST mints an organization entity).

## Applied
- **AnchorRegistry.swift** — `JobRow` gained the missing `datePrecision` (allowlisted; needed for edit
  prefill / optimistic update). Same gap `LocationRow` had.
- **APIModels.swift** — `JobWriteRequest` (`nonisolated`): EXACTLY the 17 allowlist columns, snake_case; shared
  POST create + PUT edit. Never-send columns are structurally impossible.
- **AuthManager.swift** — `updateJob(id:_:)` (PUT) / `createJob(_:)` (POST) via put/postIgnoringResponseBody
  (bare `/timeline/jobs`, any-2xx).
- **JobEditor.swift (new)** — `JobVocab` (employmentType 6 / workMode 3 / precision 3), `JobDraft`
  (`writeRequest()` — enums via `RelSanitize.snakeKey`, dates ISO POSIX, text as-is; `validationError(requireName:)`
  requiring employer_name), `JobFormView` (AnchorFormKit, no Your Story), vm-reactive `JobListView` off
  `vm.jobs` + "Add New" +, `JobCreateView` (defaults **Full-time / On-site / Month**), `JobDetailView`
  (read + edit; inert Delete).
- **AnchorRegistryView.swift** — jobs tile → `JobListView(vm:auth:)`. Other categories untouched.

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (JobEditor, AnchorRegistry, APIModels, AuthManager, AnchorRegistryView).
- **Hyphenated-select mapping** (RunCodeSnippet, pre-build): all 12 select values → exact stored forms —
  **Full-time→full_time, Part-time→part_time, On-site→on_site**, contract/freelance/internship/volunteer/
  remote/hybrid/day/month/year. snakeKey suffices; no hardcoded table.
- **`JobDraft.writeRequest()` emits exactly the 17 allowlist columns** (RunCodeSnippet, post-build): count 17,
  `Set(keys) == allowlist` true, **none of the 12 never-send columns present** (residence_location_id,
  living_location_context, salary_range, concurrent_education, concurrent_family, sequence_order,
  employer_entity_id, entity_id, created_at, updated_at, id, narrator_id). Values: `employment_type=full_time`,
  `work_mode=on_site`, `date_precision=month`.
- **Mode validation:** create with no name → "Please enter an employer name."; edit with no name → OK.

## Honest scope / caveats
- **Live PUT/POST round-trip NOT exercised here** (no backend on this machine). Verified: body is structurally
  the 17 columns, sanitization correct (executed), validation blocks bad input, list is vm-reactive so a
  created/edited job appears after refresh. Unverified until a device pass: server returns 2xx, the create
  trigger mints the organization entity (is_anchor=true), and the new job surfaces. Recommend: Add New a job
  (defaults Full-time/On-site/Month prefilled) → save → confirm it appears; edit one; confirm `Full-time`
  persists as `full_time` and `On-site` as `on_site`.
- Read-mode enum display uses titleCase (e.g. stored `full_time` shows as "Full Time") — cosmetic, consistent
  with the other categories; edit round-trips correctly via snakeKey matching.
- Delete stays inert; jobs only; no `/continuity/truths`.

## No git.
