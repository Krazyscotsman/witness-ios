# Witness — Locations anchor category (view + edit + create) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Mirrors the relationships pattern. Group A (POST mints
a place entity). Endpoints: PUT /timeline/locations/{id}, POST /timeline/locations — BARE paths, Bearer,
any-2xx. Same 500-footgun → send ONLY the 13-column allowlist.

## Read-first findings
- Locations currently use the generic read-only AnchorRecordListView → AnchorRecordDetailView (inert). LocationRow
  already decodes all allowlist columns + has detailFields/typeLabel/subtitle/sortKey. No Your Story.
- Relationship pattern: RelSanitize (reusable), RelationshipDraft/FormView/ListView/CreateView/DetailView,
  RelationshipWriteRequest, AuthManager put/postIgnoringResponseBody, anchorNavBar trailing "+". The form's
  field builders are private methods on RelationshipFormView; DateSheet is file-private → extract to reuse.
- snakeKey gives the exact stored forms: Vacation Home→vacation_home, Residence→residence, Day/Month/Year→
  day/month/year. country is free text (default "USA"), NOT snakeKey'd.

## Decisions (baked in; change any)
1. Extract shared AnchorFormKit (builders + AnchorDateSheet); refactor RelationshipFormView to use it (identical
   rendering; edit path re-verified). Alt: duplicate builders in LocationFormView (WET).
2. LocationListView replaces the generic read-only list for the locations category; other 5 categories untouched.
3. Create prefills country "USA", type "Residence", precision "Month".

## Allowlist (13 real narrator_locations columns)
location_name (req), location_type, street_address, city, state_province, postal_code, country, start_date,
end_date, date_precision, reason_for_move, living_situation, notes. NEVER: sequence_order, *_entity_id,
created_at, updated_at, id, narrator_id, legacy place_type/name/address/description/period/who_involved/
significance/memories/status/feelings. No nbq_response.

---

## New file: AnchorFormKit.swift (shared form building blocks)
```swift
import SwiftUI

func anchorFormSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
        VStack(spacing: 12) { content() }
    }
}
func anchorFieldLabel(_ label: String, required: Bool = false) -> some View {
    HStack(spacing: 4) {
        Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
        if required { Text("*").font(.system(size: 13, weight: .bold)).foregroundStyle(WV.danger) }
    }
}
func anchorTextField(_ label: String, _ binding: Binding<String>, required: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label, required: required)
        TextField(label, text: binding).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}
func anchorMultiField(_ label: String, _ binding: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label)
        TextField(label, text: binding, axis: .vertical).lineLimit(3...8)
            .font(.serif(16)).foregroundStyle(WT.ink).tint(WV.teal).textInputAutocapitalization(.sentences)
            .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}
func anchorSelectField(_ label: String, _ options: [String], _ binding: Binding<String>, required: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label, required: required)
        Menu {
            if !required { Button("— None —") { binding.wrappedValue = "" } }
            ForEach(options, id: \.self) { opt in Button(opt) { binding.wrappedValue = opt } }
        } label: {
            HStack {
                Text(binding.wrappedValue.isEmpty ? "Select" : binding.wrappedValue)
                    .font(.system(size: 16)).foregroundStyle(binding.wrappedValue.isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            }
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }
}
func anchorDateField(_ label: String, _ value: Date?, onEdit: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label)
        HStack {
            Button(action: onEdit) {
                HStack {
                    Text(value.map { RelSanitize.iso.string(from: $0) } ?? "Add date")
                        .font(.system(size: 16)).foregroundStyle(value == nil ? WT.ink.opacity(0.4) : WT.ink)
                    Spacer(); Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(WV.teal)
                }
            }.buttonStyle(.plain)
            if value != nil {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}

// Moved from RelationshipEditor (was private DateSheet) → shared, internal.
struct AnchorDateSheet: View {
    let initial: Date; let floor: Date; let onDone: (Date) -> Void
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
            }.witnessPress().padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment).presentationDetents([.height(420)])
    }
}
```

## RelationshipEditor.swift — refactor the form to the kit (identical rendering)
- Replace RelationshipFormView's private `section/fieldLabel/textField/multiField/selectField/dateField` with the
  `anchor*` free funcs; keep its `activeDateField`/`DateField`/`getDate`/`setDate`; date rows become
  `anchorDateField("Start date", draft.startDate, onEdit: { activeDateField = .start }, onClear: { setDate(.start, nil) })`;
  `.sheet` uses `AnchorDateSheet`. Remove the file-private `DateSheet`. `storyCard` stays (relationship-only).
- No behavior change; RelationshipDetailView / CreateView / save / writeRequest untouched.

## APIModels.swift — LocationWriteRequest (13 columns, shared POST+PUT)
```swift
/// POST /timeline/locations (create — mints a place entity) AND PUT /timeline/locations/{id} (edit) body —
/// EXACTLY the 13 editable narrator_locations columns, nothing else (unknown column → 500). Values are
/// pre-sanitized by the view (location_type/date_precision → stored lowercase; ISO dates; country free text).
nonisolated struct LocationWriteRequest: Encodable {
    let locationName: String
    let locationType: String
    let streetAddress, city, stateProvince, postalCode, country: String
    let startDate, endDate, datePrecision: String
    let reasonForMove, livingSituation, notes: String

    enum CodingKeys: String, CodingKey {
        case locationName = "location_name", locationType = "location_type"
        case streetAddress = "street_address", city, stateProvince = "state_province"
        case postalCode = "postal_code", country
        case startDate = "start_date", endDate = "end_date", datePrecision = "date_precision"
        case reasonForMove = "reason_for_move", livingSituation = "living_situation", notes
    }
}
```

## AuthManager.swift — location write calls
```swift
    func updateLocation(id: String, _ body: LocationWriteRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/timeline/locations/\(id)", body: body, timeout: 20)
    }
    func createLocation(_ body: LocationWriteRequest) async throws {
        _ = try await api.postIgnoringResponseBody("/timeline/locations", body: body, timeout: 20)
    }
```

## New file: LocationEditor.swift
```swift
import SwiftUI

enum LocationVocab {
    static let types: [String] = ["Residence","Work","School","Vacation Home","Temporary","Other"]
    static let precision: [String] = ["Day","Month","Year"]
}

struct LocationDraft {
    var name = "", type = "", street = "", city = "", state = "", postal = "", country = ""
    var startDate: Date?, endDate: Date?, precision = ""
    var reasonForMove = "", livingSituation = "", notes = ""

    func writeRequest() -> LocationWriteRequest {
        func e(_ display: String) -> String { display.isEmpty ? "" : RelSanitize.snakeKey(display) }   // type/precision
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return LocationWriteRequest(
            locationName: t(name), locationType: e(type),
            streetAddress: t(street), city: t(city), stateProvince: t(state), postalCode: t(postal), country: t(country),
            startDate: RelSanitize.string(startDate), endDate: RelSanitize.string(endDate), datePrecision: e(precision),
            reasonForMove: t(reasonForMove), livingSituation: t(livingSituation), notes: t(notes))
    }
    func validationError(requireName: Bool) -> String? {
        if requireName, name.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter a place name." }
        for (label, date) in [("Start date", startDate), ("End date", endDate)] {
            if let dt = date, dt < RelSanitize.dateFloor { return "\(label) must be on or after Jan 1, 1910." }
        }
        if let s = startDate, let e = endDate, e < s { return "End date can’t be before the start date." }
        return nil
    }
}

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
                if f == .start { draft.startDate = picked } else { draft.endDate = picked }; activeDateField = nil
            }
        }
    }
}

// vm-reactive list (off vm.locations) + Add New
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
                            Text(search.isEmpty ? "No places yet." : "No matches for “\(search)”.").font(.serif(20)).foregroundStyle(WT.ink)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
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
    private var searchBar: some View { /* identical to RelationshipListView.searchBar */ EmptyView() }
    private func row(_ r: LocationRow) -> some View { /* identical card, category icon/tone */ EmptyView() }
}

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
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !prefilled else { return }
            d.country = "USA"; d.type = "Residence"; d.precision = "Month"    // defaults
            prefilled = true
        }
    }
    private func create() async {
        if let msg = d.validationError(requireName: true) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        do { try await auth.createLocation(d.writeRequest()); await vm.refresh(auth: auth); dismiss() }
        catch { errorMessage = LocationCreateView.friendly(error) }
    }
    private static func friendly(_ error: Error) -> String { /* same mapping as RelationshipCreateView, "place" wording */ "" }
}

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

    var body: some View { /* read mode (row.detailFields, NO Your Story) + edit (LocationFormView) + inert Delete;
        mirrors RelationshipDetailView exactly, minus story */ EmptyView() }

    private func startEdit() {
        d = LocationDraft(
            name: row.locationName ?? "",
            type: RelSanitize.option(for: row.locationType, in: LocationVocab.types),
            street: row.streetAddress ?? "", city: row.city ?? "", state: row.stateProvince ?? "",
            postal: row.postalCode ?? "", country: row.country ?? "",
            startDate: RelSanitize.parse(row.startDate), endDate: RelSanitize.parse(row.endDate),
            precision: RelSanitize.option(for: row.datePrecision, in: LocationVocab.precision),
            reasonForMove: row.reasonForMove ?? "", livingSituation: row.livingSituation ?? "", notes: row.notes ?? "")
        errorMessage = nil; withAnimation { editing = true }
    }
    private func save() async {
        if let msg = d.validationError(requireName: false) { errorMessage = msg; return }
        errorMessage = nil; isSaving = true; defer { isSaving = false }
        let body = d.writeRequest()
        do { try await auth.updateLocation(id: row.id, body); applyOptimistic(body); withAnimation { editing = false }; await vm.refresh(auth: auth) }
        catch { errorMessage = LocationDetailView.friendly(error) }
    }
    private func applyOptimistic(_ b: LocationWriteRequest) {
        row.locationName = b.locationName.nlb; row.locationType = b.locationType.nlb
        row.streetAddress = b.streetAddress.nlb; row.city = b.city.nlb; row.stateProvince = b.stateProvince.nlb
        row.postalCode = b.postalCode.nlb; row.country = b.country.nlb
        row.startDate = b.startDate.nlb; row.endDate = b.endDate.nlb; row.datePrecision = b.datePrecision.nlb
        row.reasonForMove = b.reasonForMove.nlb; row.livingSituation = b.livingSituation.nlb; row.notes = b.notes.nlb
    }
    private static func friendly(_ error: Error) -> String { /* same mapping, "place" wording */ "" }
}

private extension String { var nlb: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }
```
(The `searchBar`/`row`/detail `body`/`friendly` bodies shown as EmptyView()/"" ONLY to keep this doc short —
the applied file copies them verbatim from the relationship equivalents, swapping RelationshipRow→LocationRow,
"person"→"place", and omitting Your Story.)

## AnchorRegistryView.swift — route locations to the editor
```diff
-        case "locations":  AnchorRecordListView(title: c.label, category: c, rows: vm.locations)
+        case "locations":  LocationListView(vm: vm, auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Verify (RunCodeSnippet) LocationDraft.writeRequest() emits exactly the 13
allowlist columns with Vacation Home→vacation_home / Month→month / country "USA" as-is, and that the
relationship edit path still builds/behaves unchanged after the form refactor. Honest note: the live
PUT/POST round-trip (2xx, place-entity mint) is a device/backend check. Delete inert; locations only; no
/continuity/truths. No git.
