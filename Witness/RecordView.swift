import SwiftUI
import Combine

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
    @State private var mode: Mode = .speak
    @State private var recording = false
    @State private var paused = false
    @State private var elapsed = 0
    @State private var title = ""
    @State private var dateText = ""
    @State private var bodyText = ""
    @State private var saved = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ParchmentBackground()
            if saved {
                savedView
            } else {
                VStack(spacing: 0) {
                    topBar
                    if !recording {
                        ModeSwitcher(selection: $mode)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }
                    if mode == .speak { speakMode } else { typeMode }
                }
            }
        }
        .onReceive(timer) { _ in if recording && !paused { elapsed += 1 } }
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
            if !recording {
                VStack(spacing: 12) {
                    field("Title (optional)", text: $title)
                    field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Spacer()

            Text(recording ? timeString : "Tell me about a moment.")
                .font(recording ? .system(size: 44, weight: .light, design: .monospaced) : .serif(26))
                .foregroundStyle(recording ? WT.ink : WT.ink.opacity(0.7))
                .contentTransition(.numericText())
            Text(recording ? (paused ? "Paused" : "Listening…") : "Tap the mic and just talk. There's no wrong way.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                .padding(.top, 8)

            Spacer()

            if recording {
                HStack(spacing: 28) {
                    secondaryControl(paused ? "play.fill" : "pause.fill") { paused.toggle() }
                    micButton(systemName: "stop.fill") { stopRecording() }
                    secondaryControl("trash") { cancelRecording() }
                }
            } else {
                micButton(systemName: "mic.fill") { startRecording() }
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

            Button { saveMemory() } label: {
                Text("Save memory")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WV.teal.opacity(0.4) : WV.teal,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
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
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Actions (inert; real endpoints noted)
    private func startRecording() { elapsed = 0; paused = false; recording = true }
    private func cancelRecording() { recording = false; paused = false; elapsed = 0 }
    private func stopRecording() {
        // Real: write the audio file, then POST /memories/voice (multipart `file`, optional title/memory_date).
        recording = false; paused = false
        withAnimation { saved = true }
    }
    private func saveMemory() {
        // Real: POST /api/v1/memories { title?, memory_date?, content: bodyText }
        withAnimation { saved = true }
    }

    private var timeString: String {
        String(format: "%01d:%02d", elapsed / 60, elapsed % 60)
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
