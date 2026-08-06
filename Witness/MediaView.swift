import SwiftUI
import UIKit

// MARK: - Media Gallery (web: /dashboard/media). Items grouped by memory.
//   GET    /api/v1/media/gallery?type=&search=   (list)
//   GET    /api/v1/media/{id}/file               (open)
//   DELETE /api/v1/media/{id}                    (remove)
// Captured media (camera/library) shows live in "Recently added" via MediaStore.
struct MediaView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MediaStore.shared
    @State private var groups: [MediaGroup] = MediaGroup.samples
    @State private var filter: MediaKind? = nil
    @State private var rows = false
    @State private var search = ""
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var lightbox: MediaItem?

    private var masonryCols: [GridItem] { [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    typeFilter
                    controlsRow
                    if visibleGroups.isEmpty { emptyState }
                    else { ForEach(visibleGroups, id: \.title) { group($0) } }
                }
                .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, selecting ? 90 : 110)
            }
            navBar
            if selecting { selectionBar }
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .overlay { if let item = lightbox { lightboxView(item) } }
    }

    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            }.witnessPress()
            Spacer()
            if !selecting { CaptureControl(style: .addButton) { store.add($0) } }
            Button { withAnimation { selecting.toggle(); selected.removeAll() } } label: {
                Text(selecting ? "Done" : "Select").font(.system(size: 15, weight: .medium)).foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EVERYTHING YOU'VE KEPT").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            Text("Media Gallery").font(.serif(28)).foregroundStyle(WT.ink)
            Text("Every photo, video, and recording, gathered with the memories they belong to.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: filter == nil) { filter = nil }
                ForEach(MediaKind.allCases, id: \.self) { k in chip(k.plural, active: filter == k) { filter = k } }
            }
        }
    }
    private func chip(_ text: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(text)
            .font(.system(size: 14, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? .white : WT.ink.opacity(0.6))
            .padding(.horizontal, 14).frame(height: 36)
            .background(active ? WV.teal : Color.white, in: Capsule())
            .overlay(Capsule().stroke(active ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { tap() } }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.4))
                TextField("Search", text: $search).font(.system(size: 15)).foregroundStyle(WT.ink).tint(WV.teal)
            }
            .padding(.horizontal, 12).frame(height: 44).frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            Button { withAnimation { rows.toggle() } } label: {
                Image(systemName: rows ? "rectangle.grid.1x2" : "square.grid.3x3").font(.system(size: 17)).foregroundStyle(WV.teal)
                    .frame(width: 44, height: 44).background(WV.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .witnessPress().witnessHint("Switch between a tight grid and larger rows.")
        }
    }

    private func group(_ g: MediaGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(g.title).font(.serif(20)).foregroundStyle(WT.ink)
                if let sub = g.subtitle { Text(sub).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
            }
            let items = filteredItems(g)
            if rows { VStack(spacing: 10) { ForEach(items) { tile($0, big: true) } } }
            else { LazyVGrid(columns: masonryCols, spacing: 8) { ForEach(items) { tile($0, big: false) } } }
        }
    }

    private func tile(_ item: MediaItem, big: Bool) -> some View {
        let isSel = selected.contains(item.id)
        return Button {
            if selecting { toggle(item) } else { lightbox = item }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let ui = item.image {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [item.kind.tone.opacity(0.30), item.kind.tone.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: item.kind.icon).font(.system(size: big ? 40 : 26, weight: .light)).foregroundStyle(item.kind.tone.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if item.kind == .video {
                    Image(systemName: "play.circle.fill").font(.system(size: big ? 34 : 22)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if big && item.image == nil {
                    Text(item.fileName).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .padding(8).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }
                if selecting {
                    Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(isSel ? WV.teal : .white)
                        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: big ? 180 : 110).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: big ? 18 : 12))
            .overlay(RoundedRectangle(cornerRadius: big ? 18 : 12).stroke(isSel ? WV.teal : WT.ink.opacity(0.06), lineWidth: isSel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        VStack {
            Spacer()
            HStack {
                Text("\(selected.count) selected").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                Spacer()
                Button(role: .destructive) { deleteSelected() } label: {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text("Delete") }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(selected.isEmpty ? WV.danger.opacity(0.4) : WV.danger, in: Capsule())
                }
                .witnessPress().disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.white.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }.ignoresSafeArea(edges: .bottom))
        }
    }

    private func lightboxView(_ item: MediaItem) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { lightbox = nil }
            VStack(spacing: 18) {
                ZStack {
                    if let ui = item.image {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        LinearGradient(colors: [item.kind.tone.opacity(0.4), item.kind.tone.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: item.kind.icon).font(.system(size: 70, weight: .light)).foregroundStyle(.white.opacity(0.85))
                    }
                    if item.kind == .video {
                        Image(systemName: "play.circle.fill").font(.system(size: 56)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 24)
                VStack(spacing: 4) {
                    Text(item.fileName).font(.serif(20)).foregroundStyle(.white)
                    if let m = item.memoryTitle { Text("from “\(m)”").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)) }
                }
                HStack(spacing: 12) {
                    Button { /* TODO: GET /api/v1/media/\(item.id)/file */ } label: {
                        HStack(spacing: 6) { Image(systemName: "arrow.up.forward.app"); Text("Open file") }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 18).frame(height: 48).background(.white, in: Capsule())
                    }.witnessPress()
                    Button(role: .destructive) { delete(item) } label: {
                        Image(systemName: "trash").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(WV.danger, in: Circle())
                    }.witnessPress()
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { lightbox = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No media here yet").font(.serif(20)).foregroundStyle(WT.ink)
            Text("Tap + to take a photo or video, or add photos to a memory.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    // MARK: data
    private var recentlyAdded: MediaGroup? {
        guard !store.captured.isEmpty else { return nil }
        return MediaGroup(title: "Recently added", date: nil, age: nil,
                          items: store.captured.map { MediaItem(id: $0.id, fileName: $0.fileName, kind: $0.kind, memoryTitle: nil, image: $0.image) })
    }
    private var allGroups: [MediaGroup] { (recentlyAdded.map { [$0] } ?? []) + groups }
    private func filteredItems(_ g: MediaGroup) -> [MediaItem] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return g.items.filter { item in
            (filter == nil || item.kind == filter) &&
            (q.isEmpty || item.fileName.lowercased().contains(q) || g.title.lowercased().contains(q))
        }
    }
    private var visibleGroups: [MediaGroup] { allGroups.filter { !filteredItems($0).isEmpty } }

    private func toggle(_ item: MediaItem) { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } }
    private func delete(_ item: MediaItem) {
        for i in groups.indices { groups[i].items.removeAll { $0.id == item.id } }
        store.remove(item.id); lightbox = nil
    }
    private func deleteSelected() {
        for i in groups.indices { groups[i].items.removeAll { selected.contains($0.id) } }
        selected.forEach { store.remove($0) }
        selected.removeAll(); withAnimation { selecting = false }
    }
}

// MARK: - Models + sample data
enum MediaKind: CaseIterable {
    case image, video, audio
    var plural: String { switch self { case .image: return "Images"; case .video: return "Video"; case .audio: return "Audio" } }
    var icon: String { switch self { case .image: return "photo"; case .video: return "play.rectangle.fill"; case .audio: return "waveform" } }
    var tone: Color { switch self { case .image: return WV.teal; case .video: return Color(hex: 0x6b5b95); case .audio: return Color(hex: 0xb08828) } }
}

struct MediaItem: Identifiable {
    let id: String
    let fileName: String
    let kind: MediaKind
    let memoryTitle: String?
    var image: UIImage? = nil
}

struct MediaGroup: Identifiable {
    let id = UUID()
    let title: String
    let date: String?
    let age: Int?
    var items: [MediaItem]

    var subtitle: String? {
        switch (date, age) {
        case let (d?, a?): return "\(d) · age \(a)"
        case let (d?, nil): return d
        case let (nil, a?): return "age \(a)"
        default: return nil
        }
    }

    static let samples: [MediaGroup] = [
        .init(title: "The long drive home", date: "June 2026", age: 53, items: [
            .init(id: "m1", fileName: "drive_01.jpg", kind: .image, memoryTitle: "The long drive home"),
            .init(id: "m2", fileName: "drive_02.jpg", kind: .image, memoryTitle: "The long drive home"),
            .init(id: "m3", fileName: "road_clip.mov", kind: .video, memoryTitle: "The long drive home"),
        ]),
        .init(title: "A quiet morning", date: "May 2026", age: 53, items: [
            .init(id: "m4", fileName: "morning.jpg", kind: .image, memoryTitle: "A quiet morning"),
            .init(id: "m5", fileName: "voice_note.m4a", kind: .audio, memoryTitle: "A quiet morning"),
        ]),
        .init(title: "The old back porch", date: "April 2026", age: 52, items: [
            .init(id: "m6", fileName: "porch_01.jpg", kind: .image, memoryTitle: "The old back porch"),
            .init(id: "m7", fileName: "porch_02.jpg", kind: .image, memoryTitle: "The old back porch"),
            .init(id: "m8", fileName: "porch_swing.mov", kind: .video, memoryTitle: "The old back porch"),
        ]),
        .init(title: "Other Media", date: nil, age: nil, items: [
            .init(id: "m9", fileName: "untitled_recording.m4a", kind: .audio, memoryTitle: nil),
        ]),
    ]
}
