import SwiftUI

// MARK: - Learn — "Ask the Pattern Layer". Whole-life single-shot Q&A grounded in your memories, with cited
// sources (memory → tap-through to detail; entity → chip) and optional confidence. Interpretive lenses are
// preset questions. Wired to POST /api/v1/learn/chat { message } (stateless — no mode, no session_id).
struct LearnView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager
    @StateObject private var vm = LearnViewModel()

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    askBox
                    if vm.isAsking { thinkingCard }
                    if case .failed(let msg) = vm.phase { errorCard(msg) }
                    if vm.reflections.isEmpty && !vm.isAsking { lensesSection }
                    else { reflectionsSection }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 120)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            if !vm.reflections.isEmpty {
                Button { withAnimation { vm.clear() } } label: {
                    Text("Clear").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)).frame(height: 44)
                }.witnessPress()
            }
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASK THE PATTERN LAYER").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            Text("Learn").font(.serif(28)).foregroundStyle(WT.ink)
            Text("Ask your life a question. Unlike Scarlett, who explores one memory, this reaches across your whole story — and shows you the memories and people it drew from.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var askBox: some View {
        HStack(spacing: 10) {
            TextField("Ask the Pattern Layer…", text: $query, axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).lineLimit(1...4).focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            Button { submit(query) } label: {
                ZStack { Circle().fill(canAsk ? WV.teal : WV.teal.opacity(0.4)); Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }
                    .frame(width: 50, height: 50)
            }
            .witnessPress().disabled(!canAsk)
        }
    }
    private var canAsk: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isAsking }

    private var thinkingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(WV.teal)
            Text("Pattern finding across memory…").font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.55))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // MARK: Interpretive lenses (preset questions)
    private var lensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTERPRETIVE PATHS").font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
            Text("Tap a path to ask, or write your own question above.").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            ForEach(InsightLens.all) { lens in
                Button { submit(lens.question) } label: {
                    HStack(spacing: 12) {
                        ZStack { Circle().fill(lens.tone.opacity(0.12)); Image(systemName: "arrow.triangle.branch").font(.system(size: 15, weight: .medium)).foregroundStyle(lens.tone) }
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lens.title).font(.serif(17)).foregroundStyle(WT.ink)
                            Text(lens.desc).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                    .shadow(color: WT.ink.opacity(0.04), radius: 7, y: 3)
                }
                .witnessPress()
            }
        }
    }

    // MARK: Reflections (answers)
    private var reflectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.reflections.count > 1 {
                Text("PREVIOUS REFLECTIONS").font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
            }
            ForEach(vm.reflections) { r in reflectionCard(r) }
        }
    }

    private func reflectionCard(_ r: LearnReflection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(r.question).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("Pattern finding across memory").font(.system(size: 11, weight: .medium)).foregroundStyle(WV.gold)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(WV.gold.opacity(0.12), in: Capsule())
                if let c = r.confidence { confidenceMeter(c) }
            }
            Text(r.answer).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.9)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)

            if !r.memorySources.isEmpty { memorySourceGroup(r.memorySources) }
            if !r.entitySources.isEmpty { entitySourceGroup(r.entitySources) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.05), radius: 10, y: 5)
    }

    private func confidenceMeter(_ c: Double) -> some View {
        HStack(spacing: 5) {
            Text("Confidence").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.45))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.1))
                    Capsule().fill(WV.teal).frame(width: geo.size.width * c)
                }
            }
            .frame(width: 50, height: 6)
            Text("\(Int(c * 100))%").font(.system(size: 11, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55))
        }
    }

    // Memory sources are tappable → real MemoryDetailView (same pattern as Timeline); disabled if id is missing.
    private func memorySourceGroup(_ sources: [LearnSource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REFERENCED MEMORIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
            FlowWrap(sources) { s in
                NavigationLink {
                    MemoryDetailView(listItem: MemoryDTO(id: s.memoryId ?? "", title: s.memoryTitle, exactDate: s.memoryDate), auth: auth)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed").font(.system(size: 10)).foregroundStyle(WV.teal)
                        Text(s.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((s.memoryId ?? "").isEmpty)
            }
        }
    }

    // Entity sources are plain chips (name + type) — not tappable.
    private func entitySourceGroup(_ sources: [LearnSource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REFERENCED PEOPLE AND ENTITIES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
            FlowWrap(sources) { s in
                HStack(spacing: 5) {
                    Image(systemName: "person").font(.system(size: 10)).foregroundStyle(WV.teal)
                    Text(s.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
            }
        }
    }

    // Soft, retryable failure — re-asks the preserved question (401 → refresh handled in the VM).
    private func errorCard(_ message: String) -> some View {
        Button { Task { await vm.retry(auth: auth) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(WV.danger)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.2), lineWidth: 1))
        }
        .witnessPress()
    }

    // MARK: Ask — single-shot POST /api/v1/learn/chat via the VM.
    private func submit(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = ""; focused = false
        Task { await vm.ask(q, auth: auth) }
    }
}

// MARK: - Models
struct InsightLens: Identifiable {
    let id = UUID()
    let title: String; let desc: String; let question: String; let tone: Color
    static let all: [InsightLens] = [
        .init(title: "Turning Points", desc: "Find moments where the life story changed direction or identity shifted.",
              question: "What are the biggest turning points in my life, and what did they change about me?", tone: WV.gold),
        .init(title: "Relationship Patterns", desc: "Trace recurring attachment, loyalty, separation, longing, and emotional asymmetry.",
              question: "What patterns do you see in my relationships across time?", tone: WV.teal),
        .init(title: "Identity Formation", desc: "Understand which memories shaped self-worth, responsibility, and inner identity.",
              question: "What memories most shaped my identity and how I see myself?", tone: Color(hex: 0x6b5b95)),
        .init(title: "Recurring Themes", desc: "Surface emotional loops and themes repeated across years, people, and places.",
              question: "What are my recurring emotional themes across all of my memories?", tone: WV.teal),
        .init(title: "Contradictions Preserved", desc: "Reveal opposing truths that coexist without forcing resolution.",
              question: "What contradictions do you see in my memories that should not be flattened?", tone: WV.danger),
        .init(title: "Influential People", desc: "Identify who exerted the strongest long-term emotional and identity influence.",
              question: "Who are the most influential people in my life story and why?", tone: Color(hex: 0x6b5b95)),
        .init(title: "Life Lessons", desc: "Extract the lessons that became beliefs, defenses, values, or grief rituals.",
              question: "What life lessons have I learned from the memories I have preserved?", tone: WV.gold),
        .init(title: "Discrimination & Exclusion", desc: "Ask where class, shame, dismissal, or social exclusion shaped behavior and identity.",
              question: "Where do you see patterns of discrimination, exclusion, class shame, or being judged before people really knew me?", tone: WV.danger),
    ]
}

struct LearnSource: Identifiable {
    let id = UUID()
    enum Kind { case memory, entity }
    let kind: Kind
    let label: String
    let memoryId: String?      // memory tap-through payload (nil for entity)
    let memoryTitle: String?
    let memoryDate: String?
}

struct LearnReflection: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let confidence: Double?     // nil → no meter (no fabricated confidence)
    let sources: [LearnSource]
    var memorySources: [LearnSource] { sources.filter { $0.kind == .memory } }
    var entitySources: [LearnSource] { sources.filter { $0.kind == .entity } }
}

// MARK: - Simple wrapping layout for source chips
struct FlowWrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) { self.data = data; self.content = content }

    var body: some View {
        var width = CGFloat.zero, height = CGFloat.zero
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(data) { item in
                    content(item)
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width { width = 0; height -= d.height + 8 }
                            let result = width
                            if item.id == data.last?.id { width = 0 } else { width -= d.width + 8 }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item.id == data.last?.id { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: 64)
    }
}
