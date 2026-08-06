import SwiftUI

// MARK: - Entity Atlas (web: /dashboard/details) — review every person/place and MERGE
// duplicates. Drag a duplicate tile onto the canonical one, or tap one then the other.
//   GET    /entities            (list)        GET /entities/{id}  (detail)
//   POST   /entities/merge      { source_entity_id, target_entity_id, force_anchor_merge }
//   DELETE /entities/{id}
// Sample data here; a deliberate duplicate ("Pat" → "Pat Morgan") demonstrates merge.
struct EntityAtlasView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entities: [AtlasEntity] = AtlasEntity.samples
    @State private var search = ""
    @State private var mergeMode = false
    @State private var mergeSource: String?
    @State private var mergeTarget: String?
    @State private var merging = false
    @State private var detail: AtlasEntity?

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock
                    searchBar
                    if mergeMode { mergeBanner }
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(filtered) { e in tile(e) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 110)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { EntityDetailView(entity: $0, onDelete: { delete($0) }) }
        .sheet(isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil; mergeSource = nil } })) {
            confirmSheet
        }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Settings").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            Button { withAnimation { mergeMode.toggle(); mergeSource = nil } } label: {
                Text(mergeMode ? "Done" : "Merge")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(mergeMode ? .white : WV.teal)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(mergeMode ? WV.teal : WV.teal.opacity(0.12), in: Capsule())
            }
            .witnessPress()
            .witnessHint("Merge mode lets you combine two tiles that are really the same person or place.")
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ENTITY ATLAS").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            Text("Everyone and everywhere").font(.serif(28)).foregroundStyle(WT.ink)
            Text("Every person and place Witness has drawn from your memories. If one shows up twice, merge mode folds the duplicate into the real one.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.4))
            TextField("Search entities", text: $search).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    private var mergeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 15)).foregroundStyle(WV.teal).padding(.top, 1)
            Text(mergeSource == nil
                 ? "Drag a duplicate tile onto the canonical one — or tap the duplicate, then the one to keep."
                 : "Now tap the tile to keep. The selected duplicate will fold into it.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.65)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tile(_ e: AtlasEntity) -> some View {
        let isSource = mergeSource == e.id
        return Button {
            if mergeMode { tapMerge(e) } else { detail = e }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack { Circle().fill(e.tone.opacity(0.14)); Image(systemName: e.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(e.tone) }
                        .frame(width: 40, height: 40)
                    Spacer()
                    if e.isAnchor { Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(WV.gold) }
                }
                Text(e.name).font(.serif(18)).foregroundStyle(WT.ink).lineLimit(1)
                Text(e.typeLabel).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                Text("\(e.memoryCount) \(e.memoryCount == 1 ? "memory" : "memories")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(e.tone)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(e.tone.opacity(0.1), in: Capsule())
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSource ? WV.teal : WT.ink.opacity(0.07), lineWidth: isSource ? 2 : 1))
            .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
            .opacity(merging ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSource ? 1.03 : 1)
        .draggable(mergeMode ? e.id : "") {
            Text(e.name).font(.serif(15)).padding(8).background(WV.card, in: RoundedRectangle(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { items, _ in
            guard mergeMode, let src = items.first, !src.isEmpty, src != e.id else { return false }
            mergeSource = src; mergeTarget = e.id; return true
        }
    }

    private var confirmSheet: some View {
        let src = entities.first { $0.id == mergeSource }
        let tgt = entities.first { $0.id == mergeTarget }
        let anchorInvolved = (src?.isAnchor ?? false) || (tgt?.isAnchor ?? false)
        return VStack(spacing: 18) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "arrow.triangle.merge").font(.system(size: 26)).foregroundStyle(WV.teal) }
                .frame(width: 70, height: 70)
            Text("Confirm merge").font(.serif(24)).foregroundStyle(WT.ink)
            if let s = src, let t = tgt {
                Text("Everything from “\(s.name)” will move into “\(t.name)”, and “\(s.name)” will be removed. This can't be undone.")
                    .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.65)).multilineTextAlignment(.center)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 28)
            }
            if anchorInvolved {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(WV.gold)
                    Text("An anchor entity is involved — this is a confirmed canonical merge.")
                        .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).background(WV.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
            }
            VStack(spacing: 10) {
                Button { performMerge() } label: {
                    Text(merging ? "Merging…" : "Merge").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
                }
                .witnessPress().disabled(merging)
                Button { mergeTarget = nil; mergeSource = nil } label: {
                    Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(WV.parchment).presentationDetents([.height(anchorInvolved ? 460 : 400)])
    }

    // MARK: actions
    private var filtered: [AtlasEntity] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entities }
        return entities.filter { $0.name.lowercased().contains(q) || $0.typeLabel.lowercased().contains(q) }
    }
    private func tapMerge(_ e: AtlasEntity) {
        if mergeSource == nil { mergeSource = e.id }
        else if mergeSource != e.id { mergeTarget = e.id }
    }
    private func performMerge() {
        // Real: POST /entities/merge { source_entity_id, target_entity_id, force_anchor_merge }
        guard let s = mergeSource, let t = mergeTarget,
              let si = entities.firstIndex(where: { $0.id == s }),
              let ti = entities.firstIndex(where: { $0.id == t }) else { return }
        merging = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            entities[ti].memoryCount += entities[si].memoryCount
            entities.remove(at: si)
            merging = false; mergeTarget = nil; mergeSource = nil
        }
    }
    private func delete(_ e: AtlasEntity) {
        // Real: DELETE /entities/{id}
        entities.removeAll { $0.id == e.id }; detail = nil
    }
}

// MARK: - Entity model + sample data
struct AtlasEntity: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let isAnchor: Bool
    var memoryCount: Int
    let aliases: [String]
    // detail narrative (attributes.*)
    let arcSummary: String
    let whatTheyMeant: String
    let whatIMeant: String
    let lifeImpacts: [String]

    var typeLabel: String { type.prefix(1).uppercased() + type.dropFirst() }
    var icon: String {
        switch type {
        case "person": return "person.fill"
        case "location": return "mappin.and.ellipse"
        case "organization": return "building.2.fill"
        case "animal": return "pawprint.fill"
        default: return "circle.fill"
        }
    }
    var tone: Color {
        switch type {
        case "person": return Color(hex: 0x6b5b95)
        case "location": return WV.teal
        case "organization": return Color(hex: 0x2f6f8f)
        case "animal": return Color(hex: 0xb08828)
        default: return WT.ink
        }
    }

    static let samples: [AtlasEntity] = [
        .init(id: "pat_full", name: "Pat Morgan", type: "person", isAnchor: true, memoryCount: 8, aliases: ["Pat"],
              arcSummary: "A steady presence across many years — the canonical record for this person.",
              whatTheyMeant: "Someone who showed up, again and again, when it counted.",
              whatIMeant: "A person they could rely on in turn.",
              lifeImpacts: ["Taught you steadiness", "A model of loyalty"]),
        .init(id: "pat_dupe", name: "Pat", type: "person", isAnchor: false, memoryCount: 2, aliases: [],
              arcSummary: "A first-name-only mention that likely belongs with Pat Morgan — a perfect merge candidate.",
              whatTheyMeant: "", whatIMeant: "", lifeImpacts: []),
        .init(id: "sam", name: "Sam Rivera", type: "person", isAnchor: true, memoryCount: 6, aliases: [],
              arcSummary: "A close, formative relationship.", whatTheyMeant: "A source of encouragement.",
              whatIMeant: "A loyal friend.", lifeImpacts: ["Widened your sense of what was possible"]),
        .init(id: "home", name: "A childhood home", type: "location", isAnchor: false, memoryCount: 4, aliases: [],
              arcSummary: "The place the earliest memories return to.", whatTheyMeant: "", whatIMeant: "", lifeImpacts: []),
        .init(id: "school", name: "Riverside School", type: "organization", isAnchor: false, memoryCount: 3, aliases: [],
              arcSummary: "Where a formative chapter unfolded.", whatTheyMeant: "", whatIMeant: "", lifeImpacts: []),
        .init(id: "mentor", name: "A mentor", type: "person", isAnchor: false, memoryCount: 3, aliases: [],
              arcSummary: "Someone who shaped how you work.", whatTheyMeant: "A guide at the right moment.",
              whatIMeant: "An eager student.", lifeImpacts: ["Shaped your standards"]),
        .init(id: "dog", name: "A family dog", type: "animal", isAnchor: false, memoryCount: 2, aliases: [],
              arcSummary: "A companion through several years.", whatTheyMeant: "", whatIMeant: "", lifeImpacts: []),
    ]
}

// MARK: - Entity detail (Relationship Arc, What They Meant, What I Meant, Life Impact)
struct EntityDetailView: View {
    let entity: AtlasEntity
    var onDelete: (AtlasEntity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ZStack { Circle().fill(entity.tone.opacity(0.14)); Image(systemName: entity.icon).font(.system(size: 22)).foregroundStyle(entity.tone) }
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entity.name).font(.serif(26)).foregroundStyle(WT.ink)
                            Text(entity.typeLabel).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                        }
                        Spacer()
                        if entity.isAnchor { Text("Anchor").font(.system(size: 11, weight: .semibold)).foregroundStyle(WV.gold).padding(.horizontal, 9).padding(.vertical, 4).background(WV.gold.opacity(0.12), in: Capsule()) }
                    }
                    HStack(spacing: 10) {
                        pill("\(entity.memoryCount) linked memories", "book.closed")
                        if !entity.aliases.isEmpty { pill("Also: \(entity.aliases.joined(separator: ", "))", "tag") }
                    }
                    Button { /* TODO: POST /api/v1/tts/generate */ } label: {
                        HStack(spacing: 6) { Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)); Text("Read aloud").font(.system(size: 14, weight: .medium)) }.foregroundStyle(WV.teal)
                    }.witnessPress()

                    if !entity.arcSummary.isEmpty { section("Relationship Arc", entity.arcSummary) }
                    if !entity.whatTheyMeant.isEmpty { section("What They Meant To Me", entity.whatTheyMeant) }
                    if !entity.whatIMeant.isEmpty { section("What I Meant To Them", entity.whatIMeant) }
                    if !entity.lifeImpacts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LIFE IMPACT").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
                            ForEach(entity.lifeImpacts, id: \.self) { i in
                                HStack(alignment: .top, spacing: 8) { Circle().fill(WV.gold).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(i).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WV.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                    }

                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete this entity").font(.system(size: 16, weight: .semibold)).foregroundStyle(WV.danger)
                            .frame(maxWidth: .infinity).frame(height: 52).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.3), lineWidth: 1))
                    }.witnessPress()
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Atlas").font(.system(size: 16)) }
                        .foregroundStyle(WV.teal).frame(height: 44)
                }.witnessPress()
                Spacer()
            }
            .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete this entity? It will be removed from the knowledge graph.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(entity) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func pill(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 5) { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(WV.teal); Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7)) }
            .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
            Text(body).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }
}
