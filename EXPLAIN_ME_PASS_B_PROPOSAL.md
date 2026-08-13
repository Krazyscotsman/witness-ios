# Witness — Explain Me PASS B (the six detail tabs) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Reuses the Pass A VM + helpers + card renderers.
Read-only, lazy per tab. Field names authoritative from Witness_Explain_Me_Spec.md §3.

## Flags
1. List endpoints modeled as wrappers ({forces:[…]}, {patterns:[…]}, {breaking_points:[…]}, {contradictions:[…]})
   per §3 "active-forces forces[]". If an endpoint returns a bare array, that tab shows its failed state (not a
   crash) — one-line fix. Will confirm on device.
2. ?limit=50: §2 table applies it to all FOUR list tabs; prose says "three". Passing on all four (harmless if
   ignored).

---

## APIModels.swift — list wrappers + identity/beliefs DTOs (append; nonisolated, convertFromSnakeCase)
```swift
nonisolated struct ExForcesResponse: Decodable { let forces: [ExForceDTO]? }
nonisolated struct ExPatternsResponse: Decodable { let patterns: [ExPatternDTO]? }
nonisolated struct ExBreakingResponse: Decodable { let breakingPoints: [ExBreakingDTO]? }
nonisolated struct ExContradictionsResponse: Decodable { let contradictions: [ExContradictionDTO]? }

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
```

## ExplainViewModel.swift — per-tab state + caches + unified lazy load
```diff
     @Published private(set) var overviewState: LoadState = .idle
     @Published private(set) var overview: ExplainOverview?
+    @Published private(set) var forcesState: LoadState = .idle
+    @Published private(set) var forces: [ExForceDTO] = []
+    @Published private(set) var patternsState: LoadState = .idle
+    @Published private(set) var patterns: [ExPatternDTO] = []
+    @Published private(set) var breakingState: LoadState = .idle
+    @Published private(set) var breaking: [ExBreakingDTO] = []
+    @Published private(set) var contradictionsState: LoadState = .idle
+    @Published private(set) var contradictions: [ExContradictionDTO] = []
+    @Published private(set) var identityState: LoadState = .idle
+    @Published private(set) var identity: ExIdentity?
+    @Published private(set) var beliefsState: LoadState = .idle
+    @Published private(set) var beliefs: ExBeliefs?
```
```swift
    // Unified lazy entry — called by the view on each tab's first appearance (task id: tab).
    func load(_ tab: ExplainView.ExTab, auth: AuthManager) async {
        switch tab {
        case .overview:       await loadOverview(auth: auth)
        case .forces:         await loadForces(auth: auth)
        case .patterns:       await loadPatterns(auth: auth)
        case .breaking:       await loadBreaking(auth: auth)
        case .contradictions: await loadContradictions(auth: auth)
        case .identity:       await loadIdentity(auth: auth)
        case .beliefs:        await loadBeliefs(auth: auth)
        }
    }
    func retry(_ tab: ExplainView.ExTab, auth: AuthManager) async {
        switch tab {
        case .overview:       overviewState = .idle
        case .forces:         forcesState = .idle
        case .patterns:       patternsState = .idle
        case .breaking:       breakingState = .idle
        case .contradictions: contradictionsState = .idle
        case .identity:       identityState = .idle
        case .beliefs:        beliefsState = .idle
        }
        await load(tab, auth: auth)
    }

    private func loadForces(auth: AuthManager) async {
        if forcesState == .loading || forcesState == .loaded { return }
        forcesState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/active-forces?limit=50", timeout: 20, decoder: Self.snake, as: ExForcesResponse.self) }
            forces = r.forces ?? []; forcesState = .loaded
        } catch { forcesState = Self.fail(error) }
    }
    private func loadPatterns(auth: AuthManager) async {
        if patternsState == .loading || patternsState == .loaded { return }
        patternsState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/patterns?limit=50", timeout: 20, decoder: Self.snake, as: ExPatternsResponse.self) }
            patterns = r.patterns ?? []; patternsState = .loaded
        } catch { patternsState = Self.fail(error) }
    }
    private func loadBreaking(auth: AuthManager) async {
        if breakingState == .loading || breakingState == .loaded { return }
        breakingState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/breaking-points?limit=50", timeout: 20, decoder: Self.snake, as: ExBreakingResponse.self) }
            breaking = r.breakingPoints ?? []; breakingState = .loaded
        } catch { breakingState = Self.fail(error) }
    }
    private func loadContradictions(auth: AuthManager) async {
        if contradictionsState == .loading || contradictionsState == .loaded { return }
        contradictionsState = .loading
        do {
            let r = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/contradictions?limit=50", timeout: 20, decoder: Self.snake, as: ExContradictionsResponse.self) }
            contradictions = r.contradictions ?? []; contradictionsState = .loaded
        } catch { contradictionsState = Self.fail(error) }
    }
    private func loadIdentity(auth: AuthManager) async {
        if identityState == .loading || identityState == .loaded { return }
        identityState = .loading
        do {
            identity = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/identity", timeout: 20, decoder: Self.snake, as: ExIdentity.self) }
            identityState = .loaded
        } catch { identityState = Self.fail(error) }
    }
    private func loadBeliefs(auth: AuthManager) async {
        if beliefsState == .loading || beliefsState == .loaded { return }
        beliefsState = .loading
        do {
            beliefs = try await withAuth(auth) { try await APIClient.shared.get("/api/v1/explain-me/beliefs", timeout: 20, decoder: Self.snake, as: ExBeliefs.self) }
            beliefsState = .loaded
        } catch { beliefsState = Self.fail(error) }
    }

    // withAuth already rethrows SessionError.sessionEnded; map to a friendly failed message.
    private static func fail(_ error: Error) -> LoadState {
        // task(id:) cancels an in-flight load on a fast tab switch → don't show a false error.
        if error is CancellationError { return .idle }
        if case let APIError.network(e) = error, (e as? URLError)?.code == .cancelled { return .idle }
        return .failed("We couldn’t load this yet. Check your connection and try again.")
    }
```
(`SessionError.sessionEnded` currently `private`; keep — `fail(_)` maps any thrown error incl. it to the same
friendly message. loadOverview keeps its own explicit sessionEnded copy from Pass A.)

## ExplainView.swift — wire the six tabs + lazy per-tab task
```diff
                     VStack(alignment: .leading, spacing: 18) {
                         switch tab {
                         case .overview: overviewTab
-                        default:        placeholderTab(tab.label)   // Pass B fills the six detail tabs
+                        case .forces:         forcesTab
+                        case .patterns:       patternsTab
+                        case .breaking:       breakingTab
+                        case .contradictions: contradictionsTab
+                        case .identity:       identityTab
+                        case .beliefs:        beliefsTab
                         }
                     }
```
```diff
-        .task { await vm.loadOverview(auth: auth) }
+        .task(id: tab) { await vm.load(tab, auth: auth) }
```
```swift
    // MARK: Detail tabs (lazy; reuse the DTO card renderers)
    @ViewBuilder private var forcesTab: some View {
        detailScaffold(vm.forcesState, retry: .forces, header: "Active Forces",
                       subtitle: "The currents still shaping how you choose, today.", isEmpty: vm.forces.isEmpty,
                       emptyText: "No active forces surfaced yet.") {
            ForEach(Array(vm.forces.enumerated()), id: \.offset) { _, x in forceCard(x) }
        }
    }
    @ViewBuilder private var patternsTab: some View {
        detailScaffold(vm.patternsState, retry: .patterns, header: "Patterns of a Life",
                       subtitle: "What repeats — across years, people, and places.", isEmpty: vm.patterns.isEmpty,
                       emptyText: "No patterns surfaced yet.") {
            ForEach(Array(vm.patterns.enumerated()), id: \.offset) { _, x in patternCard(x) }
        }
    }
    @ViewBuilder private var breakingTab: some View {
        detailScaffold(vm.breakingState, retry: .breaking, header: "Breaking Points",
                       subtitle: "The moments the story changed direction.", isEmpty: vm.breaking.isEmpty,
                       emptyText: "No breaking points surfaced yet.") {
            ForEach(Array(vm.breaking.enumerated()), id: \.offset) { _, x in breakingCard(x) }
        }
    }
    @ViewBuilder private var contradictionsTab: some View {
        detailScaffold(vm.contradictionsState, retry: .contradictions, header: "Contradictions Preserved",
                       subtitle: "Two truths that are both real — held without forcing resolution.", isEmpty: vm.contradictions.isEmpty,
                       emptyText: "No contradictions surfaced yet.") {
            ForEach(Array(vm.contradictions.enumerated()), id: \.offset) { _, x in contradictionCard(x) }
        }
    }
    @ViewBuilder private var identityTab: some View {
        detailScaffold(vm.identityState, retry: .identity, header: "Identity",
                       subtitle: "Who you've been, across time.",
                       isEmpty: (vm.identity?.identityStates ?? []).isEmpty && (vm.identity?.transitions ?? []).isEmpty,
                       emptyText: "No identity states surfaced yet.") {
            if let c = vm.identity?.callout, !c.isEmpty { calloutRow(c) }
            let states = vm.identity?.identityStates ?? []
            if !states.isEmpty {
                sectionLabel("ACTIVE INTERPRETATIONS")
                ForEach(Array(states.enumerated()), id: \.offset) { _, s in stateCard(s) }
            }
            let trans = vm.identity?.transitions ?? []
            if !trans.isEmpty {
                sectionLabel("TRANSITIONS")
                ForEach(Array(trans.enumerated()), id: \.offset) { _, t in transitionCard(t) }
            }
        }
    }
    @ViewBuilder private var beliefsTab: some View {
        detailScaffold(vm.beliefsState, retry: .beliefs, header: "Beliefs",
                       subtitle: "What you hold to be true — and how it has changed.",
                       isEmpty: (vm.beliefs?.activeBeliefs ?? []).isEmpty && (vm.beliefs?.changedBeliefs ?? []).isEmpty && (vm.beliefs?.evolutions ?? []).isEmpty,
                       emptyText: "No beliefs surfaced yet.") {
            if let c = vm.beliefs?.callout, !c.isEmpty { calloutRow(c) }
            let held = vm.beliefs?.activeBeliefs ?? []
            if !held.isEmpty { sectionLabel("STILL HELD"); ForEach(Array(held.enumerated()), id: \.offset) { _, b in beliefCard(b) } }
            let changed = vm.beliefs?.changedBeliefs ?? []
            if !changed.isEmpty { sectionLabel("CHANGED"); ForEach(Array(changed.enumerated()), id: \.offset) { _, b in beliefCard(b) } }
            let evo = vm.beliefs?.evolutions ?? []
            if !evo.isEmpty { sectionLabel("HOW BELIEFS EVOLVED"); ForEach(Array(evo.enumerated()), id: \.offset) { _, e in evolutionCard(e) } }
        }
    }

    // Scaffold: header + loading/failed/empty/content per tab.
    @ViewBuilder private func detailScaffold<C: View>(_ state: ExplainViewModel.LoadState, retry tab: ExTab,
        header: String, subtitle: String, isEmpty: Bool, emptyText: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            tabHeader(header, subtitle)
            switch state {
            case .idle, .loading: loadingBlock("Reading your whole story…")
            case .failed(let m):  failedBlock(m) { Task { await vm.retry(tab, auth: auth) } }
            case .loaded:         if isEmpty { emptyPanel(emptyText) } else { content() }
            }
        }
    }
    private func emptyPanel(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(WT.ink.opacity(0.25))
            Text(text).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.5)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }
    private func calloutRow(_ c: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(WV.teal).padding(.top, 1)
            Text(c).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    // New DTO card renderers (identity + beliefs)
    private func stateCard(_ s: ExIdentityStateDTO) -> some View {
        cardShell {
            HStack {
                Text(orDash(s.stateLabel)).font(.serif(19)).foregroundStyle(WT.ink)
                Spacer()
                if s.stillActive == true { tag("Active") }
            }
            let range = [s.startDate, s.endDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
            if !range.isEmpty { Text(range).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)) }
            if let d = s.description, !d.isEmpty { Text(d).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
            let traits = safeArr(s.dominantTraits); if !traits.isEmpty { chipRow("Traits", traits.map(pretty), tone: WV.teal) }
            let emos = safeArr(s.dominantEmotions); if !emos.isEmpty { chipRow("Emotions", emos.map(pretty), tone: WV.gold) }
            let bels = safeArr(s.dominantBeliefs); if !bels.isEmpty { chipRow("Beliefs", bels.map(pretty), tone: Color(hex: 0x6b5b95)) }
        }
    }
    private func transitionCard(_ t: ExTransitionDTO) -> some View {
        cardShell {
            HStack(spacing: 8) {
                Text(orDash(t.fromState)).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.7))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WV.gold)
                Text(orDash(t.toState)).font(.serif(16)).foregroundStyle(WT.ink)
                Spacer()
            }
            if let s = t.summary, !s.isEmpty { Text(s).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }
            if let e = t.emotionalCost, !e.isEmpty { meta("Emotional cost", e) }
        }
    }
    private func beliefCard(_ b: ExBeliefDTO) -> some View {
        cardShell {
            Text("“\(orDash(b.beliefStatement))”").font(.serif(17)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            if let t = b.beliefType, !t.isEmpty { Text(pretty(t)).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)) }
        }
    }
    private func evolutionCard(_ e: ExBeliefEvolutionDTO) -> some View {
        cardShell {
            truthBlock("From", orDash(e.fromBelief), tone: WT.ink.opacity(0.4))
            truthBlock("To", orDash(e.toBelief), tone: WV.teal)
            if let r = e.changeReason, !r.isEmpty { whyBlock("What changed it", r) }
        }
    }
```
Plus a small addition to the existing `contradictionCard` for the `internal_conflict` source:
```diff
             if let b = c.sideB, !b.isEmpty { truthBlock("Another truth", b, tone: WV.gold) }
+            if let ea = c.emotionA, let eb = c.emotionB, !ea.isEmpty, !eb.isEmpty {
+                meta("Tension", "\(pretty(ea)) vs \(pretty(eb))")
+            }
             if let w = c.whyBothAreTrue, !w.isEmpty { whyBlock("Why both are true", w) }
```
(`placeholderTab` becomes unused after this — remove it.)

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: live round-trips for all 6 detail endpoints (real arrays, the
list-wrapper shape, heterogeneous pattern_type/source variants, null-heavy fields, empty→"nothing yet") are a
device/backend check. All 7 tabs then real, lazy, cached. No git.
