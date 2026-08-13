# Witness — Education anchor category (view + edit + create) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git. Group A (POST mints an entity).

## Applied
- **AnchorFormKit.swift** — added reusable `anchorToggleField(label, Binding<Bool>)`.
- **APIModels.swift** — `EducationWriteRequest` (`nonisolated`): EXACTLY the 13 allowlist columns;
  `degreeAchieved: Bool`, the other 12 `String`; snake_case. **No `date_precision`** (structurally absent).
- **AuthManager.swift** — `updateEducation(id:_:)` / `createEducation(_:)` (bare `/timeline/education`, any-2xx).
- **EducationEditor.swift (new)** — `EducationVocab` (institutionType 6 / attendanceMode 3, no precision),
  `EducationDraft` (`writeRequest()` — selects→snakeKey, 3 dates→ISO POSIX, `degreeAchieved` Bool straight
  through; `validationError(requireName:)` requires institution_name), `EducationFormView` (AnchorFormKit + the
  toggle, no Your Story, 3 date fields), vm-reactive `EducationListView` + "Add New", `EducationCreateView`
  (defaults **attendance_mode = In-person, degree_achieved = false**), `EducationDetailView` (read shows
  Degree achieved as Yes/No via existing detailFields; read + edit; inert Delete).
- **AnchorRegistryView.swift** — education tile → `EducationListView(vm:auth:)`. Others untouched.
- No `EducationRow` change needed — it already had all fields (incl. `degreeAchieved: Bool?`, `graduationDate`,
  and no `datePrecision`).

## Verified (executed, not asserted)
- Build **0/0**; per-file diagnostics clean (EducationEditor, AnchorFormKit, APIModels, AuthManager,
  AnchorRegistryView). (AnchorFormKit hit the transient SourceEditor error 5 once; cleared on retry.)
- **`EducationDraft.writeRequest()` emits exactly the 13 allowlist columns** (RunCodeSnippet): count 13,
  `Set(keys) == allowlist` true; **`date_precision` absent**; **none of the 13 never-send columns present**
  (date_precision/grade_start/grade_end/residence_location_id/living_location_context/school_context/
  sequence_order/institution_entity_id/entity_id/created_at/updated_at/id/narrator_id).
- **`degree_achieved` serializes as a JSON bool** — `obj["degree_achieved"] is Bool` = true, and the raw JSON
  contains `"degree_achieved":true` (not `"true"`).
- **Selects map right:** `Online Course → online_course`, `In-person → in_person`.
- **Mode validation:** create with no name → "Please enter a school or institution name."; edit with no name → OK.

## Honest scope / caveats
- **Live PUT/POST round-trip NOT exercised here** (no backend on this machine). Verified: body is structurally
  the 13 columns, sanitization correct + Bool encodes correctly (executed), validation blocks bad input, list
  is vm-reactive. Unverified until a device pass: server returns 2xx, create trigger mints the entity, new
  record surfaces. Recommend: Add New (In-person + degree_achieved off) → toggle Degree achieved on → save →
  confirm it appears and Degree achieved shows Yes; edit one; confirm `Online Course` persists as
  `online_course`.
- Delete stays inert; education only; no `/continuity/truths`.

## No git.
