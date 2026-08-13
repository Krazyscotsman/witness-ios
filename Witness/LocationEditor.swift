import SwiftUI

// MARK: - Vocabularies (DISPLAY labels; sent as snakeKey via RelSanitize). Stored forms per spec:
// Residence/Work/School/Vacation Home/Temporary/Other → residence/work/school/vacation_home/temporary/other;
// Day/Month/Year → day/month/year. country is FREE TEXT (default "USA"), never snake_cased.
enum LocationVocab {
    static let types: [String] = ["Residence","Work","School","Vacation Home","Temporary","Other"]
    static let precision: [String] = ["Day","Month","Year"]
}

// MARK: - Shared edit/create draft (one sanitize + one validation for POST create and PUT edit)
struct LocationDraft {
    var name = "", type = "", street = "", city = "", state = "", postal = "", country = ""
    var startDate: Date?, endDate: Date?, precision = ""
    var reasonForMove = "", livingSituation = "", notes = ""

    /// Sanitized allowlisted body — the SAME 13 columns for POST and PUT.
    func writeRequest() -> LocationWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }  // type/precision
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return LocationWriteRequest(
            locationName: t(name), locationType: e(type),
            streetAddress: t(street), city: t(city), stateProvince: t(state), postalCode: t(postal), country: t(country),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate), datePrecision: e(precision),
            reasonForMove: t(reasonForMove), livingSituation: t(livingSituation), notes: t(notes))
    }
    /// Create requires a place name; edit does not. Dates always ≥ 1910 and end ≥ start.
    func validationError(requireName: Bool) -> String? {
        if requireName, name.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter a place name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

// MARK: - Shared form (no Your Story — locations have none)
struct LocationFormView: View {
    let title: String
    @Binding var draft: LocationDraft
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
            anchorFormSection("Place") {
                anchorTextField("Place name", $draft.name, required: true)
                anchorSelectField("Type", LocationVocab.types, $draft.type)
            }
            anchorFormSection("Address") {
                anchorTextField("Street address", $draft.street)
                anchorTextField("City", $draft.city)
                anchorTextField("State / province", $draft.state)
                anchorTextField("Postal code", $draft.postal)
                anchorTextField("Country", $draft.country)
            }
            anchorFormSection("Dates") {
                anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { draft.startDate = nil })
                anchorDateField("End date", draft.endDate, onEdit: { activeDateField = .end }, onClear: { draft.endDate = nil })
                anchorSelectField("Date precision", LocationVocab.precision, $draft.precision)
            }
            anchorFormSection("Story & notes") {
                anchorMultiField("Reason for move", $draft.reasonForMove)
                anchorMultiField("Living situation", $draft.livingSituation)
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

// MARK: - vm-reactive list (off vm.locations) + "Add New"
struct LocationListView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    private let category = AnchorCategory.find("locations")
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [LocationRow] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let f = q.isEmpty ? vm.locations : vm.locations.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
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
                            Text(search.isEmpty ? "No places yet." : "No matches for “\(search)”.")
                                .font(.serif(20)).foregroundStyle(WT.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(visible) { r in
                            NavigationLink { LocationDetailView(row: r, vm: vm, auth: auth) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
                NavigationLink { LocationCreateView(vm: vm, auth: auth) } label: { anchorAddIcon() }
                    .witnessPress().witnessHint("Add a new place.")
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
    private func row(_ r: LocationRow) -> some View {
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

// MARK: - Create (POST /timeline/locations) — empty form, country/type/precision defaults
struct LocationCreateView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("locations")

    @State private var d = LocationDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                LocationFormView(title: "New \(category.singular)", draft: $d, errorMessage: $errorMessage,
                                 isSaving: isSaving, saveTitle: "Add place",
                                 onSave: { Task { await create() } }, onCancel: { dismiss() })
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !prefilled else { return }
            d.country = "USA"; d.type = "Residence"; d.precision = "Month"   // defaults
            prefilled = true
        }
    }

    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do {
            try await auth.createLocation(d.writeRequest())
            await vm.refresh(auth: auth)
            dismiss()
        } catch {
            errorMessage = LocationCreateView.friendly(error)
        }
    }
    private static func friendly(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return "Your session has timed out. Please sign in again."
            case .network:        return "We couldn’t add this place. Please check your connection and try again."
            case .http(let s, _): return "The server couldn’t save this (error \(s)). Please try again."
            default:              return "Something went wrong adding this place. Please try again."
            }
        }
        return "Something went wrong adding this place. Please try again."
    }
}

// MARK: - Location detail (read mode + edit mode → PUT /timeline/locations/{id}). No Your Story.
struct LocationDetailView: View {
    @State var row: LocationRow
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("locations")

    @State private var editing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var d = LocationDraft()

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
        LocationFormView(title: "Edit \(category.singular)", draft: $d, errorMessage: $errorMessage,
                         isSaving: isSaving, saveTitle: "Save changes",
                         onSave: { Task { await save() } }, onCancel: cancelEdit)
    }

    private func startEdit() {
        d = LocationDraft(
            name: row.locationName ?? "",
            type: RelSanitize.option(for: row.locationType, in: LocationVocab.types),
            street: row.streetAddress ?? "", city: row.city ?? "", state: row.stateProvince ?? "",
            postal: row.postalCode ?? "", country: row.country ?? "",
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            precision: RelSanitize.option(for: row.datePrecision, in: LocationVocab.precision),
            reasonForMove: row.reasonForMove ?? "", livingSituation: row.livingSituation ?? "", notes: row.notes ?? "")
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) { editing = true }
    }
    private func cancelEdit() { errorMessage = nil; withAnimation(.easeInOut(duration: 0.2)) { editing = false } }

    private func save() async {
        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        let body = d.writeRequest()
        do {
            try await auth.updateLocation(id: row.id, body)
            applyOptimistic(body)
            withAnimation(.easeInOut(duration: 0.2)) { editing = false }
            await vm.refresh(auth: auth)
        } catch {
            errorMessage = LocationDetailView.friendly(error)
        }
    }

    private func applyOptimistic(_ b: LocationWriteRequest) {
        row.locationName = b.locationName.nlb; row.locationType = b.locationType.nlb
        row.streetAddress = b.streetAddress.nlb; row.city = b.city.nlb; row.stateProvince = b.stateProvince.nlb
        row.postalCode = b.postalCode.nlb; row.country = b.country.nlb
        row.startDate = b.startDate.nlb; row.endDate = b.endDate.nlb; row.datePrecision = b.datePrecision.nlb
        row.reasonForMove = b.reasonForMove.nlb; row.livingSituation = b.livingSituation.nlb; row.notes = b.notes.nlb
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

private extension String { var nlb: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
