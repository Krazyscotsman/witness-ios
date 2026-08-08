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

    enum Mode: String, CaseIterable { case speak = "Speak", type = "Type" }
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var transcriber = Transcriber()   // TEMP: item-3 engine validation

    @State private var mode: Mode = .speak
    @State private var title = ""
    @State private var dateText = ""
    @State private var bodyText = ""
    @State private var saved = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            if saved {
                savedView
            } else {
                VStack(spacing: 0) {
                    topBar
                    if !recorder.isRecording {
                        ModeSwitcher(selection: $mode)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }
                    if mode == .speak { speakMode } else { typeMode }
                }
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
                micButton(systemName: "mic.fill") { recorder.startRecording() }
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
            if recorder.lastRecordingURL != nil {
                transcribeScaffold
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

    // TEMP SCAFFOLD (item 3): validates the on-device Transcriber engine. NOT a shipped
    // feature — remove once transcription is wired into the real flow.
    private var transcribeScaffold: some View {
        VStack(spacing: 8) {
            Button {
                if let url = recorder.lastRecordingURL { transcriber.transcribe(url: url) }
            } label: {
                Text(transcriber.isTranscribing ? "Transcribing…" : "Transcribe (temp)")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(WV.teal)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(WV.teal.opacity(0.12), in: Capsule())
            }
            .witnessPress()
            .disabled(transcriber.isTranscribing)

            Text("Engine: \(transcriber.stateDescription)")
                .font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.45))
                .multilineTextAlignment(.center)

            if !transcriber.transcript.isEmpty {
                ScrollView {
                    Text(transcriber.transcript)
                        .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(.top, 10)
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
    private func stopRecording() {
        // Audio file is at recorder.lastRecordingURL; backend owns upload/transcription.
        Haptics.recordStop()
        recorder.stopRecording()
        // Register the finished recording with the in-session MediaStore the gallery reads,
        // so it shows in "Recently added" as an audio item (gold waveform tile, distinct from
        // photo tiles). Reuses MediaStore / CapturedMedia (kind: .audio). In-memory only —
        // appears this session, not across relaunches (durable storage is backend-era, item 10).
        if let url = recorder.lastRecordingURL {
            MediaStore.shared.add(CapturedMedia(image: nil, kind: .audio, videoURL: nil,
                                                fileName: url.lastPathComponent))
        }
        withAnimation { saved = true }
    }
    private func saveMemory() {
        // Real: POST /api/v1/memories { title?, memory_date?, content: bodyText }
        withAnimation { saved = true }
    }

    private var timeString: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%01d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Branded Speak/Type toggle (teal pill on a soft track).
private struct ModeSwitcher: View {
    @Binding var selection: RecordView.Mode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordView.Mode.allCases, id: \.self) { m in
                let sel = (m == selection)
                HStack(spacing: 7) {
                    Image(systemName: m == .speak ? "mic.fill" : "pencil")
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
