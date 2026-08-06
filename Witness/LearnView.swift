import SwiftUI

// MARK: - Learn — "Ask the Pattern Layer". Whole-life Q&A grounded in your memories,
// with cited sources, confidence, modes, and interpretive lenses.
//   POST /api/v1/learn/chat { message, mode, session_id } -> { answer, confidence, query_type, sources }
//   POST /api/v1/tts/generate (Read aloud)
// Answers are sample here; mapped to the engine for wiring.
struct LearnView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mode = "jarvis"
    @State private var query = ""
    @State private var thinking = false
    @State private var reflections: [LearnReflection] = []
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    modeSelector
                    askBox
                    if thinking { thinkingCard }
                    if reflections.isEmpty && !thinking { lensesSection }
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
            if !reflections.isEmpty {
                Button { withAnimation { reflections.removeAll() } } label: {
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

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LearnModeOption.all) { m in
                        let sel = mode == m.id
                        Text(m.label)
                            .font(.system(size: 14, weight: sel ? .semibold : .regular))
                            .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(sel ? WV.teal : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(sel ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
                            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { mode = m.id } }
                    }
                }
            }
            if let m = LearnModeOption.all.first(where: { $0.id == mode }) {
                Text(m.desc).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var askBox: some View {
        HStack(spacing: 10) {
            TextField("Ask the Pattern Layer…", text: $query, axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).lineLimit(1...4).focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            Button { ask(query) } label: {
                ZStack { Circle().fill(canAsk ? WV.teal : WV.teal.opacity(0.4)); Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }
                    .frame(width: 50, height: 50)
            }
            .witnessPress().disabled(!canAsk)
        }
    }
    private var canAsk: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking }

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
                Button { ask(lens.question) } label: {
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
            if reflections.count > 1 {
                Text("PREVIOUS REFLECTIONS").font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
            }
            ForEach(reflections) { r in reflectionCard(r) }
        }
    }

    private func reflectionCard(_ r: LearnReflection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(r.question).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("Pattern finding across memory").font(.system(size: 11, weight: .medium)).foregroundStyle(WV.gold)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(WV.gold.opacity(0.12), in: Capsule())
                confidenceMeter(r.confidence)
            }
            Text(r.answer).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.9)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)

            if !r.memorySources.isEmpty { sourceGroup("Referenced memories", r.memorySources, icon: "book.closed") }
            if !r.entitySources.isEmpty { sourceGroup("Referenced people and entities", r.entitySources, icon: "person") }

            Button { /* TODO: POST /api/v1/tts/generate { text: answer } */ } label: {
                HStack(spacing: 6) { Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)); Text("Read").font(.system(size: 14, weight: .medium)) }
                    .foregroundStyle(WV.teal)
            }
            .witnessPress().padding(.top, 2)
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

    private func sourceGroup(_ title: String, _ sources: [LearnSource], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
            FlowWrap(sources) { s in
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(WV.teal)
                    Text(s.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75))
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(WV.teal.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: Ask (sample reflection)
    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = ""; focused = false
        withAnimation { thinking = true }
        // Real: POST /api/v1/learn/chat { message: q, mode } -> answer, confidence, query_type, sources
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                thinking = false
                reflections.insert(LearnReflection.sample(question: q), at: 0)
            }
        }
    }
}

// MARK: - Models
struct LearnModeOption: Identifiable {
    let id: String; let label: String; let desc: String
    static let all: [LearnModeOption] = [
        .init(id: "jarvis", label: "Grounded", desc: "Answers plainly from your memories — the default, conversational voice."),
        .init(id: "commercial", label: "Accessible", desc: "Broad, reader-friendly framing, as if for a wider audience."),
        .init(id: "storyteller", label: "Storyteller", desc: "Told as story — vivid, warm, scene by scene."),
        .init(id: "analytical", label: "Analytical", desc: "Structured patterns, evidence, and reasoning."),
        .init(id: "devil_advocate", label: "Challenger", desc: "Pushes back and tests what you might be avoiding."),
    ]
}

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
}

struct LearnReflection: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let confidence: Double
    let sources: [LearnSource]
    var memorySources: [LearnSource] { sources.filter { $0.kind == .memory } }
    var entitySources: [LearnSource] { sources.filter { $0.kind == .entity } }

    static func sample(question: String) -> LearnReflection {
        LearnReflection(
            question: question,
            answer: "This is a sample reflection, shown so you can see how an answer reads — grounded in your memories, with its sources named below. Once connected, this draws across your whole life story to answer in your chosen voice, citing the specific memories and people it reasoned from. Your real reflections will replace this text.",
            confidence: 0.82,
            sources: [
                .init(kind: .memory, label: "A big move · 2005"),
                .init(kind: .memory, label: "Graduation · 1992"),
                .init(kind: .memory, label: "A new chapter · 2012"),
                .init(kind: .entity, label: "A mentor"),
                .init(kind: .entity, label: "Family"),
            ]
        )
    }
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
