import SwiftUI

// MARK: - Talk: open conversation (Door #3). Built to design spec §3.5.
// Greeting is client-side (instant). Turns/anchor-gate are sampled; real endpoints noted.
//   POST /api/v1/jarvis/witness/sessions {}                  -> session, opening_message
//   POST /api/v1/jarvis/witness/sessions/{id}/turns {content} -> response, discoveries?, new_entities?
//   POST /api/v1/jarvis/witness/sessions/{id}/end             -> closing_message, summary
//   Auth: Bearer <keychain vivid_token>
struct TalkView: View {
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    // Memory-scoped "Ask Scarlett": nil = the standalone Talk tab (unchanged).
    var memory: SampleMemory? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var thinking = false
    @State private var showAnchorGate = false
    @State private var gateUsed = false
    @State private var pendingDiscovery = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            ParchmentBackground()
            VStack(spacing: 0) {
                header
                conversation
                composer
            }
        }
        .onAppear {
            if messages.isEmpty { messages = [ChatMessage(role: .companion, text: openingText())] }
            // PLACEHOLDER — backend already implements this; connect later:
            //   POST /api/v1/jarvis/witness/sessions { memory_id: <server id> }
            // Uses memory?.id (client-side UUID today; becomes the server memory id once
            // memories load from the backend). No network call here yet.
        }
        .sheet(isPresented: $showAnchorGate) { anchorGate }
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(companion.uppercased())  ✦")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(WV.gold)
                Text("Talk").font(.serif(22)).foregroundStyle(WV.teal)
            }
            Spacer()
            Button { saveAndExit() } label: {
                Text("Save & exit")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WT.ink.opacity(0.55))
            }
            .witnessPress()
            .witnessHint("Ends this conversation and saves it. \(companion) reflects on what you shared.")
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: Conversation
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(messages) { m in
                        Group {
                            if m.role == .companion { CompanionBubble(text: m.text, name: companion) }
                            else { UserBubble(text: m.text) }
                        }
                        .id(m.id)
                    }
                    if thinking { thinkingRow.id("thinking") }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: thinking) { _, t in
                if t { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            Text("\(companion.uppercased())  ✦")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold.opacity(0.7))
            Text("thinking with you…")
                .font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Composer (voice-first)
    private var composer: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .tint(WV.teal)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(WT.ink.opacity(0.12), lineWidth: 1))

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { /* TODO: hold-to-speak -> on-device capture, then send transcript */ } label: {
                    circleIcon("mic.fill")
                }
                .witnessPress()
                .witnessHint("Hold to speak your message; tap the box to type instead.")
            } else {
                Button { send() } label: { circleIcon("arrow.up", weight: .semibold) }
                    .witnessPress()
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(
            WV.parchment.overlay(alignment: .top) {
                Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1)
            }
        )
    }

    private func circleIcon(_ name: String, weight: Font.Weight = .regular) -> some View {
        ZStack {
            Circle().fill(WV.teal)
            Image(systemName: name).font(.system(size: 20, weight: weight)).foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .shadow(color: WV.teal.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: Anchor gate — "Shall I remember this?" (never silent; the human confirms).
    private var anchorGate: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            CompassMark(color: WV.gold).frame(width: 34, height: 34).padding(.top, 4)
            Text("Shall I remember this?").font(.serif(24)).foregroundStyle(WV.teal)
            Text("\(companion) noticed something worth keeping. Nothing is saved unless you say so.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6))
                .multilineTextAlignment(.center).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(WV.gold)
                Text(pendingDiscovery).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                Spacer()
            }
            .padding(15)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 24).padding(.top, 4)

            VStack(spacing: 10) {
                Button { showAnchorGate = false /* Real: confirm -> persist the anchor */ } label: {
                    Text("Remember this")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .witnessPress()
                Button { showAnchorGate = false /* discard — nothing persists */ } label: {
                    Text("Not now")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }
                .witnessPress()
            }
            .padding(.horizontal, 24).padding(.top, 4)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .background(WV.parchment)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: Logic
    // Opening line: memory-scoped when launched from a memory's "Ask Scarlett", else the
    // standalone Talk greeting. The real loop — Scarlett's questions, voice answers
    // (record↔playback), transcription of both sides, transcript (text) storage, dedup so a
    // question is never re-asked, and knowledge-graph enrichment — all live on the backend
    // and connect later. This is the front-end shell only.
    private func openingText() -> String {
        if let memory {
            return "Let's talk about “\(memory.title).” What comes back to you when you return to it?"
        }
        return greetingText()
    }

    private func greetingText() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let when: String
        switch h {
        case 5..<12:  when = "this morning"
        case 12..<17: when = "this afternoon"
        case 17..<22: when = "this evening"
        default:      when = "tonight"
        }
        let invitations = [
            "What's on your mind \(when)?",
            "Where would you like to begin \(when)?",
            "Tell me what you're thinking about \(when).",
            "Is there a memory pulling at you \(when)?",
            "What would you like to talk through \(when)?"
        ]
        return invitations.randomElement() ?? invitations[0]
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        composerFocused = false
        thinking = true
        // Real: POST /api/v1/jarvis/witness/sessions/{id}/turns { content: text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            thinking = false
            messages.append(ChatMessage(role: .companion, text: sampleReply()))
            // Real: if response.discoveries / new_entities present -> open the gate (never silent).
            if !gateUsed {
                gateUsed = true
                pendingDiscovery = "A new person you mentioned"
                showAnchorGate = true
            }
        }
    }

    private func sampleReply() -> String {
        [
            "That stays with you, I can tell. What happened next?",
            "I'm here for it — tell me more about that.",
            "Say more. What did that feel like in the moment?"
        ].randomElement() ?? "Tell me more."
    }

    private func saveAndExit() {
        // Real: POST /api/v1/jarvis/witness/sessions/{id}/end
        composerFocused = false
        thinking = false
        gateUsed = false
        withAnimation { messages = [ChatMessage(role: .companion, text: greetingText())] }
        dismiss()   // dismisses the memory-scoped sheet; no-op when this is the Talk tab
    }
}

// MARK: - Chat model + bubbles (component-inventory names from spec §4).
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    enum Role { case companion, user }
    let role: Role
    let text: String
}

struct CompanionBubble: View {
    let text: String
    let name: String
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 20,
                               bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(name.uppercased())  ✦")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(WV.gold)
            Text(text)
                .font(.serif(17)).foregroundStyle(WT.ink.opacity(0.9))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(hex: 0xfaf7f0), in: shape)
        .overlay(shape.stroke(WT.ink.opacity(0.06), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 36)
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 16)).foregroundStyle(WT.ink)
            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(WV.teal.opacity(0.35), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 36)
    }
}
