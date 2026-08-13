import SwiftUI

// MARK: - Vocabularies (DISPLAY labels; sent as snakeKey via RelSanitize). Stored forms verified by execution:
// Full-time/Part-time/Contract/Freelance/Internship/Volunteer → full_time/part_time/contract/freelance/
// internship/volunteer; On-site/Remote/Hybrid → on_site/remote/hybrid; Day/Month/Year → day/month/year.
enum JobVocab {
    static let employmentType: [String] = ["Full-time","Part-time","Contract","Freelance","Internship","Volunteer"]
    static let workMode: [String] = ["On-site","Remote","Hybrid"]
    static let precision: [String] = ["Day","Month","Year"]
}

// MARK: - Shared edit/create draft (one sanitize + one validation for POST create and PUT edit)
struct JobDraft {
    var employerName = "", industry = "", workLocation = "", jobTitle = "", department = ""
    var employmentType = "", workMode = "", precision = ""
    var startDate: Date?, endDate: Date?
    var reasonForJoining = "", reasonForLeaving = "", keyResponsibilities = "", majorAchievements = ""
    var skillsGained = "", certificationsEarned = "", notes = ""

    /// Sanitized allowlisted body — the SAME 17 columns for POST and PUT.
    func writeRequest() -> JobWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }  // enums
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
    /// Create requires an employer name; edit does not. Dates always ≥ 1910 and end ≥ start.
    func validationError(requireName: Bool) -> String? {
        if requireName, employerName.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter an employer name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

// MARK: - Shared form (no Your Story — jobs have none)
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
                if f == .start { draft.startDate = picked } else { draft.endDate = picked }
                activeDateField = nil
            }
        }
    }
}

// MARK: - vm-reactive list (off vm.jobs) + "Add New"
struct JobListView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    private let category = AnchorCategory.find("jobs")
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [JobRow] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let f = q.isEmpty ? vm.jobs : vm.jobs.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
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
                            Text(search.isEmpty ? "No jobs yet." : "No matches for “\(search)”.")
                                .font(.serif(20)).foregroundStyle(WT.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(visible) { r in
                            NavigationLink { JobDetailView(row: r, vm: vm, auth: auth) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
                NavigationLink { JobCreateView(vm: vm, auth: auth) } label: { anchorAddIcon() }
                    .witnessPress().witnessHint("Add a new job.")
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
    private func row(_ r: JobRow) -> some View {
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

// MARK: - Create (POST /timeline/jobs) — empty form, employment/mode/precision defaults
struct JobCreateView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("jobs")

    @State private var d = JobDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                JobFormView(title: "New \(category.singular)", draft: $d, errorMessage: $errorMessage,
                            isSaving: isSaving, saveTitle: "Add job",
                            onSave: { Task { await create() } }, onCancel: { dismiss() })
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !prefilled else { return }
            d.employmentType = "Full-time"; d.workMode = "On-site"; d.precision = "Month"   // defaults
            prefilled = true
        }
    }

    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do {
            try await auth.createJob(d.writeRequest())
            await vm.refresh(auth: auth)
            dismiss()
        } catch {
            errorMessage = JobCreateView.friendly(error)
        }
    }
    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return "Your session has timed out. Please sign in again."
            case .network:        return "We couldn’t add this job. Please check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:              return "Something went wrong adding this job. Please try again."
            }
        }
        return "Something went wrong adding this job. Please try again."
    }
}

// MARK: - Job detail (read mode + edit mode → PUT /timeline/jobs/{id}). No Your Story.
struct JobDetailView: View {
    @State var row: JobRow
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("jobs")

    @State private var editing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var d = JobDraft()

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
        JobFormView(title: "Edit \(category.singular)", draft: $d, errorMessage: $errorMessage,
                    isSaving: isSaving, saveTitle: "Save changes",
                    onSave: { Task { await save() } }, onCancel: cancelEdit)
    }

    private func startEdit() {
        d = JobDraft(
            employerName: row.employerName ?? "", industry: row.employerIndustry ?? "",
            workLocation: row.workLocation ?? "", jobTitle: row.jobTitle ?? "", department: row.department ?? "",
            employmentType: RelSanitize.option(for: row.employmentType, in: JobVocab.employmentType),
            workMode: RelSanitize.option(for: row.workMode, in: JobVocab.workMode),
            precision: RelSanitize.option(for: row.datePrecision, in: JobVocab.precision),
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            reasonForJoining: row.reasonForJoining ?? "", reasonForLeaving: row.reasonForLeaving ?? "",
            keyResponsibilities: row.keyResponsibilities ?? "", majorAchievements: row.majorAchievements ?? "",
            skillsGained: row.skillsGained ?? "", certificationsEarned: row.certificationsEarned ?? "", notes: row.notes ?? "")
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) { editing = true }
    }
    private func cancelEdit() { errorMessage = nil; withAnimation(.easeInOut(duration: 0.2)) { editing = false } }

    private func save() async {
        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        let body = d.writeRequest()
        do {
            try await auth.updateJob(id: row.id, body)
            applyOptimistic(body)
            withAnimation(.easeInOut(duration: 0.2)) { editing = false }
            await vm.refresh(auth: auth)
        } catch {
            errorMessage = JobDetailView.friendly(error)
        }
    }

    private func applyOptimistic(_ b: JobWriteRequest) {
        row.employerName = b.employerName.njb; row.employerIndustry = b.employerIndustry.njb
        row.workLocation = b.workLocation.njb; row.jobTitle = b.jobTitle.njb; row.department = b.department.njb
        row.employmentType = b.employmentType.njb; row.workMode = b.workMode.njb
        row.startDate = b.startDate.njb; row.endDate = b.endDate.njb; row.datePrecision = b.datePrecision.njb
        row.reasonForJoining = b.reasonForJoining.njb; row.reasonForLeaving = b.reasonForLeaving.njb
        row.keyResponsibilities = b.keyResponsibilities.njb; row.majorAchievements = b.majorAchievements.njb
        row.skillsGained = b.skillsGained.njb; row.certificationsEarned = b.certificationsEarned.njb; row.notes = b.notes.njb
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

private extension String { var njb: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
