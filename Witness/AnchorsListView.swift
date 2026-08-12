import SwiftUI
import Combine

// MARK: - Type indicator (free-string `type`; neutral fallback for unknowns)
enum AnchorTypeStyle {
    static func icon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "person":              return "person.fill"
        case "place", "location":   return "mappin.and.ellipse"
        case "organization", "org": return "building.2.fill"
        case "pet":                 return "pawprint.fill"
        case "vehicle":             return "car.fill"
        default:                    return "circle.grid.2x2.fill"   // neutral fallback
        }
    }
    static func label(_ type: String?) -> String {
        let t = (type ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Anchor" : t.capitalized
    }
}

// MARK: - List VM: GET /entities → filter is_anchor == true (no server filter param)
@MainActor
final class AnchorsListViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }
    @Published private(set) var anchors: [EntitySummary] = []
    @Published private(set) var state: LoadState = .idle

    func load(auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        await fetch(auth: auth)
    }
    func refresh(auth: AuthManager) async {
        if state == .loading { return }
        await fetch(auth: auth)
    }
    private func fetch(auth: AuthManager) async {
        state = .loading
        do {
            anchors = try await request().filter { $0.isAnchor == true }
            state = .loaded
        } catch let APIError.unauthorized(_, code) {
            if await auth.handleUnauthorized(code: code) {
                do { anchors = try await request().filter { $0.isAnchor == true }; state = .loaded }
                catch { state = .failed(message: Self.message(for: error)) }
            } else { state = .failed(message: "Your session ended. Please sign in again.") }
        } catch { state = .failed(message: Self.message(for: error)) }
    }
    private func request() async throws -> [EntitySummary] {
        try await APIClient.shared.get("/api/v1/entities", timeout: 20, as: [EntitySummary].self)
    }
    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .network: return "Can’t reach the server. Check your connection and try again."
            case .http(let s, _): return "The server responded with an error (\(s))."
            case .decoding: return "The server sent something unexpected."
            default: return api.errorDescription ?? "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Detail VM: GET /entities/{id} (per-open)
@MainActor
final class AnchorEntityDetailViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(message: String) }
    @Published private(set) var detail: EntityDetailDTO?
    @Published private(set) var state: LoadState = .idle

    func load(id: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }
        await fetch(id: id, auth: auth)
    }
    func retry(id: String, auth: AuthManager) async {
        if state == .loading { return }
        await fetch(id: id, auth: auth)
    }
    private func fetch(id: String, auth: AuthManager) async {
        state = .loading
        do { detail = try await request(id); state = .loaded }
        catch let APIError.unauthorized(_, code) {
            if await auth.handleUnauthorized(code: code) {
                do { detail = try await request(id); state = .loaded }
                catch { state = .failed(message: Self.message(for: error)) }
            } else { state = .failed(message: "Your session ended. Please sign in again.") }
        } catch { state = .failed(message: Self.message(for: error)) }
    }
    private func request(_ id: String) async throws -> EntityDetailDTO {
        try await APIClient.shared.get("/api/v1/entities/\(id)", timeout: 20, as: EntityDetailDTO.self)
    }
    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .network: return "Can’t reach the server. Check your connection and try again."
            case .http(let s, _): return "The server responded with an error (\(s))."
            case .decoding: return "The server sent something unexpected."
            default: return api.errorDescription ?? "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}

// Build a MemoryDTO from a linked memory so linked rows can open the existing MemoryDetailView.
private extension MemoryDTO {
    init?(linked m: LinkedMemory) {
        guard let id = m.id, !id.isEmpty else { return nil }
        self.init(id: id, title: m.title, narrative: nil, narrativeSnippet: nil,
                  exactDate: m.date, timeGranularity: nil, exactDateEstimated: nil,
                  narratorAge: nil, qualityScore: nil, importanceScore: nil,
                  people: nil, location: nil, createdAt: nil, updatedAt: nil)
    }
}

// MARK: - Anchors list (anchors-only). Pushed inside the Insights NavigationStack.
struct AnchorsListView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AnchorsListViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            Group {
                switch vm.state {
                case .idle, .loading: loadingState
                case .failed(let m):  failedState(m)
                case .loaded:         vm.anchors.isEmpty ? AnyView(emptyState) : AnyView(list)
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(auth: auth) }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVStack(spacing: 14) {
                    ForEach(vm.anchors) { a in
                        NavigationLink { AnchorEntityDetailView(entity: a, auth: auth) } label: { row(a) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Anchors").font(.serif(28)).foregroundStyle(WV.teal)
            Text("The defining people, places, and things your memories orbit.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private func row(_ a: EntitySummary) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: AnchorTypeStyle.icon(a.type)).font(.system(size: 18, weight: .medium)).foregroundStyle(WV.teal)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.name ?? "Unnamed anchor").font(.serif(19)).foregroundStyle(WT.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(AnchorTypeStyle.label(a.type)).font(.system(size: 12, weight: .medium)).foregroundStyle(WV.teal)
                    if let c = a.memoryCount {
                        Text("·").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.3))
                        Text("\(c) \(c == 1 ? "memory" : "memories")").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.07), radius: 12, y: 6)
        .contentShape(Rectangle())
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(WV.teal)
            Text("Gathering your anchors…").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5))
        }
    }
    private func failedState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(WT.ink.opacity(0.3))
            Text("Couldn’t load your anchors").font(.serif(22)).foregroundStyle(WV.teal)
            Text(message).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth) } } label: {
                Text("Try again").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 50).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.top, 4)
        }
        .padding(28)
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            CompassMark(color: WV.gold).frame(width: 40, height: 40)
            Text("No anchors yet.").font(.serif(26)).foregroundStyle(WV.teal)
            Text("As you share memories, the people, places, and things that matter most will settle here.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 44)
        }
        .padding(28)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }
}

// MARK: - Anchor detail: header + linked memories + inert Delete
struct AnchorEntityDetailView: View {
    let entity: EntitySummary            // instant header
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AnchorEntityDetailViewModel()
    @State private var confirmDelete = false
    @State private var deleteUnavailable = false   // subtle "coming soon" note (honest — nothing was deleted)

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    switch vm.state {
                    case .idle, .loading: loadingBlock
                    case .failed(let m):  failedBlock(m)
                    case .loaded:         loadedBody
                    }
                    deleteSection
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(id: entity.id, auth: auth) }
        .confirmationDialog("Delete this anchor? This can't be undone.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAnchor() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AnchorTypeStyle.label(vm.detail?.type ?? entity.type).uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(WV.teal.opacity(0.12))
                    Image(systemName: AnchorTypeStyle.icon(vm.detail?.type ?? entity.type)).font(.system(size: 20, weight: .medium)).foregroundStyle(WV.teal)
                }
                .frame(width: 54, height: 54)
                Text(vm.detail?.name ?? entity.name ?? "Unnamed anchor")
                    .font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let c = entity.memoryCount {
                Text("\(c) \(c == 1 ? "memory" : "memories")").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            }
        }
    }

    private var loadedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LINKED MEMORIES").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            let mems = vm.detail?.linkedMemories ?? []
            if mems.isEmpty {
                Text("No linked memories yet.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(mems.enumerated()), id: \.offset) { _, m in linkedRow(m) }
                }
            }
        }
    }

    @ViewBuilder private func linkedRow(_ m: LinkedMemory) -> some View {
        if let dto = MemoryDTO(linked: m) {
            NavigationLink { MemoryDetailView(listItem: dto, auth: auth) } label: { linkedCard(m) }
                .buttonStyle(.plain)
        } else {
            linkedCard(m)   // no id → not tappable
        }
    }

    private func linkedCard(_ m: LinkedMemory) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "book.closed").font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal) }
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title ?? "Untitled memory").font(.serif(18)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let d = m.date, !d.isEmpty { Text(d).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)) }
                    if let r = m.role, !r.isEmpty {
                        if m.date?.isEmpty == false { Text("·").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.3)) }
                        Text(r).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            if MemoryDTO(linked: m) != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
        .contentShape(Rectangle())
    }

    private var deleteSection: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete this anchor").font(.system(size: 16, weight: .semibold)).foregroundStyle(WV.danger)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.3), lineWidth: 1))
            }
            .witnessPress()
            if deleteUnavailable {
                Text("Anchor deletion isn’t available yet.")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
            }
        }
        .padding(.top, 8)
    }

    /// The single function to wire when the backend supports it.
    private func deleteAnchor() {
        // TODO(anchor-delete): wire to the new backend delete endpoint once it exists.
        //   Do NOT call DELETE /api/v1/entities/{id} (403) or DELETE /timeline/{category}/{id} (orphans the anchor).
        //   Target flow when wired:
        //     do { try await auth-scoped delete(entity.id) ; dismiss() /* pop to list */ }  // + trigger a list refresh
        //     catch { show a friendly failure }
        deleteUnavailable = true   // safe no-op — nothing is sent to the backend
    }

    private var loadingBlock: some View {
        HStack { Spacer(); ProgressView().tint(WV.teal); Spacer() }.padding(.top, 24)
    }
    private func failedBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn’t load this anchor’s memories").font(.serif(18)).foregroundStyle(WV.teal)
            Text(message).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            Button { Task { await vm.retry(id: entity.id, auth: auth) } } label: {
                Text("Try again").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).frame(height: 46).background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
            }.witnessPress()
        }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Anchors").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }
}
