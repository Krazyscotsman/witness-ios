# Witness — Explain Me → real backend, PASS A (Overview + VM + helpers) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Pass A of two (spec §8). Read-only.
Field names are authoritative from `Witness_Explain_Me_Spec.md` §3.

## Read-first (ExplainView + ExplainSample)
- Nested `ExTab` enum + chip tabBar + ScrollView switch. Constructed `ExplainView()` in InsightsView (has auth).
- Overview: headline hero + 4 preview sections via forceCard/patternCard/breakingCard/contradictionCard(.prefix).
- 6 detail tabs render lists via those card renderers + stateCard/transitionCard/beliefCard/evolutionCard.
- Shared blocks: tabHeader/sectionLabel/sublabel/meta/chipRow/whyBlock/strengthBadge/cardShell/truthBlock/beforeAfter.
- All data from hardcoded ExplainSample (+ Ex* structs, ExConfidence).

## Decisions (baked in; change any)
1. Decode via `.convertFromSnakeCase` (reuse the APIClient `decoder:` param) → clean camelCase DTOs, no CodingKeys.
2. Drop `confidence` from DTOs + remove confidenceBadge (spec: don't build UI on confidence).
3. All descriptive fields optional; arrays `[String]?` → defensive `safeArr` at render; prettify via AnchorText.titleCase.
4. Overview timeout 30s (slow Gemini). 401→refresh→retry.
5. Pass A: Overview rendered from real data; the other 6 tabs show a neutral "coming together" placeholder
   (Pass B wires their fetch + rendering). Drop the "Read"/tts TODO button (out of scope).

---

## APIModels.swift — Overview + 4 preview element DTOs (append)
```swift
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
    let activeStrength: String?          // high/medium/low
    let affectedDomains: [String]?
    let downstreamEffects: [String]?
    let beforeSelf: String?
    let afterSelf: String?
    let identityImpact: String?
    let decisionWeight: String?          // life_altering/high/moderate/low
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
```

## New file: ExplainViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class ExplainViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    // Overview (Pass A). Pass B adds: forces/patterns/breaking/contradictions/identity/beliefs states + caches.
    @Published private(set) var overviewState: LoadState = .idle
    @Published private(set) var overview: ExplainOverview?

    private static let snake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
    private enum SessionError: Error { case sessionEnded }

    func loadOverview(auth: AuthManager) async {
        if overviewState == .loading || overviewState == .loaded { return }
        overviewState = .loading
        do {
            overview = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/explain-me/overview", timeout: 30, decoder: Self.snake, as: ExplainOverview.self)
            }
            overviewState = .loaded
        } catch SessionError.sessionEnded {
            overviewState = .failed("Your session has ended. Please sign in again.")
        } catch {
            overviewState = .failed("We couldn’t load this yet. Check your connection and try again.")
        }
    }
    func retryOverview(auth: AuthManager) async { overviewState = .idle; await loadOverview(auth: auth) }

    // 401 → refresh → retry-once
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
```

## ExplainView.swift — FULL rewrite (Pass A). Overview real; 6 tabs placeholder; sample data removed.
```swift
import SwiftUI

struct ExplainView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ExplainViewModel()
    @State private var tab: ExTab = .overview

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
                        default:              placeholderTab(tab.label)   // Pass B fills the six
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 110)
                    .id(tab)
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadOverview(auth: auth) }
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

    // MARK: Overview (real data)
    @ViewBuilder private var overviewTab: some View {
        switch vm.overviewState {
        case .idle, .loading: loadingBlock("Reading your whole story…")
        case .failed(let m):  failedBlock(m) { Task { await vm.retryOverview(auth: auth) } }
        case .loaded:         loadedOverview(vm.overview)
        }
    }

    @ViewBuilder private func loadedOverview(_ ov: ExplainOverview?) -> some View {
        let da = ov?.dataAvailable
        let sm = ov?.summary
        let enough = (da?.hasEnoughData ?? true)
        let headline = (sm?.headline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let anyPreview = !safeCards(sm?.coreForces).isEmpty || !safeCards(sm?.topPatterns).isEmpty
            || !safeCards(sm?.topBreakingPoints).isEmpty || !safeCards(sm?.topContradictions).isEmpty

        if !enough || (headline.isEmpty && !anyPreview && (da == nil)) {
            notEnoughBlock
        } else {
            VStack(alignment: .leading, spacing: 22) {
                if !headline.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THE SYNTHESIS").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                        Text(headline).font(.serif(25)).foregroundStyle(WT.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                statGrid(da)   // TRUE totals from data_available.*_count
                if let f = sm?.coreForces, !f.isEmpty {
                    overviewSection("ACTIVE FORCES") { ForEach(Array(f.enumerated()), id: \.offset) { _, x in forceCard(x) } }
                }
                if let p = sm?.topPatterns, !p.isEmpty {
                    overviewSection("PATTERNS OF A LIFE") { ForEach(Array(p.enumerated()), id: \.offset) { _, x in patternCard(x) } }
                }
                if let b = sm?.topBreakingPoints, !b.isEmpty {
                    overviewSection("BREAKING POINTS") { ForEach(Array(b.enumerated()), id: \.offset) { _, x in breakingCard(x) } }
                }
                if let c = sm?.topContradictions, !c.isEmpty {
                    overviewSection("CONTRADICTIONS PRESERVED") { ForEach(Array(c.enumerated()), id: \.offset) { _, x in contradictionCard(x) } }
                }
            }
        }
    }
    private func safeCards<T>(_ a: [T]?) -> [T] { a ?? [] }
    private func overviewSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { sectionLabel(title); content() }
    }

    private func statGrid(_ da: ExplainOverview.DataAvailable?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { statCard(da?.forcesCount, "Forces"); statCard(da?.patternsCount, "Patterns") }
            HStack(spacing: 10) { statCard(da?.breakingPointsCount, "Breaking points"); statCard(da?.contradictionsCount, "Contradictions") }
        }
    }
    private func statCard(_ n: Int?, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(n ?? 0)").font(.serif(26)).foregroundStyle(WV.teal)
            Text(label).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // MARK: DTO card renderers (reused by Pass B's list tabs)
    private func forceCard(_ f: ExForceDTO) -> some View {
        cardShell {
            HStack {
                Text(orDash(f.title)).font(.serif(20)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if f.activeToday == true, let s = f.activeStrength, !s.isEmpty { strengthBadge(pretty(s)) }
            }
            if let o = f.originEventTitle, !o.isEmpty { meta("Origin", o) }
            else if let d = f.originDate, !d.isEmpty { meta("Origin", d) }
            let domains = safeArr(f.affectedDomains)
            if !domains.isEmpty { chipRow("Affected domains", domains.map(pretty), tone: WV.teal) }
            let effects = safeArr(f.downstreamEffects)
            if !effects.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sublabel("Downstream effects")
                    ForEach(Array(effects.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .top, spacing: 7) { Circle().fill(WV.gold).frame(width: 5, height: 5).padding(.top, 7)
                            Text(e).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            if let bs = f.beforeSelf, let asf = f.afterSelf, !bs.isEmpty || !asf.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    beforeAfter("Who I was", bs); Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)).padding(.top, 22); beforeAfter("Who I became", asf)
                }
            }
            if let i = f.identityImpact, !i.isEmpty { whyBlock("Why this matters", i) }
        }
    }

    private func patternCard(_ p: ExPatternDTO) -> some View {
        cardShell {
            Text(orDash(p.title)).font(.serif(19)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            if let d = p.description, !d.isEmpty { Text(d).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                if let n = p.occurrenceCount, n > 0 { tag("Observed \(n)×") }
                if let r = p.resolvedCount, let u = p.unresolvedCount { tag("\(r) resolved · \(u) open") }
                if let a = p.stillActiveCount { tag("\(a) still active") }
            }
        }
    }

    private func breakingCard(_ b: ExBreakingDTO) -> some View {
        cardShell {
            if let d = b.dateLabel, !d.isEmpty { Text(d.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WV.gold) }
            Text(orDash(b.title)).font(.serif(20)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            if let s = b.summary, !s.isEmpty { Text(s).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
            if let w = b.whyItMattered, !w.isEmpty { whyBlock("Why it mattered", w) }
            if let bs = b.beforeSelf, let asf = b.afterSelf, !bs.isEmpty || !asf.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    beforeAfter("Who I was before", bs); Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)).padding(.top, 22); beforeAfter("Who I became", asf)
                }
            }
            let quotes = safeArr(b.evidenceQuotes)
            if !quotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sublabel("In your words")
                    ForEach(Array(quotes.enumerated()), id: \.offset) { _, q in
                        Text("“\(q)”").font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func contradictionCard(_ c: ExContradictionDTO) -> some View {
        cardShell {
            if let s = c.source, !s.isEmpty { HStack { Spacer(); tag(pretty(s)) } }
            if let a = c.sideA, !a.isEmpty { truthBlock("One truth", a, tone: WV.teal) }
            HStack(spacing: 8) { Rectangle().fill(WT.ink.opacity(0.1)).frame(height: 1); Text("and yet").font(.serif(13)).italic().foregroundStyle(WT.ink.opacity(0.45)); Rectangle().fill(WT.ink.opacity(0.1)).frame(height: 1) }
            if let b = c.sideB, !b.isEmpty { truthBlock("Another truth", b, tone: WV.gold) }
            if let w = c.whyBothAreTrue, !w.isEmpty { whyBlock("Why both are true", w) }
        }
    }

    // MARK: States
    private func loadingBlock(_ text: String) -> some View {
        VStack(spacing: 14) { ProgressView().tint(WV.teal); Text(text).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)) }
            .frame(maxWidth: .infinity).padding(.top, 60)
    }
    private func failedBlock(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.3))
            Text(message).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: retry) { Text("Try again").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 24).frame(height: 48).background(WV.teal, in: RoundedRectangle(cornerRadius: 14)) }.witnessPress()
        }.frame(maxWidth: .infinity).padding(.top, 50).padding(.horizontal, 20)
    }
    private var notEnoughBlock: some View {
        VStack(spacing: 12) {
            CompassMark(color: WV.gold).frame(width: 40, height: 40)
            Text("Your synthesis is still forming").font(.serif(22)).foregroundStyle(WV.teal)
            Text("As you record more memories, the forces, patterns, and turning points that shape you will gather here.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }.frame(maxWidth: .infinity).padding(.top, 40)
    }
    private func placeholderTab(_ title: String) -> some View {
        VStack(spacing: 12) { ProgressView().tint(WV.teal); Text("\(title) is coming together…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)) }
            .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: Defensive helpers (mirror web safeArr/pretty)
    private func safeArr(_ a: [String]?) -> [String] { a ?? [] }
    private func pretty(_ s: String?) -> String { AnchorText.titleCase(s) }
    private func orDash(_ s: String?) -> String { let t = (s ?? "").trimmingCharacters(in: .whitespaces); return t.isEmpty ? "—" : t }

    // MARK: Shared building blocks (carried over unchanged, minus confidenceBadge)
    private func tabHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.serif(26)).foregroundStyle(WT.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 2)
    }
    private func sectionLabel(_ s: String) -> some View { Text(s).font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45)) }
    private func sublabel(_ s: String) -> some View { Text(s.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WT.ink.opacity(0.4)) }
    private func meta(_ label: String, _ value: String) -> some View { HStack(spacing: 6) { sublabel(label); Text(value).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.7)) } }
    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
            .padding(.horizontal, 9).padding(.vertical, 5).background(WV.teal.opacity(0.1), in: Capsule())
    }
    private func chipRow(_ label: String, _ items: [String], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sublabel(label)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Text(it).font(.system(size: 12, weight: .medium)).foregroundStyle(tone).padding(.horizontal, 10).padding(.vertical, 5).background(tone.opacity(0.1), in: Capsule())
                }
            }
        }
    }
    private func whyBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { sublabel(label); Text(text).font(.serif(15)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(WV.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func strengthBadge(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(WV.teal).padding(.horizontal, 9).padding(.vertical, 4).background(WV.teal.opacity(0.12), in: Capsule())
    }
    private func beforeAfter(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { sublabel(label); Text(text.isEmpty ? "—" : text).font(.serif(15)).foregroundStyle(WT.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func truthBlock(_ label: String, _ text: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(tone); Text(text).font(.serif(16)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(tone.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func cardShell<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
}
```
(REMOVED: `ExConfidence`, `confidenceBadge`, `ExplainSample`, and the 8 sample structs ExForce/ExBreaking/
ExPattern/ExContradiction/ExIdentityState/ExTransition/ExBelief/ExEvolution. `chipRow` now uses the existing
`FlowLayout` for safe wrapping. `tabHeader` kept for Pass B's detail tabs.)

## InsightsView.swift — pass auth
```diff
-                case "explain":  ExplainView()
+                case "explain":  ExplainView(auth: auth)
```

---

## After Pass A approval + apply
Build 0/0 + diagnostics. Then I propose **Pass B** (the six detail tabs: active-forces/patterns/breaking-points/
contradictions/identity/beliefs — their DTOs + list rendering + lazy per-tab load, reusing this VM + helpers).
Honest note: live overview round-trip (slow Gemini headline, real counts vs previews, null-heavy fields) is a
device/backend check. No git.
