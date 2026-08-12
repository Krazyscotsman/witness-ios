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
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
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
    @State private var d = Draft()
    @State private var activeDateField: DateField?

    private enum DateField: Int, Identifiable { case start, end, birth, death; var id: Int { rawValue } }
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
                Group { if editing { editForm } else { readOnly } }
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: category.singular, onBack: { editing ? cancelEdit() : dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeDateField) { field in dateSheet(field) }
    }

    // MARK: Read mode
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

    // MARK: Edit mode — all allowlist fields
    private var editForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit \(category.singular)").font(.serif(26)).foregroundStyle(WT.ink)

            section("Name") {
                textField("First name", $d.firstName)
                textField("Middle name", $d.middleName)
                textField("Last name", $d.lastName)
                textField("Nickname", $d.nickname)
                textField("Maiden name", $d.maidenName)
            }
            section("Relationship") {
                selectField("Relationship type", RelationshipVocab.types, $d.relationshipType, required: true)
                selectField("Family role", RelationshipVocab.familyRoles, $d.familyRole)
                selectField("Significance", RelationshipVocab.significance, $d.significance)
            }
            section("Dates") {
                dateField("Start date", .start, d.startDate)
                dateField("End date", .end, d.endDate)
                selectField("Date precision", RelationshipVocab.precision, $d.datePrecision)
                dateField("Birth date", .birth, d.birthDate)
                selectField("Birth date precision", RelationshipVocab.precision, $d.birthPrecision)
                dateField("Death date", .death, d.deathDate)
                selectField("Death date precision", RelationshipVocab.precision, $d.deathPrecision)
            }
            section("Story & notes") {
                multiField("How you met", $d.howMet)
                multiField("Relationship context", $d.relationshipContext)
                multiField("How it ended", $d.howEnded)
                multiField("Lessons learned", $d.lessonsLearned)
                multiField("Notes", $d.notes)
                multiField("Appearance", $d.appearance)
            }
            section("Privacy") {
                selectField("Privacy level", RelationshipVocab.privacy, $d.privacy)
            }

            // Your Story — read-only, never editable, never sent.
            if let story = row.story {
                VStack(alignment: .leading, spacing: 6) {
                    storyCard(story)
                    Text("Your Story is read-only and isn’t changed by editing.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                }
            }

            if let e = errorMessage {
                Text(e).font(.system(size: 13)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button { cancelEdit() } label: {
                    Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }.witnessPress().disabled(isSaving)
                Button { Task { await save() } } label: {
                    Group { if isSaving { ProgressView().tint(.white) } else { Text("Save changes").font(.system(size: 16, weight: .semibold)) } }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                        .background(isSaving ? WV.teal.opacity(0.5) : WV.teal, in: RoundedRectangle(cornerRadius: 14))
                }.witnessPress().disabled(isSaving)
            }
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

    // MARK: Field builders
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            VStack(spacing: 12) { content() }
        }
    }
    private func fieldLabel(_ label: String, required: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
            if required { Text("*").font(.system(size: 13, weight: .bold)).foregroundStyle(WV.danger) }
        }
    }
    private func textField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(label, text: binding).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14).frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }
    private func multiField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(label, text: binding, axis: .vertical).lineLimit(3...8)
                .font(.serif(16)).foregroundStyle(WT.ink).tint(WV.teal).textInputAutocapitalization(.sentences)
                .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }
    private func selectField(_ label: String, _ options: [String], _ binding: Binding<String>, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label, required: required)
            Menu {
                if !required { Button("— None —") { binding.wrappedValue = "" } }
                ForEach(options, id: \.self) { opt in Button(opt) { binding.wrappedValue = opt } }
            } label: {
                HStack {
                    Text(binding.wrappedValue.isEmpty ? "Select" : binding.wrappedValue)
                        .font(.system(size: 16)).foregroundStyle(binding.wrappedValue.isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            }
        }
    }
    private func dateField(_ label: String, _ field: DateField, _ value: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            HStack {
                Button { activeDateField = field } label: {
                    HStack {
                        Text(value.map { RelSanitize.iso.string(from: $0) } ?? "Add date")
                            .font(.system(size: 16)).foregroundStyle(value == nil ? WT.ink.opacity(0.4) : WT.ink)
                        Spacer()
                        Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(WV.teal)
                    }
                }.buttonStyle(.plain)
                if value != nil {
                    Button { setDate(field, nil) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }
    private func dateSheet(_ field: DateField) -> some View {
        DateSheet(initial: getDate(field) ?? Date(), floor: RelSanitize.dateFloor) { picked in
            setDate(field, picked); activeDateField = nil
        }
    }

    private func getDate(_ f: DateField) -> Date? {
        switch f { case .start: return d.startDate; case .end: return d.endDate; case .birth: return d.birthDate; case .death: return d.deathDate }
    }
    private func setDate(_ f: DateField, _ date: Date?) {
        switch f { case .start: d.startDate = date; case .end: d.endDate = date; case .birth: d.birthDate = date; case .death: d.deathDate = date }
    }

    // MARK: Edit lifecycle
    private func startEdit() {
        d = Draft(
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

    private func validate() -> String? {
        if d.relationshipType.trimmingCharacters(in: .whitespaces).isEmpty { return "Please choose a relationship type." }
        for (label, date) in [("Start date", d.startDate), ("End date", d.endDate), ("Birth date", d.birthDate), ("Death date", d.deathDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = d.startDate, let e = d.endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }

    private func save() async {
        if let msg = validate() { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        func enumVal(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        let body = RelationshipUpdateRequest(
            firstName: t(d.firstName), middleName: t(d.middleName), lastName: t(d.lastName),
            nickname: t(d.nickname), maidenName: t(d.maidenName),
            relationshipType: enumVal(d.relationshipType),
            familyRole: enumVal(d.familyRole), significance: enumVal(d.significance),
            startDate: RelSanitize.string(d.startDate), endDate: RelSanitize.string(d.endDate),
            datePrecision: enumVal(d.datePrecision),
            personBirthDate: RelSanitize.string(d.birthDate), personBirthDatePrecision: enumVal(d.birthPrecision),
            personDeathDate: RelSanitize.string(d.deathDate), personDeathDatePrecision: enumVal(d.deathPrecision),
            howMet: t(d.howMet), relationshipContext: t(d.relationshipContext), howEnded: t(d.howEnded),
            lessonsLearned: t(d.lessonsLearned), notes: t(d.notes), appearanceDescription: t(d.appearance),
            privacyLevel: enumVal(d.privacy))
        do {
            try await auth.updateRelationship(id: row.id, body)
            applyOptimistic(body)
            withAnimation(.easeInOut(duration: 0.2)) { editing = false }
            await vm.refresh(auth: auth)   // reconcile registry counts/chips/list
        } catch {
            errorMessage = Self.friendly(error)   // preserve edits; stay in edit mode
        }
    }

    /// Reflect the sent (stored-form) values locally. Names reach the anchors-list display name only once the
    /// backend name-propagation (Gap 1) lands — the relationship row itself is correct immediately.
    private func applyOptimistic(_ b: RelationshipUpdateRequest) {
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

// Small reusable date-picker sheet with a floor date.
private struct DateSheet: View {
    let initial: Date
    let floor: Date
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: Date, floor: Date, onDone: @escaping (Date) -> Void) {
        self.initial = initial; self.floor = floor; self.onDone = onDone
        _date = State(initialValue: max(initial, floor))
    }
    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            DatePicker("", selection: $date, in: floor...Date(), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
            Button { onDone(date); dismiss() } label: {
                Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment).presentationDetents([.height(420)])
    }
}
