import SwiftUI

struct MemoryDetailView: View {
    let listItem: MemoryDTO                       // from the list: id (to fetch) + instant header
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @StateObject private var vm = MemoryDetailViewModel()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var speaker = Speaker()
    @State private var audioURL: URL?
    @State private var showAsk = false

    // Set true once a memory carries a real cover photo; none today.
    private var hasCoverPhoto: Bool { false }

    private var displayTitle: String { vm.detail?.title ?? listItem.title ?? "Untitled memory" }
    private var displayDate: String { MemoryFormat.date(listItem) }
    // Text spoken by Read aloud: the full narrative once loaded, else the list snippet.
    private var spokenText: String { vm.detail?.narrative ?? listItem.narrativeSnippet ?? "" }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()

            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cover
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        switch vm.state {
                        case .idle, .loading: loadingBlock
                        case .failed(let m):  failedBlock(m)
                        case .loaded:         loadedBody
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, hasCoverPhoto ? 6 : 22)
                    .padding(.bottom, 110)  // clears the tab bar so the Ask card is fully visible
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .ignoresSafeArea(edges: .top)
            .onChange(of: speaker.currentParagraph) { _, idx in
                guard let idx else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.paraID(idx), anchor: .center) }
            }
            }

            topControls
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load(id: listItem.id, auth: auth) }
        .onAppear {
            audioURL = resolveMemoryAudioURL()
            if let url = audioURL { audioPlayer.load(url) }
        }
        .onDisappear { audioPlayer.stop(); speaker.stop() }
        .sheet(isPresented: $showAsk) {
            // Memory-scoped "Ask Scarlett" — opens TalkView about this memory (real server id + title).
            TalkView(memory: vm.detail)
        }
    }

    // MARK: - Header (instant from the list item)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayDate.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1.5)
                .foregroundStyle(WV.gold)
            Text(displayTitle)
                .font(.serif(30)).foregroundStyle(WT.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let people = vm.detail?.people, !people.isEmpty { peopleChips(people) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loaded body

    private var loadedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Playback controls live ABOVE the narrative so they're reachable without scrolling a
            // very large memory. Read aloud (on-device TTS of the written words) + the recording player.
            readAloudControl
            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
            if audioURL != nil {
                listenPlayer
            } else {
                Text("No recording to play yet.")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.4))
            }

            narrative

            if let emotions = vm.detail?.emotions, !emotions.isEmpty { emotionsSection(emotions) }
            if let quotes = vm.detail?.quotes, !quotes.isEmpty { quotesSection(quotes) }

            askCard.padding(.top, 4)
        }
    }

    // MARK: - Narrative (lazy, chunked — scales to any size, never blanks)

    // The narrative is pre-split (off the main thread) into paragraph-sized chunks. Rendering them as
    // individual Text views in a LazyVStack — with NO .fixedSize — means only near-viewport paragraphs
    // are laid out, so even the densest (~174K-char) narrative renders and scrolls without blanking.
    private var narrative: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(vm.paragraphs.enumerated()), id: \.offset) { i, para in
                Text(para)
                    .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(speaker.currentParagraph == i ? WV.teal.opacity(0.10) : .clear))
                    .id(Self.paraID(i))
                    .animation(.easeInOut(duration: 0.25), value: speaker.currentParagraph)
            }
        }
    }
    private static func paraID(_ i: Int) -> String { "para-\(i)" }

    // MARK: - Emotions

    private func emotionsSection(_ items: [MemoryEmotion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Emotions")
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, e in
                    emotionRow(e)
                }
            }
        }
        .padding(.top, 4)
    }

    private func emotionRow(_ e: MemoryEmotion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(WV.teal)
                Text((e.emotionType ?? "—").capitalized)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.85))
                Spacer(minLength: 8)
                if let intensity = e.intensity { intensityDots(intensity) }
            }
            if let trigger = e.triggerDescription, !trigger.isEmpty {
                Text(trigger)
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    // Normalizes an intensity that may be 0–1 or 0–10 into five dots.
    private func intensityDots(_ raw: Double) -> some View {
        let scaled = raw <= 1.0 ? raw * 5.0 : raw / 2.0
        let filled = max(0, min(5, Int(scaled.rounded())))
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < filled ? WV.teal : WT.ink.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Quotes

    private func quotesSection(_ items: [MemoryQuote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Quotes")
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, q in
                    quoteRow(q)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func quoteRow(_ q: MemoryQuote) -> some View {
        let text = (q.quoteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(WV.teal.opacity(0.5)).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(text)”")
                        .font(.serif(17)).italic().foregroundStyle(WT.ink.opacity(0.85))
                        .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    if let attribution = quoteAttribution(q) {
                        Text(attribution)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.5))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        }
    }

    private func quoteAttribution(_ q: MemoryQuote) -> String? {
        var parts: [String] = []
        if let s = q.speakerName, !s.isEmpty { parts.append("— \(s)") }
        if let t = q.emotionalTone, !t.isEmpty { parts.append(t.capitalized) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: - Loading / failed

    private var loadingBlock: some View {
        VStack(spacing: 14) {
            ProgressView().tint(WV.teal)
            Text("Gathering this memory…")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func failedBlock(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(WT.ink.opacity(0.3))
            Text("Couldn’t load this memory").font(.serif(22)).foregroundStyle(WV.teal)
            Text(message)
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24)
            Button { Task { await vm.retry(id: listItem.id, auth: auth) } } label: {
                Text("Try again")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 50)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold)).tracking(1.5)
            .foregroundStyle(WV.gold)
    }

    // With a photo: a tall cover that dissolves into the page. Without: a slim band of color.
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

    private func peopleChips(_ people: [MemoryPerson]) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, p in
                let name = (p.canonicalName ?? "").trimmingCharacters(in: .whitespaces)
                let anchor = p.isAnchor == true
                if !name.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: anchor ? "mappin.circle.fill" : "person.fill")
                            .font(.system(size: 12)).foregroundStyle(anchor ? WV.gold : WV.teal)
                        Text(name)
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background((anchor ? WV.gold : WV.teal).opacity(0.10), in: Capsule())
                }
            }
        }
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

    // Read aloud: speaks the memory's WRITTEN text via on-device TTS. Distinct from "Listen"
    // (original audio recording). Tap toggles read → pause → resume.
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
        .disabled(vm.paragraphs.isEmpty && spokenText.isEmpty)
        .opacity(vm.paragraphs.isEmpty && spokenText.isEmpty ? 0.45 : 1)
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
    // Simple progress sense while reading: "Reading N of M" + a thin bar. Shown only during playback.
    private var readAloudProgress: some View {
        let n = (speaker.currentParagraph ?? 0) + 1
        let m = max(speaker.paragraphCount, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Reading \(n) of \(m)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.1))
                    Capsule().fill(WV.teal).frame(width: geo.size.width * CGFloat(n) / CGFloat(m))
                }
            }
            .frame(height: 4)
        }
    }

    private func toggleReadAloud() {
        if speaker.isPaused { speaker.resume() }
        else if speaker.isSpeaking { speaker.pause() }
        else {
            audioPlayer.stop()                // mutual exclusion with the recording player
            if !vm.paragraphs.isEmpty { speaker.speak(paragraphs: vm.paragraphs) }
            else if !spokenText.isEmpty { speaker.speak(spokenText) }   // snippet before detail loads
        }
    }

    private func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    /// Resolves the audio to play for a memory.
    /// PLACEHOLDER until GET /api/v1/memories/{id}/audio: for now, play the most-recent local
    /// recording in Documents/Recordings/, or nil.
    private func resolveMemoryAudioURL() -> URL? {
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
