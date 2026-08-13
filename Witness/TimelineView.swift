import SwiftUI

// MARK: - Timeline — "A Life Arranged Across Time". Two modes (Narrative / Pattern), client-side filters,
// search. Data: GET /timeline/visual (year-grouped events; bare path; N+1 → spinner). Narrative renders the
// years/events; Pattern derives rails from the REAL memory events' people/location/significance. Filters are
// memory-only by nature (anchors & milestones don't carry those fields — never faked into a match).
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
                if mode == .narrative {
                    searchBar
                    filterChips
                    narrative
                } else {
                    pattern
                }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    // MARK: Nav + header
    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            Button { showRecord = true } label: {
                HStack(spacing: 5) { Image(systemName: "plus"); Text("Memory").font(.system(size: 14, weight: .medium)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }
            .witnessPress()
            .witnessHint("Record a new memory — it joins your timeline.")
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A LIFE ARRANGED ACROSS TIME").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            Text("Timeline").font(.serif(28)).foregroundStyle(WT.ink)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.4))
            TextField("Search Timeline", text: $searchText).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TLFilter.allCases, id: \.self) { fl in
                    let sel = fl == filter
                    Text(fl.label)
                        .font(.system(size: 14, weight: sel ? .semibold : .regular))
                        .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(sel ? WV.teal : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(sel ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { filter = fl } }
                }
            }
        }
    }

    // MARK: Filtering (client-side; memory-only filters never match anchors/milestones — no faking)
    private func matches(_ e: TimelineEventDTO) -> Bool {
        guard filter.matches(e) else { return false }
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = ([e.title, e.subtitle, e.snippet, e.location] + (e.people ?? []))
            .compactMap { $0 }.joined(separator: " ").lowercased()
        return hay.contains(q)
    }
    private var visibleYears: [(year: TimelineYear, events: [TimelineEventDTO])] {
        vm.years.compactMap { y in
            let evs = (y.events ?? []).filter(matches)
            return evs.isEmpty ? nil : (y, evs)
        }
    }

    // MARK: Narrative mode
    @ViewBuilder private var narrative: some View {
        let groups = visibleYears
        if groups.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                if filter != .all { filterFootnote }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(String(g.year.year ?? 0)).font(.serif(22)).foregroundStyle(WV.teal)
                            if let a = g.year.age { Text("Age \(a)").font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.4)) }
                        }
                        ForEach(Array(g.events.enumerated()), id: \.offset) { _, e in eventCard(e) }
                    }
                }
            }
        }
    }

    // A timeline node (colored dot + connecting line) beside a typed card.
    private func eventCard(_ e: TimelineEventDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(nodeColor(e)).frame(width: 11, height: 11)
                Rectangle().fill(WT.ink.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
            }
            .padding(.top, 4)
            typedCard(e)
        }
    }
    private func nodeColor(_ e: TimelineEventDTO) -> Color {
        switch (e.type ?? "") {
        case "memory": return WV.teal
        case "anchor": return anchorStyle(e).tone
        default:       return WV.gold        // milestone / birth
        }
    }

    @ViewBuilder private func typedCard(_ e: TimelineEventDTO) -> some View {
        switch (e.type ?? "") {
        case "memory": memoryCard(e)
        case "anchor": anchorCard(e)
        default:       milestoneCard(e)
        }
    }

    // MARK: memory event — expandable; "View memory" → real detail (when memory_id present)
    private func memoryCard(_ e: TimelineEventDTO) -> some View {
        let k = key(e)
        let expanded = expandedID == k
        let people = e.people ?? []
        let hasMeta = !people.isEmpty || !(e.location ?? "").isEmpty
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(dateText(e)).font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.45))
                Spacer()
                if (e.significance ?? "") == "critical" { criticalTag }
            }
            Text(e.title ?? "Untitled memory").font(.serif(19)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            if let s = e.snippet, !s.isEmpty {
                Text(s).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.65)).lineSpacing(3)
                    .lineLimit(expanded ? nil : 2).fixedSize(horizontal: false, vertical: true)
                if !expanded && s.count > 90 {
                    Text("Tap to read more").font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
                }
            }
            if expanded && hasMeta { metaRow(e) }
            if expanded, let mid = e.memoryId, !mid.isEmpty {
                NavigationLink {
                    MemoryDetailView(listItem: MemoryDTO(id: mid, title: e.title, exactDate: e.date), auth: auth)
                } label: {
                    HStack(spacing: 5) { Text("View memory").font(.system(size: 13, weight: .medium)); Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
                        .foregroundStyle(WV.teal)
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { expandedID = expanded ? nil : k } }
    }

    private var criticalTag: some View {
        Text("Critical")
            .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(WV.gold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(WV.gold.opacity(0.12), in: Capsule())
    }

    private func metaRow(_ e: TimelineEventDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loc = e.location, !loc.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12)).foregroundStyle(WV.teal)
                    Text(loc).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.65))
                }
            }
            let people = e.people ?? []
            if !people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(people, id: \.self) { p in
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(WV.teal)
                                Text(p).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5).background(WV.teal.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: anchor event — factual (location / job / education), category-styled, not tappable
    private func anchorCard(_ e: TimelineEventDTO) -> some View {
        let st = anchorStyle(e)
        return HStack(alignment: .top, spacing: 12) {
            ZStack { Circle().fill(st.tone.opacity(0.12)); Image(systemName: st.icon).font(.system(size: 15, weight: .medium)).foregroundStyle(st.tone) }
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(dateText(e)).font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.4))
                Text(e.title ?? "—").font(.serif(17)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                if let sub = e.subtitle, !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }

    // Lenient category → icon/tone (only location/job/education anchors appear).
    private func anchorStyle(_ e: TimelineEventDTO) -> (icon: String, tone: Color) {
        let c = (e.category ?? e.type ?? "").lowercased()
        if c.contains("job") || c.contains("employ") || c.contains("work") { return ("briefcase", WV.teal) }
        if c.contains("educat") || c.contains("school") || c.contains("degree") { return ("graduationcap", WV.gold) }
        if c.contains("locat") || c.contains("place") || c.contains("home") || c.contains("address") { return ("mappin.and.ellipse", WV.teal) }
        return ("smallcircle.filled.circle", WT.ink.opacity(0.5))
    }

    // MARK: milestone event — birth / life marker, gold accent
    private func milestoneCard(_ e: TimelineEventDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack { Circle().fill(WV.gold.opacity(0.14)); Image(systemName: "flag.checkered").font(.system(size: 15, weight: .medium)).foregroundStyle(WV.gold) }
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(dateText(e)).font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.4))
                Text(e.title ?? "—").font(.serif(17)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                if let sub = e.subtitle, !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WV.gold.opacity(0.18), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }

    // MARK: Pattern mode — three rails bound to the REAL memory events (people / places / significance)
    @ViewBuilder private var pattern: some View {
        let span = yearSpan()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PATTERNS ACROSS TIME").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Text("When people, places, and defining moments cluster in your life.").font(.serif(20)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let span {
                axisRuler(span)
                dimensionRail("People", tone: WV.teal, span: span) { !($0.people ?? []).isEmpty }
                dimensionRail("Places", tone: WV.gold, span: span) { !($0.location ?? "").isEmpty }
                dimensionRail("Significant", tone: WV.danger, span: span) { ($0.significance ?? "") == "critical" }
                filterFootnote
            } else {
                patternEmpty
            }
        }
    }

    private func yearSpan() -> ClosedRange<Int>? {
        let ys = vm.years.compactMap { $0.year }
        guard let lo = ys.min(), let hi = ys.max() else { return nil }
        return lo...(hi == lo ? lo + 1 : hi)
    }

    private func dimensionRail(_ label: String, tone: Color, span: ClosedRange<Int>, _ predicate: @escaping (TimelineEventDTO) -> Bool) -> some View {
        // Years (from the loaded set) containing ≥1 memory event that matches this dimension.
        let hitYears = vm.years.filter { ($0.events ?? []).contains(where: predicate) }.compactMap { $0.year }.sorted()
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7)).frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                let total = CGFloat(max(1, span.upperBound - span.lowerBound))
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.06)).frame(height: 6).frame(maxHeight: .infinity, alignment: .center)
                    if hitYears.isEmpty {
                        Text("none").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.3)).padding(.leading, 4).frame(maxHeight: .infinity, alignment: .center)
                    } else {
                        ForEach(hitYears, id: \.self) { y in
                            Circle().fill(tone).frame(width: 10, height: 10)
                                .offset(x: min(CGFloat(y - span.lowerBound) / total * geo.size.width, geo.size.width - 10))
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 2)
    }

    private func axisRuler(_ span: ClosedRange<Int>) -> some View {
        HStack {
            Text(String(span.lowerBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
            Spacer()
            Text(String(span.upperBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
        }
        .padding(.leading, 92)
    }

    // MARK: States + footnote
    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(WV.teal)
            Text("Arranging your life across time…").font(.serif(18)).foregroundStyle(WT.ink.opacity(0.7))
            Text("This can take a moment for a full life.").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.45))
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    private func failedState(_ m: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(WV.danger.opacity(0.8))
            Text(m).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.7)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth) } } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)); Text("Try again").font(.system(size: 15, weight: .medium)) }.foregroundStyle(WV.teal)
            }.witnessPress()
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text(filter == .all && searchText.isEmpty ? "No timeline yet" : "Nothing matches").font(.serif(20)).foregroundStyle(WT.ink)
            Text(filter == .all && searchText.isEmpty
                 ? "Record a memory and it will take its place here, arranged across the years of your life."
                 : "Try a different filter or clear your search.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }
    private var patternEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.dots.scatter").font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
            Text("Not enough yet").font(.serif(18)).foregroundStyle(WT.ink)
            Text("As you record more memories, the people, places, and defining moments in them will show up here as rails across your years.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.top, 24)
    }
    private var filterFootnote: some View {
        Text("Filters and rails reflect memory events — anchors and milestones don’t carry people, places, or significance, so they don’t appear under these.")
            .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: helpers
    private func key(_ e: TimelineEventDTO) -> String {
        e.id ?? e.memoryId ?? "\(e.title ?? "")-\(e.year ?? 0)"
    }
    private func dateText(_ e: TimelineEventDTO) -> String {
        if let d = e.date, !d.isEmpty { return d }
        if let y = e.year { return String(y) }
        return ""
    }
}

// MARK: - Filters — memory-only by nature (anchors/milestones lack the fields → never matched)
enum TLFilter: String, CaseIterable {
    case all, people, places, significant
    var label: String {
        switch self {
        case .all: return "All"; case .people: return "People"; case .places: return "Places"; case .significant: return "Significant"
        }
    }
    func matches(_ e: TimelineEventDTO) -> Bool {
        switch self {
        case .all:         return true
        case .people:      return !(e.people ?? []).isEmpty
        case .places:      return !(e.location ?? "").isEmpty
        case .significant: return (e.significance ?? "") == "critical"
        }
    }
}

// MARK: - Mode toggle
private struct ModePill: View {
    @Binding var selection: TimelineView.Mode
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimelineView.Mode.allCases, id: \.self) { m in
                let sel = m == selection
                Text(m.rawValue)
                    .font(.system(size: 15, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Group { if sel { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WV.teal).matchedGeometryEffect(id: "tl_mode", in: ns) } })
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = m } }
            }
        }
        .padding(4).background(WT.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
    }
}
