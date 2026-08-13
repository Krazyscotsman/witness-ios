# Witness — Pets anchor category (view + edit + create) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Mirrors education/jobs; plugs into AnchorFormKit.
Group A (POST mints a pet entity). Endpoints: PUT /timeline/pets/{id}, POST /timeline/pets (bare, Bearer,
any-2xx). Same 500-footgun → send ONLY the 9-col allowlist.

## Read-first findings
- Pets currently: generic read-only AnchorRecordListView → AnchorRecordDetailView (inert).
- PetRow ALREADY decodes all 9 allowlist fields (petName/petType/breed/startDate/endDate/howAcquired/personality/
  significance/notes); NO datePrecision (correct); detailFields shows significance RAW (free text). → no changes.
- AnchorFormKit already has text/select/date/toggle — no additions needed.

## THE GOTCHA — significance is FREE TEXT (handled)
significance is a plain user string ("childhood best friend"), NOT the relationships enum. It's an
`anchorTextField`, and writeRequest() runs it through trim `t()` ONLY — never snakeKey. Not copied from
relationships.

## Allowlist (9 real narrator_pets editor columns)
pet_name (req), pet_type, breed, start_date, end_date, how_acquired, personality, significance (FREE TEXT), notes.
NEVER: date_precision, pet_entity_id, entity_id, created_at, updated_at, name, animal_name, species,
age_in_memory, sex, all *_jsonb blocks, id, narrator_id. No nbq_response.

---

## APIModels.swift — PetWriteRequest (9 cols, all String; NO date_precision)
```swift
/// POST /timeline/pets (create — mints a pet entity) AND PUT /timeline/pets/{id} (edit) body — EXACTLY the 9
/// editable narrator_pets columns, nothing else (unknown column → 500). Pre-sanitized by the view (pet_type →
/// stored lowercase via snakeKey; ISO dates; significance + other text trimmed VERBATIM — significance is free
/// text, never an enum). No date_precision (server-side for pets).
nonisolated struct PetWriteRequest: Encodable {
    let petName: String
    let petType, breed: String
    let startDate, endDate: String
    let howAcquired, personality, significance, notes: String

    enum CodingKeys: String, CodingKey {
        case petName = "pet_name", petType = "pet_type", breed
        case startDate = "start_date", endDate = "end_date"
        case howAcquired = "how_acquired", personality, significance, notes
    }
}
```

## AuthManager.swift
```swift
    /// Pets write (Group A). PUT edits; POST creates and mints a pet entity. Bare paths, any-2xx.
    func updatePet(id: String, _ body: PetWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/pets/\(id)", body: body, timeout: 20)
    }
    func createPet(_ body: PetWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/pets", body: body, timeout: 20)
    }
```

## New file: PetEditor.swift
```swift
import SwiftUI

enum PetVocab {
    static let petType: [String] = ["Dog","Cat","Bird","Fish","Reptile","Rodent","Horse","Other"]
    // no precision; significance is NOT a vocab (free text)
}

struct PetDraft {
    var petName = "", petType = "", breed = ""
    var startDate: Date?, endDate: Date?
    var howAcquired = "", personality = "", significance = "", notes = ""

    func writeRequest() -> PetWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }  // pet_type ONLY
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return PetWriteRequest(
            petName: t(petName), petType: e(petType), breed: t(breed),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate),
            howAcquired: t(howAcquired), personality: t(personality),
            significance: t(significance),                 // FREE TEXT — trimmed, never snakeKey'd
            notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, petName.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter your pet’s name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

struct PetFormView: View {
    let title: String
    @Binding var draft: PetDraft
    @Binding var errorMessage: String?
    let isSaving: Bool
    let saveTitle: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var activeDateField: DateField?
    private enum DateField: Int, Identifiable { case start, end; var id: Int { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            anchorFormSection("Pet") {
                anchorTextField("Pet name", $draft.petName, required: true)
                anchorSelectField("Type", PetVocab.petType, $draft.petType)
                anchorTextField("Breed", $draft.breed)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { draft.startDate = nil })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { draft.endDate = nil })
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("How acquired", $draft.howAcquired)
                anchorMultiField("Personality", $draft.personality)
                anchorTextField("Significance", $draft.significance)   // FREE TEXT (plain field, not a select)
                anchorMultiField("Notes", $draft.notes)
            }
            if let e = errorMessage { Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(action: onCancel) { /* Cancel (white) */ }.witnessPress().disabled(isSaving)
                Button(action: onSave) { /* Save spinner/title (teal) */ }.witnessPress().disabled(isSaving)
            }
        }
        .sheet(item: $activeDateField) { f in
            AnchorDateSheet(initial: (f == .start ? draft.startDate : draft.endDate) ?? Date(), floor: RelSanitize.dateFloor) { picked in
                if f == .start { draft.startDate = picked } else { draft.endDate = picked }; activeDateField = nil
            }
        }
    }
}

struct PetListView: View { /* identical to EducationListView, off vm.pets, category "pets", routes to
    PetDetailView, Add New → PetCreateView, "No pets yet." */ }

struct PetCreateView: View { /* identical to EducationCreateView but NO onAppear defaults (pets specify none);
    create() → auth.createPet; "pet" wording ("Add pet") */ }

struct PetDetailView: View { /* identical to EducationDetailView (read row.detailFields incl. Significance raw,
    NO Your Story, inert Delete); startEdit prefills petType via RelSanitize.option(...), significance =
    row.significance ?? "" (raw, no option mapping); save() → auth.updatePet + applyOptimistic + vm.refresh */ }
```
(List/Create/Detail are byte-for-byte mirrors of the Education equivalents with EducationRow→PetRow, vocab/
fields swapped, significance handled as raw free text, and pet wording — the applied file writes them in full.
Save/Cancel button bodies match the other form views.)

## AnchorRegistryView.swift — route pets to the editor
```diff
-        case "pets":       AnchorRecordListView(title: c.label, category: c, rows: vm.pets)
+        case "pets":       PetListView(vm: vm, auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics; RunCodeSnippet confirming PetDraft.writeRequest() emits exactly the 9 allowlist
columns (no date_precision, no never-send), pet_type maps (Dog→dog), and significance passes as free text
(e.g. "childhood best friend" unchanged, not snakeKey'd). Honest note: live PUT/POST round-trip (2xx, pet-entity
mint) is a device/backend check. Delete inert; pets only. No git.
