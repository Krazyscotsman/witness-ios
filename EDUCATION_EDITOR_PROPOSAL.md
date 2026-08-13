# Witness — Education anchor category (view + edit + create) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Mirrors jobs; plugs into AnchorFormKit (adds a toggle).
Group A (POST mints an entity). Endpoints: PUT /timeline/education/{id}, POST /timeline/education (bare, Bearer,
any-2xx). Same 500-footgun → send ONLY the 13-col allowlist.

## Read-first findings
- Education currently: generic read-only AnchorRecordListView → AnchorRecordDetailView (inert).
- EducationRow ALREADY decodes all allowlist fields incl. degreeAchieved: Bool? and graduationDate; has NO
  datePrecision (correct); detailFields already shows "Degree achieved" as Yes/No. → no field additions needed.
- AnchorFormKit has text/multi/select/date builders + AnchorDateSheet, but NO toggle → add anchorToggleField.

## The three differences from jobs/locations (handled)
1. degree_achieved is Bool → EducationWriteRequest.degreeAchieved: Bool (JSON true/false), kept OUT of the
   empty-string text sanitize; new anchorToggleField.
2. NO date_precision — not in struct/vocab/form/draft (structurally impossible to send).
3. Third date graduation_date (DateField enum: start/end/graduation).

## Allowlist (13 real narrator_education editor columns)
institution_name (req), institution_type, institution_location, attendance_mode, degree_type, field_of_study,
degree_achieved (BOOL), start_date, end_date, graduation_date, achievements, challenges, notes.
NEVER: date_precision, grade_start, grade_end, residence_location_id, living_location_context, school_context,
sequence_order, institution_entity_id, entity_id, created_at, updated_at, id, narrator_id. No nbq_response.

---

## AnchorFormKit.swift — add toggle builder
```swift
func anchorToggleField(_ label: String, _ binding: Binding<Bool>) -> some View {
    Toggle(isOn: binding) { Text(label).font(.system(size: 15)).foregroundStyle(WT.ink) }
        .tint(WV.teal)
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
}
```

## APIModels.swift — EducationWriteRequest (13 cols; degree_achieved is a Bool; NO date_precision)
```swift
/// POST /timeline/education (create — mints an entity) AND PUT /timeline/education/{id} (edit) body — EXACTLY
/// the 13 editable narrator_education columns, nothing else (unknown column → 500). degree_achieved is a JSON
/// bool; the rest are pre-sanitized strings (selects → stored lowercase via snakeKey; ISO dates). No
/// date_precision (server-side for education).
nonisolated struct EducationWriteRequest: Encodable {
    let institutionName: String
    let institutionType, institutionLocation, attendanceMode, degreeType, fieldOfStudy: String
    let degreeAchieved: Bool
    let startDate, endDate, graduationDate: String
    let achievements, challenges, notes: String

    enum CodingKeys: String, CodingKey {
        case institutionName = "institution_name", institutionType = "institution_type"
        case institutionLocation = "institution_location", attendanceMode = "attendance_mode"
        case degreeType = "degree_type", fieldOfStudy = "field_of_study", degreeAchieved = "degree_achieved"
        case startDate = "start_date", endDate = "end_date", graduationDate = "graduation_date"
        case achievements, challenges, notes
    }
}
```

## AuthManager.swift
```swift
    /// Education write (Group A). PUT edits; POST creates and mints an entity. Bare paths, any-2xx.
    func updateEducation(id: String, _ body: EducationWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/education/\(id)", body: body, timeout: 20)
    }
    func createEducation(_ body: EducationWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/education", body: body, timeout: 20)
    }
```

## New file: EducationEditor.swift
```swift
import SwiftUI

enum EducationVocab {
    static let institutionType: [String] = ["High School","College","University","Bootcamp","Online Course","Certification"]
    static let attendanceMode: [String] = ["In-person","Online","Hybrid"]
}

struct EducationDraft {
    var institutionName = "", institutionType = "", institutionLocation = "", attendanceMode = ""
    var degreeType = "", fieldOfStudy = ""
    var degreeAchieved = false                                  // Bool, not a string
    var startDate: Date?, endDate: Date?, graduationDate: Date?
    var achievements = "", challenges = "", notes = ""

    func writeRequest() -> EducationWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }  // selects
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return EducationWriteRequest(
            institutionName: t(institutionName), institutionType: e(institutionType),
            institutionLocation: t(institutionLocation), attendanceMode: e(attendanceMode),
            degreeType: t(degreeType), fieldOfStudy: t(fieldOfStudy),
            degreeAchieved: degreeAchieved,                    // Bool passed straight through
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate),
            graduationDate: RelSanitize.string(graduationDate),
            achievements: t(achievements), challenges: t(challenges), notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, institutionName.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter a school or institution name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate), ("Graduation date", graduationDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

struct EducationFormView: View {
    let title: String
    @Binding var draft: EducationDraft
    @Binding var errorMessage: String?
    let isSaving: Bool
    let saveTitle: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var activeDateField: DateField?
    private enum DateField: Int, Identifiable { case start, end, graduation; var id: Int { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            anchorFormSection("Institution") {
                anchorTextField("School / institution name", $draft.institutionName, required: true)
                anchorSelectField("Type", EducationVocab.institutionType, $draft.institutionType)
                anchorTextField("Location", $draft.institutionLocation)
            }
            anchorFormSection("Program") {
                anchorTextField("Degree type", $draft.degreeType)
                anchorTextField("Field of study", $draft.fieldOfStudy)
                anchorSelectField("Attendance mode", EducationVocab.attendanceMode, $draft.attendanceMode)
                anchorToggleField("Degree achieved", $draft.degreeAchieved)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { draft.startDate = nil })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { draft.endDate = nil })
                anchorDateField("Graduation date", draft.graduationDate, onEdit: { activeDateField = .graduation }, onClear: { draft.graduationDate = nil })
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("Achievements", $draft.achievements)
                anchorMultiField("Challenges", $draft.challenges)
                anchorMultiField("Notes", $draft.notes)
            }
            if let e = errorMessage { Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(action: onCancel) { /* Cancel (white) */ }.witnessPress().disabled(isSaving)
                Button(action: onSave) { /* Save spinner/title (teal) */ }.witnessPress().disabled(isSaving)
            }
        }
        .sheet(item: $activeDateField) { f in
            let cur = f == .start ? draft.startDate : (f == .end ? draft.endDate : draft.graduationDate)
            AnchorDateSheet(initial: cur ?? Date(), floor: RelSanitize.dateFloor) { picked in
                switch f { case .start: draft.startDate = picked; case .end: draft.endDate = picked; case .graduation: draft.graduationDate = picked }
                activeDateField = nil
            }
        }
    }
}

struct EducationListView: View { /* identical to JobListView, off vm.education, category "education", routes to
    EducationDetailView, Add New → EducationCreateView, "No education yet." */ }

struct EducationCreateView: View { /* identical to JobCreateView; onAppear defaults attendanceMode="In-person",
    degreeAchieved=false; create() → auth.createEducation; "education" wording */ }

struct EducationDetailView: View { /* identical to JobDetailView (read row.detailFields incl. Degree achieved
    Yes/No, NO Your Story, inert Delete); startEdit prefills incl. degreeAchieved: row.degreeAchieved ?? false;
    save() → auth.updateEducation + applyOptimistic (row.degreeAchieved = body.degreeAchieved) + vm.refresh */ }
```
(List/Create/Detail are byte-for-byte mirrors of the Job equivalents with JobRow→EducationRow, JobVocab→
EducationVocab, update/createJob→update/createEducation, the toggle prefill/optimistic for degreeAchieved, and
education wording — the applied file writes them out in full. Save/Cancel button bodies match JobFormView.)

## AnchorRegistryView.swift — route education to the editor
```diff
-        case "education":  AnchorRecordListView(title: c.label, category: c, rows: vm.education)
+        case "education":  EducationListView(vm: vm, auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics; RunCodeSnippet confirming EducationDraft.writeRequest() emits exactly the 13
allowlist columns (NO date_precision, no never-send), degree_achieved serializes as a JSON bool (true/false),
and selects map (High School→high_school, Online Course→online_course, In-person→in_person). Honest note: live
PUT/POST round-trip (2xx, entity mint) is a device/backend check. Delete inert; education only. No git.
