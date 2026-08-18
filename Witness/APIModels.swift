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

// MARK: - Settings profile (GET /api/v1/settings/profile) — launch routing + companion identity.

/// Lenient: keys may be absent/null; unknown keys are ignored by Decodable. `onboarding_completed` is the
/// routing source of truth; `companion_name`/`companion_voice` hydrate the app's stored companion identity
/// at launch.
struct ProfileDTO: Decodable {
    let id: String?
    let onboardingCompleted: Bool?
    let companionName: String?
    let companionVoice: String?

    enum CodingKeys: String, CodingKey {
        case id
        case onboardingCompleted = "onboarding_completed"
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
    }
}

/// POST /api/v1/settings/profile body. Saves the profile AND flips onboarding_completed (one call — no
/// /auth/complete-onboarding). first_name / last_name / birth_date are ALWAYS sent (last_name "" when empty,
/// never omitted). Optional details are omitted when nil (synthesized encodeIfPresent). All three voice
/// fields are always sent; custom_voice_name (the Gemini name) is what drives playback.
struct ProfileCreateRequest: Encodable {
    let firstName: String
    let lastName: String
    let birthDate: String            // yyyy-MM-dd (en_US_POSIX)
    let birthCity: String?
    let birthState: String?
    let gender: String?
    let companionName: String
    let companionVoice: String
    let companionPersonality: String
    let customVoiceName: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case birthCity = "birth_city"
        case birthState = "birth_state"
        case gender
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
        case companionPersonality = "companion_personality"
        case customVoiceName = "custom_voice_name"
    }
}

/// POST /api/v1/settings/profile response: { "status": "created"|"updated", "narrator_id": "<uuid>" }.
/// A small ack — the server flips onboarding_completed regardless of this body, so any 2xx = success; we do
/// NOT read the flag back from here (the launch profile-fetch confirms it).
struct ProfileCreateResponse: Decodable {
    let status: String?
    let narratorId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case narratorId = "narrator_id"
    }
}

/// PUT /api/v1/settings/profile body (partial update). All optional → nil fields are omitted (synthesized
/// encodeIfPresent), so unmanaged fields are never sent and server-side nulls are avoided. The editor always
/// sends first_name/last_name/companion_name; it sends the three voice fields ONLY when the voice changed.
struct ProfileUpdateRequest: Encodable {
    let firstName: String?
    let lastName: String?
    let companionName: String?
    let companionVoice: String?
    let companionPersonality: String?
    let customVoiceName: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
        case companionPersonality = "companion_personality"
        case customVoiceName = "custom_voice_name"
    }
}

// MARK: - Entities / Anchors (GET /api/v1/entities, GET /api/v1/entities/{id})

/// Summary row from GET /api/v1/entities (returns a top-level ARRAY). No is_anchor filter param exists —
/// callers filter client-side to isAnchor == true. `type` is a free string (person/place/organization/pet/
/// vehicle/…); handle unknowns gracefully. Lenient: only `id` is required.
struct EntitySummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let type: String?
    let memoryCount: Int?
    let firstSeen: String?
    let isAnchor: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case memoryCount = "memory_count"
        case firstSeen = "first_seen"
        case isAnchor = "is_anchor"
    }
}

/// GET /api/v1/entities/{id}. `attributes` (untyped dict) is intentionally NOT modeled/decoded.
struct EntityDetailDTO: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let isAnchor: Bool?
    let linkedMemories: [LinkedMemory]?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case isAnchor = "is_anchor"
        case linkedMemories = "linked_memories"
        // `attributes` omitted on purpose (untyped dict).
    }
}

/// A memory linked to an entity. `narrative` (heavy) is intentionally NOT decoded.
struct LinkedMemory: Decodable, Hashable {
    let id: String?
    let title: String?
    let date: String?
    let role: String?
    // `narrative` omitted on purpose (heavy).
}

/// POST /timeline/relationships (create) AND PUT /timeline/relationships/{id} (edit) body — EXACTLY the 22
/// editable columns of narrator_relationships,
/// nothing else. The backend has NO request validation: an unknown/misspelled column throws 500, so making
/// the type structurally hold only real columns is the defense. Values are pre-sanitized by the view
/// (snake_case enums, ISO dates, "" for blanks → server NULL). Read-only nbq_response / person_canonical_name
/// are structurally absent — impossible to send. `nonisolated` because it's encoded in a nonisolated context.
nonisolated struct RelationshipWriteRequest: Encodable {
    let firstName, middleName, lastName, nickname, maidenName: String
    let relationshipType: String
    let familyRole, significance: String
    let startDate, endDate, datePrecision: String
    let personBirthDate, personBirthDatePrecision, personDeathDate, personDeathDatePrecision: String
    let howMet, relationshipContext, howEnded, lessonsLearned, notes, appearanceDescription: String
    let privacyLevel: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name", middleName = "middle_name", lastName = "last_name"
        case nickname, maidenName = "maiden_name"
        case relationshipType = "relationship_type", familyRole = "family_role", significance
        case startDate = "start_date", endDate = "end_date", datePrecision = "date_precision"
        case personBirthDate = "person_birth_date", personBirthDatePrecision = "person_birth_date_precision"
        case personDeathDate = "person_death_date", personDeathDatePrecision = "person_death_date_precision"
        case howMet = "how_met", relationshipContext = "relationship_context", howEnded = "how_ended"
        case lessonsLearned = "lessons_learned", notes, appearanceDescription = "appearance_description"
        case privacyLevel = "privacy_level"
    }
}

/// POST /timeline/locations (create — mints a place entity) AND PUT /timeline/locations/{id} (edit) body —
/// EXACTLY the 13 editable narrator_locations columns, nothing else (unknown column → 500). Pre-sanitized by
/// the view (location_type/date_precision → stored lowercase; ISO dates; country is free text, not snake_cased).
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

/// POST /timeline/jobs (create — mints an organization entity) AND PUT /timeline/jobs/{id} (edit) body —
/// EXACTLY the 17 editable narrator_employment columns, nothing else (unknown column → 500). Pre-sanitized by
/// the view (employment_type/work_mode/date_precision → stored lowercase via snakeKey; ISO dates; text as-is).
nonisolated struct JobWriteRequest: Encodable {
    let employerName: String
    let employerIndustry, workLocation, jobTitle, department: String
    let employmentType, workMode: String
    let startDate, endDate, datePrecision: String
    let reasonForJoining, reasonForLeaving, keyResponsibilities, majorAchievements: String
    let skillsGained, certificationsEarned, notes: String

    enum CodingKeys: String, CodingKey {
        case employerName = "employer_name", employerIndustry = "employer_industry"
        case workLocation = "work_location", jobTitle = "job_title", department
        case employmentType = "employment_type", workMode = "work_mode"
        case startDate = "start_date", endDate = "end_date", datePrecision = "date_precision"
        case reasonForJoining = "reason_for_joining", reasonForLeaving = "reason_for_leaving"
        case keyResponsibilities = "key_responsibilities", majorAchievements = "major_achievements"
        case skillsGained = "skills_gained", certificationsEarned = "certifications_earned", notes
    }
}

/// POST /timeline/education (create — mints an entity) AND PUT /timeline/education/{id} (edit) body — EXACTLY
/// the 13 editable narrator_education columns, nothing else (unknown column → 500). degree_achieved is a JSON
/// bool; the rest are pre-sanitized strings (selects → stored lowercase via snakeKey; ISO dates). NOTE: NO
/// date_precision — it's server-side for education, never sent from the editor.
nonisolated struct EducationWriteRequest: Encodable {
    let institutionName: String
    let institutionType, institutionLocation, attendanceMode, degreeType, fieldOfStudy: String
    let degreeAchieved: Bool
    let startDate, endDate, graduationDate: String
    let achievements, challenges, notes: String

    enum CodingKeys: String, CodingKey {
        case institutionName = "institution_name", institutionType = "institution_type"
        case institutionLocation = "institution_location", attendanceMode = "attendance_mode"
        case degreeType = "degree_type", fieldOfStudy = "field_of_study", degreeAchieved = "degree_achieved"
        case startDate = "start_date", endDate = "end_date", graduationDate = "graduation_date"
        case achievements, challenges, notes
    }
}

/// POST /timeline/pets (create — mints a pet entity) AND PUT /timeline/pets/{id} (edit) body — EXACTLY the 9
/// editable narrator_pets columns, nothing else (unknown column → 500). Pre-sanitized by the view (pet_type →
/// stored lowercase via snakeKey; ISO dates; significance + other text trimmed VERBATIM — significance is FREE
/// TEXT, never an enum). No date_precision (server-side for pets).
nonisolated struct PetWriteRequest: Encodable {
    let petName: String
    let petType, breed: String
    let startDate, endDate: String
    let howAcquired, personality, significance, notes: String

    enum CodingKeys: String, CodingKey {
        case petName = "pet_name", petType = "pet_type", breed
        case startDate = "start_date", endDate = "end_date"
        case howAcquired = "how_acquired", personality, significance, notes
    }
}

// MARK: - Jarvis witness session (Ask Scarlett — memory-scoped exploration)

nonisolated struct WitnessStartRequest: Encodable {
    let memoryId: String
    let voiceMode: Bool
    enum CodingKeys: String, CodingKey { case memoryId = "memory_id", voiceMode = "voice_mode" }
}
nonisolated struct WitnessStartResponse: Decodable {
    let sessionId: String?
    let conversationId: String?
    let openingMessage: String?
    // context_summary intentionally NOT decoded: the backend sends it as an OBJECT and iOS never uses it.
    // (Declaring it as String? was the decode mismatch that broke every witness session start.)
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", conversationId = "conversation_id"
        case openingMessage = "opening_message"
    }
}
nonisolated struct WitnessTurnRequest: Encodable { let content: String }
nonisolated struct WitnessTurnResponse: Decodable {
    let response: String?
    // turn_number / response_type / discoveries / new_entities intentionally NOT decoded — iOS uses only
    // `response`. Omitting them avoids any String-vs-object decode fragility on the turn path.
}
nonisolated struct WitnessEndResponse: Decodable {
    let status: String?
    let sessionId: String?
    let turns: Int?
    let closingMessage: String?
    let summary: JSONValue?     // backend sends an OBJECT — decode opaquely (never String) so end() never fails
    var summaryText: String? { summary?.stringValue }   // shown only if the server ever sends a plain string
    enum CodingKeys: String, CodingKey {
        case status, sessionId = "session_id", turns, closingMessage = "closing_message", summary
    }
}

/// Opaque JSON value — for a field whose shape isn't fixed (string OR object/array). Decodes any JSON without
/// ever throwing, so a shape change on an unused/opaque field can't break the whole response.
nonisolated enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .null }
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
}

// MARK: - Jarvis conversation history (read-only). Two DISTINCT list shapes (not forced into one):
//  • memory-scoped (GET /jarvis/memories/{id}/conversations): has ended_at, no memory fields.
//  • recent (GET /jarvis/conversations/recent, MIXED scopes): has memory fields, no ended_at.
// Decoded with .convertFromSnakeCase. ⚠️ memory_id can be the literal string "None" — decoded as String?
// (NEVER UUID?) and normalized; whole-life is discriminated by memory_title == nil, NOT memory_id.
nonisolated struct MemoryConversationsResponse: Decodable { let conversations: [MemoryConvSummary]? }
nonisolated struct MemoryConvSummary: Decodable, Identifiable {
    let id: String
    let startedAt: String?
    let endedAt: String?
    let turnCount: Int?
    let summary: String?
    let status: String?
}
nonisolated struct RecentConversationsResponse: Decodable { let conversations: [RecentConvSummary]? }
nonisolated struct RecentConvSummary: Decodable, Identifiable {
    let id: String
    let memoryId: String?      // ⚠️ can be the literal "None"
    let memoryTitle: String?
    let status: String?
    let startedAt: String?
    let turnCount: Int?
    let summary: String?

    /// "None"/""/nil → nil (same backend quirk that made context_summary crash when typed as a scalar).
    static func normNone(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s != "None" else { return nil }
        return s
    }
    var memoryIdNorm: String? { Self.normNone(memoryId) }
    var isWholeLife: Bool { Self.normNone(memoryTitle) == nil }   // discriminate by memory_title, NOT memory_id
}
nonisolated struct ConversationTurnsResponse: Decodable { let turns: [ConversationTurn]? }
nonisolated struct ConversationTurn: Decodable {
    let turnNumber: Int?
    let role: String?          // "jarvis" | "user"
    let content: String?
    let phase: String?
    let turnType: String?
    let createdAt: String?
}

// MARK: - Explain Me (GET /api/v1/explain-me/…) — read-only synthesis. Decoded with .convertFromSnakeCase,
// so properties are camelCase (no CodingKeys). Descriptive text is optional; arrays are [String]? (safeArr at
// render). Patterns/Contradictions decode the UNION of fields and branch on type/source at render.

nonisolated struct ExplainOverview: Decodable {
    let narratorId: String?
    let summary: Summary?
    let dataAvailable: DataAvailable?

    nonisolated struct Summary: Decodable {
        let headline: String?
        let coreForces: [ExForceDTO]?
        let topPatterns: [ExPatternDTO]?
        let topBreakingPoints: [ExBreakingDTO]?
        let topContradictions: [ExContradictionDTO]?
    }
    nonisolated struct DataAvailable: Decodable {
        let forcesCount: Int?
        let breakingPointsCount: Int?
        let contradictionsCount: Int?
        let patternsCount: Int?
        let hasEnoughData: Bool?
    }
}

nonisolated struct ExForceDTO: Decodable {
    let forceId: String?
    let title: String?
    let originEventTitle: String?
    let originDate: String?
    let activeToday: Bool?
    let activeStrength: String?
    let affectedDomains: [String]?
    let downstreamEffects: [String]?
    let beforeSelf: String?
    let afterSelf: String?
    let identityImpact: String?
    let decisionWeight: String?
}

nonisolated struct ExPatternDTO: Decodable {   // heterogeneous by patternType
    let patternId: String?
    let patternType: String?
    let title: String?
    let description: String?
    let occurrenceCount: Int?
    let firstSeen: String?
    let lastSeen: String?
    let resolvedCount: Int?
    let unresolvedCount: Int?
    let stillActiveCount: Int?
    let sourceCount: Int?
}

nonisolated struct ExBreakingDTO: Decodable {
    let inflectionId: String?
    let title: String?
    let summary: String?
    let dateLabel: String?
    let memoryTitle: String?
    let inflectionType: String?
    let whyItMattered: String?
    let beforeSelf: String?
    let afterSelf: String?
    let downstreamEffects: [String]?
    let evidenceQuotes: [String]?
    let activeToday: Bool?
}

nonisolated struct ExContradictionDTO: Decodable {   // heterogeneous by source
    let contradictionId: String?
    let source: String?
    let title: String?
    let sideA: String?
    let sideB: String?
    let whyBothAreTrue: String?
    let stillActive: Bool?
    let emotionA: String?
    let emotionB: String?
    let tensionLevel: String?
    let conflictType: String?
}

// List-tab response wrappers (per §3: active-forces `forces[]`, etc.)
nonisolated struct ExForcesResponse: Decodable { let forces: [ExForceDTO]? }
nonisolated struct ExPatternsResponse: Decodable { let patterns: [ExPatternDTO]? }
nonisolated struct ExBreakingResponse: Decodable { let breakingPoints: [ExBreakingDTO]? }
nonisolated struct ExContradictionsResponse: Decodable { let contradictions: [ExContradictionDTO]? }

// Identity — GET /identity
nonisolated struct ExIdentity: Decodable {
    let identityStates: [ExIdentityStateDTO]?
    let transitions: [ExTransitionDTO]?
    let activeStates: [ExIdentityStateDTO]?
    let callout: String?
}
nonisolated struct ExIdentityStateDTO: Decodable {
    let stateId: String?
    let stateLabel: String?
    let description: String?
    let startDate: String?
    let endDate: String?
    let dominantTraits: [String]?
    let dominantEmotions: [String]?
    let dominantBeliefs: [String]?
    let evidenceQuotes: [String]?
    let stillActive: Bool?
    let memoryCount: Int?
}
nonisolated struct ExTransitionDTO: Decodable {
    let transitionId: String?
    let fromState: String?
    let toState: String?
    let transitionType: String?
    let summary: String?
    let emotionalCost: String?
    let permanence: String?
}

// Beliefs — GET /beliefs
nonisolated struct ExBeliefs: Decodable {
    let activeBeliefs: [ExBeliefDTO]?
    let changedBeliefs: [ExBeliefDTO]?
    let evolutions: [ExBeliefEvolutionDTO]?
    let reactivatedBeliefs: [ExBeliefEvolutionDTO]?
    let callout: String?
}
nonisolated struct ExBeliefDTO: Decodable {
    let beliefId: String?
    let beliefStatement: String?
    let beliefType: String?
    let stillHeld: Bool?
    let evidenceQuotes: [String]?
}
nonisolated struct ExBeliefEvolutionDTO: Decodable {
    let evolutionId: String?
    let fromBelief: String?
    let toBelief: String?
    let evolutionType: String?
    let changeReason: String?
    let emotionalDriver: String?
}

// MARK: - Timeline (GET /timeline/visual — BARE path, no /api/v1). Year-grouped, chronological, no params
// (all filtering client-side). Decoded with .convertFromSnakeCase. Events are a UNION branched on `type`
// (milestone/memory/anchor); the four enrichment fields (people/location/importanceScore/significance) are
// MEMORY-ONLY — absent on birth & anchor events. `nonisolated`: decoded off-main in APIClient.

nonisolated struct TimelineResponse: Decodable {
    let birthdate: String?
    let totalMemories: Int?
    let totalYears: Int?
    let years: [TimelineYear]?
}
nonisolated struct TimelineYear: Decodable {
    let year: Int?
    let age: Int?
    let events: [TimelineEventDTO]?
}
nonisolated struct TimelineEventDTO: Decodable {
    let id: String?
    let type: String?          // "milestone" | "memory" | "anchor"
    let category: String?
    let title: String?
    let subtitle: String?
    let date: String?
    let year: Int?
    let age: Int?
    let memoryId: String?
    let snippet: String?
    // memory-only enrichment (null on birth & anchor events):
    let people: [String]?
    let location: String?
    let importanceScore: Double?
    let significance: String?  // "critical" | null (binary — no gradient)
}

extension MemoryDTO {
    /// Build a light MemoryDTO from a timeline memory event so a tap can open the real memory detail —
    /// MemoryDetailView fetches the rich /detail by id; title + date give an instant header.
    init(id: String, title: String?, exactDate: String?) {
        self.init(id: id, title: title, narrative: nil, narrativeSnippet: nil, exactDate: exactDate,
                  timeGranularity: nil, exactDateEstimated: nil, narratorAge: nil, qualityScore: nil,
                  importanceScore: nil, people: nil, location: nil, createdAt: nil, updatedAt: nil)
    }
}

// MARK: - Media gallery (GET /api/v1/media/gallery) — READ side. Decoded with .convertFromSnakeCase. `metadata`
// is an untyped/loose dict, intentionally NOT modeled. `url` is either an ABSOLUTE presigned URL or a RELATIVE
// /api/v1/media/{id}/file path (the VM resolves + presign-refreshes). `nonisolated`: decoded off-main.

nonisolated struct MediaGalleryResponse: Decodable {
    let media: [MediaItemDTO]?
    let total: Int?
    let limit: Int?
    let offset: Int?
}
nonisolated struct MediaItemDTO: Decodable, Identifiable {
    let id: String
    let memoryId: String?
    let fileName: String?
    let fileType: String?     // image | video | audio | document
    let fileSize: Int?
    let mimeType: String?
    let url: String
    let createdAt: String?
    let memoryTitle: String?
    let memoryDate: String?
    let narratorAge: Int?
    // `metadata` omitted on purpose (loose/untyped).
}
nonisolated struct MediaURLResponse: Decodable { let url: String? }   // GET /api/v1/media/{id}/url (presign refresh)

// GET /api/v1/memories/{id}/audio?voice=&style=warm_memory → base64 WAV + meta (HD/Gemini memory voice).
// .convertFromSnakeCase.
nonisolated struct MemoryAudioResponse: Decodable {
    let audioBase64: String?
    let mimeType: String?
    let duration: Double?
    let voice: String?
    let style: String?
    let characterCount: Int?
}

// MARK: - Graph (GET /api/v1/graph) — relationship/entity map. Decoded with .convertFromSnakeCase. Precomputed
// styling (color/border_color/size/line_style/width) is decoded but INTENTIONALLY UNUSED — the app palette
// (RelGroup + WV/WT) drives rendering. `nonisolated`: decoded off-main in APIClient.
nonisolated struct GraphResponse: Decodable {
    let narratorId: String?
    let narratorNodeId: String?
    let nodes: [GraphNode]?
    let edges: [GraphEdge]?
    let stats: GraphStats?
}
nonisolated struct GraphNode: Decodable {
    let id: String
    let label: String?
    let type: String?
    let isAnchor: Bool?
    let isNarrator: Bool?
    let memoryCount: Int?
    let aliases: [String]?
    let nameComplete: Bool?    // ⚠️ backend sends a BOOL (name_complete: true), NOT a string
    let anchorRelType: String?
    let birthDate: String?
    let deathDate: String?
    let color: String?
    let borderColor: String?
    let size: Double?          // precomputed; unused (app palette instead)
}
nonisolated struct GraphEdge: Decodable {
    let source: String
    let target: String
    let relationshipType: String?
    let strength: Double?
    // id / memory_count / line_style / color / width / label intentionally NOT decoded — unused by iOS (app
    // palette drives styling). Edges were truncated from the DEBUG body, so decoding only the 4 used fields
    // pre-empts the name_complete decode-mismatch class on the unverified part of the response.
}
nonisolated struct GraphStats: Decodable {
    let totalNodes: Int?
    let totalEdges: Int?
    let anchorCount: Int?
}
