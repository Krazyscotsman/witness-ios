# Witness — Jobs & Career anchor category (view + edit + create) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Mirrors locations; plugs into AnchorFormKit.
Group A (POST mints an organization entity). Endpoints: PUT /timeline/jobs/{id}, POST /timeline/jobs (bare,
Bearer, any-2xx). Backing table narrator_employment; slug jobs. Same 500-footgun → send ONLY the 17-col allowlist.

## KEY RISK — hyphenated selects: RESOLVED (verified by execution)
snakeKey output over all select values (RunCodeSnippet, RelSanitize.snakeKey):
- Full-time → full_time · Part-time → part_time · Contract → contract · Freelance → freelance ·
  Internship → internship · Volunteer → volunteer
- On-site → on_site · Remote → remote · Hybrid → hybrid
- Day → day · Month → month · Year → year
snakeKey collapses hyphen AND space to a single underscore → exact stored forms. **No hardcoded display→stored
table needed.**

## Read-first findings
- Jobs currently: generic read-only AnchorRecordListView → AnchorRecordDetailView (inert). JobRow decodes all
  allowlist fields EXCEPT date_precision (same gap LocationRow had) → add `datePrecision`. detailFields/
  typeLabel/subtitle/sortKey already present.
- Mirror LocationEditor exactly (Vocab/Draft/FormView/ListView/CreateView/DetailView + WriteRequest + Auth calls
  + registry route), swapping fields and wording.

## Allowlist (17 real narrator_employment columns)
employer_name (req), employer_industry, work_location, job_title, department, employment_type, work_mode,
start_date, end_date, date_precision, reason_for_joining, reason_for_leaving, key_responsibilities,
major_achievements, skills_gained, certifications_earned, notes.
NEVER: residence_location_id, living_location_context, salary_range, concurrent_education, concurrent_family,
sequence_order, employer_entity_id, entity_id, created_at, updated_at, id, narrator_id. No nbq_response.

---

## AnchorRegistry.swift — add datePrecision to JobRow
```diff
     var employmentType: String? = nil, workMode: String? = nil
     var startDate: String? = nil, endDate: String? = nil
+    var datePrecision: String? = nil
     var reasonForJoining: String? = nil, reasonForLeaving: String? = nil
```

## APIModels.swift — JobWriteRequest (17 columns, shared POST+PUT)
```swift
/// POST /timeline/jobs (create — mints an organization entity) AND PUT /timeline/jobs/{id} (edit) body —
/// EXACTLY the 17 editable narrator_employment columns, nothing else (unknown column → 500). Pre-sanitized by
/// the view (employment_type/work_mode/date_precision → stored lowercase via snakeKey; ISO dates; text as-is).
nonisolated struct JobWriteRequest: Encodable {
    let employerName: String
    let employerIndustry, workLocation, jobTitle, department: String
    let employmentType, workMode: String
    let startDate, endDate, datePrecision: String
    let reasonForJoining, reasonForLeaving, keyResponsibilities, majorAchievements: String
    let skillsGained, certificationsEarned, notes: String

    enum CodingKeys: String, CodingKey {
        case employerName = "employer_name", employerIndustry = "employer_industry"
        case workLocation = "work_location", jobTitle = "job_title", department
        case employmentType = "employment_type", workMode = "work_mode"
        case startDate = "start_date", endDate = "end_date", datePrecision = "date_precision"
        case reasonForJoining = "reason_for_joining", reasonForLeaving = "reason_for_leaving"
        case keyResponsibilities = "key_responsibilities", majorAchievements = "major_achievements"
        case skillsGained = "skills_gained", certificationsEarned = "certifications_earned", notes
    }
}
```

## AuthManager.swift — job write calls
```swift
    /// Jobs write (Group A). PUT edits; POST creates and mints an organization entity. Bare paths, any-2xx.
    func updateJob(id: String, _ body: JobWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/jobs/\(id)", body: body, timeout: 20)
    }
    func createJob(_ body: JobWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/jobs", body: body, timeout: 20)
    }
```

## New file: JobEditor.swift  (full mirror of LocationEditor)
```swift
import SwiftUI

enum JobVocab {
    static let employmentType: [String] = ["Full-time","Part-time","Contract","Freelance","Internship","Volunteer"]
    static let workMode: [String] = ["On-site","Remote","Hybrid"]
    static let precision: [String] = ["Day","Month","Year"]
}

struct JobDraft {
    var employerName = "", industry = "", workLocation = "", jobTitle = "", department = ""
    var employmentType = "", workMode = "", precision = ""
    var startDate: Date?, endDate: Date?
    var reasonForJoining = "", reasonForLeaving = "", keyResponsibilities = "", majorAchievements = ""
    var skillsGained = "", certificationsEarned = "", notes = ""

    func writeRequest() -> JobWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }   // enums
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return JobWriteRequest(
            employerName: t(employerName), employerIndustry: t(industry), workLocation: t(workLocation),
            jobTitle: t(jobTitle), department: t(department),
            employmentType: e(employmentType), workMode: e(workMode),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate), datePrecision: e(precision),
            reasonForJoining: t(reasonForJoining), reasonForLeaving: t(reasonForLeaving),
            keyResponsibilities: t(keyResponsibilities), majorAchievements: t(majorAchievements),
            skillsGained: t(skillsGained), certificationsEarned: t(certificationsEarned), notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, employerName.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter an employer name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

struct JobFormView: View {
    let title: String
    @Binding var draft: JobDraft
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
            anchorFormSection("Employer") {
                anchorTextField("Employer name", $draft.employerName, required: true)
                anchorTextField("Industry", $draft.industry)
                anchorTextField("Work location", $draft.workLocation)
            }
            anchorFormSection("Role") {
                anchorTextField("Job title", $draft.jobTitle)
                anchorTextField("Department", $draft.department)
                anchorSelectField("Employment type", JobVocab.employmentType, $draft.employmentType)
                anchorSelectField("Work mode", JobVocab.workMode, $draft.workMode)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { draft.startDate = nil })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { draft.endDate = nil })
                anchorSelectField("Date precision", JobVocab.precision, $draft.precision)
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("Reason for joining", $draft.reasonForJoining)
                anchorMultiField("Reason for leaving", $draft.reasonForLeaving)
                anchorMultiField("Key responsibilities", $draft.keyResponsibilities)
                anchorMultiField("Major achievements", $draft.majorAchievements)
                anchorMultiField("Skills gained", $draft.skillsGained)
                anchorMultiField("Certifications earned", $draft.certificationsEarned)
                anchorMultiField("Notes", $draft.notes)
            }
            if let e = errorMessage { Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }.witnessPress().disabled(isSaving)
                Button(action: onSave) {
                    Group { if isSaving { ProgressView().tint(.white) } else { Text(saveTitle).font(.system(size: 16, weight: .semibold)) } }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                        .background(isSaving ? WV.teal.opacity(0.5) : WV.teal, in: RoundedRectangle(cornerRadius: 14))
                }.witnessPress().disabled(isSaving)
            }
        }
        .sheet(item: $activeDateField) { f in
            AnchorDateSheet(initial: (f == .start ? draft.startDate : draft.endDate) ?? Date(), floor: RelSanitize.dateFloor) { picked in
                if f == .start { draft.startDate = picked } else { draft.endDate = picked }; activeDateField = nil
            }
        }
    }
}

struct JobListView: View { /* identical to LocationListView, off vm.jobs, category "jobs", routes to JobDetailView,
    Add New → JobCreateView, "No jobs yet." */ }

struct JobCreateView: View { /* identical to LocationCreateView; onAppear defaults employmentType="Full-time",
    workMode="On-site", precision="Month"; create() → auth.createJob → vm.refresh → dismiss; "job" wording */ }

struct JobDetailView: View { /* identical to LocationDetailView (read row.detailFields, NO Your Story, inert
    Delete); startEdit prefills via RelSanitize.option(for: row.*, in: JobVocab.*); save() → auth.updateJob +
    applyOptimistic + vm.refresh */ }
```
(JobListView / JobCreateView / JobDetailView are byte-for-byte mirrors of the Location equivalents with
LocationRow→JobRow, LocationVocab→JobVocab, update/createLocation→update/createJob, and job wording — the
applied file writes them out in full.)

## AnchorRegistryView.swift — route jobs to the editor
```diff
-        case "jobs":       AnchorRecordListView(title: c.label, category: c, rows: vm.jobs)
+        case "jobs":       JobListView(vm: vm, auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics; RunCodeSnippet confirming JobDraft.writeRequest() emits exactly the 17 allowlist
columns with full_time/on_site/month and no never-send columns. Honest note: live PUT/POST round-trip (2xx,
org-entity mint) is a device/backend check. Delete inert; jobs only; no /continuity/truths. No git.
