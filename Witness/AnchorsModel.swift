import SwiftUI
import Combine

// MARK: - Anchors data model — the full FIELD_CONFIG from the web app, verbatim.
// Categories fetch/save via /timeline/{category} (GET list, POST create, PUT/{id}, DELETE/{id}).

enum AnchorFieldType { case text, textarea, select, date, boolean }

struct FieldConfig: Identifiable {
    let key: String
    let type: AnchorFieldType
    let label: String?
    let required: Bool
    let options: [String]?
    let def: String?
    let maxLength: Int?
    var id: String { key }
    var displayLabel: String { label ?? FieldConfig.humanize(key) }

    static func humanize(_ k: String) -> String {
        k.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

private func f(_ key: String, _ type: AnchorFieldType, label: String? = nil, req: Bool = false,
               options: [String]? = nil, def: String? = nil, max: Int? = nil) -> FieldConfig {
    FieldConfig(key: key, type: type, label: label, required: req, options: options, def: def, maxLength: max)
}

enum AnchorSchema {
    static let config: [String: [FieldConfig]] = [
        "locations": [
            f("location_name", .text, req: true, max: 255),
            f("location_type", .select, options: ["Residence","Work","School","Vacation Home","Temporary","Other"]),
            f("street_address", .text, max: 255),
            f("city", .text, max: 100),
            f("state_province", .text, max: 100),
            f("country", .text, def: "USA", max: 100),
            f("postal_code", .text, max: 20),
            f("date_precision", .select, options: ["Day","Month","Year"]),
            f("start_date", .date), f("end_date", .date),
            f("reason_for_move", .textarea), f("living_situation", .textarea), f("notes", .textarea),
        ],
        "relationships": [
            f("first_name", .text, req: true, max: 100),
            f("middle_name", .text, max: 100),
            f("last_name", .text, req: true, max: 100),
            f("nickname", .text, max: 100),
            f("maiden_name", .text, max: 100),
            f("relationship_type", .select, options: ["Spouse","Parent Child","Siblings","Half Siblings","Step Sibling","Step Parent","Step Child","Twin","Grandparent Grandchild","Aunt Uncle Niece Nephew","Cousins","Adopted Parent","Adopted Child","Foster Parent","Foster Child","Godparent","Godchild","In-Law Parent","In-Law Sibling","In-Law Child","Partners Parent","Romantic","Partner","Ex Spouse","Ex Partner","Friend","Best Friend","Acquaintance","Neighbor","Roommate","Classmate","Professional","Colleague","Boss","Subordinate","Mentor","Mentee","Client","Pet Owner","Caregiver","Doctor","Therapist","Teacher","Student","Family","Enemy","Other"]),
            f("significance", .select, options: ["Critical","High","Moderate","Low"]),
            f("person_birth_date", .date, label: "Birth Date"),
            f("person_birth_date_precision", .select, label: "Birth Date Precision", options: ["Day","Month","Year"]),
            f("person_death_date", .date, label: "Death Date"),
            f("person_death_date_precision", .select, label: "Death Date Precision", options: ["Day","Month","Year"]),
            f("appearance_description", .textarea, label: "Appearance Description"),
            f("privacy_level", .select, options: ["Private","Family Only","Public"]),
            f("include_in_memoir", .boolean),
            f("use_pseudonym", .boolean),
            f("pseudonym", .text),
            f("start_date", .date), f("end_date", .date),
            f("how_met", .textarea), f("relationship_context", .textarea), f("how_ended", .textarea),
            f("lessons_learned", .textarea), f("notes", .textarea),
            f("nbq_response", .textarea, label: "Your Story / NBQ Response"),
        ],
        "jobs": [
            f("employer_name", .text, req: true, max: 255),
            f("employer_industry", .text),
            f("work_location", .text),
            f("job_title", .text, max: 255),
            f("department", .text),
            f("employment_type", .select, options: ["Full-time","Part-time","Contract","Freelance","Internship","Volunteer"]),
            f("work_mode", .select, options: ["On-site","Remote","Hybrid"]),
            f("start_date", .date), f("end_date", .date),
            f("date_precision", .select, options: ["Day","Month","Year"]),
            f("reason_for_joining", .textarea), f("reason_for_leaving", .textarea),
            f("key_responsibilities", .textarea), f("major_achievements", .textarea),
            f("skills_gained", .textarea), f("certifications_earned", .textarea), f("notes", .textarea),
        ],
        "education": [
            f("institution_name", .text, req: true, max: 255),
            f("institution_type", .select, options: ["High School","College","University","Bootcamp","Online Course","Certification"]),
            f("institution_location", .text),
            f("attendance_mode", .select, options: ["In-person","Online","Hybrid"]),
            f("degree_type", .text),
            f("field_of_study", .text),
            f("degree_achieved", .boolean),
            f("start_date", .date), f("end_date", .date), f("graduation_date", .date),
            f("achievements", .textarea), f("challenges", .textarea), f("notes", .textarea),
        ],
        "service": [
            f("service_member", .text, max: 100),
            f("branch", .select, options: ["Army","Navy","Air Force","Marines","Coast Guard","Space Force","National Guard"]),
            f("rank_at_start", .text, max: 50),
            f("rank_at_end", .text, max: 50),
            f("start_date", .date), f("end_date", .date),
            f("duty_stations", .textarea), f("deployments", .textarea), f("notes", .textarea),
        ],
        "pets": [
            f("pet_name", .text, req: true, max: 255),
            f("pet_type", .select, options: ["Dog","Cat","Bird","Fish","Reptile","Rodent","Horse","Other"]),
            f("breed", .text, max: 100),
            f("start_date", .date), f("end_date", .date),
            f("how_acquired", .textarea), f("personality", .textarea), f("significance", .textarea), f("notes", .textarea),
        ],
        "hobbies": [
            f("hobby_name", .text, req: true, max: 255),
            f("hobby_type", .select, options: ["Creative","Athletic","Intellectual","Social","Collecting","Outdoors","Interest"]),
            f("activity_level", .select, options: ["Active","Occasional","Dormant","Past"]),
            f("start_date", .date),
            f("how_started", .textarea), f("achievements", .textarea), f("notes", .textarea),
        ],
    ]

    // Title/subtitle derivation per category.
    static func title(_ category: String, _ r: AnchorRecord) -> String {
        func v(_ k: String) -> String { (r.values[k] ?? "").trimmingCharacters(in: .whitespaces) }
        switch category {
        case "relationships":
            let n = "\(v("first_name")) \(v("last_name"))".trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (v("nickname").isEmpty ? "Unnamed" : v("nickname")) : n
        case "locations":  return v("location_name").isEmpty ? "Untitled" : v("location_name")
        case "jobs":       return v("employer_name").isEmpty ? "Untitled" : v("employer_name")
        case "education":  return v("institution_name").isEmpty ? "Untitled" : v("institution_name")
        case "pets":       return v("pet_name").isEmpty ? "Untitled" : v("pet_name")
        case "hobbies":    return v("hobby_name").isEmpty ? "Untitled" : v("hobby_name")
        case "service":    return !v("service_member").isEmpty ? v("service_member") : (v("branch").isEmpty ? "Service" : v("branch"))
        default:           return "Untitled"
        }
    }
    static func subtitle(_ category: String, _ r: AnchorRecord) -> String {
        func v(_ k: String) -> String { (r.values[k] ?? "").trimmingCharacters(in: .whitespaces) }
        switch category {
        case "relationships": return v("relationship_type")
        case "locations":     return [v("location_type"), v("city")].filter { !$0.isEmpty }.joined(separator: " · ")
        case "jobs":          return v("job_title")
        case "education":     return [v("degree_type"), v("institution_type")].filter { !$0.isEmpty }.joined(separator: " · ")
        case "pets":          return [v("pet_type"), v("breed")].filter { !$0.isEmpty }.joined(separator: " · ")
        case "hobbies":       return v("hobby_type")
        case "service":       return [v("branch"), v("rank_at_end")].filter { !$0.isEmpty }.joined(separator: " · ")
        default:              return ""
        }
    }
}

// MARK: - A single anchor record (field values keyed by field key).
struct AnchorRecord: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var values: [String: String] = [:]
}

// MARK: - Category metadata (verbatim labels/descriptions/truth-roles).
struct AnchorCategory: Identifiable {
    let id: String
    let label: String
    let singular: String
    let description: String
    let truthRole: String
    let icon: String
    let tone: Color
    var fields: [FieldConfig] { AnchorSchema.config[id] ?? [] }

    static let all: [AnchorCategory] = [
        .init(id: "relationships", label: "People & Relationships", singular: "Person",
              description: "The people whose names, roles, dates, and relationship truths must remain factually correct.",
              truthRole: "Keeps every person's name, role, dates, and relationship facts from drifting as memories are woven together.",
              icon: "person.2.fill", tone: Color(hex: 0x6b5b95)),
        .init(id: "locations", label: "Places Lived & Known", singular: "Location",
              description: "Homes, towns, schools, workplaces, and other places that anchor memories in physical truth.",
              truthRole: "Grounds memories in real geography, residence history, and place-based identity.",
              icon: "mappin.and.ellipse", tone: WV.teal),
        .init(id: "jobs", label: "Jobs & Career", singular: "Job",
              description: "Employers, roles, duties, skills, career periods, and work identity facts.",
              truthRole: "Keeps work chronology and professional identity from drifting during synthesis.",
              icon: "briefcase.fill", tone: Color(hex: 0x2f6f8f)),
        .init(id: "education", label: "Education", singular: "Education",
              description: "Schools, degrees, attendance windows, achievements, and academic experiences.",
              truthRole: "Preserves accurate educational sequence, school names, and achievement context.",
              icon: "graduationcap.fill", tone: Color(hex: 0x3f7d5a)),
        .init(id: "service", label: "Military / Service", singular: "Service",
              description: "Military service, duty stations, deployments, rank, and service-related identity context.",
              truthRole: "Keeps service chronology and rank facts grounded when memories reference military life.",
              icon: "shield.fill", tone: Color(hex: 0x6b6256)),
        .init(id: "pets", label: "Pets", singular: "Pet",
              description: "Animals that were part of family life, grief, companionship, and memory.",
              truthRole: "Keeps emotionally important animal companions distinct and accurately named.",
              icon: "pawprint.fill", tone: Color(hex: 0xb08828)),
        .init(id: "hobbies", label: "Hobbies & Interests", singular: "Hobby",
              description: "Activities, interests, skills, and enduring patterns of attention and joy.",
              truthRole: "Preserves the repeated activities that reveal identity beyond major life events.",
              icon: "paintpalette.fill", tone: Color(hex: 0xb08828)),
    ]

    static func find(_ id: String) -> AnchorCategory { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Local store with persistence (stands in for /timeline/{category} until wired).
final class AnchorStore: ObservableObject {
    @Published private(set) var data: [String: [AnchorRecord]] = [:]
    private let key = "anchors.store.v1"

    init() { load() }

    func records(_ category: String) -> [AnchorRecord] { data[category] ?? [] }
    func record(_ category: String, id: String) -> AnchorRecord? { records(category).first { $0.id == id } }

    // POST /timeline/{category} (new) or PUT /timeline/{category}/{id} (existing)
    func upsert(_ category: String, _ record: AnchorRecord) {
        var arr = data[category] ?? []
        if let i = arr.firstIndex(where: { $0.id == record.id }) { arr[i] = record } else { arr.append(record) }
        data[category] = arr
        save()
    }
    // DELETE /timeline/{category}/{id}
    func delete(_ category: String, id: String) {
        data[category] = (data[category] ?? []).filter { $0.id != id }
        save()
    }

    var totalCount: Int { data.values.reduce(0) { $0 + $1.count } }
    func count(_ category: String) -> Int { (data[category] ?? []).count }
    func criticalPeople() -> [AnchorRecord] {
        records("relationships").filter { ($0.values["significance"] ?? "").lowercased() == "critical" }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [AnchorRecord]].self, from: d) {
            data = decoded
        }
    }
}
