# Witness — Timeline → GET /timeline/visual (year-grouped, client-side filters, Narrative + Pattern) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Read-only.
Endpoint: GET /timeline/visual — BARE path, Bearer, NO params (all filtering client-side). N+1 slow → spinner.

## Read-first
- InsightsView → `case "timeline": TimelineView()`. Shell: Narrative/Pattern ModePill, search, 6 TLFilter chips
  (all/high/people/places/childhood/recent), + Memory button.
- Narrative = hardcoded TimelineEvent.samples grouped by year; Pattern = "Life Anchor Rails" from the STALE
  local AnchorStore (UserDefaults). Memory-detail nav reachable via MemoryDetailView(listItem:auth:).
- Retire: TimelineEvent.samples, AnchorStore usage. TimelineView needs auth.

## Decisions (baked in; change any)
1. Pattern mode = 3 dimension rails (People/Places/Significant) across the min→max year axis, a mark per year
   with matching memory events (real endpoint has no entity spans → the old per-category span rails can't be
   rebuilt from it). Interpretation of "rails bound to memory-event people/location/significance."
2. Filters = All + People-Linked + Place-Linked + High-Significance (memory-only; never fake anchor/milestone
   matches). Keep client-side search. Drop childhood/recent.
3. Add shared MemoryDTO(id:title:exactDate:) init (Learn will reuse). Timeout 60s (N+1).

---

## APIModels.swift — DTOs + MemoryDTO init
```swift
nonisolated struct TimelineResponse: Decodable {
    let birthdate: String?
    let totalMemories: Int?
    let totalYears: Int?
    let years: [TimelineYear]?
    enum CodingKeys: String, CodingKey { case birthdate, totalMemories = "total_memories", totalYears = "total_years", years }
}
nonisolated struct TimelineYear: Decodable {
    let year: Int?
    let age: Int?
    let events: [TimelineEventDTO]?
}
// Union, branch on `type` (milestone/memory/anchor). The four enrichment fields are MEMORY-ONLY.
nonisolated struct TimelineEventDTO: Decodable {
    let id: String?
    let type: String?
    let category: String?
    let title: String?
    let subtitle: String?
    let date: String?
    let year: Int?
    let age: Int?
    let memoryId: String?
    let snippet: String?
    let people: [String]?
    let location: String?
    let importanceScore: Double?
    let significance: String?     // "critical" | null (binary)
    enum CodingKeys: String, CodingKey {
        case id, type, category, title, subtitle, date, year, age, snippet, people, location, significance
        case memoryId = "memory_id", importanceScore = "importance_score"
    }
}
```
```swift
extension MemoryDTO {   // build a light MemoryDTO from a timeline memory event → open real memory detail
    init(id: String, title: String?, exactDate: String?) {
        self.init(id: id, title: title, narrative: nil, narrativeSnippet: nil, exactDate: exactDate,
                  timeGranularity: nil, exactDateEstimated: nil, narratorAge: nil, qualityScore: nil,
                  importanceScore: nil, people: nil, location: nil, createdAt: nil, updatedAt: nil)
    }
}
```
(NOTE: if the Learn tab is later wired and also adds this init, keep ONE definition — this is the shared copy.)

## New file: TimelineViewModel.swift
```swift
import SwiftUI
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var years: [TimelineYear] = []
    @Published private(set) var birthdate: String?
    @Published private(set) var totalMemories = 0
    @Published private(set) var totalYears = 0

    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private enum SessionError: Error { case sessionEnded }

    func load(auth: AuthManager) async { if state == .loading || state == .loaded { return }; await fetch(auth: auth) }
    func refresh(auth: AuthManager) async { if state == .loading { return }; await fetch(auth: auth) }

    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            let r = try await withAuth(auth) {
                try await APIClient.shared.get("/timeline/visual", timeout: 60, decoder: Self.snake, as: TimelineResponse.self)
            }
            years = (r.years ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            birthdate = r.birthdate; totalMemories = r.totalMemories ?? 0; totalYears = r.totalYears ?? 0
            state = .loaded
        } catch SessionError.sessionEnded {
            state = .failed("Your session has ended. Please sign in again.")
        } catch {
            state = .failed("We couldn’t load your timeline. Check your connection and try again.")
        }
    }
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }
}
```

## TimelineView.swift — rewrite (keep ModePill; retire samples + AnchorStore)
```swift
struct TimelineView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = TimelineViewModel()

    enum Mode: String, CaseIterable { case narrative = "Narrative", pattern = "Pattern" }
    @State private var mode: Mode = .narrative
    @State private var filter: TLFilter = .all
    @State private var searchText = ""
    @State private var expandedID: String?
    @State private var showRecord = false

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: loadingState
                case .failed(let m):  failedState(m)
                case .loaded:         content
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(auth: auth) }
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                ModePill(selection: $mode)
                if mode == .narrative { searchBar; filterChips }
                if mode == .narrative { narrative } else { pattern }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    // MARK: Nav + header (unchanged design)
    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            Button { showRecord = true } label: {
                HStack(spacing: 5) { Image(systemName: "plus"); Text("Memory").font(.system(size: 14, weight: .medium)) }.foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress().witnessHint("Record a new memory — it joins your timeline.")
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A LIFE ARRANGED ACROSS TIME").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            Text("Timeline").font(.serif(28)).foregroundStyle(WT.ink)
        }
    }
    private var searchBar: some View { /* identical to the current search bar, bound to $searchText */ EmptyView() }
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TLFilter.allCases, id: \.self) { fl in
                    let sel = fl == filter
                    Text(fl.label).font(.system(size: 14, weight: sel ? .semibold : .regular))
                        .foregroundStyle(sel ? .white : WT.ink.opacity(0.6)).padding(.horizontal, 14).frame(height: 36)
                        .background(sel ? WV.teal : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(sel ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { filter = fl } }
                }
            }
        }
    }

    // MARK: Filtering (client-side; memory-only filters never match anchors/milestones)
    private func matches(_ e: TimelineEventDTO) -> Bool {
        guard filter.matches(e) else { return false }
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = ([e.title, e.subtitle, e.snippet, e.location] + (e.people ?? [])).compactMap { $0 }.joined(separator: " ").lowercased()
        return hay.contains(q)
    }
    private var visibleYears: [(year: TimelineYear, events: [TimelineEventDTO])] {
        vm.years.compactMap { y in
            let evs = (y.events ?? []).filter(matches)
            return evs.isEmpty ? nil : (y, evs)
        }
    }

    // MARK: Narrative
    @ViewBuilder private var narrative: some View {
        let groups = visibleYears
        if groups.isEmpty { emptyState }
        else {
            VStack(alignment: .leading, spacing: 18) {
                if filter == .all && searchText.isEmpty { footnote }   // memory-only-filters note when relevant
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(String(g.year.year ?? 0)).font(.serif(22)).foregroundStyle(WV.teal)
                            if let a = g.year.age { Text("Age \(a)").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)) }
                        }
                        ForEach(Array(g.events.enumerated()), id: \.offset) { _, e in eventCard(e) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func eventCard(_ e: TimelineEventDTO) -> some View {
        switch (e.type ?? "") {
        case "memory":   memoryEventCard(e)
        case "anchor":   anchorEventCard(e)
        default:         milestoneEventCard(e)   // milestone / birth
        }
    }
    // memory event — expandable; tap "View memory" → real detail (if memory_id)
    private func memoryEventCard(_ e: TimelineEventDTO) -> some View { /* date + significance tag + title + snippet
        + people/location chips; a "View memory" NavigationLink → MemoryDetailView(listItem: MemoryDTO(id: memoryId,
        title: title, exactDate: date), auth: auth) when memoryId present */ EmptyView() }
    private func anchorEventCard(_ e: TimelineEventDTO) -> some View { /* category-styled (location/job/education
        icon+tone), title + subtitle/date. Not tappable. */ EmptyView() }
    private func milestoneEventCard(_ e: TimelineEventDTO) -> some View { /* title + subtitle + date, gold accent */ EmptyView() }

    // MARK: Pattern — 3 dimension rails from the real memory events (AnchorStore retired)
    @ViewBuilder private var pattern: some View {
        let span = yearSpan()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PATTERNS ACROSS TIME").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Text("When people, places, and defining moments cluster in your life.").font(.serif(20)).foregroundStyle(WT.ink)
            }
            if span == nil { emptyState }
            else {
                axisRuler(span!)
                dimensionRail("People", tone: WV.teal, span: span!) { !($0.people ?? []).isEmpty }
                dimensionRail("Places", tone: WV.gold, span: span!) { ($0.location ?? "").isEmpty == false }
                dimensionRail("Significant", tone: WV.danger, span: span!) { ($0.significance ?? "") == "critical" }
                footnote
            }
        }
    }
    private func yearSpan() -> ClosedRange<Int>? {
        let ys = vm.years.compactMap { $0.year }
        guard let lo = ys.min(), let hi = ys.max() else { return nil }
        return lo...(hi == lo ? lo + 1 : hi)
    }
    private func dimensionRail(_ label: String, tone: Color, span: ClosedRange<Int>, _ predicate: (TimelineEventDTO) -> Bool) -> some View {
        // years (from vm.years) that contain ≥1 memory event matching the predicate
        let hitYears = Set(vm.years.filter { ($0.events ?? []).contains(where: predicate) }.compactMap { $0.year })
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7)).frame(width: 82, alignment: .leading)
            GeometryReader { geo in
                let total = CGFloat(span.upperBound - span.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.06)).frame(height: 6).frame(maxHeight: .infinity, alignment: .center)
                    ForEach(Array(hitYears).sorted(), id: \.self) { y in
                        Circle().fill(tone).frame(width: 10, height: 10)
                            .offset(x: min(CGFloat(y - span.lowerBound) / total * geo.size.width, geo.size.width - 10))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 24)
        }.padding(.vertical, 2)
    }
    private func axisRuler(_ span: ClosedRange<Int>) -> some View {
        HStack { Text(String(span.lowerBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4)); Spacer(); Text(String(span.upperBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4)) }
            .padding(.leading, 90)
    }

    // MARK: States + footnote
    private var loadingState: some View { /* spinner + "Arranging your life across time…" (N+1 is slow) */ EmptyView() }
    private func failedState(_ m: String) -> some View { /* icon + message + Try again → vm.refresh */ EmptyView() }
    private var emptyState: some View { /* clock icon + "No timeline yet" + record hint */ EmptyView() }
    private var footnote: some View {
        Text("Filters and rails reflect memory events — anchors and milestones don’t carry people, places, or significance.")
            .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
    }
}

// Filters — memory-only by nature (anchors/milestones lack the fields → never matched)
enum TLFilter: String, CaseIterable {
    case all, people, places, significant
    var label: String { switch self { case .all: return "All"; case .people: return "People"; case .places: return "Places"; case .significant: return "Significant" } }
    func matches(_ e: TimelineEventDTO) -> Bool {
        switch self {
        case .all:         return true
        case .people:      return !(e.people ?? []).isEmpty
        case .places:      return (e.location ?? "").isEmpty == false
        case .significant: return (e.significance ?? "") == "critical"
        }
    }
}

// ModePill kept as-is (unchanged from the current file).
```
(EmptyView() placeholders are ONLY to keep this doc short — the applied file writes out searchBar, the three
eventCard bodies (matching the current card design, with the memory card's `NavigationLink → MemoryDetailView`),
loading/failed/empty states, in full. Removed: `TimelineEvent`+`samples`, `AnchorStore`, `birthdateISO`,
childhood/recent filters, `year(_:)`/rail-span helpers tied to AnchorStore.)

## InsightsView.swift — pass auth
```diff
-                case "timeline": TimelineView()
+                case "timeline": TimelineView(auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live /timeline/visual round-trip (N+1 slow, real
year/event/age data, heterogeneous types, memory tap → /detail, sparse criticals) is a device/backend check.
Filters are memory-only by design (surfaced in a footnote, not hidden). No git.
