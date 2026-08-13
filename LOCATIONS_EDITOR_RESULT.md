# Witness — Locations anchor category (view + edit + create) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git. Group A (POST mints a place entity).

## Applied
- **AnchorFormKit.swift (new)** — shared, stateless form builders (`anchorFormSection`/`anchorFieldLabel`/
  `anchorTextField`/`anchorMultiField`/`anchorSelectField`/`anchorDateField`) + internal `AnchorDateSheet`.
- **RelationshipEditor.swift** — `RelationshipFormView` refactored to use the kit; its private builders and the
  file-private `DateSheet` removed. Rendering + behavior unchanged (edit/create paths intact).
- **APIModels.swift** — `LocationWriteRequest` (`nonisolated`): EXACTLY the 13 allowlist columns, snake_case;
  shared by POST create + PUT edit. Legacy/entity/server columns are structurally impossible to send.
- **AuthManager.swift** — `updateLocation(id:_:)` (PUT) and `createLocation(_:)` (POST) via the existing
  put/postIgnoringResponseBody (bare paths, any-2xx).
- **AnchorRegistry.swift** — `LocationRow` gained the missing `datePrecision` (needed for edit prefill /
  optimistic update; it's in the allowlist).
- **LocationEditor.swift (new)** — `LocationVocab` (types + precision), `LocationDraft`
  (`writeRequest()` sanitizes type/precision→snakeKey, dates→ISO POSIX, country/text as-is;
  `validationError(requireName:)`), `LocationFormView` (no Your Story), vm-reactive `LocationListView` off
  `vm.locations` + "Add New" +, `LocationCreateView` (defaults **country "USA" / type "Residence" /
  precision "Month"**), `LocationDetailView` (read + edit; inert Delete).
- **AnchorRegistryView.swift** — locations dashboard tile → `LocationListView(vm:auth:)`. Other 5 read-only
  categories untouched.

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (LocationEditor, AnchorFormKit, RelationshipEditor, AnchorRegistry,
  APIModels, AnchorRegistryView, AuthManager).
- **`LocationDraft.writeRequest()` emits exactly the 13 allowlist columns** (RunCodeSnippet): count 13,
  `Set(keys) == allowlist` true, none of id/narrator_id/*_entity_id/sequence_order/place_type/created_at
  present. Values sanitized: **`Vacation Home`→`vacation_home`**, `Month`→`month`, **country `USA` left as free
  text** (not snake_cased), date `1998-07-15`.
- **Relationship regression check:** after the shared-form refactor, `RelationshipDraft.writeRequest()` still
  emits exactly **22** columns (`In-Law Parent`→`in_law_parent`) — edit path unchanged.
- **Mode validation:** location create with no name → "Please enter a place name."; edit with no name → OK.

## Iteration (honest)
One build error on the first pass (0 warnings): `LocationRow` had no `datePrecision` (I'd only added it to
`RelationshipRow` earlier) — the edit prefill/optimistic update referenced it. Added the field; rebuilt clean.

## Honest scope / caveats
- **Live PUT/POST round-trip NOT exercised here** (no backend on this machine). Verified: body is structurally
  the 13 columns, sanitization correct (executed), validation blocks bad input, list is vm-reactive so a
  created/edited place appears after refresh. Unverified until a device pass: server returns 2xx, the create
  trigger mints the place entity (is_anchor=true), and the new place surfaces. Recommend: Add New a place
  (defaults USA/Residence/Month prefilled) → save → confirm it appears; edit an existing place; confirm
  `Vacation Home` persists as `vacation_home`.
- Delete stays inert; locations only; no `/continuity/truths`.

## No git.
