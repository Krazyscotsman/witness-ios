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
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
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
