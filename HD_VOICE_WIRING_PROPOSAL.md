# Witness — HD (Gemini) memory voice + Native↔HD toggle — Proposal

Status: **PROPOSED — nothing applied, no build, no git.** iOS-only; backend endpoint already works.

## Read-first
- Listen UI (MemoryDetailView): `readAloudRow` (native pill + Stop) → `toggleReadAloud()` → `speaker.speak(paragraphs:)`;
  `readAloudProgress` ("Reading N of M" + "Voice: {name}"); `enhancedVoiceHint`. Plus a DORMANT recording player
  (`listenPlayer` + `audioPlayer` + `resolveMemoryAudioURL()` → nil).
- Speaker "NEURAL-TTS SEAM": comment describing fetch→AudioPlayer behind currentParagraph/paragraphCount. The
  real endpoint returns ONE WAV for the WHOLE memory → HD is a whole-file AudioPlayer play (not a per-chunk
  Speaker swap); the seam's intent (fetch → AudioPlayer, shared transport) holds.
- AudioPlayer: @MainActor ObservableObject; `load(_ url:)`, play/pause/stop, published isPlaying/currentTime/
  duration/progress. NO `load(Data)` yet. MemoryDetailView already owns `@StateObject audioPlayer` (idle) → reuse.
- Voice: `@AppStorage(Profile.voiceKey)` stores the STYLE id ("warm_female"); `VoiceOption.geminiName(for:)`
  maps → Kore/Leda/Aoede/Orus/Charon/Puck (the 6 the app emits; default Aoede). No separate stored
  custom_voice_name — derived from the style id.

Endpoint: `GET /api/v1/memories/{id}/audio?voice={voice}&style=warm_memory`, Bearer → JSON
`{ audio_base64 (WAV), mime_type, duration, voice, style, character_count }`. Synchronous (first ~seconds +
caches; repeat fast). voice MUST be one of the 8 valid TTS_VOICES or silently becomes Kore. No chunking → long
memories fail.

## Decisions (recommended; change any)
1. Reuse `audioPlayer` for HD + HD fetch state in the view (no new ObservableObject).
2. HD voice whitelist = the 6 app-emitted names (default Kore) — can't enumerate the backend's 8 from iOS; the
   app never produces others, so we never send an invalid voice.
3. Remove the dead recording player (`resolveMemoryAudioURL`/`listenPlayer`/`toggleListen`/`audioURL`); repurpose
   `audioPlayer` for HD.
4. Defer the recorded-memory `GET /memories/{id}/media` original-audio check to a follow-up.

Length guard: HD disabled when narrative > ~9000 chars (tunable) → "too long for HD yet — coming soon."; Device
always available.

---

## APIModels.swift — response DTO (append)
```swift
// GET /api/v1/memories/{id}/audio?voice=&style=warm_memory → base64 WAV + meta. .convertFromSnakeCase.
nonisolated struct MemoryAudioResponse: Decodable {
    let audioBase64: String?
    let mimeType: String?
    let duration: Double?
    let voice: String?
    let style: String?
    let characterCount: Int?
}
```

## AudioPlayer.swift — play decoded bytes
```diff
     func load(_ url: URL) { … }
+
+    /// Builds the player from in-memory audio (e.g. decoded base64 WAV). Same reset/fail behavior as load(url:).
+    func load(_ data: Data) {
+        stopTimer()
+        do {
+            let p = try AVAudioPlayer(data: data)
+            p.delegate = self
+            p.prepareToPlay()
+            player = p
+            duration = p.duration
+        } catch { player = nil; duration = 0 }
+        currentTime = 0
+        progress = 0
+        isPlaying = false
+    }
```

## MemoryDetailView.swift — unified Listen surface (Device ↔ HD)

### State + voice + decoder
```diff
     @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
+    @AppStorage(Profile.voiceKey) private var voiceKey: String = "playful_female"
+    @AppStorage("listen.preferHD") private var preferHD = false
     @StateObject private var vm = MemoryDetailViewModel()
     @StateObject private var audioPlayer = AudioPlayer()      // now the HD (WAV) player
     @StateObject private var speaker = Speaker()
-    @State private var audioURL: URL?
     @State private var showAsk = false
     @State private var onlyDefaultVoice = false
+    @State private var hdPhase: HDPhase = .idle
+    @State private var hdLoadedKey: String?                    // memoryId|voice already fetched this session
     @AppStorage("hint.enhancedVoiceDismissed") private var enhancedVoiceHintDismissed = false
```
```swift
enum HDPhase: Equatable { case idle, preparing, failed(String) }
enum ListenMode { case device, hd }

private static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
private static let hdCharLimit = 9000
private static let validHDVoices: Set<String> = ["Kore","Leda","Aoede","Orus","Charon","Puck"]   // 6 the app emits (⊂ backend's 8)

private var hdVoice: String {
    let g = VoiceOption.geminiName(for: voiceKey)
    return Self.validHDVoices.contains(g) ? g : "Kore"
}
private var hdAllowed: Bool { (vm.detail?.narrative?.count ?? .max) <= Self.hdCharLimit }   // needs detail + short enough
private var mode: ListenMode { (preferHD && hdAllowed) ? .hd : .device }
```

### onAppear — drop the recording-URL load
```diff
         .onAppear {
-            audioURL = resolveMemoryAudioURL()
-            if let url = audioURL { audioPlayer.load(url) }
             onlyDefaultVoice = Speaker.readingVoiceInfo().isDefaultOnly
         }
```

### loadedBody — replace read-aloud + recording blocks with one surface
```diff
-            readAloudRow
-            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
-            enhancedVoiceHint
-            if audioURL != nil {
-                listenPlayer
-            } else {
-                Text("No recording to play yet.")
-                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.4))
-            }
+            listenSurface
```

### The surface
```swift
private var listenSurface: some View {
    VStack(alignment: .leading, spacing: 10) {
        // Device ↔ HD toggle
        HStack(spacing: 6) {
            modeChip("Device voice", active: mode == .device) { setPreferHD(false) }
            modeChip("HD voice", active: mode == .hd, disabled: !hdAllowed) { if hdAllowed { setPreferHD(true) } }
            Spacer(minLength: 0)
        }
        // Controls
        HStack(spacing: 10) {
            Button { primaryTapped() } label: {
                HStack(spacing: 7) {
                    Image(systemName: primaryIcon).font(.system(size: 14, weight: .medium))
                    Text(primaryLabel).font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(WV.teal).padding(.horizontal, 14).frame(height: 38)
                .background(WV.teal.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(WV.teal.opacity(0.25), lineWidth: 1))
            }
            .disabled(primaryDisabled).opacity(primaryDisabled ? 0.45 : 1).witnessPress()
            if listenActive {
                Button { stopListen() } label: {
                    HStack(spacing: 6) { Image(systemName: "stop.fill").font(.system(size: 13, weight: .medium)); Text("Stop").font(.system(size: 14, weight: .medium)) }
                        .foregroundStyle(WV.danger).padding(.horizontal, 14).frame(height: 38)
                        .background(WV.danger.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(WV.danger.opacity(0.25), lineWidth: 1))
                }.witnessPress()
            }
            Spacer(minLength: 0)
        }
        // Progress / status per mode
        if mode == .device {
            if speaker.isSpeaking || speaker.isPaused { readAloudProgress }
            enhancedVoiceHint
        } else {
            hdStatus
        }
    }
}

private func modeChip(_ title: String, active: Bool, disabled: Bool = false, _ tap: @escaping () -> Void) -> some View {
    Text(title)
        .font(.system(size: 13, weight: active ? .semibold : .regular))
        .foregroundStyle(disabled ? WT.ink.opacity(0.3) : (active ? .white : WT.ink.opacity(0.6)))
        .padding(.horizontal, 12).frame(height: 34)
        .background(active ? WV.teal : Color.white, in: Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : WT.ink.opacity(0.12), lineWidth: 1))
        .onTapGesture { if !disabled { withAnimation(.easeOut(duration: 0.15)) { tap() } } }
}

@ViewBuilder private var hdStatus: some View {
    switch hdPhase {
    case .preparing:
        HStack(spacing: 8) { ProgressView().tint(WV.teal); Text("Preparing HD audio…").font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)) }
    case .failed(let m):
        Text(m).font(.system(size: 12)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
    case .idle:
        if !hdAllowed {
            Text("This memory is too long for HD yet — coming soon. Device voice is available.")
                .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
        } else if audioPlayer.duration > 0 {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WT.ink.opacity(0.1))
                        Capsule().fill(WV.teal).frame(width: max(0, geo.size.width * audioPlayer.progress))
                    }
                }.frame(height: 6)
                HStack { Text(mmss(audioPlayer.currentTime)); Spacer(); Text("Voice: \(hdVoice) · HD"); Spacer(); Text(mmss(audioPlayer.duration)) }
                    .font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.5))
            }
        }
    }
}

// MARK: transport routing
private var listenActive: Bool {
    mode == .device ? (speaker.isSpeaking || speaker.isPaused) : (audioPlayer.isPlaying || audioPlayer.duration > 0 || hdPhase == .preparing)
}
private var primaryDisabled: Bool {
    if mode == .device { return vm.paragraphs.isEmpty && spokenText.isEmpty }
    return hdPhase == .preparing || !hdAllowed
}
private var primaryIcon: String {
    if mode == .device { return speaker.isPaused ? "play.fill" : (speaker.isSpeaking ? "pause.fill" : "text.bubble.fill") }
    return audioPlayer.isPlaying ? "pause.fill" : "play.fill"
}
private var primaryLabel: String {
    if mode == .device { return speaker.isPaused ? "Resume" : (speaker.isSpeaking ? "Pause" : "Read aloud") }
    return audioPlayer.isPlaying ? "Pause" : (audioPlayer.duration > 0 ? "Play" : "Play HD")
}
private func primaryTapped() {
    if mode == .device { toggleReadAloud() }
    else {
        if hdPhase == .preparing { return }
        if audioPlayer.isPlaying { audioPlayer.pause() }
        else { Task { await playHD() } }        // resumes if cached (play()) else fetches
    }
}
private func stopListen() { speaker.stop(); audioPlayer.stop() }
private func setPreferHD(_ on: Bool) { stopListen(); hdPhase = .idle; preferHD = on }

// MARK: HD fetch
private func playHD() async {
    speaker.stop()
    let key = "\(listItem.id)|\(hdVoice)"
    if key == hdLoadedKey, audioPlayer.duration > 0 { audioPlayer.play(); return }   // cached this session
    hdPhase = .preparing
    let path = "/api/v1/memories/\(listItem.id)/audio?voice=\(hdVoice)&style=warm_memory"
    do {
        let r = try await getHD(path)
        guard let b64 = r.audioBase64, let data = Data(base64Encoded: b64), !data.isEmpty else { throw HDErr.decode }
        audioPlayer.load(data); audioPlayer.play()
        hdLoadedKey = key; hdPhase = .idle
    } catch {
        hdPhase = .failed("HD voice isn’t available right now — using the device voice.")
        preferHD = false                        // graceful fallback to Native
    }
}
private enum HDErr: Error { case decode }
private func getHD(_ path: String) async throws -> MemoryAudioResponse {
    do { return try await APIClient.shared.get(path, timeout: 60, decoder: Self.snake, as: MemoryAudioResponse.self) }
    catch APIError.unauthorized(_, let code) {
        if await auth.handleUnauthorized(code: code) { return try await APIClient.shared.get(path, timeout: 60, decoder: Self.snake, as: MemoryAudioResponse.self) }
        throw HDErr.decode
    }
}
```
REMOVE (now dead): `readAloudRow` may stay as-is but is no longer referenced — I'll fold its Stop into the new
surface and delete `readAloudRow`; also delete `listenPlayer`, `toggleListen`, `resolveMemoryAudioURL`,
`audioURL`. `readAloudControl`/`readAloudProgress`/`readAloudIcon`/`readAloudLabel`/`toggleReadAloud` stay (used
by Device mode). `enhancedVoiceHint` stays (Device only).

---

## After approval
Apply; build 0/0 + diagnostics. Honest note: the live WAV round-trip (base64 decode + AVAudioPlayer(data:),
first-call latency, the 8-voice validation, `warm_memory`, and the length guard preventing the un-chunked
backend from failing) is a device/backend check I can't run here. Recorded-memory original audio deferred. No git.
