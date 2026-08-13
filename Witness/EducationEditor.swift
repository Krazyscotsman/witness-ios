import SwiftUI

// MARK: - Vocabularies (DISPLAY labels; sent as snakeKey via RelSanitize). No date_precision (server-side).
enum EducationVocab {
    static let institutionType: [String] = ["High School","College","University","Bootcamp","Online Course","Certification"]
    static let attendanceMode: [String] = ["In-person","Online","Hybrid"]
}

// MARK: - Shared edit/create draft. degree_achieved is a Bool (kept out of the text sanitize path).
struct EducationDraft {
    var institutionName = "", institutionType = "", institutionLocation = "", attendanceMode = ""
    var degreeType = "", fieldOfStudy = ""
    var degreeAchieved = false
    var startDate: Date?, endDate: Date?, graduationDate: Date?
    var achievements = "", challenges = "", notes = ""

    /// Sanitized allowlisted body — the SAME 13 columns for POST and PUT. NO date_precision.
    func writeRequest() -> EducationWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }  // selects
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return EducationWriteRequest(
            institutionName: t(institutionName), institutionType: e(institutionType),
            institutionLocation: t(institutionLocation), attendanceMode: e(attendanceMode),
            degreeType: t(degreeType), fieldOfStudy: t(fieldOfStudy),
            degreeAchieved: degreeAchieved,                    // Bool passed straight through (JSON true/false)
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

// MARK: - Shared form (AnchorFormKit + the toggle; no Your Story)
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
            let cur = f == .start ? draft.startDate : (f == .end ? draft.endDate : draft.graduationDate)
            AnchorDateSheet(initial: cur ?? Date(), floor: RelSanitize.dateFloor) { picked in
                switch f { case .start: draft.startDate = picked; case .end: draft.endDate = picked; case .graduation: draft.graduationDate = picked }
                activeDateField = nil
            }
        }
    }
}

// MARK: - vm-reactive list (off vm.education) + "Add New"
struct EducationListView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    private let category = AnchorCategory.find("education")
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [EducationRow] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let f = q.isEmpty ? vm.education : vm.education.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
        return f.sorted { $0.sortKey > $1.sortKey }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(category.label).font(.serif(26)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    searchBar
                    if visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: category.icon).font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
                            Text(search.isEmpty ? "No education yet." : "No matches for “\(search)”.")
                                .font(.serif(20)).foregroundStyle(WT.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(visible) { r in
                            NavigationLink { EducationDetailView(row: r, vm: vm, auth: auth) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
                NavigationLink { EducationCreateView(vm: vm, auth: auth) } label: { anchorAddIcon() }
                    .witnessPress().witnessHint("Add a new education record.")
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
    private func row(_ r: EducationRow) -> some View {
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

// MARK: - Create (POST /timeline/education) — attendance In-person + degree_achieved false defaults
struct EducationCreateView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("education")

    @State private var d = EducationDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                EducationFormView(title: "New \(category.singular)", draft: $d, errorMessage: $errorMessage,
                                  isSaving: isSaving, saveTitle: "Add education",
                                  onSave: { Task { await create() } }, onCancel: { dismiss() })
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !prefilled else { return }
            d.attendanceMode = "In-person"; d.degreeAchieved = false   // defaults
            prefilled = true
        }
    }

    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do {
            try await auth.createEducation(d.writeRequest())
            await vm.refresh(auth: auth)
            dismiss()
        } catch {
            errorMessage = EducationCreateView.friendly(error)
        }
    }
    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return "Your session has timed out. Please sign in again."
            case .network:        return "We couldn’t add this. Please check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:              return "Something went wrong adding this. Please try again."
            }
        }
        return "Something went wrong adding this. Please try again."
    }
}

// MARK: - Education detail (read mode + edit mode → PUT /timeline/education/{id}). No Your Story.
struct EducationDetailView: View {
    @State var row: EducationRow
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("education")

    @State private var editing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var d = EducationDraft()

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

    private var editForm: some View {
        EducationFormView(title: "Edit \(category.singular)", draft: $d, errorMessage: $errorMessage,
                          isSaving: isSaving, saveTitle: "Save changes",
                          onSave: { Task { await save() } }, onCancel: cancelEdit)
    }

    private func startEdit() {
        d = EducationDraft(
            institutionName: row.institutionName ?? "",
            institutionType: RelSanitize.option(for: row.institutionType, in: EducationVocab.institutionType),
            institutionLocation: row.institutionLocation ?? "",
            attendanceMode: RelSanitize.option(for: row.attendanceMode, in: EducationVocab.attendanceMode),
            degreeType: row.degreeType ?? "", fieldOfStudy: row.fieldOfStudy ?? "",
            degreeAchieved: row.degreeAchieved ?? false,
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            graduationDate: RelSanitize.parse(row.graduationDate),
            achievements: row.achievements ?? "", challenges: row.challenges ?? "", notes: row.notes ?? "")
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) { editing = true }
    }
    private func cancelEdit() { errorMessage = nil; withAnimation(.easeInOut(duration: 0.2)) { editing = false } }

    private func save() async {
        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        let body = d.writeRequest()
        do {
            try await auth.updateEducation(id: row.id, body)
            applyOptimistic(body)
            withAnimation(.easeInOut(duration: 0.2)) { editing = false }
            await vm.refresh(auth: auth)
        } catch {
            errorMessage = EducationDetailView.friendly(error)
        }
    }

    private func applyOptimistic(_ b: EducationWriteRequest) {
        row.institutionName = b.institutionName.neb; row.institutionType = b.institutionType.neb
        row.institutionLocation = b.institutionLocation.neb; row.attendanceMode = b.attendanceMode.neb
        row.degreeType = b.degreeType.neb; row.fieldOfStudy = b.fieldOfStudy.neb
        row.degreeAchieved = b.degreeAchieved
        row.startDate = b.startDate.neb; row.endDate = b.endDate.neb; row.graduationDate = b.graduationDate.neb
        row.achievements = b.achievements.neb; row.challenges = b.challenges.neb; row.notes = b.notes.neb
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

private extension String { var neb: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
