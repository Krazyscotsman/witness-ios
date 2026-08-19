import SwiftUI
import Combine

/// Optional instant-header context from the entry point (graph node / anchor row). The page still fetches the
/// canonical record; the seed just avoids an empty header while loading.
struct EntitySeed {
    var name: String? = nil
    var type: String? = nil
    var isAnchor: Bool? = nil
    var relationship: String? = nil
}

/// Phase 1 of the full Entity Detail page. Fetches GET /api/v1/entities/{id}; `attributes` is decoded opaquely
/// (JSONValue) and never dumped. Renders Header + Summary cards + Linked Memories. Later phases add the
/// attribute-driven sections (dialogue, people details, arcs, …).
@MainActor
final class EntityDetailViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var detail: EntityDetailDTO?
    @Published private(set) var entityNames: [String: String] = [:]   // uuid → name (responder resolution)
    private var namesLoaded = false
    private enum SessionError: Error { case sessionEnded }

    func load(entityId: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        guard !entityId.isEmpty else { state = .failed("This entity isn’t available."); return }
        state = .loading
        do {
            detail = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/entities/\(entityId)", timeout: 30, as: EntityDetailDTO.self)
            }
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load these details. Please try again.")
        }
    }

    var linkedMemories: [LinkedMemory] { detail?.linkedMemories ?? [] }

    /// Load the entity list once (cache) for responder-name resolution. Failure leaves the map empty → pills omit.
    func loadEntityNames(auth: AuthManager) async {
        if namesLoaded { return }
        namesLoaded = true
        if let list = try? await withAuth(auth, {
            try await APIClient.shared.get("/api/v1/entities?limit=1000&offset=0", timeout: 30, as: [EntitySummary].self)
        }) {
            var map: [String: String] = [:]
            for e in list {
                if let n = e.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { map[e.id] = n }
            }
            entityNames = map
        }
    }

    /// Memory titles from Phase-1 linked_memories → [id: title] (neutral fallback handled at the call site).
    var memoryTitles: [String: String] {
        var m: [String: String] = [:]
        for lm in linkedMemories {
            if let id = lm.id, let t = lm.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { m[id] = t }
        }
        return m
    }

    /// attributes.dialogue_spoken → ordered lines; empty-quote rows skipped; backend order preserved (verbatim).
    var dialogueLines: [DialogueLine] {
        guard let arr = detail?.attributes?["dialogue_spoken"]?.arrayValue else { return [] }
        return arr.compactMap { el in
            guard let o = el.objectValue,
                  let raw = o["quote"]?.stringValue,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return DialogueLine(quote: raw,
                                memoryId: o["memory_id"]?.stringValue,
                                responderId: o["responder_entity_id"]?.stringValue,
                                scene: o["scene_number"]?.intValue,
                                order: o["dialogue_order"]?.intValue)
        }
    }

    /// Count of non-empty top-level attribute keys — the honest "Populated sections" number. Opaque; never dumped.
    var populatedSectionCount: Int {
        guard case .object(let o)? = detail?.attributes else { return 0 }
        return o.values.filter { !Self.isEmptyValue($0) }.count
    }
    private static func isEmptyValue(_ v: JSONValue) -> Bool {
        switch v {
        case .null: return true
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        case .bool, .number: return false
        }
    }
    /// Provisional (pending the spec): read a scalar string attribute for a header pill.
    func attrString(_ key: String) -> String? {
        guard case .object(let o)? = detail?.attributes, case .string(let s)? = o[key],
              !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    // MARK: Phase 3 — people_details_by_memory

    /// Memory dates from Phase-1 linked_memories → [id: date].
    var memoryDates: [String: String] {
        var m: [String: String] = [:]
        for lm in linkedMemories {
            if let id = lm.id, let d = lm.date?.trimmingCharacters(in: .whitespaces), !d.isEmpty { m[id] = d }
        }
        return m
    }

    /// attributes.people_details_by_memory → per-memory cards. Dict (keyed by memory_id, ordered by
    /// linked_memories) OR array (order preserved). Defensive: unknown shape → [].
    var peopleDetails: [PersonMemoryDetail] {
        guard let pd = detail?.attributes?["people_details_by_memory"] else { return [] }
        if let dict = pd.objectValue {
            let order = Dictionary(linkedMemories.enumerated().compactMap { (i, lm) in lm.id.map { ($0, i) } },
                                   uniquingKeysWith: { a, _ in a })
            return dict.map { PersonMemoryDetail(memoryId: $0.key, obj: $0.value.objectValue ?? [:]) }
                .sorted { (order[$0.memoryId ?? ""] ?? Int.max) < (order[$1.memoryId ?? ""] ?? Int.max) }
        }
        if let arr = pd.arrayValue {
            return arr.compactMap { el in
                guard let o = el.objectValue else { return nil }
                return PersonMemoryDetail(memoryId: o["memory_id"]?.stringValue, obj: o)
            }
        }
        return []
    }

    private func firstDetailString(_ key: String) -> String? {
        for d in peopleDetails { if let v = d.obj[key]?.displayString { return v } }
        return nil
    }
    var derivedAge: String? { firstDetailString("age_in_memory") }
    var derivedRelationship: String? { firstDetailString("relationship_type") }
    var derivedSignificance: String? { firstDetailString("significance") }

    /// Hero picks — first non-empty across the memory cards; carries the source memory id (may be unresolved).
    var heroAppearance: (text: String, memoryId: String?)? {
        for d in peopleDetails { if let v = d.obj["physical_description"]?.displayString { return (v, d.memoryId) } }
        return nil
    }
    var heroQuote: (text: String, memoryId: String?)? {
        for d in peopleDetails {
            if let q = d.obj["dialogue_and_quotes"]?.arrayValue?.first?.objectValue?["quote_text"]?.displayString {
                return (q, d.memoryId)
            }
        }
        return nil
    }

    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}

struct EntityDetailPage: View {
    let entityId: String
    var seed: EntitySeed = .init()
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = EntityDetailViewModel()
    @StateObject private var speaker = Speaker()
    @State private var shownDialogue = 50

    private var name: String { vm.detail?.name ?? seed.name ?? "Entity" }
    private var type: String? { vm.detail?.type ?? seed.type }
    private var isAnchor: Bool { vm.detail?.isAnchor ?? seed.isAnchor ?? false }
    private var relationship: String? { vm.derivedRelationship ?? seed.relationship ?? vm.attrString("relationship_type") }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    switch vm.state {
                    case .idle, .loading: loadingBlock
                    case .failed(let m):  failedBlock(m)
                    case .loaded:
                        heroCards
                        summaryCards
                        dialogueSection
                        acrossMemoriesSection
                        linkedMemoriesSection
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(entityId: entityId, auth: auth) }
        .task { await vm.loadEntityNames(auth: auth) }        // responder-name resolution (parallel)
        .onDisappear { speaker.stop() }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Back").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                kicker("Entity Detail", tone: WV.gold)
                if let t = type, !t.isEmpty { kicker(t.capitalized, tone: WV.teal) }
                if isAnchor { kicker("Anchor", tone: WV.gold) }
                if let r = relationship, !r.isEmpty { kicker(humanize(r), tone: WV.teal) }
            }
            Text(name).font(.serif(30)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                pill("\(vm.linkedMemories.count) linked", "book.closed")
                if let age = vm.derivedAge { pill("Age \(age)", "number") }
                if let s = vm.derivedSignificance ?? vm.attrString("significance") { pill(s.capitalized, "star") }
                if let d = vm.attrString("date") ?? vm.attrString("first_seen") { pill(d, "calendar") } // date still provisional
            }
            readAloud
        }
    }

    private var readAloud: some View {
        Button { toggleReadAloud() } label: {
            HStack(spacing: 7) {
                Image(systemName: speaker.isSpeaking ? "pause.fill" : "speaker.wave.2.fill").font(.system(size: 14, weight: .medium))
                Text(speaker.isSpeaking ? "Pause" : "Read aloud").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(WV.teal).padding(.horizontal, 14).frame(height: 38)
            .background(WV.teal.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
        }.witnessPress()
    }
    private func toggleReadAloud() {
        if speaker.isSpeaking { speaker.pause(); return }
        if speaker.isPaused { speaker.resume(); return }
        var parts: [String] = [name]
        if let t = type?.capitalized, !t.isEmpty { parts.append(t) }
        parts.append("\(vm.linkedMemories.count) linked memories")
        speaker.speak(parts.joined(separator: ". "))
    }

    // MARK: Hero cards (best pick — not definitive) + Across memories

    @ViewBuilder private var heroCards: some View {
        let appear = vm.heroAppearance
        let quote = vm.heroQuote
        if appear != nil || quote != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("BEST PICK — NOT DEFINITIVE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
                let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                    if let a = appear { heroCard(title: "Appearance", body: a.text, memoryId: a.memoryId, quoted: false) }
                    if let q = quote { heroCard(title: "In their words", body: "“\(q.text)”", memoryId: q.memoryId, quoted: true) }
                }
            }
        }
    }
    private func heroCard(title: String, body: String, memoryId: String?, quoted: Bool) -> some View {
        let source = memoryId.flatMap { vm.memoryTitles[$0] }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(WV.gold)
            Text(body).font(.serif(16)).italic(quoted).foregroundStyle(WT.ink.opacity(0.9))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let source, !source.isEmpty {
                Text("From “\(source)”").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.45))
            } else {
                Text("source unattributed").font(.system(size: 11)).italic().foregroundStyle(WT.ink.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder private var acrossMemoriesSection: some View {
        let people = vm.peopleDetails
        if !people.isEmpty {
            EDSection("Across memories", count: people.count, defaultExpanded: false) {
                VStack(spacing: 12) { ForEach(people) { personMemoryCard($0) } }
            }
        }
    }
    private func personMemoryCard(_ d: PersonMemoryDetail) -> some View {
        let title = d.memoryId.flatMap { vm.memoryTitles[$0] } ?? "A memory"
        let date = d.memoryId.flatMap { vm.memoryDates[$0] }
        let isPublic = d.obj["is_public_figure"]?.boolValue ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    if let date { Text(date).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
                }
                Spacer()
                if isPublic { EDPill(text: "Public figure", icon: "star", tone: WV.gold) }
            }
            VStack(alignment: .leading, spacing: 0) {
                detailField("Appearance", d.obj["physical_description"])
                detailField("Role in scene", d.obj["role_in_scene"])
                detailField("Relationship", d.obj["relationship_type"])
                detailField("Age", d.obj["age_in_memory"])
                detailField("Significance", d.obj["significance"])
                detailField("Personality", d.obj["personality_traits"])
                detailField("Clothing", d.obj["clothing"])
                detailField("Scents", d.obj["scents"])
                detailField("Emotional state", d.obj["emotional_state_in_memory"])
                detailField("Health", d.obj["health_status"])
                detailField("Abilities & skills", d.obj["abilities_skills"])
                detailField("Voice", d.obj["voice_description"])
                detailField("Mannerisms", d.obj["mannerisms"])
                detailField("Family", d.obj["family_relationships"])
                extendedAttributes(d.obj["extended_attributes"])
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    /// Array → label + pills; scalar → EDFieldRow; empty → nothing.
    @ViewBuilder private func detailField(_ label: String, _ value: JSONValue?) -> some View {
        if let arr = value?.stringArray, !arr.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                EDPillWrap(values: arr)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        } else {
            EDFieldRow(label: label, value: EDFormat.value(value))
        }
    }
    @ViewBuilder private func extendedAttributes(_ v: JSONValue?) -> some View {
        if let o = v?.objectValue, !o.isEmpty {
            ForEach(o.keys.sorted(), id: \.self) { k in detailField(humanize(k), o[k]) }
        }
    }

    // MARK: Everything they said (dialogue_spoken) — the centerpiece; collapsed by default.
    @ViewBuilder private var dialogueSection: some View {
        let all = vm.dialogueLines
        let total = all.count
        if total > 0 {
            EDSection("Everything they said", count: total, defaultExpanded: false) {
                let shown = Array(all.prefix(shownDialogue))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, line in
                        if i == 0 || line.memoryId != shown[i - 1].memoryId {   // header when the memory changes
                            Text(memoryHeader(line.memoryId).uppercased())
                                .font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, i == 0 ? 0 : 6)
                        }
                        dialogueRow(line)
                    }
                    if shownDialogue < total {
                        Button { shownDialogue = min(shownDialogue + 50, total) } label: {
                            Text("Show 50 more — showing \(min(shownDialogue, total)) of \(total)")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(WV.teal)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(WV.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }.witnessPress()
                    } else {
                        Text("Showing all \(total)").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                    }
                }
            }
        }
    }
    private func memoryHeader(_ memId: String?) -> String {
        if let id = memId, let t = vm.memoryTitles[id], !t.isEmpty { return t }
        return "A memory"     // neutral when unresolved
    }
    private func dialogueRow(_ line: DialogueLine) -> some View {
        let responder = line.responderId.flatMap { vm.entityNames[$0] }?.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 6) {
            Text("“\(line.quote)”")                                  // verbatim — their actual voice
                .font(.serif(17)).italic().foregroundStyle(WT.ink.opacity(0.9))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if line.scene != nil || (responder?.isEmpty == false) {
                HStack(spacing: 8) {
                    if let s = line.scene { EDPill(text: "Scene \(s)", icon: "film") }
                    if let r = responder, !r.isEmpty { EDPill(text: "to \(r)", icon: "arrow.turn.up.right") }
                    // responder pill shows the resolved NAME only — a raw UUID is never rendered
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: Summary cards
    private var summaryCards: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            summaryCard("Entity type", (type ?? "—").capitalized, "tag")
            summaryCard("Anchor", isAnchor ? "Yes" : "No", "star")
            summaryCard("Linked memories", "\(vm.linkedMemories.count)", "book.closed")
            summaryCard("Sections", "\(vm.populatedSectionCount)", "square.stack.3d.up")
        }
    }
    private func summaryCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(WV.teal)
            Text(value).font(.serif(20)).foregroundStyle(WT.ink).lineLimit(1)
            Text(label).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // MARK: Linked Memories (open by default)
    private var linkedMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINKED MEMORIES").font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.4))
            if vm.linkedMemories.isEmpty {
                Text("No linked memories.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)).padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(vm.linkedMemories.enumerated()), id: \.offset) { _, m in memoryRow(m) }
                }
            }
        }
    }
    @ViewBuilder private func memoryRow(_ m: LinkedMemory) -> some View {
        let title = (m.title ?? "").trimmingCharacters(in: .whitespaces)
        let display = title.isEmpty ? "Untitled memory" : title
        let sub = [(m.date ?? "").trimmingCharacters(in: .whitespaces),
                   (m.role ?? "").trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }.joined(separator: " · ")
        if let id = m.id, !id.isEmpty {
            // Destination-closure (not value-based) so it works in any ancestor stack without needing a
            // registered navigationDestination — avoids a duplicate MemoryDTO destination in the graph stack.
            NavigationLink {
                MemoryDetailView(listItem: MemoryDTO(id: id, title: m.title, exactDate: m.date), auth: auth)
            } label: {
                memoryRowContent(display, sub, tappable: true)
            }.buttonStyle(.plain)
        } else {
            memoryRowContent(display, sub, tappable: false)
        }
    }
    private func memoryRowContent(_ title: String, _ sub: String, tappable: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "book.closed").font(.system(size: 14)).foregroundStyle(WV.teal) }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(16)).foregroundStyle(WT.ink).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if tappable { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // MARK: states + bits
    private var loadingBlock: some View {
        HStack(spacing: 8) {
            ProgressView().tint(WV.teal)
            Text("Loading details…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
    private func failedBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            Button { Task { await vm.load(entityId: entityId, auth: auth) } } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)); Text("Try again").font(.system(size: 14, weight: .medium)) }
                    .foregroundStyle(WV.teal)
            }.witnessPress()
        }
        .padding(.top, 8)
    }

    private func kicker(_ text: String, tone: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(tone)
            .padding(.horizontal, 8).padding(.vertical, 4).background(tone.opacity(0.12), in: Capsule())
    }
    private func pill(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(WV.teal)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
    }
    private func humanize(_ s: String) -> String {
        s.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
