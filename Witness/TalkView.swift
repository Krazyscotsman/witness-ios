import SwiftUI

// MARK: - Talk: open, whole-life conversation (Door #3). Real Jarvis witness session in OPEN mode, via the
// shared WitnessSessionViewModel. Greeting is client-composed (instant, discards the backend opening_message).
//   POST /api/v1/jarvis/witness/sessions {}                    -> session (opening_message discarded)
//   POST /api/v1/jarvis/witness/sessions/{id}/turns {content}  -> response
//   POST /api/v1/jarvis/witness/sessions/{id}/end              -> closing_message, summary
// Voice/mic deferred (stub). Open mode is purely conversational — no save-as-anchor (endpoint doesn't exist).
struct TalkView: View {
    @ObservedObject var auth: AuthManager
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @AppStorage(Profile.firstNameKey) private var firstName: String = ""
    @StateObject private var vm = WitnessSessionViewModel()
    @State private var draft = ""
    @State private var showHistory = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            ParchmentBackground()
            VStack(spacing: 0) {
                header
                conversation
                footer
            }
        }
        .task { await begin() }
        .sheet(isPresented: $showHistory) { ConversationHistoryView(scope: .talk, auth: auth) }
    }

    private func begin() async {
        guard vm.messages.isEmpty, vm.phase == .starting else { return }
        await vm.startWholeLife(greeting: greeting(), auth: auth)
    }
    private func newConversation() { vm.reset(); Task { await begin() } }

    // Client greeting — instant, time-synced, first name if present.
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let daypart = h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
        let name = firstName.trimmingCharacters(in: .whitespaces)
        let named = name.isEmpty ? "" : ", \(name)"
        let invitations = [
            "What’s on your mind?",
            "Where would you like to begin?",
            "Is there a memory pulling at you today?",
            "What would you like to talk through?",
            "Tell me what you’re thinking about."
        ]
        return "\(daypart)\(named). How are you? \(invitations.randomElement() ?? invitations[0])"
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
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress().witnessHint("Review past conversations with \(companion).")
            if vm.phase == .ended {
                Button { newConversation() } label: {
                    Text("New").font(.system(size: 14, weight: .semibold)).foregroundStyle(WV.teal)
                }.witnessPress().witnessHint("Start a fresh conversation with \(companion).")
            } else {
                Button { Task { await vm.end(auth: auth) } } label: {
                    Text("Save & exit").font(.system(size: 14, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55))
                }
                .witnessPress()
                .disabled(vm.phase == .starting || vm.phase == .ending)
                .witnessHint("Ends this conversation and saves it. \(companion) reflects on what you shared.")
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: Conversation
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(vm.messages) { m in
                        Group {
                            if m.role == .companion { CompanionBubble(text: m.text, name: companion) }
                            else { UserBubble(text: m.text) }
                        }
                        .id(m.id)
                    }
                    if vm.reconnecting { reconnectingRow.id("status") }
                    else if vm.phase == .sending || vm.phase == .ending { thinkingRow.id("status") }
                    if vm.phase == .ended, let s = vm.summary { summaryRow(s) }
                    if let e = vm.errorText { errorRow(e) }
                    if case .failed(let m) = vm.phase { startRetryRow(m) }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages) { _, _ in bump(proxy) }
            .onChange(of: vm.phase) { _, _ in bump(proxy) }
            .onChange(of: vm.reconnecting) { _, _ in bump(proxy) }
        }
    }
    private func bump(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if vm.reconnecting || vm.phase == .sending || vm.phase == .ending {
                proxy.scrollTo("status", anchor: .bottom)
            } else {
                proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            Text("\(companion.uppercased())  ✦")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold.opacity(0.7))
            Text(vm.phase == .ending ? "reflecting…" : "thinking with you…")
                .font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var reconnectingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(WV.teal)
            Text("Reconnecting…").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func summaryRow(_ s: String) -> some View {
        Text(s).font(.serif(14)).italic().foregroundStyle(WT.ink.opacity(0.5))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.top, 6)
    }
    private func errorRow(_ e: String) -> some View {
        Button { Task { await vm.retryLast(auth: auth) } } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                Text(e).font(.system(size: 13, weight: .medium))
            }.foregroundStyle(WV.danger)
        }.frame(maxWidth: .infinity)
    }
    private func startRetryRow(_ m: String) -> some View {
        VStack(spacing: 10) {
            Text(m).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { Task { await vm.retryStartWholeLife(auth: auth) } } label: {
                Text("Try again").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).frame(height: 46).background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
            }.witnessPress()
        }
        .frame(maxWidth: .infinity).padding(.top, 24)
    }

    // MARK: Footer — composer (mic stub + send), or a saved note when ended
    @ViewBuilder private var footer: some View {
        if vm.phase == .ended {
            Text("Saved. \(companion) will remember this.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
        } else if case .failed = vm.phase {
            EmptyView()   // startRetryRow handles retry
        } else {
            composer
        }
    }
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
            .disabled(!vm.canSend)

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { /* TODO: hold-to-speak — voice deferred */ } label: { circleIcon("mic.fill") }
                    .witnessPress()
                    .witnessHint("Voice is coming soon — tap the box to type.")
            } else {
                Button { sendTapped() } label: { circleIcon("arrow.up", weight: .semibold) }
                    .witnessPress().disabled(!vm.canSend)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(
            WV.parchment.overlay(alignment: .top) {
                Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1)
            }
        )
    }
    private func sendTapped() {
        let t = draft; draft = ""; composerFocused = false
        Task { await vm.send(t, auth: auth) }
    }

    private func circleIcon(_ name: String, weight: Font.Weight = .regular) -> some View {
        ZStack {
            Circle().fill(WV.teal)
            Image(systemName: name).font(.system(size: 20, weight: weight)).foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .shadow(color: WV.teal.opacity(0.3), radius: 8, y: 4)
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
