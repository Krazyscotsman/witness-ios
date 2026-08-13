# Witness — Hobbies + Service anchor categories (view + edit + create) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Both mirror pets/education via AnchorFormKit.
Group B (mint NO entity — nothing special on iOS). Endpoints: PUT/POST /timeline/hobbies (narrator_hobbies),
PUT/POST /timeline/service (narrator_military_service). Bare, Bearer, any-2xx. 500-footgun → send ONLY each
allowlist. Completes the Registry.

## Read-first findings
- Hobbies + Service currently: generic read-only AnchorRecordListView → AnchorRecordDetailView (inert).
- HobbyRow decodes all 7 allowlist fields; NO end_date, NO datePrecision (correct) → no changes.
- ServiceRow decodes all 9 allowlist fields; NO datePrecision; name field is serviceMember (not first/last) →
  no changes.
- AnchorFormKit needs nothing new. Pet editor is the mirror.

## Allowlists
HOBBIES (7, narrator_hobbies): hobby_name (req), hobby_type, activity_level, start_date (ONE date), how_started,
achievements, notes. NEVER: end_date, date_precision, peak_period_start, peak_period_end, equipment_tools,
social_aspect, skills_developed, related_to_career, related_to_relationships, sequence_order, category,
created_at, updated_at, all *_jsonb, id, narrator_id.
SERVICE (9, narrator_military_service): service_member (req, prefill "Self"), branch, rank_at_start,
rank_at_end, start_date, end_date, duty_stations, deployments, notes. NEVER: service_member_name,
date_precision, impact_on_family, first_name, middle_name, last_name, nickname, rank, created_at, updated_at,
id, narrator_id.

---

## APIModels.swift — two write structs
```swift
/// POST/PUT /timeline/hobbies — EXACTLY the 7 editable narrator_hobbies columns. Group B (no entity). ONE date
/// (start_date only — no end_date). No date_precision. Selects → snakeKey; text trimmed.
nonisolated struct HobbyWriteRequest: Encodable {
    let hobbyName: String
    let hobbyType, activityLevel: String
    let startDate: String
    let howStarted, achievements, notes: String
    enum CodingKeys: String, CodingKey {
        case hobbyName = "hobby_name", hobbyType = "hobby_type", activityLevel = "activity_level"
        case startDate = "start_date", howStarted = "how_started", achievements, notes
    }
}

/// POST/PUT /timeline/service — EXACTLY the 9 editable narrator_military_service columns. Group B (no entity).
/// Name field is service_member (NOT first/last). No date_precision. branch → snakeKey; text trimmed.
nonisolated struct ServiceWriteRequest: Encodable {
    let serviceMember: String
    let branch, rankAtStart, rankAtEnd: String
    let startDate, endDate: String
    let dutyStations, deployments, notes: String
    enum CodingKeys: String, CodingKey {
        case serviceMember = "service_member", branch
        case rankAtStart = "rank_at_start", rankAtEnd = "rank_at_end"
        case startDate = "start_date", endDate = "end_date"
        case dutyStations = "duty_stations", deployments, notes
    }
}
```

## AuthManager.swift
```swift
    /// Hobbies write (Group B — no entity minted). Bare paths, any-2xx.
    func updateHobby(id: String, _ body: HobbyWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/hobbies/\(id)", body: body, timeout: 20)
    }
    func createHobby(_ body: HobbyWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/hobbies", body: body, timeout: 20)
    }
    /// Service write (Group B — no entity minted). Bare paths, any-2xx.
    func updateService(id: String, _ body: ServiceWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/service/\(id)", body: body, timeout: 20)
    }
    func createService(_ body: ServiceWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/service", body: body, timeout: 20)
    }
```

## New file: HobbyEditor.swift
```swift
import SwiftUI

enum HobbyVocab {
    static let hobbyType: [String] = ["Creative","Athletic","Intellectual","Social","Collecting","Outdoors","Interest"]
    static let activityLevel: [String] = ["Active","Occasional","Dormant","Past"]
}

struct HobbyDraft {
    var hobbyName = "", hobbyType = "", activityLevel = ""
    var startDate: Date?
    var howStarted = "", achievements = "", notes = ""

    func writeRequest() -> HobbyWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return HobbyWriteRequest(
            hobbyName: t(hobbyName), hobbyType: e(hobbyType), activityLevel: e(activityLevel),
            startDate: RelSanitize.string(startDate),
            howStarted: t(howStarted), achievements: t(achievements), notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, hobbyName.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter a hobby name." }
        if let dt = startDate, dt < RelSanitize.dateFloor { return "Start date must be on or after Jan 1, 1910." }
        return nil   // one date only — no end≥start check
    }
}

struct HobbyFormView: View {
    let title: String
    @Binding var draft: HobbyDraft
    @Binding var errorMessage: String?
    let isSaving: Bool
    let saveTitle: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            anchorFormSection("Hobby") {
                anchorTextField("Hobby name", $draft.hobbyName, required: true)
                anchorSelectField("Type", HobbyVocab.hobbyType, $draft.hobbyType)
                anchorSelectField("Activity level", HobbyVocab.activityLevel, $draft.activityLevel)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { showDate = true }, onClear: { draft.startDate = nil })
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("How it started", $draft.howStarted)
                anchorMultiField("Achievements", $draft.achievements)
                anchorMultiField("Notes", $draft.notes)
            }
            if let e = errorMessage { Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(action: onCancel) { /* Cancel (white) */ }.witnessPress().disabled(isSaving)
                Button(action: onSave) { /* Save spinner/title (teal) */ }.witnessPress().disabled(isSaving)
            }
        }
        .sheet(isPresented: $showDate) {
            AnchorDateSheet(initial: draft.startDate ?? Date(), floor: RelSanitize.dateFloor) { picked in draft.startDate = picked; showDate = false }
        }
    }
}

struct HobbyListView: View { /* identical to PetListView, off vm.hobbies, category "hobbies", → HobbyDetailView,
    Add New → HobbyCreateView, "No hobbies yet." */ }

struct HobbyCreateView: View { /* identical to PetCreateView; onAppear default activityLevel="Active";
    create() → auth.createHobby; "Add hobby" */ }

struct HobbyDetailView: View { /* identical to PetDetailView (read row.detailFields, NO Your Story, inert
    Delete); startEdit prefills hobbyType/activityLevel via RelSanitize.option, startDate parse;
    save() → auth.updateHobby + applyOptimistic + vm.refresh */ }
```

## New file: ServiceEditor.swift
```swift
import SwiftUI

enum ServiceVocab {
    static let branch: [String] = ["Army","Navy","Air Force","Marines","Coast Guard","Space Force","National Guard"]
}

struct ServiceDraft {
    var serviceMember = "", branch = "", rankAtStart = "", rankAtEnd = ""
    var startDate: Date?, endDate: Date?
    var dutyStations = "", deployments = "", notes = ""

    func writeRequest() -> ServiceWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return ServiceWriteRequest(
            serviceMember: t(serviceMember), branch: e(branch),
            rankAtStart: t(rankAtStart), rankAtEnd: t(rankAtEnd),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate),
            dutyStations: t(dutyStations), deployments: t(deployments), notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, serviceMember.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter who served." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

struct ServiceFormView: View {
    let title: String
    @Binding var draft: ServiceDraft
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
            anchorFormSection("Service") {
                anchorTextField("Who served", $draft.serviceMember, required: true)
                anchorSelectField("Branch", ServiceVocab.branch, $draft.branch)
            }
            anchorFormSection("Rank") {
                anchorTextField("Rank at start", $draft.rankAtStart)
                anchorTextField("Rank at end", $draft.rankAtEnd)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { draft.startDate = nil })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { draft.endDate = nil })
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("Duty stations", $draft.dutyStations)
                anchorMultiField("Deployments", $draft.deployments)
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

struct ServiceListView: View { /* identical to PetListView, off vm.service, category "service", → ServiceDetailView,
    Add New → ServiceCreateView, "No service records yet." */ }

struct ServiceCreateView: View { /* identical to PetCreateView; onAppear default serviceMember="Self";
    create() → auth.createService; "Add service" */ }

struct ServiceDetailView: View { /* identical to PetDetailView (read row.detailFields, NO Your Story, inert
    Delete); startEdit prefills branch via RelSanitize.option, dates parse, rank/text raw;
    save() → auth.updateService + applyOptimistic + vm.refresh */ }
```
(List/Create/Detail for both are byte-for-byte mirrors of the Pet equivalents with the row type / vocab / fields
/ auth calls / wording swapped — the applied files write them out in full, matching the other editors' styling.)

## AnchorRegistryView.swift — route the last two categories
```diff
-        case "hobbies":    AnchorRecordListView(title: c.label, category: c, rows: vm.hobbies)
+        case "hobbies":    HobbyListView(vm: vm, auth: auth)
-        case "service":    AnchorRecordListView(title: c.label, category: c, rows: vm.service)
+        case "service":    ServiceListView(vm: vm, auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics; RunCodeSnippet confirming: HobbyWriteRequest = exactly the 7 cols (no end_date,
no date_precision, no never-send); ServiceWriteRequest = exactly the 9 cols (no first/last, no date_precision,
no never-send); selects map incl. Air Force→air_force / Coast Guard→coast_guard / Space Force→space_force /
National Guard→national_guard. Honest note: live PUT/POST (2xx, Group B no-entity) is a device/backend check.
Delete inert. No git. This completes all 7 Registry categories.
