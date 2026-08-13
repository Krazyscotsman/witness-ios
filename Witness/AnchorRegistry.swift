import SwiftUI
import Combine

// MARK: - Display helpers
// This data layer is `nonisolated` (the module defaults types to @MainActor): the rows decode in a
// nonisolated context (APIClient), so their Decodable conformance — and the helpers/protocol they use —
// must not be main-actor-isolated.
nonisolated enum AnchorText {
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

nonisolated struct AnchorField: Identifiable { let id = UUID(); let label: String; let value: String? }

// A uniform surface so the record list + detail can be generic across all 7 categories.
nonisolated protocol AnchorRow: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var subtitle: String { get }
    var sortKey: String { get }          // startDate ?? createdAt ?? ""
    var typeLabel: String? { get }       // eyebrow on the detail (e.g. relationship type)
    var detailFields: [AnchorField] { get }
    var story: String? { get }           // nbq_response ("Your Story") when present
}
extension AnchorRow { nonisolated var typeLabel: String? { nil }; nonisolated var story: String? { nil } }

private extension String { nonisolated var nilIfEmpty: String? { isEmpty ? nil : self } }

// MARK: - Rows (decode a known subset of SELECT *; extras ignored; only id required)
nonisolated struct RelationshipRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var personCanonicalName: String? = nil
    var firstName: String? = nil, middleName: String? = nil, lastName: String? = nil
    var nickname: String? = nil, maidenName: String? = nil
    var relationshipType: String? = nil, significance: String? = nil
    var familyRole: String? = nil, datePrecision: String? = nil
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
          .init(label: "Family role", value: AnchorText.titleCase(familyRole).nilIfEmpty),
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

nonisolated struct LocationRow: Decodable, AnchorRow {
    let id: String
    var narratorId: String? = nil
    var locationName: String? = nil, locationType: String? = nil
    var streetAddress: String? = nil, city: String? = nil, stateProvince: String? = nil
    var country: String? = nil, postalCode: String? = nil
    var startDate: String? = nil, endDate: String? = nil, datePrecision: String? = nil
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

nonisolated struct JobRow: Decodable, AnchorRow {
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

nonisolated struct EducationRow: Decodable, AnchorRow {
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

nonisolated struct ServiceRow: Decodable, AnchorRow {
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

nonisolated struct PetRow: Decodable, AnchorRow {
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

nonisolated struct HobbyRow: Decodable, AnchorRow {
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
