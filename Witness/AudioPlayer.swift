import AVFoundation
import Combine

/// Plays a local audio file for the record screen's saved state. Mirrors
/// AudioRecorder's structure (ObservableObject, @MainActor, cycle-free timer).
/// Backend/stored-memory playback, TTS, and app-wide Listen buttons are out of scope.
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: Published state
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var progress: Double = 0          // 0…1, divide-by-zero guarded

    // MARK: Private
    private var player: AVAudioPlayer?
    private var displayTimer: Timer?

    // MARK: Load

    /// Builds the player for `url`, reads duration, resets state. Fails gracefully.
    func load(_ url: URL) {
        stopTimer()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
        } catch {
            player = nil
            duration = 0
        }
        currentTime = 0
        progress = 0
        isPlaying = false
    }

    /// Builds the player from in-memory audio (e.g. a decoded base64 WAV). Same reset/fail behavior as load(url:).
    func load(_ data: Data) {
        stopTimer()
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
        } catch {
            player = nil
            duration = 0
        }
        currentTime = 0
        progress = 0
        isPlaying = false
    }

    // MARK: Transport

    func play() {
        guard let player else { return }
        configureSession()
        if player.play() {
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        player?.pause()
        stopTimer()
        currentTime = player?.currentTime ?? currentTime   // retain position
        updateProgress()
        isPlaying = false
        // Session left active on pause — resuming is the likely next action.
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0        // stop() does not zero currentTime; do it ourselves
        stopTimer()
        isPlaying = false
        currentTime = 0
        progress = 0
        deactivateSession()
    }

    /// Seek to a 0…1 fraction of the duration. Included for future UI; safe to call now.
    func seek(toFraction fraction: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let target = clamped * duration
        player.currentTime = target
        currentTime = target
        updateProgress()
    }

    // MARK: - Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Display timer (cycle-free / Swift-6-clean; mirrors AudioRecorder.startTimer())

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        displayTimer = t
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        guard let player, player.isPlaying else { return }
        currentTime = player.currentTime
        updateProgress()
    }

    private func updateProgress() {
        progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.isPlaying = false
            self.currentTime = 0
            self.progress = 0
            self.deactivateSession()   // release the session after a normal play-through
        }
    }
}
