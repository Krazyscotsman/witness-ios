# Witness — Anchor Registry (categorized, read-only nav) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Replaces the Phase 1 flat `AnchorsListView`.
Endpoint: `GET /timeline/{category}` — BARE path (no /api/v1), Bearer, no params, returns a bare array of raw
rows (SELECT *; decode a known subset). Categories: relationships, locations, jobs, education, pets, hobbies,
service. Fetch all 7 once; derive everything client-side. NO POST/PUT/DELETE /timeline/* at all.

## Read-first findings
- Insights → Anchors currently opens Phase 1 `AnchorsListView(auth:)` (GET /entities). Single swap point:
  `InsightsView` `case "anchors"`.
- `AnchorsModel.swift` already has `AnchorCategory.all` (7 categories, icon/tone/label/singular/description,
  verbatim from web) — reused for dashboard tiles. Old local `AnchorsView` stays unreferenced.
- APIClient resolves bare `/timeline/{cat}` correctly (relativeTo baseURL). Its get() uses a plain
  JSONDecoder → needs snake_case handling for raw rows (decision #1).

## Decisions (baked in; change any)
1. Add a defaulted `decoder: JSONDecoder = JSONDecoder()` param to APIClient.get/request (backwards-compatible)
   so the registry passes a `.convertFromSnakeCase` decoder → clean camelCase models, no CodingKeys.
2. Delete `AnchorsListView.swift` (Phase 1, explicitly replaced); KEEP entity models in APIModels (different
   endpoint, likely reused later).
3. `id` decoded as String (consistent with the app; assumes UUID string ids from /timeline).

---

## 1) APIClient.swift — defaulted decoder param
```diff
     func get<Response: Decodable>(_ path: String, authorized: Bool = true, timeout: TimeInterval? = nil,
+                                  decoder: JSONDecoder = JSONDecoder(),
                                   as: Response.Type = Response.self) async throws -> Response {
-        try await request(path, method: "GET", body: Optional<Empty>.none, authorized: authorized, timeout: timeout)
+        try await request(path, method: "GET", body: Optional<Empty>.none, authorized: authorized, timeout: timeout, decoder: decoder)
     }
```
```diff
     private func request<Body: Encodable, Response: Decodable>(
-        _ path: String, method: String, body: Body?, authorized: Bool, timeout: TimeInterval? = nil
+        _ path: String, method: String, body: Body?, authorized: Bool, timeout: TimeInterval? = nil,
+        decoder: JSONDecoder = JSONDecoder()
     ) async throws -> Response {
         ...
-        do { return try JSONDecoder().decode(Response.self, from: data) }
+        do { return try decoder.decode(Response.self, from: data) }
         catch { throw APIError.decoding(error) }
     }
```
(post() calls request without a decoder → default preserves current behavior.)

## 2) InsightsView.swift — repoint
```diff
-                case "anchors":  AnchorsListView(auth: auth)
+                case "anchors":  AnchorRegistryView(auth: auth)
```

## 3) DELETE file: AnchorsListView.swift (Phase 1) — replaced. (Entity models in APIModels kept.)

## 4) New file: AnchorRegistry.swift  (rows + protocol + normalizer + VM)
```swift
import SwiftUI
import Combine

// MARK: - Display helpers
enum AnchorText {
    /// snake_case / UPPER / Mixed enum value → Title Case. Used for BOTH display and grouping (so chips
    /// derived from relationship_type never duplicate due to casing).
    static func titleCase(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }
        return s.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
    static func key(_ raw: String?) -> String { titleCase(raw).lowercased() }   // grouping key
    static func date(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(s.prefix(10))) { let o = DateFormatter(); o.dateStyle = .long; return o.string(from: d) }
        return s
    }
    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

struct AnchorField: Identifiable { let id = UUID(); let label: String; let value: String? }

// A uniform surface so the record list + detail can be generic across all 7 categories.
protocol AnchorRow: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var subtitle: String { get }
    var sortKey: String { get }          // startDate ?? createdAt ?? ""
    var typeLabel: String? { get }       // eyebrow on the detail (e.g. relationship type)
    var detailFields: [AnchorField] { get }
    var story: String? { get }           // nbq_response ("Your Story") when present
}
extension AnchorRow { var typeLabel: String? { nil }; var story: String? { nil } }

// MARK: - Rows (decode a known subset of SELECT *; extras ignored; only id required)
struct RelationshipRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var personCanonicalName: String? = nil
    var firstName: String? = nil, middleName: String? = nil, lastName: String? = nil
    var nickname: String? = nil, maidenName: String? = nil
    var relationshipType: String? = nil, significance: String? = nil
    var personBirthDate: String? = nil, personBirthDatePrecision: String? = nil
    var personDeathDate: String? = nil, personDeathDatePrecision: String? = nil
    var appearanceDescription: String? = nil, privacyLevel: String? = nil, pseudonym: String? = nil
    var startDate: String? = nil, endDate: String? = nil
    var howMet: String? = nil, relationshipContext: String? = nil, howEnded: String? = nil
    var lessonsLearned: String? = nil, notes: String? = nil, nbqResponse: String? = nil
    var createdAt: String? = nil

    var displayName: String {
        if let c = personCanonicalName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        let n = [firstName, lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        if let nn = nickname, !nn.isEmpty { return nn }
        return "Unnamed"
    }
    var subtitle: String { AnchorText.join([AnchorText.titleCase(relationshipType).nilIfEmpty,
                                            AnchorText.titleCase(significance).nilIfEmpty,
                                            AnchorText.date(startDate)]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(relationshipType).nilIfEmpty }
    var story: String? { nbqResponse?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Nickname", value: nickname),
          .init(label: "Maiden name", value: maidenName),
          .init(label: "Relationship type", value: AnchorText.titleCase(relationshipType).nilIfEmpty),
          .init(label: "Significance", value: AnchorText.titleCase(significance).nilIfEmpty),
          .init(label: "Birth date", value: AnchorText.date(personBirthDate)),
          .init(label: "Death date", value: AnchorText.date(personDeathDate)),
          .init(label: "Appearance", value: appearanceDescription),
          .init(label: "Privacy level", value: AnchorText.titleCase(privacyLevel).nilIfEmpty),
          .init(label: "Pseudonym", value: pseudonym),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "How we met", value: howMet),
          .init(label: "Relationship context", value: relationshipContext),
          .init(label: "How it ended", value: howEnded),
          .init(label: "Lessons learned", value: lessonsLearned),
          .init(label: "Notes", value: notes) ]
    }
}

struct LocationRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var locationName: String? = nil, locationType: String? = nil
    var streetAddress: String? = nil, city: String? = nil, stateProvince: String? = nil
    var country: String? = nil, postalCode: String? = nil
    var startDate: String? = nil, endDate: String? = nil
    var reasonForMove: String? = nil, livingSituation: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { locationName?.nilIfEmpty ?? "Untitled" }
    var subtitle: String { AnchorText.join([AnchorText.titleCase(locationType).nilIfEmpty, city]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(locationType).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Type", value: AnchorText.titleCase(locationType).nilIfEmpty),
          .init(label: "Street address", value: streetAddress),
          .init(label: "City", value: city),
          .init(label: "State / province", value: stateProvince),
          .init(label: "Country", value: country),
          .init(label: "Postal code", value: postalCode),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "Reason for move", value: reasonForMove),
          .init(label: "Living situation", value: livingSituation),
          .init(label: "Notes", value: notes) ]
    }
}

struct JobRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var employerName: String? = nil, employerIndustry: String? = nil, workLocation: String? = nil
    var jobTitle: String? = nil, department: String? = nil
    var employmentType: String? = nil, workMode: String? = nil
    var startDate: String? = nil, endDate: String? = nil
    var reasonForJoining: String? = nil, reasonForLeaving: String? = nil
    var keyResponsibilities: String? = nil, majorAchievements: String? = nil
    var skillsGained: String? = nil, certificationsEarned: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { employerName?.nilIfEmpty ?? "Untitled" }
    var subtitle: String { AnchorText.join([jobTitle, AnchorText.titleCase(employmentType).nilIfEmpty]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { jobTitle?.nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Job title", value: jobTitle),
          .init(label: "Industry", value: employerIndustry),
          .init(label: "Work location", value: workLocation),
          .init(label: "Department", value: department),
          .init(label: "Employment type", value: AnchorText.titleCase(employmentType).nilIfEmpty),
          .init(label: "Work mode", value: AnchorText.titleCase(workMode).nilIfEmpty),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "Reason for joining", value: reasonForJoining),
          .init(label: "Reason for leaving", value: reasonForLeaving),
          .init(label: "Key responsibilities", value: keyResponsibilities),
          .init(label: "Major achievements", value: majorAchievements),
          .init(label: "Skills gained", value: skillsGained),
          .init(label: "Certifications earned", value: certificationsEarned),
          .init(label: "Notes", value: notes) ]
    }
}

struct EducationRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var institutionName: String? = nil, institutionType: String? = nil, institutionLocation: String? = nil
    var attendanceMode: String? = nil, degreeType: String? = nil, fieldOfStudy: String? = nil
    var degreeAchieved: Bool? = nil
    var startDate: String? = nil, endDate: String? = nil, graduationDate: String? = nil
    var achievements: String? = nil, challenges: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { institutionName?.nilIfEmpty ?? "Untitled" }
    var subtitle: String { AnchorText.join([degreeType, AnchorText.titleCase(institutionType).nilIfEmpty]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(institutionType).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Type", value: AnchorText.titleCase(institutionType).nilIfEmpty),
          .init(label: "Location", value: institutionLocation),
          .init(label: "Attendance mode", value: AnchorText.titleCase(attendanceMode).nilIfEmpty),
          .init(label: "Degree type", value: degreeType),
          .init(label: "Field of study", value: fieldOfStudy),
          .init(label: "Degree achieved", value: degreeAchieved.map { $0 ? "Yes" : "No" }),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "Graduation date", value: AnchorText.date(graduationDate)),
          .init(label: "Achievements", value: achievements),
          .init(label: "Challenges", value: challenges),
          .init(label: "Notes", value: notes) ]
    }
}

struct ServiceRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var serviceMember: String? = nil, branch: String? = nil
    var rankAtStart: String? = nil, rankAtEnd: String? = nil
    var startDate: String? = nil, endDate: String? = nil
    var dutyStations: String? = nil, deployments: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { serviceMember?.nilIfEmpty ?? AnchorText.titleCase(branch).nilIfEmpty ?? "Service" }
    var subtitle: String { AnchorText.join([AnchorText.titleCase(branch).nilIfEmpty, rankAtEnd]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(branch).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Branch", value: AnchorText.titleCase(branch).nilIfEmpty),
          .init(label: "Rank at start", value: rankAtStart),
          .init(label: "Rank at end", value: rankAtEnd),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "Duty stations", value: dutyStations),
          .init(label: "Deployments", value: deployments),
          .init(label: "Notes", value: notes) ]
    }
}

struct PetRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var petName: String? = nil, petType: String? = nil, breed: String? = nil
    var startDate: String? = nil, endDate: String? = nil
    var howAcquired: String? = nil, personality: String? = nil, significance: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { petName?.nilIfEmpty ?? "Untitled" }
    var subtitle: String { AnchorText.join([AnchorText.titleCase(petType).nilIfEmpty, breed]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(petType).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Type", value: AnchorText.titleCase(petType).nilIfEmpty),
          .init(label: "Breed", value: breed),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "End date", value: AnchorText.date(endDate)),
          .init(label: "How acquired", value: howAcquired),
          .init(label: "Personality", value: personality),
          .init(label: "Significance", value: significance),
          .init(label: "Notes", value: notes) ]
    }
}

struct HobbyRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var hobbyName: String? = nil, hobbyType: String? = nil, activityLevel: String? = nil
    var startDate: String? = nil
    var howStarted: String? = nil, achievements: String? = nil, notes: String? = nil
    var createdAt: String? = nil
    var displayName: String { hobbyName?.nilIfEmpty ?? "Untitled" }
    var subtitle: String { AnchorText.join([AnchorText.titleCase(hobbyType).nilIfEmpty, AnchorText.titleCase(activityLevel).nilIfEmpty]) }
    var sortKey: String { startDate ?? createdAt ?? "" }
    var typeLabel: String? { AnchorText.titleCase(hobbyType).nilIfEmpty }
    var detailFields: [AnchorField] {
        [ .init(label: "Type", value: AnchorText.titleCase(hobbyType).nilIfEmpty),
          .init(label: "Activity level", value: AnchorText.titleCase(activityLevel).nilIfEmpty),
          .init(label: "Start date", value: AnchorText.date(startDate)),
          .init(label: "How it started", value: howStarted),
          .init(label: "Achievements", value: achievements),
          .init(label: "Notes", value: notes) ]
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

// MARK: - Registry VM: fetch all 7 once, derive client-side
@MainActor
final class AnchorRegistryViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var relationships: [RelationshipRow] = []
    @Published private(set) var locations: [LocationRow] = []
    @Published private(set) var jobs: [JobRow] = []
    @Published private(set) var education: [EducationRow] = []
    @Published private(set) var pets: [PetRow] = []
    @Published private(set) var hobbies: [HobbyRow] = []
    @Published private(set) var service: [ServiceRow] = []

    private static let snake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()

    func load(auth: AuthManager) async { if state == .loaded || state == .loading { return }; await fetchAll(auth: auth) }
    func refresh(auth: AuthManager) async { if state == .loading { return }; await fetchAll(auth: auth) }

    private enum Outcome<T> { case ok(T), unauthorized(String?), failed }
    private func get<T: Decodable>(_ cat: String, _ t: [T].Type) async -> Outcome<[T]> {
        do { return .ok(try await APIClient.shared.get("/timeline/\(cat)", timeout: 20, decoder: Self.snake, as: [T].self)) }
        catch let APIError.unauthorized(_, code) { return .unauthorized(code) }
        catch { return .failed }
    }
    private struct Batch {
        let rel: Outcome<[RelationshipRow]>, loc: Outcome<[LocationRow]>, job: Outcome<[JobRow]>
        let edu: Outcome<[EducationRow]>, pet: Outcome<[PetRow]>, hob: Outcome<[HobbyRow]>, svc: Outcome<[ServiceRow]>
    }
    private func runAll() async -> Batch {
        async let rel = get("relationships", [RelationshipRow].self)
        async let loc = get("locations", [LocationRow].self)
        async let job = get("jobs", [JobRow].self)
        async let edu = get("education", [EducationRow].self)
        async let pet = get("pets", [PetRow].self)
        async let hob = get("hobbies", [HobbyRow].self)
        async let svc = get("service", [ServiceRow].self)
        return await Batch(rel: rel, loc: loc, job: job, edu: edu, pet: pet, hob: hob, svc: svc)
    }
    private func anyUnauthorized(_ b: Batch) -> (Bool, String?) {
        func u<T>(_ o: Outcome<T>) -> (Bool, String?) { if case .unauthorized(let c) = o { return (true, c) }; return (false, nil) }
        for r in [u(b.rel), u(b.loc), u(b.job), u(b.edu), u(b.pet), u(b.hob), u(b.svc)] where r.0 { return r }
        return (false, nil)
    }
    private func fetchAll(auth: AuthManager) async {
        state = .loading
        var b = await runAll()
        let un = anyUnauthorized(b)
        if un.0 {
            if await auth.handleUnauthorized(code: un.1) { b = await runAll() }
            else { state = .failed(message: "Your session ended. Please sign in again."); return }
        }
        var any = false
        func take<T>(_ o: Outcome<[T]>) -> [T] { if case .ok(let v) = o { any = true; return v }; return [] }
        relationships = take(b.rel); locations = take(b.loc); jobs = take(b.job)
        education = take(b.edu); pets = take(b.pet); hobbies = take(b.hob); service = take(b.svc)
        state = any ? .loaded : .failed(message: "Couldn’t load your anchors. Check your connection and try again.")
    }

    // Derivations
    func count(_ categoryID: String) -> Int {
        switch categoryID {
        case "relationships": return relationships.count
        case "locations": return locations.count
        case "jobs": return jobs.count
        case "education": return education.count
        case "pets": return pets.count
        case "hobbies": return hobbies.count
        case "service": return service.count
        default: return 0
        }
    }
    struct RelChip: Identifiable { let id: String; let title: String; let count: Int }  // id = normalized key
    var relationshipChips: [RelChip] {
        var map: [String: (title: String, count: Int)] = [:]
        for r in relationships {
            let title = AnchorText.titleCase(r.relationshipType); guard !title.isEmpty else { continue }
            map[title.lowercased(), default: (title, 0)].count += 1
        }
        return map.map { RelChip(id: $0.key, title: $0.value.title, count: $0.value.count) }.sorted { $0.title < $1.title }
    }
    var criticalPeople: [RelationshipRow] { relationships.filter { AnchorText.key($0.significance) == "critical" } }
    func relationships(typeKey: String) -> [RelationshipRow] { relationships.filter { AnchorText.key($0.relationshipType) == typeKey } }
}
```

## 5) New file: AnchorRegistryView.swift  (L1–L4)
```swift
import SwiftUI

// L1 — Categories dashboard
struct AnchorRegistryView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AnchorRegistryViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: loading
                case .failed(let m):  failed(m)
                case .loaded:         dashboard
                }
            }
            navBar(title: "Insights", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(auth: auth) }
    }

    private var dashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ANCHOR REGISTRY").font(.system(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(WV.gold)
                    Text("The facts your story stands on.").font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    Text("People, places, work, and milestones — kept factually true so memories never blur or drift.")
                        .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(AnchorCategory.all) { c in
                    NavigationLink { destination(for: c) } label: { tile(c) }.witnessPress()
                }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    @ViewBuilder private func destination(for c: AnchorCategory) -> some View {
        switch c.id {
        case "relationships": AnchorRelationshipsView(vm: vm, category: c)
        case "locations":  AnchorRecordListView(title: c.label, category: c, rows: vm.locations)
        case "jobs":       AnchorRecordListView(title: c.label, category: c, rows: vm.jobs)
        case "education":  AnchorRecordListView(title: c.label, category: c, rows: vm.education)
        case "pets":       AnchorRecordListView(title: c.label, category: c, rows: vm.pets)
        case "hobbies":    AnchorRecordListView(title: c.label, category: c, rows: vm.hobbies)
        case "service":    AnchorRecordListView(title: c.label, category: c, rows: vm.service)
        default: EmptyView()
        }
    }

    private func tile(_ c: AnchorCategory) -> some View {
        let n = vm.count(c.id)
        return HStack(spacing: 14) {
            ZStack { Circle().fill(c.tone.opacity(0.12)); Image(systemName: c.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(c.tone) }
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.label).font(.serif(18)).foregroundStyle(WT.ink)
                Text("\(n) \(n == 1 ? "record" : "records")").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.05), radius: 9, y: 4)
    }

    private var loading: some View {
        VStack(spacing: 14) { ProgressView().tint(WV.teal); Text("Gathering your anchors…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)) }
    }
    private func failed(_ m: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(WT.ink.opacity(0.3))
            Text("Couldn’t load your anchors").font(.serif(22)).foregroundStyle(WV.teal)
            Text(m).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth) } } label: {
                Text("Try again").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 50).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }.witnessPress().padding(.top, 4)
        }.padding(28)
    }
}

// Shared nav bar
func navBar(title: String, onBack: @escaping () -> Void) -> some View {
    HStack {
        Button(action: onBack) {
            HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text(title).font(.system(size: 16)) }
                .foregroundStyle(WV.teal).frame(height: 44)
        }.witnessPress()
        Spacer()
    }
    .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
}

// L2 — Relationships subcategories
struct AnchorRelationshipsView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    let category: AnchorCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.label).font(.serif(26)).foregroundStyle(WT.ink)
                        Text("Separate people by factual relationship role, so names, dates, and roles stay true and never merge.")
                            .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    // Pinned Critical People
                    let critical = vm.criticalPeople
                    NavigationLink {
                        AnchorRecordListView(title: "Critical People", category: category, rows: critical)
                    } label: { criticalCard(count: critical.count) }.witnessPress(scale: 0.98)

                    // Chips per normalized relationship_type
                    let chips = vm.relationshipChips
                    if chips.isEmpty {
                        emptyState
                    } else {
                        ForEach(chips) { chip in
                            NavigationLink {
                                AnchorRecordListView(title: chip.title, category: category, rows: vm.relationships(typeKey: chip.id))
                            } label: { chipRow(chip) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private func criticalCard(count: Int) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color.white.opacity(0.2)); Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(.white) }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Critical People").font(.serif(19)).foregroundStyle(.white)
                Text("\(count) \(count == 1 ? "person" : "people") everything else orbits.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x6b5b95), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color(hex: 0x6b5b95).opacity(0.3), radius: 12, y: 6)
    }
    private func chipRow(_ chip: AnchorRegistryViewModel.RelChip) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.12)); Image(systemName: "person.2.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(category.tone) }.frame(width: 44, height: 44)
            Text(chip.title).font(.serif(18)).foregroundStyle(WT.ink)
            Spacer(minLength: 4)
            Text("\(chip.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(category.tone)
                .frame(minWidth: 26, minHeight: 26).background(category.tone.opacity(0.12), in: Circle())
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No people yet.").font(.serif(20)).foregroundStyle(WT.ink)
            Text("As you share memories, the people in your life gather here.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }
}

// L3 — Record list (generic; search + sort)
struct AnchorRecordListView<Row: AnchorRow>: View {
    let title: String
    let category: AnchorCategory
    let rows: [Row]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [Row] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? rows : rows.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
        return filtered.sorted { $0.sortKey > $1.sortKey }   // start_date DESC else created_at
    }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.serif(26)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    searchBar
                    if visible.isEmpty { emptyState }
                    else {
                        ForEach(visible) { r in
                            NavigationLink { AnchorRecordDetailView(row: r, category: category) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar(title: "Anchors", onBack: { dismiss() })
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
    private func row(_ r: Row) -> some View {
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
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: category.icon).font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
            Text(search.isEmpty ? "Nothing here yet." : "No matches for “\(search)”.").font(.serif(20)).foregroundStyle(WT.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.top, 40)
    }
}

// L4 — Record detail (READ-ONLY; Edit/Delete laid out but inert)
struct AnchorRecordDetailView<Row: AnchorRow>: View {
    let row: Row
    let category: AnchorCategory
    @Environment(\.dismiss) private var dismiss

    private var shown: [AnchorField] { row.detailFields.filter { ($0.value?.trimmingCharacters(in: .whitespaces).isEmpty == false) } }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text((row.typeLabel ?? category.singular).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(category.tone)
                        Text(row.displayName).font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    if shown.isEmpty {
                        Text("No details recorded yet.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                                if i > 0 { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }
                                fieldRow(f)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                    }
                    if let story = row.story {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR STORY").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
                            Text(story).font(.serif(17)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.06), lineWidth: 1))
                    }
                    actionsRow
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            navBar(title: category.singular, onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private func fieldRow(_ f: AnchorField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(f.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
            Text(f.value ?? "").font(.system(size: 16)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }

    // Edit + Delete LAID OUT but INERT (wired in a later phase). No POST/PUT/DELETE.
    private var actionsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                inertButton("Edit", tint: WV.teal)
                inertButton("Delete", tint: WV.danger)
            }
            Text("Editing and deleting are coming soon.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .padding(.top, 6)
    }
    private func inertButton(_ label: String, tint: Color) -> some View {
        Text(label).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint.opacity(0.5))
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.2), lineWidth: 1))
            .opacity(0.6)   // visibly disabled; no action attached
    }
}
```

---

## After approval
Apply (incl. deleting AnchorsListView.swift), build 0/0 + diagnostics. Honest note: not exercised against the
live /timeline endpoints — the bare-path GET, snake_case decode of raw rows, the 7-way fan-out/partial-failure,
and case-normalized relationship chips are wired to the verified contract but unconfirmed on real JSON (device
pass recommended: dashboard counts, relationship chips don't duplicate across casings, Critical People,
read-only detail with Your Story, inert Edit/Delete). No writes. No git.
