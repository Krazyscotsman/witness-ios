import SwiftUI

// MARK: - Vocabularies (DISPLAY labels; sent as snakeKey). Verbatim from the Relationship Anchor Editor spec.
// Confirmed: snakeKey(display) == the backend's stored form for every enum, incl. "In-Law Parent" →
// in_law_parent (spec: relationship_type stored snake_case) and "Family Only" → family_only (spec-confirmed).
enum RelationshipVocab {
    static let types: [String] = [
        "Spouse","Parent Child","Siblings","Half Siblings","Step Sibling","Step Parent","Step Child","Twin",
        "Grandparent Grandchild","Aunt Uncle Niece Nephew","Cousins","Adopted Parent","Adopted Child",
        "Foster Parent","Foster Child","Godparent","Godchild","In-Law Parent","In-Law Sibling","In-Law Child",
        "Partners Parent","Romantic","Partner","Ex Spouse","Ex Partner","Friend","Best Friend","Acquaintance",
        "Neighbor","Roommate","Classmate","Professional","Colleague","Boss","Subordinate","Mentor","Mentee",
        "Client","Pet Owner","Caregiver","Doctor","Therapist","Teacher","Student","Family","Enemy","Other"
    ]
    static let familyRoles: [String] = [
        "Parent","Child","Sibling","Step Parent","Step Child","Step Sibling","Adoptive Parent","Adopted Child",
        "Half Sibling","Grandparent","Grandchild","Guardian","Ward"
    ]
    static let significance: [String] = ["Critical","High","Moderate","Low"]
    static let precision: [String] = ["Day","Month","Year"]
    static let privacy: [String] = ["Private","Family Only","Public"]
}

// MARK: - Sanitizers (UI label → stored form; ISO dates; select pre-selection)
enum RelSanitize {
    /// "In-Law Parent" → "in_law_parent"; "Ex Spouse" → "ex_spouse". Runs of non-alphanumerics → single "_".
    static func snakeKey(_ s: String) -> String {
        var out = "", lastUnderscore = true   // start true → trims any leading separators
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
    static func string(_ d: Date?) -> String { d.map { iso.string(from: $0) } ?? "" }
    static func parse(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return iso.date(from: String(s.prefix(10)))
    }
    /// Pre-select the display option whose snakeKey matches the stored value (robust to casing/hyphens).
    static func option(for stored: String?, in options: [String]) -> String {
        let key = snakeKey(stored ?? ""); guard !key.isEmpty else { return "" }
        return options.first { snakeKey($0) == key } ?? ""
    }
    static let dateFloor = iso.date(from: "1910-01-01")!
}

// MARK: - Shared edit/create draft (one sanitize + one validation, reused by PUT edit and POST create)
struct RelationshipDraft {
    var firstName = "", middleName = "", lastName = "", nickname = "", maidenName = ""
    var relationshipType = "", familyRole = "", significance = "", privacy = ""
    var datePrecision = "", birthPrecision = "", deathPrecision = ""
    var startDate: Date?, endDate: Date?, birthDate: Date?, deathDate: Date?
    var howMet = "", relationshipContext = "", howEnded = "", lessonsLearned = "", notes = "", appearance = ""

    /// Sanitized allowlisted body — the SAME 22 columns for POST (create) and PUT (edit).
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

// MARK: - Shared form (used by both edit mode and create). Your Story shows only when `story != nil`.
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

            anchorFormSection("Name") {
                anchorTextField("First name", $draft.firstName)
                anchorTextField("Middle name", $draft.middleName)
                anchorTextField("Last name", $draft.lastName)
                anchorTextField("Nickname", $draft.nickname)
                anchorTextField("Maiden name", $draft.maidenName)
            }
            anchorFormSection("Relationship") {
                anchorSelectField("Relationship type", RelationshipVocab.types, $draft.relationshipType, required: true)
                anchorSelectField("Family role", RelationshipVocab.familyRoles, $draft.familyRole)
                anchorSelectField("Significance", RelationshipVocab.significance, $draft.significance)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { setDate(.start, nil) })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { setDate(.end, nil) })
                anchorSelectField("Date precision", RelationshipVocab.precision, $draft.datePrecision)
                anchorDateField("Birth date", draft.birthDate, onEdit: { activeDateField = .birth }, onClear: { setDate(.birth, nil) })
                anchorSelectField("Birth date precision", RelationshipVocab.precision, $draft.birthPrecision)
                anchorDateField("Death date", draft.deathDate, onEdit: { activeDateField = .death }, onClear: { setDate(.death, nil) })
                anchorSelectField("Death date precision", RelationshipVocab.precision, $draft.deathPrecision)
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("How you met", $draft.howMet)
                anchorMultiField("Relationship context", $draft.relationshipContext)
                anchorMultiField("How it ended", $draft.howEnded)
                anchorMultiField("Lessons learned", $draft.lessonsLearned)
                anchorMultiField("Notes", $draft.notes)
                anchorMultiField("Appearance", $draft.appearance)
            }
            anchorFormSection("Privacy") {
                anchorSelectField("Privacy level", RelationshipVocab.privacy, $draft.privacy)
            }

            if let story {   // edit only — read-only, never sent
                VStack(alignment: .leading, spacing: 6) {
                    storyCard(story)
                    Text("Your Story is read-only and isn’t changed by editing.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                }
            }

            if let e = errorMessage {
                Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
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
            AnchorDateSheet(initial: getDate(f) ?? Date(), floor: RelSanitize.dateFloor) { picked in setDate(f, picked); activeDateField = nil }
        }
    }

    private func storyCard(_ story: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR STORY").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            Text(story).font(.serif(17)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.06), lineWidth: 1))
    }

    private func getDate(_ f: DateField) -> Date? {
        switch f { case .start: return draft.startDate; case .end: return draft.endDate; case .birth: return draft.birthDate; case .death: return draft.deathDate }
    }
    private func setDate(_ f: DateField, _ date: Date?) {
        switch f { case .start: draft.startDate = date; case .end: draft.endDate = date; case .birth: draft.birthDate = date; case .death: draft.deathDate = date }
    }
}

// MARK: - Where a relationships list gets its rows (vm-computed → new/edited people appear reactively)
enum RelSource { case type(key: String, display: String), critical }

// MARK: - Relationships list (RelationshipRow-specific; routes to the editable detail + "Add New")
struct RelationshipListView: View {
    let title: String
    let source: RelSource
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    private let category = AnchorCategory.find("relationships")
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var allRows: [RelationshipRow] {
        switch source {
        case .type(let key, _): return vm.relationships(typeKey: key)
        case .critical:         return vm.criticalPeople
        }
    }
    private var prefillType: String? { if case .type(_, let display) = source { return display } else { return nil } }
    private var visible: [RelationshipRow] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let f = q.isEmpty ? allRows : allRows.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
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
                            Text(search.isEmpty ? "Nothing here yet." : "No matches for “\(search)”.")
                                .font(.serif(20)).foregroundStyle(WT.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(visible) { r in
                            NavigationLink { RelationshipDetailView(row: r, vm: vm, auth: auth) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
                NavigationLink { RelationshipCreateView(prefillType: prefillType, vm: vm, auth: auth) } label: { anchorAddIcon() }
                    .witnessPress()
                    .witnessHint("Add a new person" + (prefillType.map { " (\($0))" } ?? "") + ".")
            }
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.4))
            TextField("Search", text: $search).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).autocorrectionDisabled()
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 14).frame(height: 50).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
    private func row(_ r: RelationshipRow) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.1)); Image(systemName: category.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(category.tone) }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.displayName).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                if !r.subtitle.isEmpty { Text(r.subtitle).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
}

// MARK: - Create (POST /timeline/relationships) — empty form, optional relationship_type prefill
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !prefilled else { return }
            if let t = prefillType { d.relationshipType = t }   // e.g. from the "Romantic" subcategory
            prefilled = true
        }
    }

    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }   // type + a name
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do {
            try await auth.createRelationship(d.writeRequest())
            await vm.refresh(auth: auth)     // new person appears in the vm-computed list
            dismiss()
        } catch {
            errorMessage = RelationshipCreateView.friendly(error)   // preserve input; stay on the form
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

// MARK: - Relationship detail (read mode + edit mode → PUT /timeline/relationships/{id})
struct RelationshipDetailView: View {
    @State var row: RelationshipRow                 // local; updated optimistically on save
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("relationships")

    @State private var editing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var d = RelationshipDraft()
    @AppStorage(Profile.enableDetailsKey) private var enableDetails = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                Group { if editing { editForm } else { readOnly } }
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: category.singular, onBack: { editing ? cancelEdit() : dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    // Read mode
    private var readOnly: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text((row.typeLabel ?? category.singular).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(category.tone)
                Text(row.displayName).font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }
            let shown = row.detailFields.filter { ($0.value?.trimmingCharacters(in: .whitespaces).isEmpty == false) }
            if shown.isEmpty {
                Text("No details recorded yet.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                            Text(f.value ?? "").font(.system(size: 16)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
            }
            if let story = row.story { storyCard(story) }
            if enableDetails, let eid = row.personEntityId, !eid.isEmpty {
                NavigationLink {
                    EntityDetailPage(entityId: eid,
                                     seed: EntitySeed(name: row.displayName, type: "person", isAnchor: true,
                                                      relationship: row.typeLabel),
                                     auth: auth)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.expand.vertical").font(.system(size: 14, weight: .semibold))
                        Text("See everything").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(WV.teal).frame(maxWidth: .infinity).frame(height: 48)
                    .background(WV.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WV.teal.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { startEdit() } label: {
                    Text("Edit").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
                }.witnessPress()
                // Delete stays INERT (backend Gap 2) — visibly disabled, no action.
                Text("Delete").font(.system(size: 16, weight: .semibold)).foregroundStyle(WV.danger.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WV.danger.opacity(0.2), lineWidth: 1)).opacity(0.6)
            }
            Text("Deleting is coming soon.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
    }

    private func storyCard(_ story: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR STORY").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            Text(story).font(.serif(17)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.06), lineWidth: 1))
    }

    // Edit mode → shared form
    private var editForm: some View {
        RelationshipFormView(title: "Edit \(category.singular)", draft: $d, story: row.story,
                             errorMessage: $errorMessage, isSaving: isSaving, saveTitle: "Save changes",
                             onSave: { Task { await save() } }, onCancel: cancelEdit)
    }

    private func startEdit() {
        d = RelationshipDraft(
            firstName: row.firstName ?? "", middleName: row.middleName ?? "", lastName: row.lastName ?? "",
            nickname: row.nickname ?? "", maidenName: row.maidenName ?? "",
            relationshipType: RelSanitize.option(for: row.relationshipType, in: RelationshipVocab.types),
            familyRole: RelSanitize.option(for: row.familyRole, in: RelationshipVocab.familyRoles),
            significance: RelSanitize.option(for: row.significance, in: RelationshipVocab.significance),
            privacy: RelSanitize.option(for: row.privacyLevel, in: RelationshipVocab.privacy),
            datePrecision: RelSanitize.option(for: row.datePrecision, in: RelationshipVocab.precision),
            birthPrecision: RelSanitize.option(for: row.personBirthDatePrecision, in: RelationshipVocab.precision),
            deathPrecision: RelSanitize.option(for: row.personDeathDatePrecision, in: RelationshipVocab.precision),
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            birthDate: RelSanitize.parse(row.personBirthDate), deathDate: RelSanitize.parse(row.personDeathDate),
            howMet: row.howMet ?? "", relationshipContext: row.relationshipContext ?? "",
            howEnded: row.howEnded ?? "", lessonsLearned: row.lessonsLearned ?? "",
            notes: row.notes ?? "", appearance: row.appearanceDescription ?? "")
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) { editing = true }
    }
    private func cancelEdit() { errorMessage = nil; withAnimation(.easeInOut(duration: 0.2)) { editing = false } }

    private func save() async {
        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        let body = d.writeRequest()
        do {
            try await auth.updateRelationship(id: row.id, body)
            applyOptimistic(body)
            withAnimation(.easeInOut(duration: 0.2)) { editing = false }
            await vm.refresh(auth: auth)
        } catch {
            errorMessage = Self.friendly(error)   // preserve edits; stay in edit mode
        }
    }

    /// Reflect the sent (stored-form) values locally. Names reach the anchors-list display name only once the
    /// backend name-propagation (Gap 1) lands — the relationship row itself is correct immediately.
    private func applyOptimistic(_ b: RelationshipWriteRequest) {
        row.firstName = b.firstName.nib; row.middleName = b.middleName.nib; row.lastName = b.lastName.nib
        row.nickname = b.nickname.nib; row.maidenName = b.maidenName.nib
        row.relationshipType = b.relationshipType.nib; row.familyRole = b.familyRole.nib
        row.significance = b.significance.nib; row.privacyLevel = b.privacyLevel.nib
        row.startDate = b.startDate.nib; row.endDate = b.endDate.nib; row.datePrecision = b.datePrecision.nib
        row.personBirthDate = b.personBirthDate.nib; row.personBirthDatePrecision = b.personBirthDatePrecision.nib
        row.personDeathDate = b.personDeathDate.nib; row.personDeathDatePrecision = b.personDeathDatePrecision.nib
        row.howMet = b.howMet.nib; row.relationshipContext = b.relationshipContext.nib; row.howEnded = b.howEnded.nib
        row.lessonsLearned = b.lessonsLearned.nib; row.notes = b.notes.nib; row.appearanceDescription = b.appearanceDescription.nib
        // nbqResponse + personCanonicalName untouched (never sent).
    }

    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return "Your session has timed out. Please sign in again."
            case .network:        return "We couldn’t save your changes. Please check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:              return "Something went wrong saving your changes. Please try again."
            }
        }
        return "Something went wrong saving your changes. Please try again."
    }
}

private extension String { var nib: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
