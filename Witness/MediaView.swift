import SwiftUI
import UIKit

// MARK: - Media Gallery (read side). Real data: GET /api/v1/media/gallery (grouped by memory, rendered by
// file_type). Images load via AsyncImage from a resolved url; on load failure we fetch a fresh presigned url
// once and retry (expiry recovery + the Bearer workaround for relative /file urls). Local capture ("Recently
// added", MediaStore) stays as a pending-upload staging area; upload + delete are separate/later.
struct MediaView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MediaStore.shared
    @StateObject private var vm = MediaViewModel()
    @StateObject private var audio = AudioPlayer()

    @State private var typeFilter: String? = nil     // nil = All, else "image"/"video"/"audio"/"document"
    @State private var rows = false
    @State private var search = ""
    @State private var lightbox: MediaItemDTO?
    @State private var playingID: String?

    private var cols: [GridItem] { [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] }

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
        .overlay { if let item = lightbox { lightboxView(item) } }
        .onDisappear { audio.stop() }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerBlock
                typeFilterRow
                controlsRow
                if let rec = recentlyAdded { localSection(rec) }
                let sections = visibleSections
                if sections.isEmpty && recentlyAdded == nil { emptyState }
                else { ForEach(sections) { section($0) } }
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }
    }

    // MARK: nav + header
    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            }.witnessPress()
            Spacer()
            CaptureControl(style: .addButton) { store.add($0) }   // local staging; upload wired later
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

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: typeFilter == nil) { typeFilter = nil }
                chip("Photos", active: typeFilter == "image") { typeFilter = "image" }
                chip("Video", active: typeFilter == "video") { typeFilter = "video" }
                chip("Audio", active: typeFilter == "audio") { typeFilter = "audio" }
                chip("Documents", active: typeFilter == "document") { typeFilter = "document" }
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

    // MARK: sections (grouped by memory, backend order preserved)
    struct MediaSection: Identifiable { let id: String; let title: String; let subtitle: String?; let items: [MediaItemDTO] }

    private var visibleSections: [MediaSection] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = vm.items.filter { it in
            (typeFilter == nil || (it.fileType ?? "") == typeFilter) &&
            (q.isEmpty || (it.fileName ?? "").lowercased().contains(q) || (it.memoryTitle ?? "").lowercased().contains(q))
        }
        var order: [String] = []
        var buckets: [String: [MediaItemDTO]] = [:]
        for it in filtered {
            let k = it.memoryId ?? "__unlinked__"
            if buckets[k] == nil { buckets[k] = []; order.append(k) }
            buckets[k]?.append(it)
        }
        return order.map { k in
            let items = buckets[k] ?? []
            let title = (k == "__unlinked__") ? "Unlinked media" : (items.first?.memoryTitle ?? "Untitled memory")
            return MediaSection(id: k, title: title, subtitle: subtitle(items.first), items: items)
        }
    }
    private func subtitle(_ it: MediaItemDTO?) -> String? {
        guard let it else { return nil }
        switch (it.memoryDate, it.narratorAge) {
        case let (d?, a?): return "\(d) · age \(a)"
        case let (d?, nil): return d
        case let (nil, a?): return "age \(a)"
        default: return nil
        }
    }

    private func section(_ s: MediaSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.serif(20)).foregroundStyle(WT.ink)
                if let sub = s.subtitle { Text(sub).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)) }
            }
            if rows { VStack(spacing: 10) { ForEach(s.items) { tile($0, big: true) } } }
            else { LazyVGrid(columns: cols, spacing: 8) { ForEach(s.items) { tile($0, big: false) } } }
        }
    }

    // MARK: tile — render by file_type
    private func tile(_ item: MediaItemDTO, big: Bool) -> some View {
        let h: CGFloat = big ? 180 : 110
        return Button { onTap(item) } label: {
            ZStack(alignment: .bottomLeading) {
                switch (item.fileType ?? "") {
                case "image":
                    MediaThumb(item: item, vm: vm, auth: auth)
                case "video":
                    placeholderFill(tone: Color(hex: 0x6b5b95), icon: "play.rectangle.fill", big: big)
                    Image(systemName: "play.circle.fill").font(.system(size: big ? 34 : 22)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case "audio":
                    placeholderFill(tone: Color(hex: 0xb08828), icon: "waveform", big: big)
                    Image(systemName: playingID == item.id ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: big ? 34 : 22)).foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    placeholderFill(tone: WT.ink.opacity(0.4), icon: "doc.fill", big: big)
                }
                if big, (item.fileType ?? "") != "image", let name = item.fileName {
                    Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                        .lineLimit(1).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }
            }
            .frame(height: h).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: big ? 18 : 12))
            .overlay(RoundedRectangle(cornerRadius: big ? 18 : 12).stroke(WT.ink.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    private func placeholderFill(tone: Color, icon: String, big: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [tone.opacity(0.30), tone.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: big ? 40 : 26, weight: .light)).foregroundStyle(tone.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onTap(_ item: MediaItemDTO) {
        switch (item.fileType ?? "") {
        case "audio": Task { await toggleAudio(item) }
        default:      lightbox = item
        }
    }
    private func toggleAudio(_ item: MediaItemDTO) async {
        if playingID == item.id { audio.stop(); playingID = nil; return }
        // Prefer a fresh presigned url — AVAudioPlayer can't send Bearer for a relative /file url.
        let raw = await vm.refreshURL(for: item.id, auth: auth) ?? item.url
        guard let u = vm.resolvedURL(raw) else { return }
        audio.load(u); audio.play(); playingID = item.id
    }

    // MARK: local staging ("Recently added") — captured this session, pending upload
    private var recentlyAdded: [CapturedMedia]? { store.captured.isEmpty ? nil : store.captured }
    private func localSection(_ items: [CapturedMedia]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recently added").font(.serif(20)).foregroundStyle(WT.ink)
                Text("On this device — pending upload.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
            }
            LazyVGrid(columns: cols, spacing: 8) { ForEach(items) { localTile($0) } }
        }
    }
    private func localTile(_ c: CapturedMedia) -> some View {
        ZStack {
            if let ui = c.image {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                placeholderFill(tone: c.kind.tone, icon: c.kind.icon, big: false)
            }
            if c.kind == .video {
                Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(height: 110).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.06), lineWidth: 1))
    }

    // MARK: read-only lightbox (image full / video + doc info; audio plays inline from its tile)
    private func lightboxView(_ item: MediaItemDTO) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { lightbox = nil }
            VStack(spacing: 18) {
                ZStack {
                    if (item.fileType ?? "") == "image" {
                        MediaThumb(item: item, vm: vm, auth: auth, fit: true)
                    } else {
                        let tone: Color = (item.fileType ?? "") == "video" ? Color(hex: 0x6b5b95) : WT.ink.opacity(0.5)
                        let icon: String = (item.fileType ?? "") == "video" ? "play.rectangle.fill" : "doc.fill"
                        LinearGradient(colors: [tone.opacity(0.4), tone.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: icon).font(.system(size: 70, weight: .light)).foregroundStyle(.white.opacity(0.85))
                        if (item.fileType ?? "") == "video" {
                            Image(systemName: "play.circle.fill").font(.system(size: 56)).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 24)
                VStack(spacing: 4) {
                    Text(item.fileName ?? "Untitled file").font(.serif(20)).foregroundStyle(.white)
                    if let m = item.memoryTitle { Text("from “\(m)”").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)) }
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

    // MARK: states
    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(WV.teal)
            Text("Gathering your media…").font(.serif(18)).foregroundStyle(WT.ink.opacity(0.7))
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
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(WT.ink.opacity(0.25))
            Text("No media yet").font(.serif(20)).foregroundStyle(WT.ink)
            Text("Photos, videos, and recordings attached to your memories will gather here.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }
}

// MARK: - Shared media kind (used by the capture layer: CapturedMedia / CaptureControl / RecordView / Memories).
enum MediaKind: CaseIterable {
    case image, video, audio
    var plural: String { switch self { case .image: return "Images"; case .video: return "Video"; case .audio: return "Audio" } }
    var icon: String { switch self { case .image: return "photo"; case .video: return "play.rectangle.fill"; case .audio: return "waveform" } }
    var tone: Color { switch self { case .image: return WV.teal; case .video: return Color(hex: 0x6b5b95); case .audio: return Color(hex: 0xb08828) } }
}

// MARK: - Presigned thumbnail with a single refresh-on-error retry.
// AsyncImage can't send Bearer, so a relative /file url fails first → we fetch a fresh presigned url once and
// retry (didRefresh guards against a loop). Absolute presigned urls load on the first try.
private struct MediaThumb: View {
    let item: MediaItemDTO
    @ObservedObject var vm: MediaViewModel
    let auth: AuthManager
    var fit: Bool = false          // lightbox uses scaledToFit; grid uses scaledToFill
    @State private var url: URL?
    @State private var didRefresh = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img):
                        if fit { img.resizable().scaledToFit() } else { img.resizable().scaledToFill() }
                    case .empty:
                        shimmer(loading: true)
                    case .failure:
                        shimmer(loading: false).task { await refreshOnce() }
                    @unknown default:
                        shimmer(loading: false)
                    }
                }
            } else {
                shimmer(loading: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { if url == nil { url = vm.resolvedURL(item.url) } }
    }

    private func refreshOnce() async {
        guard !didRefresh else { return }
        didRefresh = true
        if let fresh = await vm.refreshURL(for: item.id, auth: auth), let u = vm.resolvedURL(fresh) { url = u }
    }

    private func shimmer(loading: Bool) -> some View {
        ZStack {
            WV.teal.opacity(0.06)
            if loading { ProgressView().tint(WV.teal) }
            else { Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(WT.ink.opacity(0.25)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
