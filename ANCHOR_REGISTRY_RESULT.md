# Witness — Anchor Registry (categorized, read-only nav) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIClient.swift** — added a backwards-compatible `decoder: JSONDecoder = JSONDecoder()` param to
  `get`/`request` (post untouched; existing callers unaffected). Lets the registry decode raw snake_case rows.
- **AnchorRegistry.swift (new)** — `AnchorText` (titleCase for display + lowercased key for grouping; date
  formatter), `AnchorField`, `AnchorRow` protocol, and the **7 Decodable row structs** (relationships,
  locations, jobs, education, service, pets, hobbies) decoding a known subset (id required, rest optional,
  extras ignored; `person_birth_date`/`person_death_date`). `AnchorRegistryViewModel`: fetch-once 7-way
  `async let` fan-out of bare `GET /timeline/{cat}` with a `.convertFromSnakeCase` decoder; graceful
  partial-failure (all-fail → failed, any-success → loaded); 401→refresh→retry; derived counts, relationship
  chips (case-normalized grouping so no duplicates), Critical People (`significance == "critical"`).
- **AnchorRegistryView.swift (new)** — L1 dashboard ("Anchor Registry", 7 tiles reusing `AnchorCategory.all`,
  "N records"), L2 relationships subcategories (intro, pinned Critical People, per-type chips with counts;
  other categories skip to list), L3 generic record list (name + subtitle, search, sort start_date DESC else
  created_at), L4 **read-only** detail (labeled rows, nbq_response as "Your Story", **Edit/Delete laid out but
  inert + "coming soon"**). No POST/PUT/DELETE anywhere.
- **InsightsView.swift** — `case "anchors"` now opens `AnchorRegistryView(auth:)`.
- **Deleted** `AnchorsListView.swift` (Phase 1, replaced) → moved to Trash via Xcode. Entity models
  (`EntitySummary`/`EntityDetailDTO`/`LinkedMemory`) kept in APIModels (different endpoint; likely reused).

## Verification / iteration (honest)
- Final: **build 0 errors / 0 warnings**; per-file diagnostics clean for AnchorRegistry, AnchorRegistryView,
  APIClient, InsightsView.
- Took several warning-fix passes (build was 0-errors throughout): the project **defaults types to
  `@MainActor`**, so the row structs' `Decodable` conformance was main-actor-isolated but decoding runs
  nonisolated (in APIClient). Fixed by marking the whole pure data layer `nonisolated` — the 7 rows,
  `AnchorField`, `AnchorText`, the `AnchorRow` protocol, its default `story`/`typeLabel` extension, and the
  `String.nilIfEmpty` helper. Now isolation-clean. (Flagging the iteration rather than implying it was
  first-try clean.)

## Honest scope / caveats
- **NOT exercised against the live backend.** The bare-path `GET /timeline/{cat}`, snake_case decode of raw
  SELECT * rows, the 7-way fan-out / partial-failure, and case-normalized relationship chips are wired to the
  verified contract but unconfirmed on real JSON. Device pass recommended: dashboard counts; relationship
  chips don't duplicate across casings (e.g. `best_friend` vs `Best Friend`); Critical People; read-only
  detail with "Your Story"; inert Edit/Delete change nothing; a down backend → failed + working Try again;
  partial outage → the categories that responded still show.
- **Assumption:** `id` decoded as `String` (matches the app's convention; if `/timeline` returns numeric ids
  the decode would fail → surfaced as the failed state).
- Old local Truth Registry (`AnchorsView`/`AnchorsModel`) remains, unreferenced (its `AnchorCategory.all` is
  reused by the dashboard).

## No git.
