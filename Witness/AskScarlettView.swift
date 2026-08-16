import SwiftUI
import Combine

// MARK: - Session engine (start → turn loop → end, with 404-restart resilience)
@MainActor
final class WitnessSessionViewModel: ObservableObject {
    enum Phase: Equatable { case starting, idle, sending, ending, ended, failed(String) }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var phase: Phase = .starting
    @Published private(set) var reconnecting = false     // subtle "Reconnecting…" during a 404 restart
    @Published private(set) var errorText: String?       // soft, retryable turn failure
    @Published private(set) var summary: String?

    private var sessionId: String?
    private var conversationId: String?
    private var memoryId: String?
    private var pendingRetry: String?

    var canSend: Bool { phase == .idle }
    private enum SessionError: Error { case sessionEnded, badResponse }

    func failStart(_ message: String) { phase = .failed(message) }

    // MARK: Start (heavy — graph + Gemini)
    func start(memoryId: String, auth: AuthManager) async {
        self.memoryId = memoryId
        phase = .starting; errorText = nil
        do {
            let r = try await withAuth(auth) { try await self.postStart(memoryId) }
            guard let sid = r.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
            sessionId = sid; conversationId = r.conversationId
            let opening = (r.openingMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !opening.isEmpty { messages.append(ChatMessage(role: .companion, text: opening)) }
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            #if DEBUG
            print("🩺[WitnessStart] caught: \(error)")
            #endif
            phase = .failed("We couldn’t start the conversation. Please check your connection and try again.")
        }
    }
    func retryStart(auth: AuthManager) async {
        guard let m = memoryId else { return }
        messages.removeAll(); summary = nil; errorText = nil
        await start(memoryId: m, auth: auth)
    }

    // MARK: Start — whole-life open mode (Talk tab). Posts body {} (no memory_id) and seeds a CLIENT greeting;
    // the backend opening_message is intentionally discarded. memoryId stays nil → drives postStartCurrent().
    func startWholeLife(greeting: String, auth: AuthManager) async {
        if messages.isEmpty && !greeting.isEmpty { messages.append(ChatMessage(role: .companion, text: greeting)) }
        self.memoryId = nil
        phase = .starting; errorText = nil
        do {
            let r = try await withAuth(auth) { try await self.postStartWholeLife() }
            guard let sid = r.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
            sessionId = sid; conversationId = r.conversationId
            // r.openingMessage intentionally discarded — the client greeting is already shown.
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            #if DEBUG
            print("🩺[WitnessStart] caught: \(error)")
            #endif
            phase = .failed("We couldn’t start the conversation. Please check your connection and try again.")
        }
    }
    func retryStartWholeLife(auth: AuthManager) async {
        // keep the greeting already on screen; just retry the session start
        await startWholeLife(greeting: "", auth: auth)
    }

    // MARK: Reset — for the Talk tab's "Start a new conversation" after end() (a tab can't be dismissed).
    func reset() {
        messages.removeAll(); summary = nil; errorText = nil; pendingRetry = nil
        sessionId = nil; conversationId = nil; memoryId = nil; phase = .starting
    }

    // MARK: Send a turn (debounced; one at a time)
    func send(_ text: String, auth: AuthManager) async {
        let content = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10000))
        guard !content.isEmpty, canSend else { return }
        messages.append(ChatMessage(role: .user, text: content))
        await attemptTurn(content, auth: auth)
    }
    func retryLast(auth: AuthManager) async { if let c = pendingRetry { await attemptTurn(c, auth: auth) } }

    private func attemptTurn(_ content: String, auth: AuthManager) async {
        phase = .sending; errorText = nil; pendingRetry = nil
        do {
            let r = try await turnWithRestart(content, auth: auth)
            let reply = (r.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(ChatMessage(role: .companion, text: reply.isEmpty ? "…" : reply))
            phase = .idle
        } catch SessionError.sessionEnded {
            phase = .failed("Your session has ended. Please sign in again.")
        } catch {
            pendingRetry = content
            errorText = "That didn’t go through. Tap to try again."
            phase = .idle
        }
    }

    /// ONE transparent restart+replay on a 404 (session died — backend restart). Capped at one per send:
    /// a second 404 propagates and surfaces as a soft retryable failure. Prior context is safe server-side.
    private func turnWithRestart(_ content: String, auth: AuthManager) async throws -> WitnessTurnResponse {
        do {
            return try await withAuth(auth) { try await self.postTurn(content) }
        } catch APIError.http(let status, _) where status == 404 {
            reconnecting = true; defer { reconnecting = false }
            let s = try await withAuth(auth) { try await self.postStartCurrent() }
            guard let sid = s.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
            sessionId = sid; conversationId = s.conversationId
            // Do NOT append the fresh opening_message — we're mid-conversation.
            return try await withAuth(auth) { try await self.postTurn(content) }
        }
    }

    // MARK: End (best-effort — never traps the user)
    func end(auth: AuthManager) async {
        guard sessionId != nil, phase == .idle else { if phase != .ended { phase = .ended }; return }
        phase = .ending
        do {
            let r = try await endWithRestart(auth: auth)
            let closing = (r.closingMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !closing.isEmpty { messages.append(ChatMessage(role: .companion, text: closing)) }
            let s = (r.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            summary = s.isEmpty ? nil : s
        } catch {
            // best-effort: finalize locally regardless (the user is done).
        }
        phase = .ended
    }
    private func endWithRestart(auth: AuthManager) async throws -> WitnessEndResponse {
        do {
            return try await withAuth(auth) { try await self.postEnd() }
        } catch APIError.http(let status, _) where status == 404 {
            reconnecting = true; defer { reconnecting = false }
            let s = try await withAuth(auth) { try await self.postStartCurrent() }
            guard let sid = s.sessionId, !sid.isEmpty else { throw SessionError.badResponse }
            sessionId = sid
            return try await withAuth(auth) { try await self.postEnd() }
        }
    }

    // MARK: 401 → refresh → retry-once
    private func withAuth<T>(_ auth: AuthManager, _ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch APIError.unauthorized(_, let code) {
            if await auth.handleUnauthorized(code: code) { return try await op() }
            throw SessionError.sessionEnded
        }
    }

    // MARK: Raw calls
    private func postStart(_ memoryId: String) async throws -> WitnessStartResponse {
        try await APIClient.shared.post("/api/v1/jarvis/witness/sessions",
            body: WitnessStartRequest(memoryId: memoryId, voiceMode: false), timeout: 60, as: WitnessStartResponse.self)
    }
    private func postStartWholeLife() async throws -> WitnessStartResponse {
        try await APIClient.shared.post("/api/v1/jarvis/witness/sessions",
            body: EmptyBody(), timeout: 60, as: WitnessStartResponse.self)   // {} → open mode
    }
    /// Restart in the CURRENT mode: memory-scoped when a memoryId is set, else whole-life (empty body).
    private func postStartCurrent() async throws -> WitnessStartResponse {
        if let memoryId { return try await postStart(memoryId) }
        return try await postStartWholeLife()
    }
    private func postTurn(_ content: String) async throws -> WitnessTurnResponse {
        guard let sessionId else { throw SessionError.badResponse }
        return try await APIClient.shared.post("/api/v1/jarvis/witness/sessions/\(sessionId)/turns",
            body: WitnessTurnRequest(content: content), timeout: 45, as: WitnessTurnResponse.self)
    }
    private func postEnd() async throws -> WitnessEndResponse {
        guard let sessionId else { throw SessionError.badResponse }
        return try await APIClient.shared.post("/api/v1/jarvis/witness/sessions/\(sessionId)/end",
            body: EmptyBody(), timeout: 45, as: WitnessEndResponse.self)
    }
}

// MARK: - Memory-scoped Ask Scarlett screen
struct AskScarlettView: View {
    let memory: MemoryDetailDTO?
    @ObservedObject var auth: AuthManager
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = WitnessSessionViewModel()
    @State private var draft = ""
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
    }

    private func begin() async {
        guard vm.messages.isEmpty, vm.phase == .starting else { return }
        guard let id = memory?.id, !id.isEmpty else { vm.failStart("This memory isn’t ready for a conversation yet."); return }
        await vm.start(memoryId: id, auth: auth)
    }

    // Header: close · name · End/Done
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.6)).frame(width: 44, height: 44)
            }.witnessPress()
            Spacer()
            VStack(spacing: 2) {
                Text("\(companion.uppercased())  ✦").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
                Text("Ask \(companion)").font(.serif(20)).foregroundStyle(WV.teal)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
    }
    @ViewBuilder private var trailing: some View {
        if vm.phase == .ended {
            Button { dismiss() } label: { Text("Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(WV.teal).frame(width: 60, height: 44) }.witnessPress()
        } else {
            Button { Task { await vm.end(auth: auth) } } label: { Text("End").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)).frame(width: 60, height: 44) }
                .witnessPress().disabled(vm.phase == .starting || vm.phase == .ending)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if case .failed(let msg) = vm.phase, vm.messages.isEmpty {
                        startFailed(msg)
                    } else {
                        ForEach(vm.messages) { m in
                            Group {
                                if m.role == .companion { CompanionBubble(text: m.text, name: companion) } else { UserBubble(text: m.text) }
                            }.id(m.id)
                        }
                        if vm.reconnecting { reconnectingRow.id("status") }
                        else if vm.phase == .starting || vm.phase == .sending || vm.phase == .ending { thinkingRow.id("status") }
                        if vm.phase == .ended, let s = vm.summary { summaryRow(s) }
                        if let e = vm.errorText { errorRow(e) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages) { _, _ in bump(proxy) }
            .onChange(of: vm.phase) { _, _ in bump(proxy) }
            .onChange(of: vm.reconnecting) { _, _ in bump(proxy) }
        }
    }
    private func bump(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if vm.reconnecting || vm.phase == .starting || vm.phase == .sending || vm.phase == .ending {
                proxy.scrollTo("status", anchor: .bottom)
            } else {
                proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            Text("\(companion.uppercased())  ✦").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold.opacity(0.7))
            Text(vm.phase == .ending ? "reflecting…" : "thinking with you…").font(.serif(15)).italic().foregroundStyle(WT.ink.opacity(0.45))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var reconnectingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(WV.teal)
            Text("Reconnecting…").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.45))
        }.frame(maxWidth: .infinity, alignment: .leading)
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
    private func startFailed(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.3))
            Text(msg).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { Task { await vm.retryStart(auth: auth) } } label: {
                Text("Try again").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 48).background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
            }.witnessPress()
        }.padding(.top, 60).padding(.horizontal, 24)
    }

    @ViewBuilder private var footer: some View {
        if vm.phase == .ended {
            Text("Saved. \(companion) will remember this.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
        } else if case .failed = vm.phase, vm.messages.isEmpty {
            EmptyView()   // start-failure handles its own retry
        } else {
            composer
        }
    }
    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical).lineLimit(1...5).font(.system(size: 16)).focused($composerFocused).tint(WV.teal)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                .disabled(!vm.canSend)
            Button { sendTapped() } label: {
                ZStack { Circle().fill(WV.teal); Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white) }
                    .frame(width: 52, height: 52).shadow(color: WV.teal.opacity(0.3), radius: 8, y: 4)
            }
            .witnessPress().disabled(!canSendNow).opacity(canSendNow ? 1 : 0.4)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
    }
    private var canSendNow: Bool { vm.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func sendTapped() {
        let t = draft; draft = ""; composerFocused = false
        Task { await vm.send(t, auth: auth) }
    }
}
