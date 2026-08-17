import SwiftUI
import Combine

// MARK: - Graph node detail (bottom sheet) — Stage 1: memory tap-through.
// Fetches GET /api/v1/entities/{id} for the tapped node → linked_memories, and lets each memory push the real
// MemoryDetailView. Heavy endpoint, so the fetch runs once when the card opens (a fresh @StateObject per sheet
// presentation + the loaded/loading guard guarantees never-per-node). PLAIN decoder: EntityDetailDTO uses
// explicit CodingKeys (linked_memories), so convertFromSnakeCase must NOT be used.
@MainActor
final class EntityMemoriesViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, empty, failed(String) }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var memories: [LinkedMemory] = []
    private enum SessionError: Error { case sessionEnded }

    func load(entityId: String, auth: AuthManager) async {
        if state == .loaded || state == .loading { return }   // fetch-once per open; retry allowed from .failed
        guard !entityId.isEmpty else { state = .empty; return }
        state = .loading
        do {
            let d = try await withAuth(auth) {
                try await APIClient.shared.get("/api/v1/entities/\(entityId)", timeout: 30, as: EntityDetailDTO.self)
            }
            let mems = d.linkedMemories ?? []
            memories = mems
            state = mems.isEmpty ? .empty : .loaded
        } catch {
            if case SessionError.sessionEnded = error { state = .failed("Your session has ended. Please sign in again.") }
            else { state = .failed("We couldn’t load linked memories. Please try again.") }
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

struct NodeDetailSheet: View {
    let node: GNode
    @ObservedObject var auth: AuthManager
    var onExplore: ((GNode) -> Void)? = nil        // graph re-center; hidden when nil
    @StateObject private var vm = EntityMemoriesViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    identityHeader
                    factsCard
                    if let onExplore {
                        Button { onExplore(node) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 14, weight: .semibold))
                                Text("Explore connections").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 48)
                            .background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
                        }.witnessPress()
                    }
                    memoriesSection
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
            }
            .background(WV.parchment)
            .navigationDestination(for: MemoryDTO.self) { dto in
                MemoryDetailView(listItem: dto, auth: auth)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.load(entityId: node.id, auth: auth) }
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(node.isNarrator ? WV.teal : GraphClassify.edgeCategory(node.primaryRel).text).frame(width: 50, height: 50)
                if node.isAnchor { Circle().stroke(WV.gold, lineWidth: 2.5).frame(width: 56, height: 56) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(node.label).font(.serif(24)).foregroundStyle(WT.ink)
                Text(humanize(node.primaryRel)).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
            }
            Spacer()
            if node.isAnchor {
                Text("Anchor").font(.system(size: 11, weight: .semibold)).foregroundStyle(WV.gold)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(WV.gold.opacity(0.12), in: Capsule())
            }
        }
    }

    private var factsCard: some View {
        VStack(spacing: 0) {
            detailRow("Memories", "\(node.memoryCount)")     // node's own count — shown as-is (may differ from the fetched list)
            if let b = node.born { Divider(); detailRow("Born", b) }
            if let d = node.died { Divider(); detailRow("Died", d) }
            if !node.aliases.isEmpty { Divider(); detailRow("Also known as", node.aliases.joined(separator: ", ")) }
        }
        .padding(.horizontal, 16)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.08), lineWidth: 1))
    }

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMORIES").font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.4))
            switch vm.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().tint(WV.teal)
                    Text("Loading memories…").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            case .empty:
                Text("No linked memories.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5)).padding(.vertical, 6)
            case .failed(let m):
                VStack(alignment: .leading, spacing: 8) {
                    Text(m).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                    Button { Task { await vm.load(entityId: node.id, auth: auth) } } label: {
                        HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)); Text("Try again").font(.system(size: 14, weight: .medium)) }.foregroundStyle(WV.teal)
                    }.witnessPress()
                }.padding(.vertical, 4)
            case .loaded:
                VStack(spacing: 8) {
                    ForEach(Array(vm.memories.enumerated()), id: \.offset) { _, m in memoryRow(m) }
                }
            }
        }
    }

    @ViewBuilder private func memoryRow(_ m: LinkedMemory) -> some View {
        let title = (m.title ?? "").trimmingCharacters(in: .whitespaces)
        let display = title.isEmpty ? "Untitled memory" : title
        let date = (m.date ?? "").trimmingCharacters(in: .whitespaces)
        if let id = m.id, !id.isEmpty {
            NavigationLink(value: MemoryDTO(id: id, title: m.title, exactDate: m.date)) {
                memoryRowContent(display, date, tappable: true)
            }.buttonStyle(.plain)
        } else {
            memoryRowContent(display, date, tappable: false)
        }
    }
    private func memoryRowContent(_ title: String, _ date: String, tappable: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "book.closed").font(.system(size: 14)).foregroundStyle(WV.teal) }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(16)).foregroundStyle(WT.ink).lineLimit(1)
                if !date.isEmpty { Text(date).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
            }
            Spacer(minLength: 4)
            if tappable { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3)) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    private func detailRow(_ l: String, _ v: String) -> some View {
        HStack { Text(l).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)); Spacer(); Text(v).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink) }.frame(height: 46)
    }
    private func humanize(_ s: String) -> String { s.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
}
