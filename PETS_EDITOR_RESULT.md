# Witness — Pets anchor category (view + edit + create) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git. Group A (POST mints a pet entity).

## Applied
- **APIModels.swift** — `PetWriteRequest` (`nonisolated`): EXACTLY the 9 allowlist columns, all `String`,
  snake_case. No `date_precision`; no extraction/jsonb columns.
- **AuthManager.swift** — `updatePet(id:_:)` / `createPet(_:)` (bare `/timeline/pets`, any-2xx).
- **PetEditor.swift (new)** — `PetVocab` (petType 8 only), `PetDraft` (`writeRequest()` — **only `pet_type` →
  snakeKey**; dates → ISO POSIX; **significance + all other text → trim verbatim**; `validationError(requireName:)`
  requires pet_name), `PetFormView` (pet_type select, **significance plain `anchorTextField`**, no Your Story,
  no precision), vm-reactive `PetListView` + "Add New", `PetCreateView` (no special defaults), `PetDetailView`
  (read shows significance raw via existing detailFields; read + edit; inert Delete).
- **AnchorRegistryView.swift** — pets tile → `PetListView(vm:auth:)`. Others untouched.
- No `PetRow` change — it already had all 9 fields and no `datePrecision`.

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (PetEditor, APIModels, AuthManager, AnchorRegistryView).
  (APIModels hit the transient SourceEditor error 5 once; cleared on retry.)
- **`PetDraft.writeRequest()` emits exactly the 9 allowlist columns** (RunCodeSnippet): count 9,
  `Set(keys) == allowlist` true; **`date_precision` absent**; **none of the never-send columns present**
  (date_precision/pet_entity_id/entity_id/created_at/updated_at/name/animal_name/species/age_in_memory/sex/id/
  narrator_id).
- **`pet_type` maps:** `Dog → dog`.
- **`significance` is FREE TEXT:** input "childhood best friend" serializes **unchanged** (`== input` true) —
  not snakeKey'd.
- **Mode validation:** create with no name → "Please enter your pet’s name."; edit with no name → OK.

## Honest scope / caveats
- **Live PUT/POST round-trip NOT exercised here** (no backend on this machine). Verified: body is structurally
  the 9 columns, sanitization correct incl. significance-verbatim (executed), validation blocks bad input, list
  is vm-reactive. Unverified until a device pass: server returns 2xx, create trigger mints the pet entity, new
  pet surfaces. Recommend: Add New a pet (Type Dog, Significance "childhood best friend") → save → confirm it
  appears and significance shows verbatim; edit one; confirm `Dog` persists as `dog`.
- Delete stays inert; pets only; no `/continuity/truths`.

## No git.
