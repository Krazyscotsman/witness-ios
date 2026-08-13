import SwiftUI

// Shared nav bar (chevron back with a title + optional trailing action).
func anchorNavBar<Trailing: View>(title: String, onBack: @escaping () -> Void,
                                  @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
    HStack {
        Button(action: onBack) {
            HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text(title).font(.system(size: 16)) }
                .foregroundStyle(WV.teal).frame(height: 44)
        }.witnessPress()
        Spacer()
        trailing()
    }
    .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
}

// "Add New" icon (teal circle +) for the relationships create entries.
func anchorAddIcon() -> some View {
    Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 38, height: 38).background(WV.teal, in: Circle())
}

// MARK: - L1 — Categories dashboard
struct AnchorRegistryView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AnchorRegistryViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: loading
                case .failed(let m):  failed(m)
                case .loaded:         dashboard
                }
            }
            anchorNavBar(title: "Insights", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(auth: auth) }
    }

    private var dashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ANCHOR REGISTRY").font(.system(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(WV.gold)
                    Text("The facts your story stands on.").font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    Text("People, places, work, and milestones — kept factually true so memories never blur or drift.")
                        .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(AnchorCategory.all) { c in
                    NavigationLink { destination(for: c) } label: { tile(c) }.witnessPress()
                }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    @ViewBuilder private func destination(for c: AnchorCategory) -> some View {
        switch c.id {
        case "relationships": AnchorRelationshipsView(vm: vm, auth: auth, category: c)
        case "locations":  LocationListView(vm: vm, auth: auth)
        case "jobs":       AnchorRecordListView(title: c.label, category: c, rows: vm.jobs)
        case "education":  AnchorRecordListView(title: c.label, category: c, rows: vm.education)
        case "pets":       AnchorRecordListView(title: c.label, category: c, rows: vm.pets)
        case "hobbies":    AnchorRecordListView(title: c.label, category: c, rows: vm.hobbies)
        case "service":    AnchorRecordListView(title: c.label, category: c, rows: vm.service)
        default: EmptyView()
        }
    }

    private func tile(_ c: AnchorCategory) -> some View {
        let n = vm.count(c.id)
        return HStack(spacing: 14) {
            ZStack { Circle().fill(c.tone.opacity(0.12)); Image(systemName: c.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(c.tone) }
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.label).font(.serif(18)).foregroundStyle(WT.ink)
                Text("\(n) \(n == 1 ? "record" : "records")").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.05), radius: 9, y: 4)
    }

    private var loading: some View {
        VStack(spacing: 14) { ProgressView().tint(WV.teal); Text("Gathering your anchors…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)) }
    }
    private func failed(_ m: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(WT.ink.opacity(0.3))
            Text("Couldn’t load your anchors").font(.serif(22)).foregroundStyle(WV.teal)
            Text(m).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth) } } label: {
                Text("Try again").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 50).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }.witnessPress().padding(.top, 4)
        }.padding(28)
    }
}

// MARK: - L2 — Relationships subcategories
struct AnchorRelationshipsView: View {
    @ObservedObject var vm: AnchorRegistryViewModel
    @ObservedObject var auth: AuthManager
    let category: AnchorCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.label).font(.serif(26)).foregroundStyle(WT.ink)
                        Text("Separate people by factual relationship role, so names, dates, and roles stay true and never merge.")
                            .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    let critical = vm.criticalPeople
                    NavigationLink {
                        RelationshipListView(title: "Critical People", source: .critical, vm: vm, auth: auth)
                    } label: { criticalCard(count: critical.count) }.witnessPress(scale: 0.98)

                    let chips = vm.relationshipChips
                    if chips.isEmpty {
                        emptyState
                    } else {
                        ForEach(chips) { chip in
                            NavigationLink {
                                RelationshipListView(title: chip.title, source: .type(key: chip.id, display: chip.title), vm: vm, auth: auth)
                            } label: { chipRow(chip) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() }) {
                NavigationLink { RelationshipCreateView(prefillType: nil, vm: vm, auth: auth) } label: { anchorAddIcon() }
                    .witnessPress()
                    .witnessHint("Add a new person to your relationships.")
            }
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private func criticalCard(count: Int) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color.white.opacity(0.2)); Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(.white) }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Critical People").font(.serif(19)).foregroundStyle(.white)
                Text("\(count) \(count == 1 ? "person" : "people") everything else orbits.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x6b5b95), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color(hex: 0x6b5b95).opacity(0.3), radius: 12, y: 6)
    }
    private func chipRow(_ chip: AnchorRegistryViewModel.RelChip) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.12)); Image(systemName: "person.2.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(category.tone) }.frame(width: 44, height: 44)
            Text(chip.title).font(.serif(18)).foregroundStyle(WT.ink)
            Spacer(minLength: 4)
            Text("\(chip.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(category.tone)
                .frame(minWidth: 26, minHeight: 26).background(category.tone.opacity(0.12), in: Circle())
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No people yet.").font(.serif(20)).foregroundStyle(WT.ink)
            Text("As you share memories, the people in your life gather here.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }
}

// MARK: - L3 — Record list (generic; search + sort)
struct AnchorRecordListView<Row: AnchorRow>: View {
    let title: String
    let category: AnchorCategory
    let rows: [Row]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visible: [Row] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? rows : rows.filter { ($0.displayName + " " + $0.subtitle).lowercased().contains(q) }
        return filtered.sorted { $0.sortKey > $1.sortKey }   // start_date DESC else created_at
    }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.serif(26)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    searchBar
                    if visible.isEmpty { emptyState }
                    else {
                        ForEach(visible) { r in
                            NavigationLink { AnchorRecordDetailView(row: r, category: category) } label: { row(r) }.witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            anchorNavBar(title: "Anchors", onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.4))
            TextField("Search", text: $search).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).autocorrectionDisabled()
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 14).frame(height: 50).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
    private func row(_ r: Row) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.1)); Image(systemName: category.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(category.tone) }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.displayName).font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                if !r.subtitle.isEmpty { Text(r.subtitle).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: category.icon).font(.system(size: 28)).foregroundStyle(WT.ink.opacity(0.25))
            Text(search.isEmpty ? "Nothing here yet." : "No matches for “\(search)”.").font(.serif(20)).foregroundStyle(WT.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.top, 40)
    }
}

// MARK: - L4 — Record detail (READ-ONLY; Edit/Delete laid out but inert)
struct AnchorRecordDetailView<Row: AnchorRow>: View {
    let row: Row
    let category: AnchorCategory
    @Environment(\.dismiss) private var dismiss

    private var shown: [AnchorField] { row.detailFields.filter { ($0.value?.trimmingCharacters(in: .whitespaces).isEmpty == false) } }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text((row.typeLabel ?? category.singular).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(category.tone)
                        Text(row.displayName).font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    if shown.isEmpty {
                        Text("No details recorded yet.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                                if i > 0 { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }
                                fieldRow(f)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                    }
                    if let story = row.story {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR STORY").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
                            Text(story).font(.serif(17)).foregroundStyle(WT.ink.opacity(0.85)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.06), lineWidth: 1))
                    }
                    actionsRow
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            anchorNavBar(title: category.singular, onBack: { dismiss() })
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private func fieldRow(_ f: AnchorField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(f.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
            Text(f.value ?? "").font(.system(size: 16)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }

    // Edit + Delete LAID OUT but INERT (wired in a later phase). No POST/PUT/DELETE.
    private var actionsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                inertButton("Edit", tint: WV.teal)
                inertButton("Delete", tint: WV.danger)
            }
            Text("Editing and deleting are coming soon.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .padding(.top, 6)
    }
    private func inertButton(_ label: String, tint: Color) -> some View {
        Text(label).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint.opacity(0.5))
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.2), lineWidth: 1))
            .opacity(0.6)   // visibly disabled; no action attached
    }
}
