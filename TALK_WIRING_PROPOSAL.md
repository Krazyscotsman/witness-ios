# Witness — Wire the real whole-life Talk (reuse WitnessSessionViewModel, open mode) — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** Same witness endpoints as Ask Scarlett; no Talk API.

## Read-first
- Mock TalkView: @State messages/thinking; header "Save & exit"; composer mic(stub)+send; onAppear seeds
  greeting; `send()` = fake 1.3s + `sampleReply()` (the repeating canned lines); `saveAndExit()` resets +
  dismiss (no-op in tab); fake `anchorGate` sheet. `memory: MemoryDetailDTO?` exists but `TalkView()` is only
  built whole-life (MainTabView:41) — memory-scoped is AskScarlettView.
- WitnessSessionViewModel: `start(memoryId:)` posts WitnessStartRequest{memory_id,voice_mode}. Whole-life needs
  body `{}` → small additive tweak (whole-life start posting EmptyBody + mode-aware 404 restart). turn/end/401/
  restart-replay reused unchanged.
- TalkView has NO auth (built as `TalkView()`); MainTabView has auth.
- First name IS stored: `@AppStorage(Profile.firstNameKey)` (YouView/Settings/Onboarding) → greeting can use it.

## Decisions (recommended; change any)
1. Reuse WitnessSessionViewModel (additive whole-life start + mode-aware restart + reset); no fork.
2. Remove the fake anchorGate (open mode purely conversational; ignore discoveries/new_entities).
3. Drop the unused `memory` param from TalkView (Ask Scarlett owns memory-scoped).
4. "Save & exit" → end() → show closing_message (+summary) + "Start a new conversation" (tab can't dismiss).

---

## WitnessSessionViewModel — additive changes (Ask Scarlett path unchanged)
```swift
// NEW: whole-life open-mode start — posts body {} and seeds a CLIENT greeting (discards backend opening_message).
func startWholeLife(greeting: String, auth: AuthManager) async {
    if messages.isEmpty && !greeting.isEmpty { messages.append(ChatMessage(role: .companion, text: greeting)) }
    self.memoryId = nil                       // nil == whole-life (drives postStartCurrent on restart)
    phase = .starting; errorText = nil
    do {
        let r = try await withAuth(auth) { try await self.postStartWholeLife() }
        guard let sid = r.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
        sessionId = sid; conversationId = r.conversationId
        // r.openingMessage intentionally discarded — client greeting already shown.
        phase = .idle
    } catch SessionError.sessionEnded {
        phase = .failed("Your session has ended. Please sign in again.")
    } catch {
        phase = .failed("We couldn’t start the conversation. Please check your connection and try again.")
    }
}
func retryStartWholeLife(auth: AuthManager) async {
    // keep the greeting already on screen; just retry the session start
    await startWholeLife(greeting: "", auth: auth)
}

// NEW: reset for the Talk tab's "Start a new conversation" after end().
func reset() {
    messages.removeAll(); summary = nil; errorText = nil; pendingRetry = nil
    sessionId = nil; conversationId = nil; memoryId = nil; phase = .starting
}

// NEW raw call + mode-aware restart source
private func postStartWholeLife() async throws -> WitnessStartResponse {
    try await APIClient.shared.post("/api/v1/jarvis/witness/sessions", body: EmptyBody(), timeout: 60, as: WitnessStartResponse.self)
}
private func postStartCurrent() async throws -> WitnessStartResponse {
    if let memoryId { return try await postStart(memoryId) }   // memory-scoped (Ask Scarlett)
    return try await postStartWholeLife()                      // whole-life (Talk)
}
```
```diff
     private func turnWithRestart(_ content: String, auth: AuthManager) async throws -> WitnessTurnResponse {
         do {
             return try await withAuth(auth) { try await self.postTurn(content) }
         } catch APIError.http(let status, _) where status == 404 {
-            guard let memoryId else { throw SessionError.badResponse }
             reconnecting = true; defer { reconnecting = false }
-            let s = try await withAuth(auth) { try await self.postStart(memoryId) }
+            let s = try await withAuth(auth) { try await self.postStartCurrent() }
             guard let sid = s.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
             sessionId = sid; conversationId = s.conversationId
             return try await withAuth(auth) { try await self.postTurn(content) }
         }
     }
     private func endWithRestart(auth: AuthManager) async throws -> WitnessEndResponse {
         do {
             return try await withAuth(auth) { try await self.postEnd() }
         } catch APIError.http(let status, _) where status == 404 {
-            guard let memoryId else { throw SessionError.badResponse }
             reconnecting = true; defer { reconnecting = false }
-            let s = try await withAuth(auth) { try await self.postStart(memoryId) }
+            let s = try await withAuth(auth) { try await self.postStartCurrent() }
             guard let sid = s.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
             sessionId = sid
             return try await withAuth(auth) { try await self.postEnd() }
         }
     }
```
(Ask Scarlett is unaffected: memoryId is always set there → postStartCurrent → postStart(memoryId). Only whole-life
uses the empty-body path. `EmptyBody` already exists in APIModels; encodes `{}`.)

## TalkView.swift — rewrite (real engine; keep ChatMessage/CompanionBubble/UserBubble unchanged)
```swift
struct TalkView: View {
    @ObservedObject var auth: AuthManager
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @AppStorage(Profile.firstNameKey) private var firstName: String = ""
    @StateObject private var vm = WitnessSessionViewModel()
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            ParchmentBackground()
            VStack(spacing: 0) { header; conversation; footer }
        }
        .task { await begin() }
    }

    private func begin() async {
        guard vm.messages.isEmpty, vm.phase == .starting else { return }
        await vm.startWholeLife(greeting: greeting(), auth: auth)
    }
    private func newConversation() { vm.reset(); Task { await begin() } }

    // Client greeting — instant, time-synced, first name if present (matches web).
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let daypart = h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
        let name = firstName.trimmingCharacters(in: .whitespaces)
        let named = name.isEmpty ? "" : ", \(name)"
        let invitations = [
            "What’s on your mind?", "Where would you like to begin?",
            "Is there a memory pulling at you today?", "What would you like to talk through?",
            "Tell me what you’re thinking about."
        ]
        return "\(daypart)\(named). How are you? \(invitations.randomElement() ?? invitations[0])"
    }

    // Header: companion · Talk · Save & exit (End)
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(companion.uppercased())  ✦").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
                Text("Talk").font(.serif(22)).foregroundStyle(WV.teal)
            }
            Spacer()
            if vm.phase == .ended {
                Button { newConversation() } label: { Text("New").font(.system(size: 14, weight: .semibold)).foregroundStyle(WV.teal) }.witnessPress()
            } else {
                Button { Task { await vm.end(auth: auth) } } label: { Text("Save & exit").font(.system(size: 14, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)) }
                    .witnessPress().disabled(vm.phase == .starting || vm.phase == .ending)
                    .witnessHint("Ends this conversation and saves it. \(companion) reflects on what you shared.")
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(vm.messages) { m in
                        Group { if m.role == .companion { CompanionBubble(text: m.text, name: companion) } else { UserBubble(text: m.text) } }.id(m.id)
                    }
                    if vm.reconnecting { reconnectingRow.id("status") }
                    else if vm.phase == .sending || vm.phase == .ending { thinkingRow.id("status") }
                    if vm.phase == .ended, let s = vm.summary { summaryRow(s) }
                    if let e = vm.errorText { errorRow(e) }
                    if case .failed(let m) = vm.phase { startRetryRow(m) }        // whole-life start failure
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
            if vm.reconnecting || vm.phase == .sending || vm.phase == .ending { proxy.scrollTo("status", anchor: .bottom) }
            else { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
        }
    }

    private var thinkingRow: some View { /* companion label + (ending ? "reflecting…" : "thinking with you…") */ }
    private var reconnectingRow: some View { /* ProgressView + "Reconnecting…" */ }
    private func summaryRow(_ s: String) -> some View { /* italic centered summary */ }
    private func errorRow(_ e: String) -> some View { /* tappable retry → vm.retryLast(auth) */ }
    private func startRetryRow(_ m: String) -> some View { /* message + "Try again" → vm.retryStartWholeLife(auth) */ }

    // Footer: composer (mic stub + send) — or, when ended, a saved note.
    @ViewBuilder private var footer: some View {
        if vm.phase == .ended {
            Text("Saved. \(companion) will remember this.").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
        } else if case .failed = vm.phase { EmptyView() }   // startRetryRow handles retry
        else { composer }
    }
    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical).font(.system(size: 16)).lineLimit(1...4).focused($composerFocused).tint(WV.teal)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                .disabled(!vm.canSend)
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { /* TODO: hold-to-speak (voice deferred) */ } label: { circleIcon("mic.fill") }
                    .witnessPress().witnessHint("Voice is coming soon — tap the box to type.")
            } else {
                Button { sendTapped() } label: { circleIcon("arrow.up", weight: .semibold) }.witnessPress().disabled(!vm.canSend)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
    }
    private func sendTapped() { let t = draft; draft = ""; composerFocused = false; Task { await vm.send(t, auth: auth) } }
    private func circleIcon(_ name: String, weight: Font.Weight = .regular) -> some View { /* unchanged teal circle */ }
}
// ChatMessage / CompanionBubble / UserBubble: UNCHANGED (still defined here; reused by AskScarlettView).
```
REMOVED from TalkView: `memory` param, `openingText`, old `greetingText`, `send()` fake, `sampleReply()`,
`saveAndExit()`, `anchorGate` + showAnchorGate/gateUsed/pendingDiscovery.

## MainTabView.swift — pass auth
```diff
-            case .talk:     TalkView()
+            case .talk:     TalkView(auth: auth)
```

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live whole-life session (empty-body start, real turns,
closing on Save & exit, 404 restart, honest retry) is a device/backend check. Voice/mic deferred (stub);
no save-as-anchor (endpoint doesn't exist). No git.
