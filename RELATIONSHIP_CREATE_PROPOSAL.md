# Witness — Add New relationship anchor (POST /timeline/relationships) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Reuses Phase 2b editor (allowlist/vocab/sanitizer).
Endpoint: POST /timeline/relationships — BARE path, Bearer, free-form JSON; server drops id/empties, injects
narrator_id, INSERTs; trigger mints the entity (is_anchor=true) + dedups by normalized name. Any-2xx = success.
Send ONLY the 22-column allowlist (same 500-footgun). No /continuity/truths.

## Read-first findings
- RelationshipEditor.swift has RelationshipVocab, RelSanitize, RelationshipUpdateRequest (22-col allowlist),
  but the FORM (Draft, field builders, validate, body-build) lives inside RelationshipDetailView's edit mode.
- RelationshipListView takes a STATIC `rows: [RelationshipRow]` snapshot → a new/edited person won't appear on
  pop. Fixing to vm-computed `source`.
- APIClient.post decodes the response → add postIgnoringResponseBody (any-2xx, ignore body) like the PUT.

## Decisions (baked in; change any)
1. Rename RelationshipUpdateRequest → RelationshipWriteRequest (shared POST + PUT).
2. Extract shared RelationshipDraft + RelationshipFormView (edit + create both use them; refactors the editor).
3. RelationshipListView: static rows → vm-computed `source` (so created/edited people appear reactively).
4. Add APIClient.postIgnoringResponseBody.
5. anchorNavBar gains optional trailing (+ button); existing callers unaffected.
6. Create prefill: type-chip lists prefill relationship_type; category hub + Critical People prefill nothing.
7. Create is a pushed screen; on success await vm.refresh then dismiss.

---

## APIClient.swift — add postIgnoringResponseBody (mirrors putIgnoringResponseBody)
```swift
    /// POST that treats any 2xx as success and does NOT decode the response body (INSERT acks vary:
    /// {status}, {id}, 201, etc.). Throws APIError on 401 / non-2xx / transport. Returns raw bytes.
    @discardableResult
    func postIgnoringResponseBody<Body: Encodable>(
        _ path: String, body: Body, authorized: Bool = true, timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.encoding(error) }
        if authorized, let token = tokenProvider() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw APIError.network(error) }
        guard let http = response as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }
        if http.statusCode == 401 {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }
```

## APIModels.swift — rename the struct (POST + PUT share it)
```diff
-nonisolated struct RelationshipUpdateRequest: Encodable {
+nonisolated struct RelationshipWriteRequest: Encodable {
     ... unchanged 22 fields + CodingKeys ...
 }
```

## AuthManager.swift — rename param type + add create
```diff
-    func updateRelationship(id: String, _ body: RelationshipUpdateRequest) async throws {
+    func updateRelationship(id: String, _ body: RelationshipWriteRequest) async throws {
         _ = try await api.putIgnoringResponseBody("/timeline/relationships/\(id)", body: body, timeout: 20)
     }
+
+    /// Truth-registry create. POST /timeline/relationships (BARE path). Any 2xx = success. Backend injects
+    /// narrator_id, mints the entity (is_anchor=true), dedups by normalized name. Throws APIError.
+    func createRelationship(_ body: RelationshipWriteRequest) async throws {
+        _ = try await api.postIgnoringResponseBody("/timeline/relationships", body: body, timeout: 20)
+    }
```

## RelationshipEditor.swift — extract Draft + form; add create; refactor list

### (a) Top-level RelationshipDraft (moved out of RelationshipDetailView) + shared sanitize/validate
```swift
struct RelationshipDraft {
    var firstName = "", middleName = "", lastName = "", nickname = "", maidenName = ""
    var relationshipType = "", familyRole = "", significance = "", privacy = ""
    var datePrecision = "", birthPrecision = "", deathPrecision = ""
    var startDate: Date?, endDate: Date?, birthDate: Date?, deathDate: Date?
    var howMet = "", relationshipContext = "", howEnded = "", lessonsLearned = "", notes = "", appearance = ""

    /// Sanitized allowlisted body (shared by PUT edit + POST create).
    func writeRequest() -> RelationshipWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return RelationshipWriteRequest(
            firstName: t(firstName), middleName: t(middleName), lastName: t(lastName),
            nickname: t(nickname), maidenName: t(maidenName),
            relationshipType: e(relationshipType), familyRole: e(familyRole), significance: e(significance),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate),
            datePrecision: e(datePrecision),
            personBirthDate: RelSanitize.string(birthDate), personBirthDatePrecision: e(birthPrecision),
            personDeathDate: RelSanitize.string(deathDate), personDeathDatePrecision: e(deathPrecision),
            howMet: t(howMet), relationshipContext: t(relationshipContext), howEnded: t(howEnded),
            lessonsLearned: t(lessonsLearned), notes: t(notes), appearanceDescription: t(appearance),
            privacyLevel: e(privacy))
    }
    /// Create requires a name; edit does not. Dates always ≥ 1910 and end ≥ start.
    func validationError(requireName: Bool) -> String? {
        if relationshipType.trimmingCharacters(in: .whitespaces).isEmpty { return "Please choose a relationship type." }
        if requireName,
           firstName.trimmingCharacters(in: .whitespaces).isEmpty,
           lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Please enter a first or last name."
        }
        for (label, date) in [("Start date", startDate), ("End date", endDate), ("Birth date", birthDate), ("Death date", deathDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}
```

### (b) Shared RelationshipFormView (fields + selects + date pickers + save/cancel). Your Story only if `story != nil`.
```swift
struct RelationshipFormView: View {
    let title: String
    @Binding var draft: RelationshipDraft
    let story: String?                 // read-only Your Story; nil in create → hidden
    @Binding var errorMessage: String?
    let isSaving: Bool
    let saveTitle: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var activeDateField: DateField?
    private enum DateField: Int, Identifiable { case start, end, birth, death; var id: Int { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            section("Name") {
                textField("First name", $draft.firstName); textField("Middle name", $draft.middleName)
                textField("Last name", $draft.lastName); textField("Nickname", $draft.nickname)
                textField("Maiden name", $draft.maidenName)
            }
            section("Relationship") {
                selectField("Relationship type", RelationshipVocab.types, $draft.relationshipType, required: true)
                selectField("Family role", RelationshipVocab.familyRoles, $draft.familyRole)
                selectField("Significance", RelationshipVocab.significance, $draft.significance)
            }
            section("Dates") {
                dateField("Start date", .start, draft.startDate); dateField("End date", .end, draft.endDate)
                selectField("Date precision", RelationshipVocab.precision, $draft.datePrecision)
                dateField("Birth date", .birth, draft.birthDate)
                selectField("Birth date precision", RelationshipVocab.precision, $draft.birthPrecision)
                dateField("Death date", .death, draft.deathDate)
                selectField("Death date precision", RelationshipVocab.precision, $draft.deathPrecision)
            }
            section("Story & notes") {
                multiField("How you met", $draft.howMet); multiField("Relationship context", $draft.relationshipContext)
                multiField("How it ended", $draft.howEnded); multiField("Lessons learned", $draft.lessonsLearned)
                multiField("Notes", $draft.notes); multiField("Appearance", $draft.appearance)
            }
            section("Privacy") { selectField("Privacy level", RelationshipVocab.privacy, $draft.privacy) }

            if let story {                       // edit only — read-only, never sent
                VStack(alignment: .leading, spacing: 6) {
                    storyCard(story)
                    Text("Your Story is read-only and isn’t changed by editing.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                }
            }
            if let e = errorMessage { Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(action: onCancel) { /* Cancel button (white) */ EmptyView() }.disabled(isSaving)
                Button(action: onSave) { /* Save button: spinner when isSaving, else saveTitle */ EmptyView() }.disabled(isSaving)
            }
        }
        .sheet(item: $activeDateField) { f in
            DateSheet(initial: getDate(f) ?? Date(), floor: RelSanitize.dateFloor) { picked in setDate(f, picked); activeDateField = nil }
        }
    }
    // storyCard / section / fieldLabel / textField / multiField / selectField / dateField / getDate / setDate
    // are MOVED VERBATIM from the current RelationshipDetailView (bound to $draft instead of $d). Save/Cancel
    // buttons use the same styling as the current editForm. (EmptyView() shown only to keep this doc short.)
}
```

### (c) RelationshipDetailView — edit mode now renders the shared form; save uses draft.writeRequest()
```diff
-    @State private var d = Draft()
-    @State private var activeDateField: DateField?
-    private enum DateField ... { ... }
-    struct Draft { ... }
+    @State private var d = RelationshipDraft()
```
```diff
-    private var editForm: some View { VStack { ... all fields + builders ... } }
+    private var editForm: some View {
+        RelationshipFormView(title: "Edit \(category.singular)", draft: $d, story: row.story,
+                             errorMessage: $errorMessage, isSaving: isSaving, saveTitle: "Save changes",
+                             onSave: { Task { await save() } }, onCancel: cancelEdit)
+    }
```
```diff
     private func save() async {
-        if let msg = validate() { errorMessage = msg; return }
+        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
         errorMessage = nil; isSaving = true; defer { isSaving = false }
-        ... inline body build ...
-        let body = RelationshipUpdateRequest( ... )
+        let body = d.writeRequest()
         do { try await auth.updateRelationship(id: row.id, body); applyOptimistic(body)
              withAnimation { editing = false }; await vm.refresh(auth: auth) }
         catch { errorMessage = Self.friendly(error) }
     }
```
(The field builders / DateSheet / DateField / validate() are removed from RelationshipDetailView — moved to
the shared form/draft. startEdit() still fills `d`. applyOptimistic + friendly stay.)

### (d) RelationshipListView — static rows → vm-computed source + "Add New"
```diff
 struct RelationshipListView: View {
     let title: String
-    let rows: [RelationshipRow]
+    let source: RelSource
     @ObservedObject var vm: AnchorRegistryViewModel
     @ObservedObject var auth: AuthManager
     ...
-    private var visible: [RelationshipRow] { /* filter+sort rows */ }
+    private var allRows: [RelationshipRow] {
+        switch source { case .type(let key, _): return vm.relationships(typeKey: key); case .critical: return vm.criticalPeople }
+    }
+    private var prefillType: String? { if case .type(_, let display) = source { return display } else { return nil } }
+    private var visible: [RelationshipRow] { /* filter+sort allRows (unchanged logic) */ }
 }
enum RelSource { case type(key: String, display: String), critical }
```
Add a trailing "+" to the list's nav bar:
```diff
-            anchorNavBar(title: "Anchors", onBack: { dismiss() })
+            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
+                NavigationLink { RelationshipCreateView(prefillType: prefillType, vm: vm, auth: auth) } label: { addIcon }
+                    .witnessPress()
+            }
```
`addIcon` = a teal circle "+" (same style as the old AnchorsView add button).

### (e) NEW RelationshipCreateView
```swift
struct RelationshipCreateView: View {
    let prefillType: String?
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("relationships")

    @State private var d = RelationshipDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                RelationshipFormView(title: "New \(category.singular)", draft: $d, story: nil,
                                     errorMessage: $errorMessage, isSaving: isSaving, saveTitle: "Add person",
                                     onSave: { Task { await create() } }, onCancel: { dismiss() })
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear { if !prefilled { if let t = prefillType { d.relationshipType = t }; prefilled = true } }
    }

    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }   // type + a name
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do {
            try await auth.createRelationship(d.writeRequest())
            await vm.refresh(auth: auth)      // new person appears in the (now vm-computed) list
            dismiss()
        } catch {
            errorMessage = RelationshipCreateView.friendly(error)   // preserve input; stay on form
        }
    }
    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return "Your session has timed out. Please sign in again."
            case .network:        return "We couldn’t add this person. Please check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:              return "Something went wrong adding this person. Please try again."
            }
        }
        return "Something went wrong adding this person. Please try again."
    }
}
```

## AnchorRegistryView.swift — anchorNavBar trailing + L2 wiring + "Add New"
```diff
-func anchorNavBar(title: String, onBack: @escaping () -> Void) -> some View {
+func anchorNavBar<Trailing: View>(title: String, onBack: @escaping () -> Void,
+                                  @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
     HStack {
         Button(action: onBack) { ... back ... }.witnessPress()
         Spacer()
+        trailing()
     }
     .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
 }
```
L2 relationship links → RelationshipListView(source:) + an "Add New" "+" in L2's nav bar:
```diff
     NavigationLink {
-        RelationshipListView(title: "Critical People", rows: critical, vm: vm, auth: auth)
+        RelationshipListView(title: "Critical People", source: .critical, vm: vm, auth: auth)
     } label: { criticalCard(count: critical.count) }
```
```diff
     NavigationLink {
-        RelationshipListView(title: chip.title, rows: vm.relationships(typeKey: chip.id), vm: vm, auth: auth)
+        RelationshipListView(title: chip.title, source: .type(key: chip.id, display: chip.title), vm: vm, auth: auth)
     } label: { chipRow(chip) }
```
```diff
-            anchorNavBar(title: "Anchors", onBack: { dismiss() })
+            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
+                NavigationLink { RelationshipCreateView(prefillType: nil, vm: vm, auth: auth) } label: { addIcon }
+                    .witnessPress()
+            }
```
(Other 6 categories still call `anchorNavBar(title:onBack:)` with the defaulted empty trailing — untouched.)

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live POST round-trip (2xx, entity mint, name-dedup) is a
device/backend check I can't run here — I'll verify build + that create sends only the 22 allowlist columns
sanitized, and that the new person surfaces via the vm-computed list after refresh. Delete stays inert;
relationships only; no /continuity/truths. No git.
