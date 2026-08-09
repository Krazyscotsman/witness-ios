import SwiftUI

struct MemoriesView: View {
    @ObservedObject var vm: MemoriesViewModel
    @ObservedObject var auth: AuthManager
    @Binding var path: NavigationPath
    @State private var showRecord = false
    @State private var showGallery = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ParchmentBackground()
                Group {
                    if vm.memories.isEmpty {
                        switch vm.state {
                        case .loading, .idle: loadingState
                        case .failed(let message): failedState(message)
                        case .loaded: emptyState
                        }
                    } else {
                        list   // has data → keep showing it even while refreshing
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MemoryDTO.self) { dto in
                MemoryDetailView(listItem: dto, auth: auth)   // fetches /detail by dto.id
            }
        }
        .task { await vm.load(auth: auth) }        // fetch-once (VM guards)
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
        .fullScreenCover(isPresented: $showGallery) { MediaView() }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVStack(spacing: 14) {
                    ForEach(vm.memories) { m in
                        NavigationLink(value: m) { MemoryCard(memory: m) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await vm.refresh(auth: auth) }   // pull-to-refresh
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Memories").font(.serif(28)).foregroundStyle(WV.teal)
                Text("\(vm.total) moments kept")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            }
            Spacer()
            CaptureControl(style: .cameraButton) { MediaStore.shared.add($0) }
                .witnessHint("Take a photo or record a video for a memory.")
                .padding(.trailing, 10)
            Button { showGallery = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "photo.stack").font(.system(size: 16, weight: .semibold))
                    Text("Gallery").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(WV.teal)
                .padding(.horizontal, 16).frame(height: 48)
                .background(WV.teal.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(WV.teal.opacity(0.4), lineWidth: 1.5))
            }
            .witnessPress()
            .witnessHint("Browse all your photos, video, and audio in one gallery.")
            .padding(.trailing, 10)
            Button { showRecord = true } label: {
                ZStack {
                    Circle().fill(WV.teal)
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                .shadow(color: WV.teal.opacity(0.3), radius: 8, y: 4)
            }
            .witnessPress()
            .witnessHint("Add a new memory — speak it aloud or type it.")
        }
        .padding(.bottom, 4)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(WV.teal)
            Text("Gathering your memories…")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5))
        }
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(WT.ink.opacity(0.3))
            Text("Couldn’t load your memories").font(.serif(22)).foregroundStyle(WV.teal)
            Text(message)
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Button { Task { await vm.refresh(auth: auth) } } label: {
                Text("Try again")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 50)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.top, 4)
        }
        .padding(28)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            CompassMark(color: WV.gold).frame(width: 40, height: 40)
            Text("Your first memory is waiting").font(.serif(26)).foregroundStyle(WV.teal)
            Text("When you record a moment, it will live here — gathered, searchable, and yours.")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 44)
            Button { showRecord = true } label: {
                Text("Record your first memory")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 52)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress().padding(.top, 4)
        }
        .padding(28)
    }
}

// MARK: - Card (layout preserved from the sample version; real MemoryDTO fields)
struct MemoryCard: View {
    let memory: MemoryDTO

    // Degrades cleanly: nil when BOTH location and people are absent -> the card shows date only,
    // no dangling "·".
    private var metaLine: String? {
        if let loc = memory.location, !loc.isEmpty { return loc }
        if let people = memory.people, !people.isEmpty { return people.joined(separator: ", ") }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: "book.closed")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(WV.teal)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(memory.title ?? "Untitled memory").font(.serif(19)).foregroundStyle(WT.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let snippet = memory.narrativeSnippet, !snippet.isEmpty {
                    Text(snippet).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(MemoryFormat.date(memory)).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
                    if let meta = metaLine {
                        Text("·").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.3))
                        Text(meta).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WT.ink.opacity(0.3)).padding(.top, 14)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.07), radius: 12, y: 6)
        .contentShape(Rectangle())
    }
}

// Best-effort display date from exact_date + time_granularity (refine later with the detail wiring).
enum MemoryFormat {
    static func date(_ m: MemoryDTO) -> String {
        guard let raw = m.exactDate, !raw.isEmpty else { return "Undated" }
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = .current
        switch m.timeGranularity {
        case "year", "age_year", "school_year": out.dateFormat = "yyyy"
        case "month", "season": out.dateFormat = "LLLL yyyy"
        default: out.dateStyle = .long
        }
        return out.string(from: d)
    }
}
