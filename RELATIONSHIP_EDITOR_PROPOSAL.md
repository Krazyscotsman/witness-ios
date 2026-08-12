# Witness — Relationship anchor editor (PUT /timeline/relationships/{id}) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** BLOCKED on the exact vocabularies (see §0).
First real write to the truth registry. Relationships ONLY. No create, no delete, no other categories.

## 0) 🔴 REQUIRED INPUT — exact vocabularies (paste to unblock)
The backend has NO request validation: an unknown column or (likely) an unexpected enum value → 500. Every
select value is sent as `snakeKey(display)`, which MUST equal the backend's stored enum. So I need the exact
DISPLAY lists:
1. Relationship types (46) — confirm/replace the repo's list.
2. Family roles (13) — NOT in the repo; required.
3. Significance, date precision, privacy level — confirm.
These drop into `RelationshipVocab` below (placeholders marked `// TODO: confirm/replace`).

## Read-first findings
- Relationships use the generic read-only `AnchorRecordDetailView` (inert Edit/Delete), reached via
  `AnchorRecordListView<RelationshipRow>` in L2. `RelationshipRow` lacks `family_role` + `date_precision`
  (both allowlisted) — added below.
- APIClient already has `putIgnoringResponseBody(...)` (bare-path, Bearer, any-2xx success, body ignored) —
  reused; no new method. The `{status:success|no_change}` body is simply ignored.

## Allowlist (the ONLY columns ever sent) — 22
first_name, middle_name, last_name, nickname, maiden_name, relationship_type (required), family_role,
significance, start_date, end_date, date_precision, person_birth_date, person_birth_date_precision,
person_death_date, person_death_date_precision, how_met, relationship_context, how_ended, lessons_learned,
notes, appearance_description, privacy_level.
NEVER sent: nbq_response, person_canonical_name (+ anything else, incl. pseudonym).

---

## AnchorRegistry.swift — add 2 allowlisted fields to RelationshipRow
```diff
     var relationshipType: String? = nil, significance: String? = nil
+    var familyRole: String? = nil, datePrecision: String? = nil
     var personBirthDate: String? = nil, personBirthDatePrecision: String? = nil
```
(Decoded via convertFromSnakeCase → family_role/date_precision. Shown read-only + prefilled into the editor.)

## APIModels.swift — the allowlisted request (nonisolated; exactly 22 columns)
```swift
/// PUT /timeline/relationships/{id} body — EXACTLY the 22 editable columns, nothing else (backend 500s on
/// unknown columns). Values are pre-sanitized by the view (snake_case enums, ISO dates, "" for blanks →
/// server NULL). nonisolated because it's encoded in APIClient's nonisolated context.
nonisolated struct RelationshipUpdateRequest: Encodable {
    let firstName, middleName, lastName, nickname, maidenName: String
    let relationshipType: String
    let familyRole, significance: String
    let startDate, endDate, datePrecision: String
    let personBirthDate, personBirthDatePrecision, personDeathDate, personDeathDatePrecision: String
    let howMet, relationshipContext, howEnded, lessonsLearned, notes, appearanceDescription: String
    let privacyLevel: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name", middleName = "middle_name", lastName = "last_name"
        case nickname, maidenName = "maiden_name"
        case relationshipType = "relationship_type", familyRole = "family_role", significance
        case startDate = "start_date", endDate = "end_date", datePrecision = "date_precision"
        case personBirthDate = "person_birth_date", personBirthDatePrecision = "person_birth_date_precision"
        case personDeathDate = "person_death_date", personDeathDatePrecision = "person_death_date_precision"
        case howMet = "how_met", relationshipContext = "relationship_context", howEnded = "how_ended"
        case lessonsLearned = "lessons_learned", notes, appearanceDescription = "appearance_description"
        case privacyLevel = "privacy_level"
    }
}
```

## AuthManager.swift — the write call
```swift
    /// PUT /timeline/relationships/{id} — partial update of allowlisted columns. Any 2xx = success (the
    /// {status} ack is ignored). Throws APIError; the view maps it to friendly copy.
    func updateRelationship(id: String, _ body: RelationshipUpdateRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/relationships/\(id)", body: body, timeout: 20)
    }
```

## New file: RelationshipEditor.swift  (vocab + sanitize + list + detail/editor)
```swift
import SwiftUI

// MARK: - Vocabularies (DISPLAY labels; sent as snakeKey). CONFIRM/REPLACE from backend (see §0).
nonisolated enum RelationshipVocab {
    // TODO: confirm this is EXACTLY the backend's 46 accepted relationship types.
    static let types: [String] = [
        "Spouse","Parent Child","Siblings","Half Siblings","Step Sibling","Step Parent","Step Child","Twin",
        "Grandparent Grandchild","Aunt Uncle Niece Nephew","Cousins","Adopted Parent","Adopted Child",
        "Foster Parent","Foster Child","Godparent","Godchild","In-Law Parent","In-Law Sibling","In-Law Child",
        "Partners Parent","Romantic","Partner","Ex Spouse","Ex Partner","Friend","Best Friend","Acquaintance",
        "Neighbor","Roommate","Classmate","Professional","Colleague","Boss","Subordinate","Mentor","Mentee",
        "Client","Pet Owner","Caregiver","Doctor","Therapist","Teacher","Student","Family","Enemy","Other"
    ]
    static let familyRoles: [String] = [ /* TODO: REQUIRED — paste the 13 family roles */ ]
    static let significance: [String] = ["Critical","High","Moderate","Low"]                 // TODO: confirm
    static let precision: [String] = ["Day","Month","Year"]                                  // TODO: confirm
    static let privacy: [String] = ["Private","Family Only","Public"]                        // TODO: confirm
}

// MARK: - Sanitizers
nonisolated enum RelSanitize {
    /// "In-Law Parent" → "in_law_parent"; "Ex Spouse" → "ex_spouse". Runs of non-alphanumerics → single "_".
    static func snakeKey(_ s: String) -> String {
        var out = "", lastUnderscore = true   // start true → trims leading
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch); lastUnderscore = false }
            else if !lastUnderscore { out.append("_"); lastUnderscore = true }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out
    }
    static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func date(_ d: Date?) -> String { d.map { iso.string(from: $0) } ?? "" }
    static func parse(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return iso.date(from: String(s.prefix(10)))
    }
    /// Pre-select a display option whose snakeKey matches the stored value.
    static func option(for stored: String?, in options: [String]) -> String? {
        let key = snakeKey(stored ?? ""); guard !key.isEmpty else { return nil }
        return options.first { snakeKey($0) == key }
    }
}

// MARK: - Relationships list (RelationshipRow-specific; routes to the editable detail)
struct RelationshipListView: View {
    let title: String
    let rows: [RelationshipRow]
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    private let category = AnchorCategory.find("relationships")
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [RelationshipRow] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let f = q.isEmpty ? rows : rows.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
        return f.sorted { $0.sortKey > $1.sortKey }
    }
    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.serif(26)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    searchBar
                    if visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2").font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
                            Text(search.isEmpty ? "Nothing here yet." : "No matches for “\(search)”.").font(.serif(20)).foregroundStyle(WT.ink)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(visible) { r in
                            NavigationLink { RelationshipDetailView(row: r, vm: vm, auth: auth) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }
    private var searchBar: some View { /* identical to AnchorRecordListView's search bar */ EmptyView() }
    private func row(_ r: RelationshipRow) -> some View { /* identical card to AnchorRecordListView.row */ EmptyView() }
}
```
(The `searchBar`/`row` bodies are copied verbatim from `AnchorRecordListView` — shown as EmptyView() here only
to keep the proposal short; the applied file uses the real card/search UI.)

## RelationshipDetailView — read mode + edit mode (the core)
```swift
struct RelationshipDetailView: View {
    @State var row: RelationshipRow              // local, updated optimistically on save
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("relationships")

    @State private var editing = false
    @State private var isSaving = false
    @State private var errorMessage: String?     // save/validation failure (friendly)

    // Draft fields (prefilled on entering edit)
    @State private var d = Draft()
    struct Draft {
        var firstName = "", middleName = "", lastName = "", nickname = "", maidenName = ""
        var relationshipType = "", familyRole = "", significance = "", privacy = ""
        var datePrecision = "", birthPrecision = "", deathPrecision = ""
        var startDate: Date?, endDate: Date?, birthDate: Date?, deathDate: Date?
        var howMet = "", relationshipContext = "", howEnded = "", lessonsLearned = "", notes = "", appearance = ""
    }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                if editing { editForm } else { readOnly }
            }
            anchorNavBar(title: category.singular, onBack: { editing ? cancelEdit() : dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    // READ MODE — labeled rows (row.detailFields) + Your Story (row.story, read-only) + active Edit / inert Delete
    private var readOnly: some View { /* mirrors AnchorRecordDetailView, but the Edit button sets editing = true */ EmptyView() }

    // EDIT MODE — all 22 allowlist fields as inputs (empty ones editable), Your Story read-only, Save/Cancel
    private var editForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Names: text fields (first/middle/last/nickname/maiden)
            // Relationship: relationship_type (required select · RelationshipVocab.types),
            //               family_role (select · familyRoles), significance (select)
            // Dates: start/end (+ date_precision select), person_birth/person_death (+ their precision selects)
            // Narrative: how_met, relationship_context, how_ended, lessons_learned, notes, appearance (multiline)
            // Privacy: privacy_level (select)
            // Your Story: read-only card from row.nbqResponse (NEVER an input)
            // If errorMessage != nil → red inline message
            // Save (busy spinner) + Cancel
            EmptyView()
        }
    }

    private func startEdit() {
        d = Draft(
            firstName: row.firstName ?? "", middleName: row.middleName ?? "", lastName: row.lastName ?? "",
            nickname: row.nickname ?? "", maidenName: row.maidenName ?? "",
            relationshipType: RelSanitize.option(for: row.relationshipType, in: RelationshipVocab.types) ?? "",
            familyRole: RelSanitize.option(for: row.familyRole, in: RelationshipVocab.familyRoles) ?? "",
            significance: RelSanitize.option(for: row.significance, in: RelationshipVocab.significance) ?? "",
            privacy: RelSanitize.option(for: row.privacyLevel, in: RelationshipVocab.privacy) ?? "",
            datePrecision: RelSanitize.option(for: row.datePrecision, in: RelationshipVocab.precision) ?? "",
            birthPrecision: RelSanitize.option(for: row.personBirthDatePrecision, in: RelationshipVocab.precision) ?? "",
            deathPrecision: RelSanitize.option(for: row.personDeathDatePrecision, in: RelationshipVocab.precision) ?? "",
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            birthDate: RelSanitize.parse(row.personBirthDate), deathDate: RelSanitize.parse(row.personDeathDate),
            howMet: row.howMet ?? "", relationshipContext: row.relationshipContext ?? "",
            howEnded: row.howEnded ?? "", lessonsLearned: row.lessonsLearned ?? "",
            notes: row.notes ?? "", appearance: row.appearanceDescription ?? "")
        errorMessage = nil; editing = true
    }
    private func cancelEdit() { editing = false; errorMessage = nil }

    // Validation (backend won't 422)
    private func validate() -> String? {
        if d.relationshipType.trimmingCharacters(in: .whitespaces).isEmpty { return "Please choose a relationship type." }
        let floor = RelSanitize.iso.date(from: "1910-01-01")!
        for (label, date) in [("Start date", d.startDate), ("End date", d.endDate),
                              ("Birth date", d.birthDate), ("Death date", d.deathDate)] {
            if let dt = date, dt < floor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = d.startDate, let e = d.endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }

    private func save() async {
        if let msg = validate() { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        func enumVal(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }
        let body = RelationshipUpdateRequest(
            firstName: d.firstName.trimmingCharacters(in: .whitespaces),
            middleName: d.middleName.trimmingCharacters(in: .whitespaces),
            lastName: d.lastName.trimmingCharacters(in: .whitespaces),
            nickname: d.nickname.trimmingCharacters(in: .whitespaces),
            maidenName: d.maidenName.trimmingCharacters(in: .whitespaces),
            relationshipType: enumVal(d.relationshipType),
            familyRole: enumVal(d.familyRole),
            significance: enumVal(d.significance),
            startDate: RelSanitize.date(d.startDate), endDate: RelSanitize.date(d.endDate),
            datePrecision: enumVal(d.datePrecision),
            personBirthDate: RelSanitize.date(d.birthDate), personBirthDatePrecision: enumVal(d.birthPrecision),
            personDeathDate: RelSanitize.date(d.deathDate), personDeathDatePrecision: enumVal(d.deathPrecision),
            howMet: d.howMet.trimmingCharacters(in: .whitespaces),
            relationshipContext: d.relationshipContext.trimmingCharacters(in: .whitespaces),
            howEnded: d.howEnded.trimmingCharacters(in: .whitespaces),
            lessonsLearned: d.lessonsLearned.trimmingCharacters(in: .whitespaces),
            notes: d.notes.trimmingCharacters(in: .whitespaces),
            appearanceDescription: d.appearance.trimmingCharacters(in: .whitespaces),
            privacyLevel: enumVal(d.privacy))
        do {
            try await auth.updateRelationship(id: row.id, body)
            applyOptimistic(body)          // update local `row` to the sent (stored-form) values
            editing = false
            await vm.refresh(auth: auth)    // reconcile registry (counts/chips/list)
        } catch {
            errorMessage = Self.friendly(error)   // preserve edits; stay in edit mode
        }
    }

    private func applyOptimistic(_ b: RelationshipUpdateRequest) {
        // Names propagate to the anchors-list display name only after backend name-propagation lands (noted).
        row.firstName = b.firstName.nilIfBlank; row.middleName = b.middleName.nilIfBlank
        row.lastName = b.lastName.nilIfBlank; row.nickname = b.nickname.nilIfBlank; row.maidenName = b.maidenName.nilIfBlank
        row.relationshipType = b.relationshipType.nilIfBlank; row.familyRole = b.familyRole.nilIfBlank
        row.significance = b.significance.nilIfBlank; row.privacyLevel = b.privacyLevel.nilIfBlank
        row.startDate = b.startDate.nilIfBlank; row.endDate = b.endDate.nilIfBlank; row.datePrecision = b.datePrecision.nilIfBlank
        row.personBirthDate = b.personBirthDate.nilIfBlank; row.personBirthDatePrecision = b.personBirthDatePrecision.nilIfBlank
        row.personDeathDate = b.personDeathDate.nilIfBlank; row.personDeathDatePrecision = b.personDeathDatePrecision.nilIfBlank
        row.howMet = b.howMet.nilIfBlank; row.relationshipContext = b.relationshipContext.nilIfBlank
        row.howEnded = b.howEnded.nilIfBlank; row.lessonsLearned = b.lessonsLearned.nilIfBlank
        row.notes = b.notes.nilIfBlank; row.appearanceDescription = b.appearanceDescription.nilIfBlank
        // nbqResponse + personCanonicalName untouched (never sent).
    }

    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "Your session has timed out. Please sign in again."
            case .network:      return "We couldn’t save your changes. Check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:            return "Something went wrong saving your changes. Please try again."
            }
        }
        return "Something went wrong saving your changes. Please try again."
    }
}

private extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
```
(The `readOnly`/`editForm`/`searchBar`/`row` view bodies are shown as `EmptyView()` placeholders ONLY to keep
this proposal readable — the applied file contains the full parchment/card UI, text fields, `Menu` selects
bound to the vocab, and date-picker sheets, matching the existing Settings/AnchorForm styling.)

## L2 wiring — route relationships to the editable detail
```diff
 struct AnchorRelationshipsView: View {
     @ObservedObject var vm: AnchorRegistryViewModel
+    @ObservedObject var auth: AuthManager
     let category: AnchorCategory
```
```diff
     NavigationLink {
-        AnchorRecordListView(title: "Critical People", category: category, rows: critical)
+        RelationshipListView(title: "Critical People", rows: critical, vm: vm, auth: auth)
     } label: { criticalCard(count: critical.count) }
```
```diff
     NavigationLink {
-        AnchorRecordListView(title: chip.title, category: category, rows: vm.relationships(typeKey: chip.id))
+        RelationshipListView(title: chip.title, rows: vm.relationships(typeKey: chip.id), vm: vm, auth: auth)
     } label: { chipRow(chip) }
```
## AnchorRegistryView — pass auth into L2
```diff
-        case "relationships": AnchorRelationshipsView(vm: vm, category: c)
+        case "relationships": AnchorRelationshipsView(vm: vm, auth: auth, category: c)
```
(Other 6 categories keep `AnchorRecordListView` + read-only `AnchorRecordDetailView` — untouched.)

---

## After you paste the vocab + approve
Fill `RelationshipVocab`, apply, build 0/0 + diagnostics (all new data types `nonisolated`). Honest note: this
is a live write — I'll verify build/sanitization logic here, but the actual PUT round-trip (200 success/
no_change, and that every enum's snakeKey is accepted) is a device/backend check I can't run. Delete stays
inert. No git.
