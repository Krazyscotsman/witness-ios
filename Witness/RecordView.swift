import SwiftUI
import UIKit

// MARK: - Record: voice-first capture (design spec §3.3). Presented as a full-screen
// cover from Home and Memories (Record is not a tab). Inert; endpoints noted:
//   voice -> POST /memories/voice  (multipart `file`, optional title, memory_date)
//   text  -> POST /api/v1/memories
// Honest check: no fake level meter here; the real input-level meter binds to the
// audio engine in the voice-loop unit (§5). The elapsed timer below is real.
struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName

    @ObservedObject var auth: AuthManager
    /// Called once after a successful save so the presenter can refresh its list (e.g. Memories).
    var onSaved: (() -> Void)? = nil

    enum Mode: String, CaseIterable { case speak = "Speak", type = "Type", video = "Video" }
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var transcriber = Transcriber()   // on-device transcript for the review screen
    @StateObject private var saver = MemoryCreateViewModel()
    @StateObject private var videoVM = VideoCaptureViewModel()   // Video mode: extract audio → on-device transcribe

    // Capture → review (Speak) / compose (Type) → processing → done | failed.
    enum Stage: Equatable { case compose, reviewing, processing, done, failed(String) }
    @State private var stage: Stage = .compose
    @State private var sessionID = ""      // client-minted UUID, generated when capture begins
    @State private var reviewText = ""     // editable on-device transcript (Speak)

    @State private var mode: Mode = .speak
    @State private var title = ""
    @State private var dateText = ""
    @State private var bodyText = ""
    @State private var pendingVideoURL: URL?     // held until save, then linked to the memory id (local only)
    @State private var showVideoRecorder = false
    @State private var showVideoPicker = false

    private var availableModes: [Mode] {
        VideoCaptureViewModel.isSupported ? Mode.allCases : [.speak, .type]   // hide Video pre-iOS 26
    }
    // True while either transcription source is actively producing text (drives the review placeholder/status).
    private var isBusyTranscribing: Bool {
        if mode == .video { return videoVM.phase == .extracting || videoVM.phase == .transcribing }
        return transcriber.isTranscribing
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            switch stage {
            case .compose:
                VStack(spacing: 0) {
                    topBar
                    if !recorder.isRecording {
                        ModeSwitcher(selection: $mode, modes: availableModes)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }
                    switch mode {
                    case .speak: speakMode
                    case .type:  typeMode
                    case .video: videoMode
                    }
                }
            case .reviewing:
                reviewingView
            case .processing:
                processingView
            case .done:
                savedView
            case .failed(let message):
                failedView(message)
            }
        }
        .alert("Microphone Access Needed", isPresented: $recorder.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Allow microphone access in Settings to record a voice memory.")
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            // Firm cue only when capture truly begins (after permission + record()),
            // never on the button touch. The stop cue fires in stopRecording().
            if isRecording { Haptics.recordStart() }
        }
        .fullScreenCover(isPresented: $showVideoRecorder) {
            CameraPicker { media in if let u = media.videoURL { startVideo(u) } }
        }
        .fullScreenCover(isPresented: $showVideoPicker) {
            VideoPicker { url in startVideo(url) }
        }
    }

    // MARK: Video mode — record or import a video; transcription happens on-device in the review step.
    private var videoMode: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title (optional)", text: $title)
            field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")

            Spacer(minLength: 8)
            VStack(spacing: 12) {
                Image(systemName: "video.circle.fill").font(.system(size: 64)).foregroundStyle(WV.teal.opacity(0.85))
                Text("Record or choose a video").font(.serif(22)).foregroundStyle(WT.ink)
                Text("We transcribe it on your device — the video stays here and is never uploaded.")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            Spacer()

            VStack(spacing: 12) {
                Button { showVideoRecorder = true } label: {
                    HStack { Image(systemName: "video.fill"); Text("Record video") }
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .witnessPress()
                Button { showVideoPicker = true } label: {
                    HStack { Image(systemName: "photo.on.rectangle"); Text("Import video") }
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(WV.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.teal.opacity(0.25), lineWidth: 1))
                }
                .witnessPress()
            }
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
    }

    // MARK: Top bar
    private var topBar: some View {
        ZStack {
            Text("NEW MEMORY")
                .font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                        .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
                }
                .witnessPress()
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: Speak mode
    private var speakMode: some View {
        VStack(spacing: 0) {
            if !recorder.isRecording {
                VStack(spacing: 12) {
                    field("Title (optional)", text: $title)
                    field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Spacer()

            Text(recorder.isRecording ? timeString : "Tell me about a moment.")
                .font(recorder.isRecording ? .system(size: 44, weight: .light, design: .monospaced) : .serif(26))
                .foregroundStyle(recorder.isRecording ? WT.ink : WT.ink.opacity(0.7))
                .contentTransition(.numericText())
            Text(recorder.isRecording ? (recorder.isPaused ? "Paused" : "Listening…") : "Tap the mic and just talk. There's no wrong way.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                .padding(.top, 8)

            Spacer()

            if recorder.isRecording {
                HStack(spacing: 42) {
                    secondaryControl(recorder.isPaused ? "play.fill" : "pause.fill") { togglePause() }
                    ZStack {
                        LevelPulse(level: recorder.level)
                        micButton(systemName: "stop.fill") { stopRecording() }
                            .scaleEffect(1.0 + 0.06 * recorder.level)
                            .animation(.easeOut(duration: 0.22), value: recorder.level)
                    }
                    secondaryControl("trash") { cancelRecording() }
                }
            } else {
                micButton(systemName: "mic.fill") { beginRecording() }
            }

            Spacer()
        }
        .padding(.bottom, 24)
    }

    private func micButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(WV.teal)
                Image(systemName: systemName).font(.system(size: 44, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: 120, height: 120)
            .shadow(color: WV.teal.opacity(0.35), radius: 18, y: 8)
        }
        .witnessPress(scale: 0.93)
    }

    private func secondaryControl(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(WT.ink.opacity(0.7))
                .frame(width: 56, height: 56).background(Color.white, in: Circle())
                .overlay(Circle().stroke(WT.ink.opacity(0.1), lineWidth: 1))
        }
        .witnessPress()
    }

    // MARK: Type mode — full-height writing surface, Save pinned at the bottom.
    private var typeMode: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title (optional)", text: $title)
            field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")

            Text("YOUR WORDS")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WT.ink.opacity(0.4))

            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("Write the memory in your own words…")
                        .font(.serif(17)).foregroundStyle(WT.ink.opacity(0.35))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                }
                TextEditor(text: $bodyText)
                    .font(.serif(17)).foregroundStyle(WT.ink).tint(WV.teal)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
        .safeAreaInset(edge: .bottom) {
            Button { saveMemory() } label: {
                Text("Save memory")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WV.teal.opacity(0.4) : WV.teal,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 24).padding(.bottom, 10)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(placeholder, text: text)
                .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
                .padding(.horizontal, 16).frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4)).padding(.leading, 4) }
        }
    }

    // MARK: Saved confirmation (spec: "saved — {companion} is finding its shape")
    private var savedView: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: "checkmark").font(.system(size: 34, weight: .semibold)).foregroundStyle(WV.teal)
            }
            .frame(width: 90, height: 90)
            Text("Saved").font(.serif(30)).foregroundStyle(WV.teal)
            Text("\(companion) is finding its shape.")
                .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6))
                .multilineTextAlignment(.center)

            if recorder.lastRecordingURL != nil {
                playbackBar
                    .padding(.top, 6)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .padding(.horizontal, 24).padding(.bottom, 10)
        }
        .onAppear {
            if let url = recorder.lastRecordingURL { audioPlayer.load(url) }
        }
        .onDisappear { audioPlayer.stop(); transcriber.cancel() }
    }

    // MARK: Review (Speak) — the on-device transcript, editable before saving. This is where data quality is
    // protected: the user reads/fixes their own words, and only real text is sent to the create call.
    private var reviewingView: some View {
        VStack(spacing: 0) {
            reviewTopBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    field("Title (optional)", text: $title)
                    field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")

                    if recorder.lastRecordingURL != nil { playbackBar.padding(.vertical, 2) }

                    Text("YOUR WORDS")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WT.ink.opacity(0.4))
                    transcriptStatusLine

                    ZStack(alignment: .topLeading) {
                        if reviewText.isEmpty && !isBusyTranscribing {
                            Text("Type what you said…")
                                .font(.serif(17)).foregroundStyle(WT.ink.opacity(0.35))
                                .padding(.horizontal, 16).padding(.vertical, 14)
                        }
                        TextEditor(text: $reviewText)
                            .font(.serif(17)).foregroundStyle(WT.ink).tint(WV.teal)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            let empty = reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button { submit(text: reviewText, audio: recorder.lastRecordingURL) } label: {
                Text("Save memory")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(empty ? WV.teal.opacity(0.4) : WV.teal,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .disabled(empty)
            .padding(.horizontal, 24).padding(.bottom, 10)
        }
        .onAppear { if let url = recorder.lastRecordingURL { audioPlayer.load(url) } }
        .onChange(of: transcriber.transcript) { _, newValue in
            // Auto-fill while recognition is running; once it finishes, stop overwriting so the user can edit.
            if mode != .video, transcriber.isTranscribing || reviewText.isEmpty { reviewText = newValue }
        }
        .onChange(of: videoVM.transcript) { _, newValue in
            // Video's on-device transcript lands once; fill it (the user can then edit before saving).
            if mode == .video, !newValue.isEmpty { reviewText = newValue }
        }
        .onDisappear { audioPlayer.stop() }
    }

    private var reviewTopBar: some View {
        ZStack {
            Text("REVIEW")
                .font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            HStack {
                Button { backToCompose() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text("Re-record").font(.system(size: 15))
                    }
                    .foregroundStyle(WV.teal).frame(height: 44)
                }
                .witnessPress()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                        .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
                }
                .witnessPress()
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    @ViewBuilder private var transcriptStatusLine: some View {
        if mode == .video {
            switch videoVM.phase {
            case .extracting:
                Text("Extracting audio…")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            case .transcribing:
                Text("Transcribing… \(Int(videoVM.progress * 100))%")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            case .failed(let m):
                Text(m).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            case .idle, .ready:
                EmptyView()
            }
        } else {
            switch transcriber.state {
            case .running:
                Text("Transcribing on your device…")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            case .denied:
                Text("Transcription needs Speech access — you can type your memory here instead.")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            case .unavailable(let reason):
                Text("Couldn’t transcribe automatically (\(reason)) — type your memory here.")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            case .noSpeech:
                Text("Didn’t catch any speech — type your memory here.")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
            case .idle, .done:
                EmptyView()
            }
        }
    }

    // MARK: Processing — the honest long wait on the blocking create call. No dismiss control (guards
    // navigation-away / double-submit); rotating copy so it never looks frozen.
    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.4).tint(WV.teal)
            Text(saver.processingMessage)
                .font(.serif(24)).foregroundStyle(WV.teal)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: saver.processingMessage)
            Text("This can take up to a minute — \(companion) is reading your memory closely. You can keep this open.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24)
        .interactiveDismissDisabled(true)
    }

    // MARK: Failure — friendly retry. The transcript + recording are preserved in state, so nothing is lost.
    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(WV.danger.opacity(0.12))
                Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .semibold)).foregroundStyle(WV.danger)
            }
            .frame(width: 84, height: 84)
            Text("Couldn’t save yet").font(.serif(26)).foregroundStyle(WT.ink)
            Text(message)
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6))
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 36)
            if recorder.lastRecordingURL != nil { playbackBar.padding(.top, 6) }
            Spacer()
        }
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button { retrySubmit() } label: {
                    Text("Try again")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .witnessPress()
                Button { backFromFailure() } label: {
                    Text(mode == .type ? "Back to editing" : "Back to my words")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(WV.teal).frame(height: 24)
                }
                .witnessPress()
            }
            .padding(.horizontal, 24).padding(.bottom, 10)
        }
        .onAppear { if let url = recorder.lastRecordingURL { audioPlayer.load(url) } }
        .onDisappear { audioPlayer.stop() }
    }

    // Compact playback for the just-recorded memo (saved state only).
    private var playbackBar: some View {
        HStack(spacing: 14) {
            Button { togglePlayback() } label: {
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
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WT.ink.opacity(0.5))
            }
        }
    }

    // MARK: Actions
    private func togglePause() {
        if recorder.isPaused { recorder.resumeRecording() } else { recorder.pauseRecording() }
    }
    private func togglePlayback() {
        if audioPlayer.isPlaying { audioPlayer.pause() } else { audioPlayer.play() }
    }
    private func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
    private func cancelRecording() { recorder.cancelRecording() }
    private func beginRecording() {
        sessionID = UUID().uuidString   // one session_id per captured memory, minted at capture start
        recorder.startRecording()
    }
    private func stopRecording() {
        Haptics.recordStop()
        recorder.stopRecording()
        // In-session gallery entry (audio tile). In-memory only; the durable copy is the media upload on save.
        if let url = recorder.lastRecordingURL {
            MediaStore.shared.add(CapturedMedia(image: nil, kind: .audio, videoURL: nil,
                                                fileName: url.lastPathComponent))
            transcriber.transcribe(url: url)   // on-device transcript for the review screen
        }
        reviewText = ""
        withAnimation { stage = .reviewing }
    }

    // Type mode → create directly from the typed text (no audio).
    private func saveMemory() { submit(text: bodyText, audio: nil) }

    // Video mode → keep the local URL, mint a session, kick off extract+transcribe, go to the review screen.
    private func startVideo(_ url: URL) {
        sessionID = UUID().uuidString
        pendingVideoURL = url
        reviewText = ""
        videoVM.process(videoURL: url)
        withAnimation { stage = .reviewing }
    }

    /// The single create path: POST /memories (blocking) then best-effort media upload, via the saver VM.
    /// On success → confirmation + onSaved refresh; on failure → retry screen with text + recording preserved.
    private func submit(text: String, audio: URL?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, stage != .processing else { return }
        if sessionID.isEmpty { sessionID = UUID().uuidString }   // Type mode has no capture-start
        let memoryDate = Self.strictYMD(dateText)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let titleOpt = trimmedTitle.isEmpty ? nil : trimmedTitle
        transcriber.cancel()
        audioPlayer.stop()
        withAnimation { stage = .processing }
        Task {
            let id = await saver.save(text: trimmed, sessionID: sessionID, title: titleOpt,
                                      memoryDate: memoryDate, audioURL: audio, auth: auth)
            if let id {
                if mode == .video, let v = pendingVideoURL { VideoStore.link(v, to: id) }   // video stays local
                onSaved?()
                withAnimation { stage = .done }
            } else {
                withAnimation {
                    stage = .failed(saver.errorText ?? "We couldn’t save that just now. Your recording is safe — tap to try again.")
                }
            }
        }
    }
    private func retrySubmit() {
        switch mode {
        case .speak: submit(text: reviewText, audio: recorder.lastRecordingURL)
        case .video: submit(text: reviewText, audio: nil)   // video stays local; text-only create
        case .type:  submit(text: bodyText, audio: nil)
        }
    }
    private func backFromFailure() {
        audioPlayer.stop()
        withAnimation { stage = (mode == .type) ? .compose : .reviewing }   // Speak/Video keep the transcript
    }
    private func backToCompose() {
        transcriber.cancel()
        videoVM.reset()
        audioPlayer.stop()
        withAnimation { stage = .compose }
    }

    /// Only send memory_date when it's a real yyyy-MM-dd; the "When was this?" field is free text (prose like
    /// "April 1993"), which the backend extracts from the memory text instead.
    private static func strictYMD(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: t) != nil ? t : nil
    }

    private var timeString: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%01d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Branded Speak/Type toggle (teal pill on a soft track).
private struct ModeSwitcher: View {
    @Binding var selection: RecordView.Mode
    var modes: [RecordView.Mode]
    @Namespace private var ns

    private func icon(_ m: RecordView.Mode) -> String {
        switch m { case .speak: return "mic.fill"; case .type: return "pencil"; case .video: return "video.fill" }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.self) { m in
                let sel = (m == selection)
                HStack(spacing: 7) {
                    Image(systemName: icon(m))
                        .font(.system(size: 13, weight: .semibold))
                    Text(m.rawValue).font(.system(size: 15, weight: sel ? .semibold : .regular))
                }
                .foregroundStyle(sel ? Color.white : WT.ink.opacity(0.55))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(
                    Group {
                        if sel {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(WV.teal)
                                .matchedGeometryEffect(id: "mode_pill", in: ns)
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = m } }
            }
        }
        .padding(4)
        .background(WT.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Live input-level pulse (breathes around the stop button, driven by recorder.level).
private struct LevelPulse: View {
    var level: Double   // 0…1; eased by the parent's .animation on recorder.level

    var body: some View {
        ZStack {
            ring(scaleBoost: 0.525, base: 0.05, gain: 0.12)  // outer: larger, fainter (1.25×)
            ring(scaleBoost: 0.275, base: 0.09, gain: 0.20)  // inner: tighter, stronger (1.25×)
        }
        .animation(.easeOut(duration: 0.22), value: level)
        .allowsHitTesting(false)
    }

    private func ring(scaleBoost: CGFloat, base: Double, gain: Double) -> some View {
        Circle()
            .stroke(WV.teal, lineWidth: 2)
            .frame(width: 120, height: 120)
            .scaleEffect(1.0 + scaleBoost * CGFloat(level))
            .opacity(base + gain * level)
    }
}
