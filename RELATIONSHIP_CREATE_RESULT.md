# Witness — Add New relationship anchor (POST /timeline/relationships) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIClient.swift** — added `postIgnoringResponseBody` (mirrors the PUT: bare-path, Bearer, any-2xx =
  success, body ignored).
- **APIModels.swift** — renamed `RelationshipUpdateRequest` → **`RelationshipWriteRequest`** (one 22-column
  struct shared by POST create + PUT edit; comment updated to cover both).
- **AuthManager.swift** — `updateRelationship` retyped to `RelationshipWriteRequest`; added
  `createRelationship(_:)` → `POST /timeline/relationships` (20s, any-2xx).
- **RelationshipEditor.swift (rewritten, DRY)** — extracted top-level **`RelationshipDraft`**
  (`writeRequest()` builds the sanitized 22-col body; `validationError(requireName:)`) and shared
  **`RelationshipFormView`** (all fields/selects/date-pickers/save-cancel; "Your Story" only when `story != nil`).
  `RelationshipDetailView` edit mode now renders the shared form and saves via `d.writeRequest()` (behavior
  unchanged). New **`RelationshipCreateView`** (empty form; optional `relationship_type` prefill; validates
  type + a name; POST → `vm.refresh` → dismiss; failure preserves input, 401→sign-in; busy state).
  `RelationshipListView` changed from a static `rows` snapshot to a vm-computed **`source`** so created/edited
  people appear reactively; gained an "Add New" **+** (prefilled with the list's type).
- **AnchorRegistryView.swift** — `anchorNavBar` gained an optional `@ViewBuilder trailing` (default EmptyView →
  other callers untouched) + an `anchorAddIcon()`; L2 relationship links use `source:`; L2 hub nav bar has an
  "Add New" **+** (no prefill).

## Edit path unchanged — confirmed
The editor still compiles and behaves identically: same `RelationshipDetailView` read/edit flow, same
`updateRelationship` PUT, same optimistic update, same 22-column body — now sourced from the shared
`RelationshipDraft.writeRequest()` that create also uses. Edit validation stays `requireName: false`.

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (RelationshipEditor, AnchorRegistryView, APIClient, AuthManager,
  APIModels).
- **`writeRequest()` emits exactly the 22 allowlist columns** (RunCodeSnippet): key count 22, `Set(keys) ==
  allowlist` true, `nbq_response`/`person_canonical_name` absent, and values sanitized
  (`In-Law Parent`→`in_law_parent`, `Family Only`→`family_only`, date `1994-06-01`). Because create and edit
  share this one struct, there is no second column list to drift — the 500-protection is inherited by create.
- **Mode-differentiated validation:** create with no name → "Please enter a first or last name."; edit with no
  name → OK; missing type → blocked in both.

## Honest scope / caveats
- **The live POST round-trip is NOT exercised here** (no backend on this machine). Verified: body is
  structurally the 22 columns only, sanitization correct (executed), validation blocks bad input, and the list
  is now vm-computed so a refreshed create/edit surfaces. Unverified until a device pass: server returns 2xx,
  the trigger mints the entity (is_anchor=true) and dedups by normalized name, and the new person appears after
  `vm.refresh`. Recommend a device test: Add New from the "Romantic" subcategory (type prefilled) → fill a
  name → save → confirm it appears; also Add New from the hub (no prefill).
- Names sent on create; anchors-list display name is authoritative from the backend (no propagation lag issue
  for create since the entity is minted fresh).
- Delete stays inert; relationships only; no create/delete for other categories; no `/continuity/truths`.

## No git.
