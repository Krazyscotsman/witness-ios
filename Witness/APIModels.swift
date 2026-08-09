import Foundation

// MARK: - Auth

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct LoginResponse: Decodable {
    let status: String
    let user: User
    let token: String            // TOP-LEVEL — not nested under `user`.

    struct User: Decodable {
        let userId: String?      // assumed String (UUID); optional for safety
        let narratorId: String?
        let email: String?
        let name: String?
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case narratorId = "narrator_id"
            case email, name
        }
    }
}

// MARK: - Session helpers

struct MeResponse: Decodable {}                          // permissive: 200 = valid token (shape ignored)
struct RefreshResponse: Decodable { let token: String }  // POST /auth/refresh -> {status, token}; token kept
struct EmptyBody: Encodable {}

// MARK: - Health

struct HealthResponse: Decodable {
    let gitSha: String?          // shown to prove reachability
    enum CodingKeys: String, CodingKey { case gitSha = "git_sha" }
}

// MARK: - Memories

struct MemoriesResponse: Decodable {
    let memories: [MemoryDTO]
    let total: Int
    let sort: String
    let limit: Int
    let offset: Int
}

/// Defensive by design: only `id` is required (primary key / Identifiable). Every other field
/// is optional so a null/absent value in a future memory degrades gracefully rather than
/// throwing and making the whole pipe look broken. The three-state `exactDateEstimated` (Bool?)
/// is preserved — null/false/true are distinct facts, never collapsed to a default.
struct MemoryDTO: Decodable, Identifiable, Hashable {
    let id: String                   // required: backend always returns it; Identifiable key
    let title: String?
    let narrative: String?
    let narrativeSnippet: String?
    let exactDate: String?
    let timeGranularity: String?     // day/month/season/year/school_year/age_year/unknown
    let exactDateEstimated: Bool?    // THREE-STATE: null / false / true are distinct
    let narratorAge: Int?
    let qualityScore: Double?
    let importanceScore: Double?
    let people: [String]?            // assumed [String] names; if objects, decode surfaces .decoding
    let location: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, narrative
        case narrativeSnippet = "narrative_snippet"
        case exactDate = "exact_date"
        case timeGranularity = "time_granularity"
        case exactDateEstimated = "exact_date_estimated"
        case narratorAge = "narrator_age"
        case qualityScore = "quality_score"
        case importanceScore = "importance_score"
        case people, location
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Memory detail (GET /api/v1/memories/{id}/detail — the rich endpoint)

/// Same defensive stance as MemoryDTO: keys are always present but values may be null, so every
/// field is optional. NOTE the contract difference from the list endpoint: `people` here is an
/// array of OBJECTS (anchors-first), not the list endpoint's [String]. `exactDateEstimated` stays
/// three-state (null/false/true); scores stay lenient Double?.
struct MemoryDetailDTO: Decodable, Hashable {
    let id: String?
    let title: String?
    let narrative: String?
    let narrativeSnippet: String?
    let exactDate: String?
    let timeGranularity: String?
    let exactDateEstimated: Bool?      // three-state
    let narratorAge: Int?
    let qualityScore: Double?
    let importanceScore: Double?
    let location: String?
    let createdAt: String?
    let updatedAt: String?
    let people: [MemoryPerson]?        // OBJECTS here (anchors-first), not [String]
    let emotions: [MemoryEmotion]?
    let quotes: [MemoryQuote]?

    enum CodingKeys: String, CodingKey {
        case id, title, narrative, location, people, emotions, quotes
        case narrativeSnippet = "narrative_snippet"
        case exactDate = "exact_date"
        case timeGranularity = "time_granularity"
        case exactDateEstimated = "exact_date_estimated"
        case narratorAge = "narrator_age"
        case qualityScore = "quality_score"
        case importanceScore = "importance_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MemoryPerson: Decodable, Hashable {
    let id: String?
    let canonicalName: String?
    let entityType: String?
    let isAnchor: Bool?
    let roleInMemory: String?

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case entityType = "entity_type"
        case isAnchor = "is_anchor"
        case roleInMemory = "role_in_memory"
    }
}

struct MemoryEmotion: Decodable, Hashable {
    let emotionType: String?
    let intensity: Double?
    let triggerDescription: String?

    enum CodingKeys: String, CodingKey {
        case emotionType = "emotion_type"
        case intensity
        case triggerDescription = "trigger_description"
    }
}

struct MemoryQuote: Decodable, Hashable {
    let quoteText: String?
    let emotionalTone: String?
    let speakerName: String?

    enum CodingKeys: String, CodingKey {
        case quoteText = "quote_text"
        case emotionalTone = "emotional_tone"
        case speakerName = "speaker_name"
    }
}
