import SwiftUI

// MARK: - Explain Me — seven-tab synthesis of a life. Endpoints:
//   GET /api/v1/explain-me/overview | active-forces | patterns | breaking-points
//       | contradictions | identity | beliefs
// Sample data here; mapped to those endpoints for wiring.
struct ExplainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ExTab = .overview
    @State private var showRecord = false

    enum ExTab: String, CaseIterable, Identifiable {
        case overview, forces, breaking, patterns, contradictions, identity, beliefs
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "Overview"; case .forces: return "Forces"; case .breaking: return "Breaking Points"
            case .patterns: return "Patterns"; case .contradictions: return "Contradictions"; case .identity: return "Identity"; case .beliefs: return "Beliefs"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)
                tabBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        switch tab {
                        case .overview:       overviewTab
                        case .forces:         forcesTab
                        case .breaking:       breakingTab
                        case .patterns:       patternsTab
                        case .contradictions: contradictionsTab
                        case .identity:       identityTab
                        case .beliefs:        beliefsTab
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 110)
                    .id(tab)
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            Text("Explain Me").font(.serif(18)).foregroundStyle(WT.ink)
            Spacer()
            Color.clear.frame(width: 60, height: 44)
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExTab.allCases) { t in
                    let sel = t == tab
                    Text(t.label)
                        .font(.system(size: 14, weight: sel ? .semibold : .regular))
                        .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(sel ? WV.teal : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(sel ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { tab = t } }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(WV.parchment)
    }

    // MARK: Overview
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE SYNTHESIS").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Text(ExplainSample.headline).font(.serif(25)).foregroundStyle(WT.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                Button { /* TODO: POST /api/v1/tts/generate */ } label: {
                    HStack(spacing: 6) { Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)); Text("Read").font(.system(size: 14, weight: .medium)) }.foregroundStyle(WV.teal)
                }.witnessPress()
            }
            overviewSection("ACTIVE FORCES") { ForEach(Array(ExplainSample.forces.prefix(2))) { forceCard($0) } }
            overviewSection("PATTERNS OF A LIFE") { ForEach(Array(ExplainSample.patterns.prefix(2))) { patternCard($0) } }
            overviewSection("BREAKING POINTS") { ForEach(Array(ExplainSample.breaking.prefix(1))) { breakingCard($0) } }
            overviewSection("CONTRADICTIONS PRESERVED") { ForEach(Array(ExplainSample.contradictions.prefix(1))) { contradictionCard($0) } }
        }
    }
    private func overviewSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { sectionLabel(title); content() }
    }

    // MARK: Forces
    private var forcesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Active Forces", "The currents still shaping how you choose, today.")
            ForEach(ExplainSample.forces) { forceCard($0) }
        }
    }
    private func forceCard(_ f: ExForce) -> some View {
        cardShell {
            HStack {
                Text(f.title).font(.serif(20)).foregroundStyle(WT.ink)
                Spacer()
                if f.activeToday { strengthBadge(f.activeStrength) }
            }
            if !f.originMemory.isEmpty { meta("Origin memory", f.originMemory) }
            if !f.affectedDomains.isEmpty { chipRow("Affected domains", f.affectedDomains, tone: WV.teal) }
            if !f.downstreamEffects.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sublabel("Downstream effects")
                    ForEach(f.downstreamEffects, id: \.self) { e in
                        HStack(alignment: .top, spacing: 7) { Circle().fill(WV.gold).frame(width: 5, height: 5).padding(.top, 7)
                            Text(e).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            if !f.identityImpact.isEmpty { whyBlock("Why this matters", f.identityImpact) }
        }
    }

    // MARK: Breaking points
    private var breakingTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Breaking Points", "The moments the story changed direction.")
            ForEach(ExplainSample.breaking) { breakingCard($0) }
        }
    }
    private func breakingCard(_ b: ExBreaking) -> some View {
        cardShell {
            if let d = b.dateLabel { Text(d.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WV.gold) }
            Text(b.title).font(.serif(20)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            Text(b.summary).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if !b.whyItMattered.isEmpty { whyBlock("Why it mattered", b.whyItMattered) }
            if !b.beforeSelf.isEmpty || !b.afterSelf.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    beforeAfter("Who I was before", b.beforeSelf)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)).padding(.top, 22)
                    beforeAfter("Who I became", b.afterSelf)
                }
            }
        }
    }
    private func beforeAfter(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sublabel(label)
            Text(text).font(.serif(15)).foregroundStyle(WT.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Patterns
    private var patternsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Patterns of a Life", "What repeats — across years, people, and places.")
            ForEach(ExplainSample.patterns) { patternCard($0) }
        }
    }
    private func patternCard(_ p: ExPattern) -> some View {
        cardShell {
            HStack { Text(p.title).font(.serif(19)).foregroundStyle(WT.ink); Spacer(); confidenceBadge(p.confidence) }
            Text(p.description).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text("Observed \(p.occurrenceCount) times").font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
                .padding(.horizontal, 9).padding(.vertical, 5).background(WV.teal.opacity(0.1), in: Capsule())
        }
    }

    // MARK: Contradictions
    private var contradictionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Contradictions Preserved", "Two truths that are both real — held without forcing resolution.")
            ForEach(ExplainSample.contradictions) { contradictionCard($0) }
        }
    }
    private func contradictionCard(_ c: ExContradiction) -> some View {
        cardShell {
            HStack { Spacer(); confidenceBadge(c.confidence) }
            truthBlock("One truth", c.sideA, tone: WV.teal)
            HStack(spacing: 8) { Rectangle().fill(WT.ink.opacity(0.1)).frame(height: 1); Text("and yet").font(.serif(13)).italic().foregroundStyle(WT.ink.opacity(0.45)); Rectangle().fill(WT.ink.opacity(0.1)).frame(height: 1) }
            truthBlock("Another truth", c.sideB, tone: WV.gold)
            if !c.whyBothAreTrue.isEmpty { whyBlock("Why both are true", c.whyBothAreTrue) }
        }
    }
    private func truthBlock(_ label: String, _ text: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(tone)
            Text(text).font(.serif(16)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(tone.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Identity
    private var identityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Identity", "Longitudinal emotional continuity — who you've been, across time.")
            sectionLabel("ACTIVE INTERPRETATIONS")
            ForEach(ExplainSample.identityStates) { stateCard($0) }
            sectionLabel("TRANSITIONS")
            ForEach(ExplainSample.transitions) { transitionCard($0) }
        }
    }
    private func stateCard(_ s: ExIdentityState) -> some View {
        cardShell {
            HStack { Text(s.label).font(.serif(19)).foregroundStyle(WT.ink); Spacer()
                if s.active { Text("Active").font(.system(size: 11, weight: .semibold)).foregroundStyle(WV.teal).padding(.horizontal, 9).padding(.vertical, 4).background(WV.teal.opacity(0.12), in: Capsule()) } }
            if !s.dateRange.isEmpty { Text(s.dateRange).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)) }
            Text(s.description).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func transitionCard(_ t: ExTransition) -> some View {
        cardShell {
            HStack(alignment: .center, spacing: 8) {
                Text(t.fromState).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.7))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WV.gold)
                Text(t.toState).font(.serif(16)).foregroundStyle(WT.ink)
                Spacer()
            }
            if !t.summary.isEmpty { Text(t.summary).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }
            if !t.emotionalCost.isEmpty { meta("Emotional cost", t.emotionalCost) }
        }
    }

    // MARK: Beliefs
    private var beliefsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader("Beliefs", "What you hold to be true — and how it has changed.")
            sectionLabel("STILL HELD")
            ForEach(ExplainSample.beliefs.filter { $0.stillHeld }) { beliefCard($0) }
            sectionLabel("EVOLVED")
            ForEach(ExplainSample.evolutions) { evolutionCard($0) }
        }
    }
    private func beliefCard(_ b: ExBelief) -> some View {
        cardShell {
            HStack { Text("“\(b.statement)”").font(.serif(17)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true); Spacer(); confidenceBadge(b.confidence) }
            Text(b.beliefType).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
        }
    }
    private func evolutionCard(_ e: ExEvolution) -> some View {
        cardShell {
            VStack(alignment: .leading, spacing: 8) {
                truthBlock("From", e.fromBelief, tone: WT.ink.opacity(0.4))
                truthBlock("To", e.toBelief, tone: WV.teal)
            }
            if !e.changeReason.isEmpty { whyBlock("What changed it", e.changeReason) }
        }
    }

    // MARK: Shared building blocks
    private func tabHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }
    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
    }
    private func sublabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4))
    }
    private func meta(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) { sublabel(label); Text(value).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.7)) }
    }
    private func chipRow(_ label: String, _ items: [String], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sublabel(label)
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { Text($0).font(.system(size: 12, weight: .medium)).foregroundStyle(tone)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(tone.opacity(0.1), in: Capsule()) }
            }
        }
    }
    private func whyBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sublabel(label)
            Text(text).font(.serif(15)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(WV.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func strengthBadge(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(WV.teal)
            .padding(.horizontal, 9).padding(.vertical, 4).background(WV.teal.opacity(0.12), in: Capsule())
    }
    private func confidenceBadge(_ c: ExConfidence) -> some View {
        Text(c.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.color)
            .padding(.horizontal, 8).padding(.vertical, 3).background(c.color.opacity(0.12), in: Capsule())
    }
    private func cardShell<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
}

// MARK: - Confidence
enum ExConfidence { case high, medium, low
    var label: String { switch self { case .high: return "High"; case .medium: return "Medium"; case .low: return "Low" } }
    var color: Color { switch self { case .high: return WV.teal; case .medium: return WV.gold; case .low: return Color(hex: 0x6b6256) } }
}

// MARK: - Models + sample data (generic; real data from explain-me endpoints)
struct ExForce: Identifiable { let id = UUID(); let title: String; let originMemory: String; let activeStrength: String; let activeToday: Bool; let affectedDomains: [String]; let downstreamEffects: [String]; let identityImpact: String }
struct ExBreaking: Identifiable { let id = UUID(); let title: String; let dateLabel: String?; let summary: String; let whyItMattered: String; let beforeSelf: String; let afterSelf: String }
struct ExPattern: Identifiable { let id = UUID(); let title: String; let description: String; let occurrenceCount: Int; let confidence: ExConfidence }
struct ExContradiction: Identifiable { let id = UUID(); let sideA: String; let sideB: String; let whyBothAreTrue: String; let confidence: ExConfidence }
struct ExIdentityState: Identifiable { let id = UUID(); let label: String; let dateRange: String; let description: String; let active: Bool }
struct ExTransition: Identifiable { let id = UUID(); let fromState: String; let toState: String; let summary: String; let emotionalCost: String }
struct ExBelief: Identifiable { let id = UUID(); let statement: String; let beliefType: String; let stillHeld: Bool; let confidence: ExConfidence }
struct ExEvolution: Identifiable { let id = UUID(); let fromBelief: String; let toBelief: String; let changeReason: String }

enum ExplainSample {
    static let headline = "You return, again and again, to the people who shaped you — and to the quiet courage it takes to begin again."
    static let forces: [ExForce] = [
        .init(title: "Reinvention", originMemory: "A big move · 2005", activeStrength: "Strong", activeToday: true,
              affectedDomains: ["Work", "Home", "Identity"],
              downstreamEffects: ["A willingness to start over", "Comfort with uncertainty"],
              identityImpact: "You became someone who could begin again — and trust that you would land."),
        .init(title: "Service", originMemory: "Early responsibility · 1990s", activeStrength: "Steady", activeToday: true,
              affectedDomains: ["Relationships", "Work"],
              downstreamEffects: ["Looking after others first", "A deep sense of duty"],
              identityImpact: "Caring for others became a way of locating your own worth."),
        .init(title: "Family", originMemory: "The center of gravity", activeStrength: "Strong", activeToday: true,
              affectedDomains: ["Identity", "Belonging"], downstreamEffects: ["A pull toward home"],
              identityImpact: "Family remains the gravity most of your memories orbit."),
    ]
    static let breaking: [ExBreaking] = [
        .init(title: "The move across the country", dateLabel: "2005", summary: "A sample breaking point — a decision that reset the shape of everything after it.",
              whyItMattered: "It proved you could leave certainty behind and still build a life.",
              beforeSelf: "Someone who stayed where it was safe.", afterSelf: "Someone who could start over."),
        .init(title: "A graduation", dateLabel: "1992", summary: "A sample pivot marking the end of one chapter and the start of another.",
              whyItMattered: "It was the first door you walked through on your own.",
              beforeSelf: "A child of your circumstances.", afterSelf: "An author of your own next step."),
    ]
    static let patterns: [ExPattern] = [
        .init(title: "Returning to the people who shaped you", description: "Across years and distances, you circle back to a small set of formative people.", occurrenceCount: 9, confidence: .high),
        .init(title: "Choosing the harder, truer path", description: "When stability and honesty conflict, you tend to choose honesty.", occurrenceCount: 6, confidence: .medium),
    ]
    static let contradictions: [ExContradiction] = [
        .init(sideA: "You crave stability and a place that stays the same.", sideB: "You keep choosing to start over somewhere new.",
              whyBothAreTrue: "The longing for home and the need to grow are not opposites in you — they take turns, and both are real.", confidence: .high),
    ]
    static let identityStates: [ExIdentityState] = [
        .init(label: "The dutiful one", dateRange: "1980 – 2005", description: "Defined by responsibility and looking after others.", active: false),
        .init(label: "The reinventor", dateRange: "2005 – now", description: "Defined by the willingness to begin again, on your own terms.", active: true),
    ]
    static let transitions: [ExTransition] = [
        .init(fromState: "The dutiful one", toState: "The reinventor", summary: "A sample transition — moving from a self built on obligation to one built on choice.", emotionalCost: "Leaving certainty, and the guilt of choosing yourself."),
    ]
    static let beliefs: [ExBelief] = [
        .init(statement: "Hard work earns belonging.", beliefType: "Core value", stillHeld: true, confidence: .high),
        .init(statement: "You have to do it all alone.", beliefType: "Defense", stillHeld: false, confidence: .medium),
    ]
    static let evolutions: [ExEvolution] = [
        .init(fromBelief: "You have to do it all alone.", toBelief: "It's okay to lean on the people who love you.", changeReason: "A sample evolution — a moment when being carried taught you that needing help isn't weakness."),
    ]
}
