import SwiftUI

// MARK: - Timeline — "A Life Arranged Across Time". Two modes (Narrative / Pattern),
// six filters, search. Data: GET /api/v1/timeline/visual (events, sample here);
// Pattern rails: GET /timeline/{category} (live from your local anchors).
struct TimelineView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var anchorStore = AnchorStore()
    @AppStorage(Profile.birthdateKey) private var birthdateISO: String = ""

    enum Mode: String, CaseIterable { case narrative = "Narrative", pattern = "Pattern" }
    @State private var mode: Mode = .narrative
    @State private var filter: TLFilter = .all
    @State private var searchText = ""
    @State private var expandedID: String?
    @State private var showRecord = false

    private let events = TimelineEvent.samples

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock
                    ModePill(selection: $mode)
                    searchBar
                    filterChips
                    if mode == .narrative { narrative } else { pattern }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
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

    // MARK: Filtering
    private var filtered: [TimelineEvent] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return events.filter { e in
            guard filter.matches(e, birthYear: birthYear) else { return false }
            guard !q.isEmpty else { return true }
            let hay = (e.title + " " + e.snippet + " " + e.location + " " + e.people.joined(separator: " ")).lowercased()
            return hay.contains(q)
        }
    }
    private var birthYear: Int? {
        guard let d = SettingsView.date(fromISO: birthdateISO) else { return nil }
        return Calendar.current.component(.year, from: d)
    }

    // MARK: Narrative mode
    private var narrative: some View {
        let groups = Dictionary(grouping: filtered, by: { $0.year }).sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 18) {
            if filtered.isEmpty {
                emptyState
            } else {
                todayMarker
                ForEach(groups, id: \.key) { year, evs in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(year)).font(.serif(22)).foregroundStyle(WV.teal)
                        ForEach(evs.sorted { ($0.month ?? 0) > ($1.month ?? 0) }) { e in eventCard(e) }
                    }
                }
            }
        }
    }

    private var todayMarker: some View {
        HStack(spacing: 8) {
            Circle().fill(WV.gold).frame(width: 8, height: 8)
            Text("Today").font(.system(size: 13, weight: .semibold)).foregroundStyle(WV.gold)
            Rectangle().fill(WT.ink.opacity(0.1)).frame(height: 1)
        }
    }

    private func eventCard(_ e: TimelineEvent) -> some View {
        let expanded = expandedID == e.id
        return Button { withAnimation(.easeOut(duration: 0.2)) { expandedID = expanded ? nil : e.id } } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Circle().fill(WV.teal).frame(width: 11, height: 11)
                    Rectangle().fill(WT.ink.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
                }
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(e.dateText).font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.45))
                        Spacer()
                        if e.isHigh { significanceTag(e) }
                    }
                    Text(e.title).font(.serif(19)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    Text(e.snippet).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.65)).lineSpacing(3)
                        .lineLimit(expanded ? nil : 2).fixedSize(horizontal: false, vertical: true)
                    if !expanded && e.snippet.count > 90 {
                        Text("Click to read narrative").font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
                    }
                    if expanded {
                        if !e.people.isEmpty || !e.location.isEmpty { metaRow(e) }
                        Button { /* TODO: open memory -> GET /api/v1/memories/\(e.memoryId ?? "") */ } label: {
                            HStack(spacing: 5) { Text("View memory").font(.system(size: 13, weight: .medium)); Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
                                .foregroundStyle(WV.teal)
                        }
                        .buttonStyle(.plain).padding(.top, 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private func significanceTag(_ e: TimelineEvent) -> some View {
        Text(e.significance.isEmpty ? "Significant" : e.significance)
            .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(WV.gold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(WV.gold.opacity(0.12), in: Capsule())
    }

    private func metaRow(_ e: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !e.location.isEmpty {
                HStack(spacing: 6) { Image(systemName: "mappin.and.ellipse").font(.system(size: 12)).foregroundStyle(WV.teal)
                    Text(e.location).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.65)) }
            }
            if !e.people.isEmpty {
                HStack(spacing: 6) {
                    ForEach(e.people, id: \.self) { p in
                        HStack(spacing: 4) { Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(WV.teal)
                            Text(p).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7)) }
                            .padding(.horizontal, 9).padding(.vertical, 5).background(WV.teal.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No timeline memories found").font(.serif(20)).foregroundStyle(WT.ink)
            Text("Try a different filter, or record a memory to begin your timeline.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }

    // MARK: Pattern mode — Life Anchor Rails (from your local anchors)
    private var pattern: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIFE ANCHOR RAILS").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Text("The facts running alongside your story.").font(.serif(20)).foregroundStyle(WT.ink)
            }
            let rails = railCategories.filter { !anchorStore.records($0.id).isEmpty }
            if rails.isEmpty {
                railsEmpty
            } else {
                let span = lifeSpan(rails)
                axisRuler(span)
                ForEach(rails) { c in railRow(c, span: span) }
            }
        }
    }

    private var railCategories: [AnchorCategory] {
        ["relationships","locations","jobs","education","pets","service"].compactMap { id in AnchorCategory.all.first { $0.id == id } }
    }

    private func lifeSpan(_ cats: [AnchorCategory]) -> ClosedRange<Int> {
        var years: [Int] = events.map { $0.year }
        for c in cats {
            for r in anchorStore.records(c.id) {
                if let y = year(r.values["start_date"]) { years.append(y) }
                if let y = year(r.values["end_date"]) { years.append(y) }
            }
        }
        let lo = years.min() ?? 1980
        let hi = max(years.max() ?? Calendar.current.component(.year, from: Date()), Calendar.current.component(.year, from: Date()))
        return lo...(hi == lo ? lo + 1 : hi)
    }

    private func axisRuler(_ span: ClosedRange<Int>) -> some View {
        HStack {
            Text(String(span.lowerBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
            Spacer()
            Text(String(span.upperBound)).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.4))
        }
        .padding(.leading, 96)
    }

    private func railRow(_ c: AnchorCategory, span: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: c.icon).font(.system(size: 12)).foregroundStyle(c.tone)
                Text(c.singular).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
            }
            .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                let total = CGFloat(span.upperBound - span.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.06)).frame(height: 8).frame(maxHeight: .infinity, alignment: .center)
                    ForEach(anchorStore.records(c.id)) { r in
                        let s = year(r.values["start_date"]) ?? span.lowerBound
                        let e = year(r.values["end_date"]) ?? s
                        let x = CGFloat(s - span.lowerBound) / total * geo.size.width
                        let w = max(10, CGFloat(max(e, s) - s) / total * geo.size.width)
                        Capsule().fill(c.tone.opacity(0.85)).frame(width: w, height: 14)
                            .offset(x: min(x, geo.size.width - 10))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 28)
        }
        .padding(.vertical, 4)
    }

    private var railsEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "ruler").font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No anchors yet").font(.serif(18)).foregroundStyle(WT.ink)
            Text("Add anchors (people, places, jobs…) and they'll appear here as the rails your story runs along.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.top, 24)
    }

    private func year(_ iso: String?) -> Int? {
        guard let iso, let d = SettingsView.date(fromISO: iso) else { return nil }
        return Calendar.current.component(.year, from: d)
    }
}

// MARK: - Filters
enum TLFilter: String, CaseIterable {
    case all, high, people, places, childhood, recent
    var label: String {
        switch self {
        case .all: return "All"; case .high: return "Significant"; case .people: return "People"
        case .places: return "Places"; case .childhood: return "Childhood"; case .recent: return "Recent"
        }
    }
    func matches(_ e: TimelineEvent, birthYear: Int?) -> Bool {
        let nowYear = Calendar.current.component(.year, from: Date())
        switch self {
        case .all:       return true
        case .high:      return e.isHigh
        case .people:    return !e.people.isEmpty
        case .places:    return !e.location.isEmpty
        case .childhood: if let b = birthYear { return e.year <= b + 18 } else { return e.year <= 1995 }
        case .recent:    return e.year >= nowYear - 5
        }
    }
}

// MARK: - Event model + sample data
struct TimelineEvent: Identifiable {
    let id = UUID().uuidString
    let year: Int
    let month: Int?
    let title: String
    let snippet: String
    let location: String
    let people: [String]
    let significance: String
    let score: Double
    let memoryId: String?

    var isHigh: Bool { score >= 0.75 || significance.lowercased() == "critical" }
    var dateText: String {
        guard let m = month, m >= 1, m <= 12 else { return String(year) }
        let f = DateFormatter(); return "\(f.shortMonthSymbols[m-1]) \(year)"
    }

    static let samples: [TimelineEvent] = [
        .init(year: 1980, month: 4, title: "A first home", snippet: "Sample event — the earliest place that anchored everything that came after. Your own memories fill this space once recording is wired, in your own words and your own voice.", location: "A small town", people: [], significance: "Foundational", score: 0.9, memoryId: nil),
        .init(year: 1992, month: 6, title: "Graduation", snippet: "Sample event marking the end of one chapter and the start of another — shown here so you can see how a milestone reads on the timeline.", location: "A school", people: ["A mentor"], significance: "High", score: 0.82, memoryId: nil),
        .init(year: 1998, month: 9, title: "Starting out", snippet: "Sample event — a first job and the beginning of a working life.", location: "A city", people: [], significance: "", score: 0.55, memoryId: nil),
        .init(year: 2005, month: 3, title: "A big move", snippet: "Sample event — packing up and starting over somewhere new.", location: "A new city", people: ["A friend"], significance: "", score: 0.7, memoryId: nil),
        .init(year: 2012, month: 7, title: "A new chapter", snippet: "Sample event — a turning point that reshaped the years that followed, shown so you can see how the timeline holds the weight of a moment like this.", location: "", people: ["A loved one"], significance: "Critical", score: 0.95, memoryId: nil),
        .init(year: 2020, month: 11, title: "Looking back", snippet: "Sample event — a quiet, reflective moment.", location: "", people: [], significance: "", score: 0.4, memoryId: nil),
        .init(year: 2024, month: 5, title: "A recent day", snippet: "Sample event from recent years, near the present end of your timeline.", location: "Home", people: [], significance: "", score: 0.6, memoryId: nil),
    ]
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
