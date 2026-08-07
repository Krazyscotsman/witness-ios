# Witness — Step 1 Voice Capture: `RecordView` Wiring Proposal

**Status:** `AudioRecorder.swift` written, compiles **clean** (0 errors, 0 warnings).
Full build result: `The project built successfully.` (~5.2s).

The wiring diff below is **proposed, NOT yet applied** to `RecordView.swift`.

---

## Why this touches more than two lines

To wire correctly under the "single source of truth" ruling, the view must read
`recorder.isRecording` / `recorder.isPaused` / `recorder.elapsed` instead of keeping
its own parallel `recording` / `paused` / `elapsed` state and its own `Timer`. So the
diff **removes** the view's local `recording`, `paused`, `elapsed`, and the
`Timer.publish` (killing the second clock), and repoints every reader at the recorder.
Layout, visuals, ModeSwitcher, typeMode, savedView, and all the text fields are untouched.

---

## Proposed diff — `RecordView.swift`

### 1. Add UIKit import (needed for the Settings deep-link in the alert)
```diff
 import SwiftUI
 import Combine
+import UIKit
```
Note: `import Combine` is now unused after this change but is left to keep the diff
minimal — can drop it if preferred.

### 2. State block — add the recorder; remove the parallel state + timer (lines 15–24)
```diff
     enum Mode: String, CaseIterable { case speak = "Speak", type = "Type" }
+    @StateObject private var recorder = AudioRecorder()
+
     @State private var mode: Mode = .speak
-    @State private var recording = false
-    @State private var paused = false
-    @State private var elapsed = 0
     @State private var title = ""
     @State private var dateText = ""
     @State private var bodyText = ""
     @State private var saved = false
-
-    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
```

### 3. `body` — read `recorder.isRecording`, drop the fake-timer `onReceive`, add the permission alert (lines 26–44)
```diff
                 VStack(spacing: 0) {
                     topBar
-                    if !recording {
+                    if !recorder.isRecording {
                         ModeSwitcher(selection: $mode)
                             .padding(.horizontal, 24)
                             .padding(.top, 10)
                     }
                     if mode == .speak { speakMode } else { typeMode }
                 }
             }
         }
-        .onReceive(timer) { _ in if recording && !paused { elapsed += 1 } }
+        .alert("Microphone Access Needed", isPresented: $recorder.permissionDenied) {
+            Button("Open Settings") {
+                if let url = URL(string: UIApplication.openSettingsURLString) {
+                    UIApplication.shared.open(url)
+                }
+            }
+            Button("Cancel", role: .cancel) { }
+        } message: {
+            Text("Allow microphone access in Settings to record a voice memory.")
+        }
     }
```

### 4. `speakMode` — repoint the recording-state readers and the control buttons (lines 66–97)
```diff
         VStack(spacing: 0) {
-            if !recording {
+            if !recorder.isRecording {
                 VStack(spacing: 12) {
                     field("Title (optional)", text: $title)
                     field("When was this? (optional)", text: $dateText, hint: "“April 1993”, or “when I was 16.”")
                 }
                 .padding(.horizontal, 24)
                 .padding(.top, 16)
             }

             Spacer()

-            Text(recording ? timeString : "Tell me about a moment.")
-                .font(recording ? .system(size: 44, weight: .light, design: .monospaced) : .serif(26))
-                .foregroundStyle(recording ? WT.ink : WT.ink.opacity(0.7))
+            Text(recorder.isRecording ? timeString : "Tell me about a moment.")
+                .font(recorder.isRecording ? .system(size: 44, weight: .light, design: .monospaced) : .serif(26))
+                .foregroundStyle(recorder.isRecording ? WT.ink : WT.ink.opacity(0.7))
                 .contentTransition(.numericText())
-            Text(recording ? (paused ? "Paused" : "Listening…") : "Tap the mic and just talk. There's no wrong way.")
+            Text(recorder.isRecording ? (recorder.isPaused ? "Paused" : "Listening…") : "Tap the mic and just talk. There's no wrong way.")
                 .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                 .padding(.top, 8)

             Spacer()

-            if recording {
+            if recorder.isRecording {
                 HStack(spacing: 28) {
-                    secondaryControl(paused ? "play.fill" : "pause.fill") { paused.toggle() }
+                    secondaryControl(recorder.isPaused ? "play.fill" : "pause.fill") { togglePause() }
                     micButton(systemName: "stop.fill") { stopRecording() }
                     secondaryControl("trash") { cancelRecording() }
                 }
             } else {
-                micButton(systemName: "mic.fill") { startRecording() }
+                micButton(systemName: "mic.fill") { recorder.startRecording() }
             }
```

### 5. Actions — wire to the recorder (lines 199–214)
```diff
-    // MARK: Actions (inert; real endpoints noted)
-    private func startRecording() { elapsed = 0; paused = false; recording = true }
-    private func cancelRecording() { recording = false; paused = false; elapsed = 0 }
-    private func stopRecording() {
-        // Real: write the audio file, then POST /memories/voice (multipart `file`, optional title/memory_date).
-        recording = false; paused = false
-        withAnimation { saved = true }
-    }
+    // MARK: Actions
+    private func togglePause() {
+        if recorder.isPaused { recorder.resumeRecording() } else { recorder.pauseRecording() }
+    }
+    private func cancelRecording() { recorder.cancelRecording() }
+    private func stopRecording() {
+        // Audio file is at recorder.lastRecordingURL; backend owns upload/transcription.
+        recorder.stopRecording()
+        withAnimation { saved = true }
+    }
     private func saveMemory() {
         // Real: POST /api/v1/memories { title?, memory_date?, content: bodyText }
         withAnimation { saved = true }
     }

     private var timeString: String {
-        String(format: "%01d:%02d", elapsed / 60, elapsed % 60)
+        let seconds = Int(recorder.elapsed)
+        return String(format: "%01d:%02d", seconds / 60, seconds % 60)
     }
```

---

## Behavior notes / things to confirm
- **Mic tap** calls `recorder.startRecording()` directly; that method handles the
  permission gate internally (prompts if undetermined, sets `permissionDenied` if
  denied → the alert fires). This honors "on first record, request permission; alert
  if denied" without a separate `requestPermission()` call in the view. Alternative:
  have the view call `requestPermission()` explicitly first.
- **Stop** still transitions to the existing `savedView` (`saved = true`), unchanged.
  The recorded `.m4a` sits at `recorder.lastRecordingURL` for the future upload step
  (out of scope now).
- **Cancel (trash)** now actually stops + deletes the file via the recorder, then the
  view returns to the pre-record screen automatically because `recorder.cancelRecording()`
  sets `isRecording = false`. No extra local state needed.

---

## For reference: `AudioRecorder.swift` (as written, compiles clean)

```swift
import AVFoundation
import Combine

/// Captures microphone audio to a real .m4a file on disk, exposing a real
/// elapsed time and a normalized 0…1 input level for a future meter.
/// Transcription / scrubbing / parsing / upload are out of scope (backend-owned).
@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    // MARK: Published state
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0        // real, monotonic, pause-aware
    @Published private(set) var level: Double = 0                // 0…1, curved
    @Published private(set) var lastRecordingURL: URL?
    @Published var permissionDenied = false

    // MARK: Private
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let meterFloorDB: Float = -50                        // clamp floor for quiet speech

    // Self-tracked elapsed time (monotonic; never jumps backward across pause/resume).
    private var accumulated: TimeInterval = 0                    // sum of completed segments
    private var segmentStart: TimeInterval = 0                   // systemUptime at current segment start

    // MARK: Permission

    /// Eagerly prompts for record permission (iOS 17+ API). Updates `permissionDenied`.
    func requestPermission() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor [weak self] in self?.permissionDenied = !granted }
        }
    }

    // MARK: Recording lifecycle

    /// Entry point for the mic button. Ensures permission, then begins.
    func startRecording() {
        switch AVAudioApplication.shared.recordPermission {   // instance property via shared singleton
        case .granted:
            beginRecording()
        case .denied:
            permissionDenied = true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted { self.beginRecording() } else { self.permissionDenied = true }
                }
            }
        @unknown default:
            permissionDenied = true
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if !isPaused { accumulated += now() - segmentStart }
        recorder?.stop()
        stopTimer()
        elapsed = accumulated       // freeze final duration
        isRecording = false
        isPaused = false
        deactivateSession()
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        accumulated += now() - segmentStart      // fold the running segment in
        recorder?.pause()                        // AVAudioRecorder.pause()
        stopTimer()
        isPaused = true
        elapsed = accumulated
        level = 0                                // meter drops while paused
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        if recorder?.record() == true {          // record() resumes after pause()
            segmentStart = now()
            isPaused = false
            startTimer()
        }
    }

    /// Stops, deletes the file, and resets — so a discarded take never orphans a recording.
    func cancelRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        stopTimer()
        recorder = nil
        accumulated = 0
        elapsed = 0
        level = 0
        isRecording = false
        isPaused = false
        lastRecordingURL = nil
        deactivateSession()
    }

    // MARK: - Internals

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }  // monotonic

    private func beginRecording() {
        let channels = configureSession()          // 2 on stereo, 1 on graceful fallback
        let url = makeFileURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.prepareToRecord(), r.record() else {
                deactivateSession()
                return
            }
            recorder = r
            lastRecordingURL = url
            accumulated = 0
            segmentStart = now()
            elapsed = 0
            level = 0
            isPaused = false
            isRecording = true
            startTimer()
        } catch {
            // Couldn't create the recorder; leave state clean, no crash.
            deactivateSession()
        }
    }

    /// Configures the session and attempts true stereo, falling back cleanly to
    /// mono on any failure. Returns the channel count to record with.
    private func configureSession() -> Int {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            return 1
        }

        guard configureStereoInput(session) else { return 1 }

        // Ask for 2 channels only after activation; mono fallback if refused.
        do {
            try session.setPreferredInputNumberOfChannels(2)
            return 2
        } catch {
            return 1
        }
    }

    /// Selects the built-in mic and a stereo-capable data source. Returns false
    /// (→ mono) if anything is missing or throws. A wrong setup would yield
    /// silent dual-mono, so we only claim stereo when every step succeeds.
    private func configureStereoInput(_ session: AVAudioSession) -> Bool {
        do {
            guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                return false
            }
            try session.setPreferredInput(builtIn)

            guard let stereoSource = builtIn.dataSources?.first(where: {
                $0.supportedPolarPatterns?.contains(.stereo) ?? false
            }) else {
                return false
            }

            try stereoSource.setPreferredPolarPattern(.stereo)
            try builtIn.setPreferredDataSource(stereoSource)
            try session.setPreferredInputOrientation(.portrait)  // audio-only, portrait app
            return true
        } catch {
            return false
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func makeFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return dir.appendingPathComponent("voice_\(formatter.string(from: Date())).m4a")
    }

    // MARK: Metering / timer (~10×/sec)

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keep firing during UI tracking
        meterTimer = t
    }

    private func stopTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tick() {
        guard let r = recorder, isRecording, !isPaused else { return }
        elapsed = accumulated + (now() - segmentStart)
        r.updateMeters()
        level = Self.normalizedLevel(from: r.averagePower(forChannel: 0))
    }

    /// Maps dBFS (≈ −160…0) to 0…1, clamping at a −50 dB floor and applying a
    /// square-root curve so quiet speech still registers on the meter.
    static func normalizedLevel(from db: Float) -> Double {
        guard db.isFinite else { return 0 }
        let floor: Float = -50
        let clamped = max(floor, min(0, db))
        let linear = (clamped - floor) / (0 - floor)   // 0…1 linear
        return Double(pow(linear, 0.5))                 // lift the quiet end
    }
}
```
