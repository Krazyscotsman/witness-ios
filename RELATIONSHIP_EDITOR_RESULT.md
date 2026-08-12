# Witness — Relationship anchor editor (PUT /timeline/relationships/{id}) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git. First real write to the truth registry.

## Applied
- **APIModels.swift** — `RelationshipUpdateRequest` (`nonisolated`): EXACTLY the 22 allowlisted columns;
  `nbq_response`/`person_canonical_name` are structurally absent (impossible to send). snake_case CodingKeys.
- **AuthManager.swift** — `updateRelationship(id:_:)` → `PUT /timeline/relationships/{id}` (bare path) via the
  existing `putIgnoringResponseBody` (any-2xx success, `{status}` ignored). 20s.
- **AnchorRegistry.swift** — `RelationshipRow` gained the two missing allowlist fields (`familyRole`,
  `datePrecision`); "Family role" added to read-only detail rows.
- **RelationshipEditor.swift (new)** — `RelationshipVocab` (46 types / 13 family roles / significance /
  precision / privacy, verbatim from the confirmed spec); `RelSanitize` (snakeKey, POSIX ISO dates, snakeKey
  round-trip pre-selection); `RelationshipListView` (relationships-only, search/sort, routes to the editable
  detail); `RelationshipDetailView` (read mode + edit mode). Edit mode shows ALL 22 fields (empty ones as
  editable inputs), selects bound to the vocab, date pickers with a 1910 floor, "Your Story" read-only, client
  validation (type required; dates ≥ 1910-01-01; end ≥ start), busy state, friendly errors that preserve
  edits, optimistic local update + `vm.refresh` on success. Delete stays inert.
- **AnchorRegistryView.swift** — `AnchorRelationshipsView` takes `auth` and routes both relationship links
  (Critical People + type chips) to `RelationshipListView`. The other 6 categories + the generic
  list/detail are untouched.

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (RelationshipEditor, AnchorRegistry, APIModels, AnchorRegistryView,
  AuthManager).
- **snakeKey ran over every vocabulary value** (RunCodeSnippet). All produce clean `lowercase_snake`. The two
  flagged cautions resolve correctly: **In-Law Parent → `in_law_parent`** (also in_law_sibling / in_law_child),
  **Family Only → `family_only`**. Round-trip confirmed: `option(for:"in_law_parent")` → "In-Law Parent",
  `option(for:"family_only")` → "Family Only" (so a stored value pre-selects the right chip). No hardcoded
  overrides were needed — snakeKey matches the backend's stored form for all enums.

## Honest scope / caveats
- **The live PUT round-trip is NOT exercised here** (no backend on this machine). Verified: the body is
  structurally the 22 columns only, sanitization is correct (proven above), validation blocks bad input.
  Unverified until a device test: that the server accepts each enum value and returns `200 success`/`no_change`,
  and that ownership/auth behave. Recommend a first device pass editing ONE record (ideally an **In-Law** and a
  **Family Only** one) and confirming persistence via relaunch before trusting bulk edits.
- **In-Law stored form** is confirmed by the spec's "relationship_type stored snake_case" + snakeKey output,
  but the web `page.tsx` FIELD_CONFIG isn't on this machine to byte-compare — the one-record device check
  closes that.
- **Names:** editable and sent now; the anchors-list/graph **display name may lag** until backend
  name-propagation (Gap 1) lands — by design, not gated. The relationship row itself updates immediately.
- Delete remains inert (backend Gap 2). Relationships only — no create/delete, no other categories.

## No git.
