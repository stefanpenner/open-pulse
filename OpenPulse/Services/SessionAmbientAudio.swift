import AVFoundation
import Foundation

// MARK: - Testable seam

@MainActor
protocol SessionAmbientAudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    func sync(
        enabled: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    )
    func stop(fade: Bool)
}

/// Optional local hi-fi pad during sessions. Privacy-first: bundled file only, no network.
@MainActor
final class SessionAmbientAudio: NSObject, SessionAmbientAudioPlaying {
    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private(set) var isPlaying: Bool = false

    /// Bundle override for tests.
    var bundle: Bundle = .main

    func sync(
        enabled: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    ) {
        let want = AmbientAudioPolicy.shouldPlay(
            enabled: enabled,
            isRunning: isRunning,
            isPaused: isPaused,
            isInBackground: isInBackground
        )
        if want {
            startIfNeeded()
        } else if isPlaying || player != nil {
            stop(fade: true)
        }
    }

    func stop(fade: Bool) {
        fadeTask?.cancel()
        fadeTask = nil
        guard let player else {
            isPlaying = false
            return
        }
        if !fade || player.volume <= 0.02 {
            player.stop()
            self.player = nil
            isPlaying = false
            deactivateSessionIfIdle()
            return
        }
        let startVol = player.volume
        let steps = 12
        let stepDur = AmbientAudioPolicy.fadeOutSeconds / Double(steps)
        fadeTask = Task { @MainActor [weak self] in
            for i in 1...steps {
                guard !Task.isCancelled, let self, let p = self.player else { return }
                let t = Float(i) / Float(steps)
                p.volume = startVol * (1 - t)
                try? await Task.sleep(for: .seconds(stepDur))
            }
            guard let self else { return }
            self.player?.stop()
            self.player = nil
            self.isPlaying = false
            self.deactivateSessionIfIdle()
        }
    }

    private func startIfNeeded() {
        if let player, player.isPlaying {
            isPlaying = true
            return
        }
        guard preparePlayer() else { return }
        configureSession()
        player?.volume = 0
        player?.numberOfLoops = -1
        player?.play()
        isPlaying = player?.isPlaying == true
        fadeIn()
    }

    private func preparePlayer() -> Bool {
        if player != nil { return true }
        guard let url = bundle.url(
            forResource: AmbientAudioPolicy.resourceName,
            withExtension: AmbientAudioPolicy.resourceExtension
        ) else {
            return false
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = -1
            player = p
            return true
        } catch {
            player = nil
            return false
        }
    }

    private func fadeIn() {
        fadeTask?.cancel()
        let target = AmbientAudioPolicy.targetVolume
        let steps = 14
        let stepDur = AmbientAudioPolicy.fadeInSeconds / Double(steps)
        fadeTask = Task { @MainActor [weak self] in
            for i in 1...steps {
                guard !Task.isCancelled, let self, let p = self.player else { return }
                p.volume = target * (Float(i) / Float(steps))
                try? await Task.sleep(for: .seconds(stepDur))
            }
            self?.player?.volume = target
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // Ambient: mix with others; no exclusive takeover; no background audio mode required
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private func deactivateSessionIfIdle() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// No-op double for unit tests (no AVAudio hardware).
@MainActor
final class NullAmbientAudio: SessionAmbientAudioPlaying {
    private(set) var isPlaying = false
    private(set) var lastSyncEnabled: Bool?
    private(set) var syncCount = 0
    private(set) var stopCount = 0

    func sync(
        enabled: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    ) {
        syncCount += 1
        lastSyncEnabled = enabled
        isPlaying = AmbientAudioPolicy.shouldPlay(
            enabled: enabled,
            isRunning: isRunning,
            isPaused: isPaused,
            isInBackground: isInBackground
        )
    }

    func stop(fade: Bool) {
        stopCount += 1
        isPlaying = false
    }
}
