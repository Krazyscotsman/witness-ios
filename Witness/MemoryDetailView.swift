import SwiftUI

struct MemoryDetailView: View {
    let memory: SampleMemory
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var audioURL: URL?
    @State private var showAsk = false
    @StateObject private var speaker = Speaker()

    // Set true once a memory carries a real cover photo; sample memories have none.
    private var hasCoverPhoto: Bool { false }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cover
                    VStack(alignment: .leading, spacing: 18) {
                        Text(memory.date.uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(WV.gold)
                        Text(memory.title)
                            .font(.serif(30)).foregroundStyle(WT.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !memory.people.isEmpty { peopleChips }
                        Text(memory.narrative)
                            .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
                            .lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                        readAloudControl.padding(.top, 6)
                        metadataRow.padding(.top, 2)
                        actionsRow.padding(.top, 8)
                        if audioURL != nil {
                            listenPlayer.padding(.top, 12)
                        } else {
                            Text("No recording to play yet.")
                                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.4))
                                .padding(.top, 10)
                        }
                        askCard.padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, hasCoverPhoto ? 6 : 22)
                    .padding(.bottom, 110)  // clears the tab bar so Ask card is fully visible
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .ignoresSafeArea(edges: .top)

            topControls
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            audioURL = resolveMemoryAudioURL(for: memory)
            if let url = audioURL { audioPlayer.load(url) }
        }
        .onDisappear { audioPlayer.stop(); speaker.stop() }
        .sheet(isPresented: $showAsk) {
            // Memory-scoped "Ask Scarlett" — opens TalkView about this memory.
            // Passing the whole memory for its title (opening line) + id (session handoff);
            // memory.id is a client-side UUID today → server memory id once wired.
            TalkView(memory: memory)
        }
    }

    // With a photo: a tall cover that dissolves into the page. Without: a slim, quiet
    // band of color at the very top — a hint, not a slab.
    private var cover: some View {
        Group {
            if hasCoverPhoto {
                LinearGradient(colors: [WV.teal.opacity(0.32), Color(hex: 0xe6dccb)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                    .frame(height: 300)
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.60),
                            .init(color: .clear, location: 1.0)
                        ], startPoint: .top, endPoint: .bottom)
                    )
            } else {
                LinearGradient(colors: [WV.teal.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { controlCircle("chevron.left") }
                .witnessPress()
            Spacer()
            Button { /* TODO: edit -> PUT /api/v1/memories/{id} */ } label: { controlCircle("pencil") }
                .witnessPress()
                .witnessHint("Edit this memory's title, date, and words.")
            Button(role: .destructive) { /* TODO: delete (confirm first when wired) */ } label: {
                controlCircle("trash", tint: WV.danger)
            }
            .witnessPress()
            .witnessHint("Delete this memory. You'll be asked to confirm.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func controlCircle(_ system: String, tint: Color = WT.ink.opacity(0.8)) -> some View {
        Image(systemName: system)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Color.white, in: Circle())
            .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.12), radius: 5, y: 2)
    }

    private var peopleChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(memory.people, id: \.self) { p in
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(WV.teal)
                    Text(p).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(WV.teal.opacity(0.10), in: Capsule())
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 18) {
            metaItem("doc.text", "\(memory.wordCount) words")
            metaItem("heart", memory.texture)
        }
    }
    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            Text(text).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            actionChip(audioPlayer.isPlaying ? "pause.fill" : "speaker.wave.2.fill",
                       audioPlayer.isPlaying ? "Pause" : "Listen") { toggleListen() }
                .disabled(audioURL == nil)
                .opacity(audioURL == nil ? 0.45 : 1)
                .witnessHint("Play this memory's audio recording.")
            actionChip("photo.badge.plus", "Add media") { /* TODO: POST /api/v1/memories/{id}/media */ }
            actionChip("wand.and.stars", "Create image") { /* TODO: POST /visualize/{id} */ }
        }
    }
    private func actionChip(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(WV.teal.opacity(0.12))
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(WV.teal)
                }
                .frame(width: 44, height: 44)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.06), radius: 8, y: 4)
        }
        .witnessPress()
    }

    // Compact playback bar (mirrors the saved-screen player). Shown when audio exists.
    private var listenPlayer: some View {
        HStack(spacing: 14) {
            Button { toggleListen() } label: {
                ZStack {
                    Circle().fill(WV.teal)
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
            }
            .witnessPress()

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WT.ink.opacity(0.1))
                        Capsule().fill(WV.teal)
                            .frame(width: max(0, geo.size.width * audioPlayer.progress))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(mmss(audioPlayer.currentTime))
                    Spacer()
                    Text(mmss(audioPlayer.duration))
                }
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(WT.ink.opacity(0.5))
            }
        }
        .padding(16)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    private func toggleListen() {
        guard audioURL != nil else { return }
        if audioPlayer.isPlaying { audioPlayer.pause() }
        else { speaker.stop(); audioPlayer.play() }   // stop Read-aloud so they don't overlap
    }

    // Read aloud: speaks the memory's WRITTEN text via on-device TTS (system voice — branded
    // voices are item 12). Distinct from "Listen", which plays the original audio recording.
    // Tap toggles read → pause → resume.
    private var readAloudControl: some View {
        Button { toggleReadAloud() } label: {
            HStack(spacing: 7) {
                Image(systemName: readAloudIcon).font(.system(size: 14, weight: .medium))
                Text(readAloudLabel).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(WV.teal)
            .padding(.horizontal, 14).frame(height: 38)
            .background(WV.teal.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
        }
        .witnessPress()
        .witnessHint("Read this memory's written words aloud, on your device.")
    }

    private var readAloudIcon: String {
        if speaker.isPaused { return "play.fill" }
        if speaker.isSpeaking { return "pause.fill" }
        return "text.bubble.fill"
    }
    private var readAloudLabel: String {
        if speaker.isPaused { return "Resume" }
        if speaker.isSpeaking { return "Pause" }
        return "Read aloud"
    }
    private func toggleReadAloud() {
        if speaker.isPaused { speaker.resume() }
        else if speaker.isSpeaking { speaker.pause() }
        else {
            audioPlayer.stop()                // stop the recording player so they don't overlap
            speaker.speak(memory.narrative)
        }
    }

    private func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    /// Resolves the audio to play for a memory.
    /// PLACEHOLDER until GET /api/v1/memories/{id}/audio: the real implementation will
    /// download the memory's audio from the backend using the memory's server id
    /// (SampleMemory currently only has a client-side UUID, not a server id).
    /// For now, play the most-recent local recording in Documents/Recordings/, or nil.
    private func resolveMemoryAudioURL(for memory: SampleMemory) -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    private var askCard: some View {
        Button { showAsk = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.18))
                    CompassMark(color: WV.gold).frame(width: 22, height: 22)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask \(companion)")
                        .font(.serif(19)).foregroundStyle(.white)
                    Text("Talk through this memory together.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(WV.teal, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: WV.teal.opacity(0.35), radius: 14, y: 8)
        }
        .witnessPress(scale: 0.97)
    }
}

// Wrapping row layout: chips flow onto multiple lines and never exceed the proposed width, so an
// over-full people row can't drag the content column past the screen (fixes the vertical-bars +
// text-overflow bug). Each name uses lineLimit(1) so a single long name truncates, never wraps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            let w = min(s.width, maxWidth)
            if x > 0 && x + w > maxWidth { y += lineHeight + lineSpacing; x = 0; lineHeight = 0 }
            x += w + spacing
            lineHeight = max(lineHeight, s.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: usedWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            let w = min(s.width, maxWidth)
            if x > bounds.minX && x + w > bounds.minX + maxWidth {
                y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: s.height))
            x += w + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
