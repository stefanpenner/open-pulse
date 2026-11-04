import AVFoundation
import CoreHaptics
import Foundation

// MARK: - Testable seam

@MainActor
protocol SessionAmbientAudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    func sync(
        sound: Bool,
        haptics: Bool,
        joyCon: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    )
    func stop(fade: Bool)
    /// Which Joy-Con plays which side. Empty when none is found or the setting is off.
    var joyConPlan: JoyConTapper.Plan { get }
    var onJoyConPlanChange: (@MainActor (JoyConTapper.Plan) -> Void)? { get set }
}

/// The session tapper: a soft left/right tick-tock sound, haptic taps, or both, on one beat.
/// Privacy-first: local synth only, no file, no network.
@MainActor
final class SessionAmbientAudio: NSObject, SessionAmbientAudioPlaying {
    private struct Outputs: Equatable {
        let sound: Bool
        /// Sides the phone taps.
        let phoneSides: Set<BilateralTicks.Side>
        /// Sides the Joy-Cons tap.
        let joyCons: JoyConTapper.Plan
    }

    private struct Request {
        let sound: Bool
        let haptics: Bool
        let joyCon: Bool
        let isRunning: Bool
        let isPaused: Bool
        let isInBackground: Bool
    }

    private let joyCons = JoyConHaptics()
    private var lastRequest: Request?
    var onJoyConPlanChange: (@MainActor (JoyConTapper.Plan) -> Void)?
    var joyConPlan: JoyConTapper.Plan { joyCons.plan }

    override init() {
        super.init()
        joyCons.onChange = { [weak self] plan in
            guard let self else { return }
            self.onJoyConPlanChange?(plan)
            if self.lastRequest?.joyCon == true { self.resync() }
        }
    }

    private func resync() {
        guard let r = lastRequest else { return }
        sync(sound: r.sound, haptics: r.haptics, joyCon: r.joyCon,
             isRunning: r.isRunning, isPaused: r.isPaused, isInBackground: r.isInBackground)
    }

    private var tickEngine: AVAudioEngine?
    private var tickNode: AVAudioPlayerNode?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var fadeTask: Task<Void, Never>?
    private var outputs: Outputs?
    private var fadingOut = false
    private(set) var isPlaying: Bool = false

    func sync(
        sound: Bool,
        haptics: Bool,
        joyCon: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    ) {
        lastRequest = Request(sound: sound, haptics: haptics, joyCon: joyCon,
                              isRunning: isRunning, isPaused: isPaused, isInBackground: isInBackground)
        if joyCon { joyCons.watch() } else { joyCons.unwatch() }
        let want = AmbientAudioPolicy.shouldPlay(
            enabled: sound || haptics,
            isRunning: isRunning,
            isPaused: isPaused,
            isInBackground: isInBackground
        )
        guard want else {
            if isPlaying { stop(fade: true) }
            return
        }
        // Joy-Cons take the sides they cover. The phone taps only the rest.
        let plan = joyCon && haptics ? joyCons.plan : JoyConTapper.Plan()
        let next = Outputs(sound: sound, phoneSides: haptics ? plan.phoneSides : [], joyCons: plan)
        // A changed output restarts both, so the sound and the taps share one beat.
        if isPlaying, outputs != next { stopNow() }
        start(next)
    }

    func stop(fade: Bool) {
        fadeTask?.cancel()
        fadeTask = nil
        guard isPlaying else { return }
        stopHaptics()
        let startVol = tickNode?.volume ?? 0
        guard fade, startVol > 0.02 else {
            stopNow()
            return
        }
        fadingOut = true
        fadeTask = ramp(from: startVol, to: 0, seconds: AmbientAudioPolicy.fadeOutSeconds) { [weak self] in
            self?.stopNow()
        }
    }

    private func start(_ next: Outputs) {
        if isPlaying, !fadingOut { return }
        // Mid fade-out: restart clean, so the sound and the taps share one beat.
        if fadingOut { stopNow() }
        if next.sound {
            configureSession()
            _ = startTicks()
        }
        startHaptics(sides: next.phoneSides)
        joyCons.startTaps(next.joyCons)
        guard tickNode != nil || hapticPlayer != nil || joyCons.isTapping else { return }
        outputs = next
        isPlaying = true
        guard tickNode != nil else { return }
        let from = tickNode?.volume ?? 0
        fadeTask = ramp(from: from, to: AmbientAudioPolicy.targetVolume, seconds: AmbientAudioPolicy.fadeInSeconds) { [weak self] in
            self?.fadeTask = nil
        }
    }

    private func stopNow() {
        fadeTask?.cancel()
        fadeTask = nil
        fadingOut = false
        stopHaptics()
        let hadSound = tickEngine != nil
        tickNode?.stop()
        tickEngine?.stop()
        tickNode = nil
        tickEngine = nil
        outputs = nil
        isPlaying = false
        if hadSound { deactivateSessionIfIdle() }
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

    // MARK: - Sound

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

    // MARK: - Haptics

    /// Loops the tap pattern on the phone's haptic motor. No-op on hardware without haptics.
    private func startHaptics(sides: Set<BilateralTicks.Side>) {
        guard !sides.isEmpty, hapticPlayer == nil,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            try engine.start()
            let player = try engine.makeAdvancedPlayer(with: Self.tapPattern(for: sides))
            player.loopEnabled = true
            player.loopEnd = BilateralTicks.loopSeconds
            try player.start(atTime: CHHapticTimeImmediate)
            hapticEngine = engine
            hapticPlayer = player
        } catch {
            hapticEngine?.stop()
            hapticEngine = nil
        }
    }

    private func stopHaptics() {
        joyCons.stopTaps()
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticEngine?.stop()
        hapticPlayer = nil
        hapticEngine = nil
    }

    static func tapPattern(for sides: Set<BilateralTicks.Side>) throws -> CHHapticPattern {
        let events = BilateralTicks.hapticTaps(for: sides).map { tap in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness),
                ],
                relativeTime: tap.time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
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

/// No-op double for unit tests (no AVAudio or haptic hardware).
@MainActor
final class NullAmbientAudio: SessionAmbientAudioPlaying {
    private(set) var isPlaying = false
    private(set) var lastSyncSound: Bool?
    private(set) var lastSyncHaptics: Bool?
    private(set) var lastSyncJoyCon: Bool?
    private(set) var joyConPlan = JoyConTapper.Plan()
    var onJoyConPlanChange: (@MainActor (JoyConTapper.Plan) -> Void)?
    private(set) var syncCount = 0
    private(set) var stopCount = 0

    func sync(
        sound: Bool,
        haptics: Bool,
        joyCon: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    ) {
        syncCount += 1
        lastSyncJoyCon = joyCon
        lastSyncSound = sound
        lastSyncHaptics = haptics
        isPlaying = AmbientAudioPolicy.shouldPlay(
            enabled: sound || haptics,
            isRunning: isRunning,
            isPaused: isPaused,
            isInBackground: isInBackground
        )
    }

    /// Test hook: pretend these Joy-Cons are paired.
    func setPlan(_ plan: JoyConTapper.Plan) {
        joyConPlan = plan
        onJoyConPlanChange?(plan)
    }

    func stop(fade: Bool) {
        stopCount += 1
        isPlaying = false
    }
}
