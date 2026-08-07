import SwiftUI

struct MemoriesView: View {
    @State private var memories: [SampleMemory] = SampleMemory.samples
    @State private var showRecord = false
    @State private var showGallery = false

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                if memories.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            LazyVStack(spacing: 14) {
                                ForEach(memories) { m in
                                    NavigationLink(value: m) { MemoryCard(memory: m) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 110)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SampleMemory.self) { m in
                MemoryDetailView(memory: m)
            }
        }
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
        .fullScreenCover(isPresented: $showGallery) { MediaView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Memories").font(.serif(28)).foregroundStyle(WV.teal)
                Text("\(memories.count) moments kept")
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            CompassMark(color: WV.gold).frame(width: 40, height: 40)
            Text("No memories yet").font(.serif(26)).foregroundStyle(WV.teal)
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

struct MemoryCard: View {
    let memory: SampleMemory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: memory.kind.icon)
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(WV.teal)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(memory.title).font(.serif(19)).foregroundStyle(WT.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(memory.excerpt).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(memory.date).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
                    if let meta = memory.kind.meta {
                        Text("·").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.3))
                        Text(meta).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
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

struct SampleMemory: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let excerpt: String
    let date: String
    let kind: Kind
    let people: [String]
    let narrative: String
    let wordCount: Int
    let texture: String

    enum Kind: Hashable {
        case voice, text, photo
        var icon: String {
            switch self {
            case .voice: return "waveform"; case .text: return "text.alignleft"; case .photo: return "photo"
            }
        }
        var meta: String? {
            switch self {
            case .voice: return "Voice · 2:14"; case .text: return "Written"; case .photo: return "Photo"
            }
        }
    }

    static let sampleNarrative = "This is sample narrative text, shown so you can see how a memory reads in full — the serif body, the line spacing, the way the words sit on the page beneath the cover. Your own words, captured in your own voice, will fill this space once recording is wired."

    static let samples: [SampleMemory] = [
        .init(title: "The long drive home", excerpt: "Sample memory — the kind of moment Witness keeps. Real entries appear here once you start recording.",
              date: "June 2026", kind: .voice, people: ["Sam", "Marie"], narrative: sampleNarrative, wordCount: 412, texture: "Warm · reflective"),
        .init(title: "A quiet morning", excerpt: "Sample memory shown for layout. Your own words, in your own voice, will fill this space.",
              date: "May 2026", kind: .text, people: ["Joan"], narrative: sampleNarrative, wordCount: 168, texture: "Calm · tender"),
        .init(title: "The old back porch", excerpt: "Sample memory with a photo attached, to show how images sit alongside the story.",
              date: "April 2026", kind: .photo, people: [], narrative: sampleNarrative, wordCount: 305, texture: "Nostalgic"),
        .init(title: "First snow", excerpt: "Sample memory — placeholder text showing a second voice entry in the list.",
              date: "January 2026", kind: .voice, people: ["Sam"], narrative: sampleNarrative, wordCount: 221, texture: "Quiet · still"),
    ]
}
