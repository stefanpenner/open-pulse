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

/// Calming music: a soft left/right tick-tock during sessions, like tappers.
/// Privacy-first: local synth only, no file, no network.
@MainActor
final class SessionAmbientAudio: NSObject, SessionAmbientAudioPlaying {
    private var tickEngine: AVAudioEngine?
    private var tickNode: AVAudioPlayerNode?
    private var fadeTask: Task<Void, Never>?
    private(set) var isPlaying: Bool = false

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
        } else if isPlaying {
            stop(fade: true)
        }
    }

    func stop(fade: Bool) {
        fadeTask?.cancel()
        fadeTask = nil
        guard isPlaying else { return }
        let startVol = tickNode?.volume ?? 0
        guard fade, startVol > 0.02 else {
            stopNow()
            return
        }
        fadeTask = ramp(from: startVol, to: 0, seconds: AmbientAudioPolicy.fadeOutSeconds) { [weak self] in
            self?.stopNow()
        }
    }

    private func startIfNeeded() {
        if isPlaying, fadeTask == nil { return }
        configureSession()
        guard startTicks() else { return }
        isPlaying = true
        fadeTask?.cancel()
        let from = tickNode?.volume ?? 0
        fadeTask = ramp(from: from, to: AmbientAudioPolicy.targetVolume, seconds: AmbientAudioPolicy.fadeInSeconds) { [weak self] in
            self?.fadeTask = nil
        }
    }

    private func stopNow() {
        tickNode?.stop()
        tickEngine?.stop()
        tickNode = nil
        tickEngine = nil
        isPlaying = false
        fadeTask = nil
        deactivateSessionIfIdle()
    }

    // MARK: - Level

    private func setLevel(_ level: Float) {
        tickNode?.volume = level
    }

    private func ramp(from: Float, to: Float, seconds: TimeInterval, done: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let steps = 14
        let stepDur = seconds / Double(steps)
        return Task { @MainActor [weak self] in
            for i in 1...steps {
                guard !Task.isCancelled, let self else { return }
                self.setLevel(from + (to - from) * Float(i) / Float(steps))
                try? await Task.sleep(for: .seconds(stepDur))
            }
            guard !Task.isCancelled else { return }
            done()
        }
    }

    // MARK: - Sources

    /// Loops one rendered stereo buffer: tick left, then tock right.
    private func startTicks() -> Bool {
        if tickNode != nil { return true }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = Self.tickBuffer(format: format) else {
            return false
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = 0
        do {
            try engine.start()
        } catch {
            return false
        }
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        tickEngine = engine
        tickNode = node
        return true
    }

    private static func tickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let loop = BilateralTicks.renderLoop(sampleRate: format.sampleRate)
        let frames = AVAudioFrameCount(loop.left.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frames
        loop.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: $0.count) }
        loop.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: $0.count) }
        return buffer
    }

    // MARK: - Session

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
